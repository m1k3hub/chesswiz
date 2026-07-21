"""Adapter contract tests for the scidb-beta runtime adapter.

These tests verify that the runtime adapter's JSON responses match the
expected schema for each endpoint. The same schemas are documented in
``ADAPTER_CONTRACT.md`` and are used by ``tests/test_tcl_bridge_contract.py``
to verify that the Tcl bridge (when available) returns compatible shapes.

Run with:  pytest tests/test_adapter_contract.py -v
"""

import os

import pytest
from fastapi.testclient import TestClient

from runtime_adapter import app
from runtime_adapter import _rate_buckets

if os.environ.get("TCL_INTERP"):
    pytest.skip(
        "Adapter contract tests expect mock/sample-bridge data; "
        "unset TCL_INTERP/TCL_BRIDGE_PATH/SCIDB_DATABASE to run them",
        allow_module_level=True,
    )


@pytest.fixture(autouse=True)
def _reset_rate_limits():
    """Reset rate-limit buckets before each test to avoid cross-test interference."""
    _rate_buckets.clear()


client = TestClient(app)


# ---------------------------------------------------------------------------
# Schema helpers
# ---------------------------------------------------------------------------

def assert_database_schema(db: dict) -> None:
    """Assert that ``db`` matches the Database schema."""
    assert isinstance(db, dict), "database must be an object"
    assert isinstance(db.get("id"), str) and db["id"], "database.id must be a non-empty string"
    assert isinstance(db.get("name"), str), "database.name must be a string"
    assert isinstance(db.get("format"), str), "database.format must be a string"
    assert isinstance(db.get("games"), int), "database.games must be an integer"
    assert isinstance(db.get("readOnly"), bool), "database.readOnly must be a boolean"


def assert_game_summary_schema(game: dict) -> None:
    """Assert that ``game`` matches the GameSummary schema."""
    assert isinstance(game, dict), "game must be an object"
    for field in ("id", "white", "black", "event", "site", "date", "result", "eco"):
        assert field in game, f"game.{field} is required"
        assert isinstance(game[field], str), f"game.{field} must be a string"
    for field in ("whiteElo", "blackElo"):
        assert field in game, f"game.{field} is required"
        assert isinstance(game[field], int), f"game.{field} must be an integer"


def assert_search_result_schema(result: dict) -> None:
    """Assert that ``result`` matches the search response schema."""
    assert isinstance(result, dict)
    assert isinstance(result.get("jobId"), str) and result["jobId"], "jobId must be a non-empty string"
    assert result.get("status") in ("pending", "running", "complete", "error", "cancelled", "stopped")
    assert isinstance(result.get("total"), int), "total must be an integer"


def assert_search_results_schema(data: dict) -> None:
    """Assert that ``data`` matches the search results schema."""
    assert isinstance(data, dict)
    assert isinstance(data.get("jobId"), str)
    assert data.get("status") in ("pending", "running", "complete", "error", "cancelled", "stopped")
    assert isinstance(data.get("total"), int)
    assert "games" in data
    assert isinstance(data["games"], list)
    if data["games"]:
        assert_game_summary_schema(data["games"][0])


def assert_tree_move_schema(move: dict) -> None:
    """Assert that ``move`` matches the OpeningMove schema."""
    assert isinstance(move, dict)
    for field in ("san", "uci", "eco"):
        assert isinstance(move.get(field), str), f"move.{field} must be a string"
    for field in ("games", "white", "draw", "black"):
        assert isinstance(move.get(field), int), f"move.{field} must be an integer"
    assert isinstance(move.get("score"), (int, float)), "move.score must be numeric"


def assert_analysis_start_schema(result: dict) -> None:
    """Assert that ``result`` matches the analysis start response schema."""
    assert isinstance(result, dict)
    assert isinstance(result.get("jobId"), str) and result["jobId"]
    assert result.get("status") in ("running", "pending")


def assert_analysis_job_schema(data: dict) -> None:
    """Assert that ``data`` matches the AnalysisJob schema."""
    assert isinstance(data, dict)
    assert isinstance(data.get("jobId"), str)
    assert data.get("status") in ("pending", "running", "complete", "stopped", "unknown")
    assert isinstance(data.get("fen"), str)
    assert isinstance(data.get("depth"), int)
    assert isinstance(data.get("multiPv"), int)
    assert isinstance(data.get("lines"), list)
    assert isinstance(data.get("nodes"), int)
    assert isinstance(data.get("nps"), int)
    if data["lines"]:
        line = data["lines"][0]
        assert isinstance(line.get("pv"), str), "line.pv must be a string"
        assert isinstance(line.get("eval"), str), "line.eval must be a string"
        assert isinstance(line.get("depth"), int), "line.depth must be an integer"


def assert_game_detail_schema(detail: dict) -> None:
    """Assert that ``detail`` matches the GameDetail schema."""
    assert isinstance(detail, dict)
    assert isinstance(detail.get("id"), str) and detail["id"]
    assert isinstance(detail.get("headers"), dict), "headers must be an object"
    assert isinstance(detail.get("moves"), list), "moves must be an array"
    assert isinstance(detail.get("pgn"), str), "pgn must be a string"
    if detail["moves"]:
        move = detail["moves"][0]
        for field in ("id", "san", "uci", "fen", "color"):
            assert field in move, f"move.{field} is required"
        assert move["color"] in ("w", "b"), "move.color must be 'w' or 'b'"
        assert isinstance(move.get("ply"), int), "move.ply must be an integer"
        assert isinstance(move.get("nags"), list), "move.nags must be an array"
        assert isinstance(move.get("variations"), list), "move.variations must be an array"


# ---------------------------------------------------------------------------
# Tests: GET /api/databases
# ---------------------------------------------------------------------------

class TestDatabasesContract:
    def test_list_databases_schema(self):
        resp = client.get("/api/databases")
        assert resp.status_code == 200
        data = resp.json()
        assert isinstance(data, list)
        assert len(data) >= 2
        for db in data:
            assert_database_schema(db)

    def test_create_database_schema(self):
        resp = client.post("/api/databases", json={
            "name": "Contract Test DB",
            "format": "PGN",
            "games": 0,
            "readOnly": False,
        })
        assert resp.status_code == 200
        assert_database_schema(resp.json())


# ---------------------------------------------------------------------------
# Tests: GET /api/databases/:id/games
# ---------------------------------------------------------------------------

class TestGamesListContract:
    def test_list_games_schema(self):
        resp = client.get("/api/databases/masters/games")
        assert resp.status_code == 200
        games = resp.json()
        assert isinstance(games, list)
        assert len(games) >= 1
        for game in games:
            assert_game_summary_schema(game)


# ---------------------------------------------------------------------------
# Tests: POST /api/searches
# ---------------------------------------------------------------------------

class TestSearchContract:
    def test_search_response_schema(self):
        resp = client.post("/api/searches", json={
            "databaseId": "masters",
            "type": "advanced",
            "query": {"white": "carlsen"},
        })
        assert resp.status_code == 200
        assert_search_result_schema(resp.json())

    def test_search_results_schema(self):
        search_resp = client.post("/api/searches", json={
            "databaseId": "masters",
            "type": "advanced",
            "query": {},
        })
        job_id = search_resp.json()["jobId"]
        results_resp = client.get(f"/api/searches/{job_id}/results")
        assert results_resp.status_code == 200
        assert_search_results_schema(results_resp.json())


# ---------------------------------------------------------------------------
# Tests: POST /api/tree/query
# ---------------------------------------------------------------------------

class TestTreeContract:
    def test_tree_query_schema(self):
        resp = client.post("/api/tree/query", json={"moves": []})
        assert resp.status_code == 200
        tree = resp.json()
        assert isinstance(tree, list)
        assert len(tree) >= 1
        for move in tree:
            assert_tree_move_schema(move)


# ---------------------------------------------------------------------------
# Tests: POST /api/analysis/start, GET /api/analysis/:id
# ---------------------------------------------------------------------------

class TestAnalysisContract:
    def test_analysis_start_schema(self):
        resp = client.post("/api/analysis/start", json={
            "fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            "multiPv": 3,
            "depth": 5,
        })
        assert resp.status_code == 200
        assert_analysis_start_schema(resp.json())

    def test_analysis_job_schema(self):
        start_resp = client.post("/api/analysis/start", json={
            "fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            "multiPv": 2,
            "depth": 3,
        })
        job_id = start_resp.json()["jobId"]
        resp = client.get(f"/api/analysis/{job_id}")
        assert resp.status_code == 200
        assert_analysis_job_schema(resp.json())


# ---------------------------------------------------------------------------
# Tests: GET /api/games/:id
# ---------------------------------------------------------------------------

class TestGameDetailContract:
    def test_game_detail_schema(self):
        resp = client.get("/api/games/g-001")
        assert resp.status_code == 200
        assert_game_detail_schema(resp.json())

    def test_game_detail_not_found(self):
        resp = client.get("/api/games/nonexistent")
        assert resp.status_code == 404