"""Tests for anti-cheat v1 heuristics (Phase 7): instant-move and blur flags."""

import os
import sys

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


def _pair():
    a = client.post("/api/play/seek", json={
        "timeControl": {"kind": "blitz", "baseSeconds": 180, "incrementSeconds": 0},
        "rated": False, "color": "w",
    })
    seek_id = a.json()["id"]
    a_id = a.headers["x-play-guest-id"]
    b = client.post(f"/api/play/seek/{seek_id}/accept")
    match_id = b.json()["id"]
    b_id = b.headers["x-play-guest-id"]
    return match_id, {"id": a_id, "name": "A", "rating": 1500}, {"id": b_id, "name": "B", "rating": 1500}


def test_instant_moves_flag_after_threshold():
    match_id, white, black = _pair()
    # A Ruy Lopez opening; white makes 4 fast moves (2nd/3rd/4th count as instant).
    for uci, mover in [
        ("e2e4", white), ("e7e5", black),
        ("g1f3", white), ("b8c6", black),
        ("f1b5", white), ("a7a6", black),
        ("b5a4", white),
    ]:
        play_service.submit_move(mover, match_id, uci)
    queue = play_service.get_review_queue()
    assert any(e["matchId"] == match_id and e["reason"] == "instant_moves" and e["userId"] == white["id"] for e in queue)


def test_no_flag_for_normal_play():
    match_id, white, black = _pair()
    play_service.submit_move(white, match_id, "e2e4")
    play_service.submit_move(black, match_id, "e7e5")
    queue = play_service.get_review_queue()
    assert queue == []


def test_blur_during_opponents_turn_flags_after_threshold():
    match_id, white, black = _pair()
    play_service.submit_move(white, match_id, "e2e4")  # now black to move
    for _ in range(3):
        play_service.record_blur(white, match_id)
    queue = play_service.get_review_queue()
    assert any(e["matchId"] == match_id and e["reason"] == "blur_loss" and e["userId"] == white["id"] for e in queue)


def test_blur_during_own_turn_not_flagged():
    match_id, white, black = _pair()
    play_service.submit_move(white, match_id, "e2e4")  # black to move
    for _ in range(5):
        play_service.record_blur(black, match_id)  # black's own turn — not suspicious
    queue = play_service.get_review_queue()
    assert queue == []


def test_blur_ws_message_updates_review_queue():
    match_id, white, black = _pair()
    play_service.submit_move(white, match_id, "e2e4")
    with client.websocket_connect(f"/api/ws/play?guest={white['id']}") as ws:
        ws.receive_json()  # seek.list
        ws.receive_json()  # match.resync
        for _ in range(3):
            ws.send_json({"type": "blur", "matchId": match_id})
    queue = play_service.get_review_queue()
    assert any(e["matchId"] == match_id and e["reason"] == "blur_loss" for e in queue)
