"""Tests for the rated-game engine lock (Phase 7): /api/analysis/start
refuses to start an engine for a user with an active rated match."""

import base64
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("SCIDB_ALLOW_INSECURE_DEV_AUTH", "1")

import pytest
from fastapi.testclient import TestClient

from runtime_adapter import app
from play_service import play_service

client = TestClient(app)


def _auth_headers(sub: str, name: str | None = None) -> dict[str, str]:
    header = base64.urlsafe_b64encode(b'{"alg":"none","typ":"JWT"}').rstrip(b"=").decode()
    payload = base64.urlsafe_b64encode(json.dumps({"sub": sub, "name": name or sub}).encode()).rstrip(b"=").decode()
    signature = base64.urlsafe_b64encode(b"sig").rstrip(b"=").decode()
    return {"Authorization": f"Bearer {header}.{payload}.{signature}"}


@pytest.fixture(autouse=True)
def _reset_play_state():
    play_service.reset()
    yield
    play_service.reset()


def _pair_rated(a_sub="alice", b_sub="bob"):
    a = client.post(
        "/api/play/seek",
        json={"timeControl": {"kind": "blitz", "baseSeconds": 180, "incrementSeconds": 0}, "rated": True, "color": "w"},
        headers=_auth_headers(a_sub),
    )
    assert a.status_code == 200, a.text
    seek_id = a.json()["id"]
    b = client.post(f"/api/play/seek/{seek_id}/accept", headers=_auth_headers(b_sub))
    assert b.status_code == 200, b.text
    return b.json()["id"]


def test_engine_start_blocked_for_user_in_active_rated_match():
    _pair_rated()
    r = client.post("/api/analysis/start", json={"fen": "start"}, headers=_auth_headers("alice"))
    assert r.status_code == 403
    assert r.json()["code"] == "rated_engine_lock"


def test_engine_start_blocked_for_both_participants():
    _pair_rated()
    r = client.post("/api/analysis/start", json={"fen": "start"}, headers=_auth_headers("bob"))
    assert r.status_code == 403


def test_engine_start_allowed_for_uninvolved_user():
    _pair_rated()
    r = client.post("/api/analysis/start", json={"fen": "start"}, headers=_auth_headers("carol"))
    assert r.status_code == 200


def test_engine_start_allowed_for_anonymous_user():
    _pair_rated()
    r = client.post("/api/analysis/start", json={"fen": "start"})
    assert r.status_code == 200


def test_engine_start_allowed_after_match_finishes():
    match_id = _pair_rated()
    play_service.resign(play_service.get_match(match_id)["white"], match_id)
    r = client.post("/api/analysis/start", json={"fen": "start"}, headers=_auth_headers("alice"))
    assert r.status_code == 200


def test_engine_lock_does_not_apply_to_casual_match():
    a = client.post(
        "/api/play/seek",
        json={"timeControl": {"kind": "blitz", "baseSeconds": 180, "incrementSeconds": 0}, "rated": False, "color": "w"},
        headers=_auth_headers("dave"),
    )
    seek_id = a.json()["id"]
    client.post(f"/api/play/seek/{seek_id}/accept", headers=_auth_headers("erin"))
    r = client.post("/api/analysis/start", json={"fen": "start"}, headers=_auth_headers("dave"))
    assert r.status_code == 200
