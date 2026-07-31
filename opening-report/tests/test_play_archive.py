"""Tests for finished-game archival to a database as PGN (Phase 6)."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("SCIDB_ALLOW_INSECURE_DEV_AUTH", "1")

import pytest
from fastapi.testclient import TestClient

from runtime_adapter import app, _JOBS
from play_service import play_service

client = TestClient(app)


@pytest.fixture(autouse=True)
def _reset_play_state():
    play_service.reset()
    yield
    play_service.reset()


def _finish_a_match():
    a = client.post("/api/play/seek", json={
        "timeControl": {"kind": "blitz", "baseSeconds": 180, "incrementSeconds": 2},
        "rated": False, "color": "w",
    })
    a_id = a.headers["x-play-guest-id"]
    seek_id = a.json()["id"]
    match_id = client.post(f"/api/play/seek/{seek_id}/accept").json()["id"]
    client.post(f"/api/play/match/{match_id}/resign", headers={"X-Play-Guest-Id": a_id})
    return match_id, a_id


def test_archive_returns_job_id_and_creates_job():
    match_id, a_id = _finish_a_match()
    # Ensure a target database exists.
    dbs = client.get("/api/databases").json()
    db_id = dbs[0]["id"]
    resp = client.post(f"/api/play/match/{match_id}/archive", json={"databaseId": db_id},
                       headers={"X-Play-Guest-Id": a_id})
    assert resp.status_code == 200, resp.text
    job_id = resp.json()["jobId"]
    assert job_id.startswith("import-")
    # The job is tracked by the adapter's job store and visible to JobCenter.
    job = _JOBS.get(job_id)
    assert job is not None
    assert job["type"] == "import"
    assert job["databaseId"] == db_id
    assert job["source"] == "play-archive"


def test_archive_rejects_unfinished_match():
    a = client.post("/api/play/seek", json={
        "timeControl": {"kind": "blitz", "baseSeconds": 60, "incrementSeconds": 0},
        "rated": False, "color": "w",
    })
    a_id = a.headers["x-play-guest-id"]
    match_id = client.post(f"/api/play/seek/{a.json()['id']}/accept").json()["id"]
    dbs = client.get("/api/databases").json()
    resp = client.post(f"/api/play/match/{match_id}/archive", json={"databaseId": dbs[0]["id"]},
                       headers={"X-Play-Guest-Id": a_id})
    assert resp.status_code == 400


def test_archive_rejects_non_participant():
    match_id, _ = _finish_a_match()
    other = client.post("/api/play/seek", json={
        "timeControl": {"kind": "blitz", "baseSeconds": 60, "incrementSeconds": 0},
        "rated": False, "color": "w",
    }).headers["x-play-guest-id"]
    dbs = client.get("/api/databases").json()
    resp = client.post(f"/api/play/match/{match_id}/archive", json={"databaseId": dbs[0]["id"]},
                       headers={"X-Play-Guest-Id": other})
    assert resp.status_code == 403


def test_match_to_pgn_has_headers_and_movetext():
    a = client.post("/api/play/seek", json={
        "timeControl": {"kind": "blitz", "baseSeconds": 60, "incrementSeconds": 0},
        "rated": False, "color": "w",
    })
    a_id = a.headers["x-play-guest-id"]
    match_id = client.post(f"/api/play/seek/{a.json()['id']}/accept").json()["id"]
    play_service.submit_move({"id": a_id, "name": "A", "rating": 1500}, match_id, "e2e4")
    client.post(f"/api/play/match/{match_id}/resign", headers={"X-Play-Guest-Id": a_id})
    pgn = play_service.match_to_pgn(match_id)
    assert pgn is not None
    assert '[White "' in pgn
    assert '[Result "0-1"]' in pgn  # white (A) resigned
    assert "e4" in pgn