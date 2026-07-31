"""Tests for offers, rematch, abort, and chat (Phase 5)."""

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


def _pair(color="w"):
    a = client.post("/api/play/seek", json={
        "timeControl": {"kind": "blitz", "baseSeconds": 180, "incrementSeconds": 2},
        "rated": False, "color": color,
    })
    seek_id = a.json()["id"]
    a_id = a.headers["x-play-guest-id"]
    b = client.post(f"/api/play/seek/{seek_id}/accept")
    return b.json()["id"], a_id, b.headers["x-play-guest-id"]


def _hdr(gid):
    return {"X-Play-Guest-Id": gid}


def test_draw_offer_accept_finishes_as_agreement():
    match_id, a_id, b_id = _pair()
    # A (white) offers draw.
    r = client.post(f"/api/play/match/{match_id}/offer", json={"kind": "draw"}, headers=_hdr(a_id))
    assert r.status_code == 200
    assert play_service.get_match(match_id)["drawOfferSide"] == "w"
    # B accepts.
    r = client.post(f"/api/play/match/{match_id}/offer/respond", json={"accept": True}, headers=_hdr(b_id))
    assert r.status_code == 200
    match = play_service.get_match(match_id)
    assert match["status"] == "finished"
    assert match["result"] == {"kind": "draw", "reason": "agreement"}


def test_draw_offer_decline_clears_offer():
    match_id, a_id, b_id = _pair()
    client.post(f"/api/play/match/{match_id}/offer", json={"kind": "draw"}, headers=_hdr(a_id))
    client.post(f"/api/play/match/{match_id}/offer/respond", json={"accept": False}, headers=_hdr(b_id))
    assert play_service.get_match(match_id)["drawOfferSide"] is None
    assert play_service.get_match(match_id)["status"] == "playing"


def test_no_pending_offer_returns_400():
    match_id, a_id, _ = _pair()
    r = client.post(f"/api/play/match/{match_id}/offer/respond", json={"accept": True}, headers=_hdr(a_id))
    assert r.status_code == 400


def test_abort_only_when_few_moves_and_no_rated_effect():
    match_id, a_id, _ = _pair()
    r = client.post(f"/api/play/match/{match_id}/abort", headers=_hdr(a_id))
    assert r.status_code == 200
    match = play_service.get_match(match_id)
    assert match["status"] == "finished"
    assert match["result"] == {"kind": "aborted"}


def test_abort_rejected_after_moves():
    match_id, a_id, _ = _pair()
    play_service.submit_move({"id": a_id, "name": "A", "rating": 1500}, match_id, "e2e4")
    play_service.submit_move({"id": _b(match_id), "name": "B", "rating": 1500}, match_id, "e7e5")
    r = client.post(f"/api/play/match/{match_id}/abort", headers=_hdr(a_id))
    assert r.status_code == 400


def _b(match_id):
    m = play_service.get_match(match_id)
    return m["black"]["id"]


def test_rematch_creates_new_match_swapped_colors():
    match_id, a_id, b_id = _pair()
    # Finish the game (resign by A).
    client.post(f"/api/play/match/{match_id}/resign", headers=_hdr(a_id))
    old = play_service.get_match(match_id)
    # A offers rematch.
    r = client.post(f"/api/play/match/{match_id}/offer", json={"kind": "rematch"}, headers=_hdr(a_id))
    assert r.status_code == 200
    # B accepts → new match.
    r = client.post(f"/api/play/match/{match_id}/offer/respond", json={"accept": True}, headers=_hdr(b_id))
    assert r.status_code == 200
    # Find the new rematch (a different, playing match) with swapped colors.
    rematch = [
        rec["match"] for rec in play_service._records.values()
        if rec["match"]["status"] == "playing" and rec["match"]["id"] != match_id
        and a_id in (rec["match"]["white"]["id"], rec["match"]["black"]["id"])
    ]
    assert rematch, "rematch match should be created"
    rm = rematch[0]
    assert rm["white"]["id"] == b_id  # swapped
    assert rm["black"]["id"] == a_id


def test_rematch_requires_finished_game():
    match_id, a_id, _ = _pair()
    r = client.post(f"/api/play/match/{match_id}/offer", json={"kind": "rematch"}, headers=_hdr(a_id))
    assert r.status_code == 400


def test_chat_sanitized_and_delivered():
    match_id, a_id, _ = _pair()
    r = client.post(f"/api/play/match/{match_id}/chat", json={"text": "hi <script>"}, headers=_hdr(a_id))
    assert r.status_code == 200
    assert r.json()["side"] == "w"
    assert "<script>" not in r.json()["text"]  # html-escaped
    assert "&lt;script&gt;" in r.json()["text"]


def test_chat_empty_rejected():
    match_id, a_id, _ = _pair()
    r = client.post(f"/api/play/match/{match_id}/chat", json={"text": "   "}, headers=_hdr(a_id))
    assert r.status_code == 400


def test_offer_requires_participant():
    match_id, a_id, _ = _pair()
    other = client.post("/api/play/seek", json={
        "timeControl": {"kind": "blitz", "baseSeconds": 60, "incrementSeconds": 0},
        "rated": False, "color": "w",
    }).headers["x-play-guest-id"]
    r = client.post(f"/api/play/match/{match_id}/offer", json={"kind": "draw"}, headers=_hdr(other))
    assert r.status_code == 403


def test_takeback_not_supported_in_v1():
    match_id, a_id, _ = _pair()
    r = client.post(f"/api/play/match/{match_id}/offer", json={"kind": "takeback"}, headers=_hdr(a_id))
    assert r.status_code == 400