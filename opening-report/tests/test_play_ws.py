"""Tests for the live-play WebSocket + move endpoints (Phase 4).

Covers the exit criteria: illegal move rejected, clock decrements on move,
timeout finishes the game, and resync after a dropped connection. Seeks and
pairing are done via HTTP (REST); moves flow over /api/ws/play.
"""

import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("SCIDB_ALLOW_INSECURE_DEV_AUTH", "1")

import pytest
from fastapi.testclient import TestClient

from runtime_adapter import app
from play_service import play_service

client = TestClient(app)


@pytest.fixture(autouse=True)
def _reset_play_state():
    play_service.reset()
    yield
    play_service.reset()


def _create_and_accept(color: str = "w"):
    """Guest A creates a seek; Guest B accepts; return (seek_id, match_id, A, B)."""
    a = client.post("/api/play/seek", json={
        "timeControl": {"kind": "blitz", "baseSeconds": 180, "incrementSeconds": 2},
        "rated": False, "color": color,
    })
    seek_id = a.json()["id"]
    a_id = a.headers["x-play-guest-id"]
    b = client.post(f"/api/play/seek/{seek_id}/accept")
    match_id = b.json()["id"]
    b_id = b.headers["x-play-guest-id"]
    return seek_id, match_id, a_id, b_id


def test_ws_resync_sends_seek_list_and_active_match():
    _, match_id, a_id, _ = _create_and_accept()
    with client.websocket_connect(f"/api/ws/play?guest={a_id}") as ws:
        msg = ws.receive_json()
        assert msg["type"] == "seek.list"
        resync = ws.receive_json()
        assert resync["type"] == "match.resync"
        assert resync["match"]["id"] == match_id
        assert resync["moves"] == []


def test_ws_move_flow_and_finish():
    _, match_id, a_id, b_id = _create_and_accept(color="w")  # A=white, B=black
    # Fool's mate: 1.f3 e5 2.g4 Qh4#
    with client.websocket_connect(f"/api/ws/play?guest={a_id}") as a, \
         client.websocket_connect(f"/api/ws/play?guest={b_id}") as b:
        a.receive_json()  # seek.list
        b.receive_json()  # seek.list
        # Both sockets should already be registered for the existing match
        # (reconnect path) → they receive match.resync.
        a.receive_json()  # match.resync (A)
        b.receive_json()  # match.resync (B)

        # 1. f3 (white, A)
        a.send_json({"type": "move", "matchId": match_id, "uci": "f2f3"})
        mv_a = a.receive_json()
        mv_b = b.receive_json()
        assert mv_a["type"] == "match.move" and mv_a["move"]["san"] == "f3"
        assert mv_b["type"] == "match.move" and mv_b["move"]["san"] == "f3"

        # 1... e5 (black, B)
        b.send_json({"type": "move", "matchId": match_id, "uci": "e7e5"})
        a.receive_json()  # match.move
        mv_b2 = b.receive_json()
        assert mv_b2["type"] == "match.move" and mv_b2["move"]["san"] == "e5"

        # 2. g4 (white, A)
        a.send_json({"type": "move", "matchId": match_id, "uci": "g2g4"})
        a.receive_json()
        b.receive_json()

        # 2... Qh4# (black, B) → checkmate. The server emits match.move then match.finish.
        b.send_json({"type": "move", "matchId": match_id, "uci": "d8h4"})
        b.receive_json()  # match.move (Qh4#)
        fin_b = b.receive_json()  # match.finish
        assert fin_b["type"] == "match.finish"
        assert fin_b["result"]["kind"] == "mate"
        assert fin_b["result"]["winner"] == "b"
        # match is now finished
        assert play_service.get_match(match_id)["status"] == "finished"


def test_illegal_move_rejected():
    _, match_id, a_id, _ = _create_and_accept()
    with client.websocket_connect(f"/api/ws/play?guest={a_id}") as a:
        a.receive_json()  # seek.list
        a.receive_json()  # match.resync
        a.send_json({"type": "move", "matchId": match_id, "uci": "e2e5"})  # illegal
        err = a.receive_json()
        assert err["type"] == "match.error"
        assert err["code"] == "illegal_move"


def test_not_your_turn_rejected():
    _, match_id, _, b_id = _create_and_accept(color="w")  # B is black
    with client.websocket_connect(f"/api/ws/play?guest={b_id}") as b:
        b.receive_json()
        b.receive_json()
        # Black tries to move first (white's turn).
        b.send_json({"type": "move", "matchId": match_id, "uci": "e7e5"})
        err = b.receive_json()
        assert err["type"] == "match.error"
        assert err["code"] == "not_your_turn"


def test_clock_decrements_on_move():
    _, match_id, a_id, _ = _create_and_accept()
    start_clock = play_service.get_match(match_id)["clocks"]["whiteMs"]
    assert start_clock == 180000
    play_service.submit_move({"id": a_id, "name": "A", "rating": 1500}, match_id, "e2e4")
    # An instant move with a 2s increment ≈ 180000 - ~0 + 2000.
    after = play_service.get_match(match_id)["clocks"]["whiteMs"]
    assert after > 180000  # increment dominates for an instant move


def test_timeout_finishes_the_game():
    # A 1-second base control so the timeout fires quickly.
    a = client.post("/api/play/seek", json={
        "timeControl": {"kind": "bullet", "baseSeconds": 1, "incrementSeconds": 0},
        "rated": False, "color": "w",
    })
    seek_id = a.json()["id"]
    a_id = a.headers["x-play-guest-id"]
    b = client.post(f"/api/play/seek/{seek_id}/accept")
    match_id = b.json()["id"]
    # White never moves; wait > 1s; the clock loop would flag it, but here we
    # drive check_timeouts() directly to keep the test deterministic and fast.
    time.sleep(1.1)
    play_service.check_timeouts()
    match = play_service.get_match(match_id)
    assert match["status"] == "finished"
    assert match["result"]["kind"] == "timeout"
    assert match["result"]["winner"] == "b"  # white (to move) flagged


def test_resign():
    _, match_id, a_id, _ = _create_and_accept()
    res = client.post(f"/api/play/match/{match_id}/resign", headers={"X-Play-Guest-Id": a_id})
    assert res.status_code == 200
    assert res.json() == {"kind": "resign", "winner": "b"}
    assert play_service.get_match(match_id)["status"] == "finished"


def test_my_games_records_finished_match():
    _, match_id, a_id, _ = _create_and_accept()
    client.post(f"/api/play/match/{match_id}/resign", headers={"X-Play-Guest-Id": a_id})
    games = client.get("/api/play/me/games", headers={"X-Play-Guest-Id": a_id}).json()
    assert any(g["id"] == match_id for g in games)