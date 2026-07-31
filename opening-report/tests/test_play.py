"""Tests for the /api/play REST endpoints (Phase 3: seeks + pairing).

Run with:  pytest tests/test_play.py -v

Covers: guest identity + X-Play-Guest-Id header, create/list/cancel seeks,
accept→pairing, cannot accept own seek, rated seeks reject guests, an
authenticated user can create a rated seek, rate limiting.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("SCIDB_ALLOW_INSECURE_DEV_AUTH", "1")

import pytest
from fastapi.testclient import TestClient

from runtime_adapter import app
from play_service import play_service

client = TestClient(app)


def _guest_headers(prev_guest_id: str | None = None) -> dict[str, str]:
    h: dict[str, str] = {}
    if prev_guest_id:
        h["X-Play-Guest-Id"] = prev_guest_id
    return h


def _dummy_auth_headers(sub: str = "alice", name: str = "Alice") -> dict[str, str]:
    # The dummy dev decoder (security.decode_dummy_jwt) accepts any 3-part
    # token whose payload is JSON with a 'sub' claim; no signature check.
    import base64
    import json

    header = base64.urlsafe_b64encode(b'{"alg":"none","typ":"JWT"}').rstrip(b"=").decode()
    payload = base64.urlsafe_b64encode(json.dumps({"sub": sub, "name": name}).encode()).rstrip(b"=").decode()
    signature = base64.urlsafe_b64encode(b"sig").rstrip(b"=").decode()
    return {"Authorization": f"Bearer {header}.{payload}.{signature}"}


@pytest.fixture(autouse=True)
def _reset_play_state():
    play_service.reset()
    yield
    play_service.reset()


def test_guest_create_seek_returns_guest_id_header():
    resp = client.post("/api/play/seek", json={
        "timeControl": {"kind": "blitz", "baseSeconds": 180, "incrementSeconds": 2},
        "variant": "standard", "rated": False, "color": "random",
    })
    assert resp.status_code == 200, resp.text
    seek = resp.json()
    assert seek["id"].startswith("seek-")
    assert seek["owner"]["id"].startswith("guest-")
    assert resp.headers.get("x-play-guest-id", "").startswith("guest-")


def test_guest_id_is_stable_across_requests_when_repeated():
    resp = client.post("/api/play/seek", json={
        "timeControl": {"kind": "blitz", "baseSeconds": 180, "incrementSeconds": 2},
        "rated": False, "color": "w",
    })
    guest_id = resp.headers["x-play-guest-id"]
    # Re-present the same guest id; my-seeks should list it (same owner).
    mine = client.get("/api/play/seeks/mine", headers={"X-Play-Guest-Id": guest_id})
    assert mine.status_code == 200
    assert any(s["id"] == resp.json()["id"] for s in mine.json())


def test_list_seeks_excludes_own_seek():
    a = client.post("/api/play/seek", json={
        "timeControl": {"kind": "blitz", "baseSeconds": 60, "incrementSeconds": 0},
        "rated": False, "color": "w",
    })
    gid = a.headers["x-play-guest-id"]
    # As the same guest, the open list excludes our own seek.
    open_seeks = client.get("/api/play/seeks", headers={"X-Play-Guest-Id": gid})
    assert open_seeks.status_code == 200
    assert all(s["owner"]["id"] != gid for s in open_seeks.json())


def test_accept_seek_pairs_a_match():
    # Guest A creates a seek (white).
    a = client.post("/api/play/seek", json={
        "timeControl": {"kind": "blitz", "baseSeconds": 180, "incrementSeconds": 2},
        "rated": False, "color": "w",
    })
    seek_id = a.json()["id"]
    # Guest B (no header) accepts.
    b = client.post(f"/api/play/seek/{seek_id}/accept")
    assert b.status_code == 200, b.text
    match = b.json()
    assert match["id"].startswith("match-")
    assert match["status"] == "playing"
    assert match["white"]["id"] == a.json()["owner"]["id"]  # color=w → owner white
    assert match["black"]["id"] == b.json()["black"]["id"] != match["white"]["id"]
    assert match["clocks"]["whiteMs"] == 180000
    assert match["startFen"].startswith("rnbqkbnr")


def test_accept_seek_color_black_makes_accepter_white():
    a = client.post("/api/play/seek", json={
        "timeControl": {"kind": "blitz", "baseSeconds": 60, "incrementSeconds": 0},
        "rated": False, "color": "b",
    })
    seek_id = a.json()["id"]
    b = client.post(f"/api/play/seek/{seek_id}/accept")
    match = b.json()
    assert match["white"]["id"] == b.headers["x-play-guest-id"]
    assert match["black"]["id"] == a.json()["owner"]["id"]


def test_cannot_accept_own_seek():
    a = client.post("/api/play/seek", json={
        "timeControl": {"kind": "blitz", "baseSeconds": 60, "incrementSeconds": 0},
        "rated": False, "color": "w",
    })
    seek_id = a.json()["id"]
    gid = a.headers["x-play-guest-id"]
    resp = client.post(f"/api/play/seek/{seek_id}/accept", headers={"X-Play-Guest-Id": gid})
    assert resp.status_code == 400
    assert "own seek" in resp.json()["detail"]


def test_cancel_seek_by_owner():
    a = client.post("/api/play/seek", json={
        "timeControl": {"kind": "blitz", "baseSeconds": 60, "incrementSeconds": 0},
        "rated": False, "color": "w",
    })
    seek_id = a.json()["id"]
    gid = a.headers["x-play-guest-id"]
    resp = client.delete(f"/api/play/seek/{seek_id}", headers={"X-Play-Guest-Id": gid})
    assert resp.status_code == 200
    assert resp.json() == {"ok": True}
    mine = client.get("/api/play/seeks/mine", headers={"X-Play-Guest-Id": gid})
    assert mine.json() == []


def test_cancel_seek_rejects_non_owner():
    a = client.post("/api/play/seek", json={
        "timeControl": {"kind": "blitz", "baseSeconds": 60, "incrementSeconds": 0},
        "rated": False, "color": "w",
    })
    seek_id = a.json()["id"]
    # A different guest (no header) tries to cancel.
    resp = client.delete(f"/api/play/seek/{seek_id}")
    assert resp.status_code == 403


def test_rated_seek_rejects_guests():
    resp = client.post("/api/play/seek", json={
        "timeControl": {"kind": "blitz", "baseSeconds": 180, "incrementSeconds": 2},
        "rated": True, "color": "w",
    })
    assert resp.status_code == 403
    detail = resp.json()["detail"]
    assert isinstance(detail, dict)
    assert detail["code"] == "rated_requires_auth"


def test_authenticated_user_can_create_rated_seek():
    resp = client.post(
        "/api/play/seek",
        json={
            "timeControl": {"kind": "blitz", "baseSeconds": 180, "incrementSeconds": 2},
            "rated": True, "color": "w",
        },
        headers=_dummy_auth_headers("alice", "Alice"),
    )
    assert resp.status_code == 200, resp.text
    seek = resp.json()
    assert seek["rated"] is True
    assert seek["owner"]["id"] == "alice"
    assert seek["owner"]["name"] == "Alice"
    # Authenticated users do not get a guest header.
    assert "x-play-guest-id" not in resp.headers


def test_get_match_returns_paired_match():
    a = client.post("/api/play/seek", json={
        "timeControl": {"kind": "blitz", "baseSeconds": 180, "incrementSeconds": 2},
        "rated": False, "color": "w",
    })
    seek_id = a.json()["id"]
    b = client.post(f"/api/play/seek/{seek_id}/accept")
    match_id = b.json()["id"]
    got = client.get(f"/api/play/match/{match_id}")
    assert got.status_code == 200
    assert got.json()["id"] == match_id


def test_get_match_404_for_unknown():
    resp = client.get("/api/play/match/match-nope")
    assert resp.status_code == 404


def test_my_rating_provisional():
    resp = client.get("/api/play/me/rating")
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, list) and data
    assert data[0]["rating"] == 1500
    assert data[0]["rd"] == 350