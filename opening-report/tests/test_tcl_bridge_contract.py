"""Tcl bridge contract tests for the scidb-beta runtime adapter.

These tests compare the JSON output of the Tcl bridge against the same
schemas used in ``tests/test_adapter_contract.py``. When a Tcl bridge is
available (either via ``TCL_BRIDGE_PATH`` env var or the bundled
``tcl_bridge_sample.tcl``), the tests run; otherwise they skip.

Run with:  pytest tests/test_tcl_bridge_contract.py -v
"""

import json
import os
import shutil
import subprocess
import sys

import pytest

from tests.test_adapter_contract import (
    assert_database_schema,
    assert_game_summary_schema,
    assert_search_result_schema,
    assert_search_results_schema,
    assert_tree_move_schema,
    assert_analysis_start_schema,
    assert_analysis_job_schema,
    assert_game_detail_schema,
)


# ---------------------------------------------------------------------------
# Tcl bridge discovery
# ---------------------------------------------------------------------------

# Prefer the env var; fall back to the bundled sample script.
_SAMPLE_BRIDGE = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "tcl_bridge_sample.tcl",
)


def _get_bridge_path() -> str:
    env_path = os.environ.get("TCL_BRIDGE_PATH", "")
    if env_path and os.path.isfile(env_path):
        return env_path
    if os.path.isfile(_SAMPLE_BRIDGE):
        return _SAMPLE_BRIDGE
    return ""


TCL_BRIDGE_PATH = _get_bridge_path()


def _skip_if_no_bridge():
    if os.environ.get("TCL_INTERP", ""):
        pytest.skip("Contract tests exercise the per-call script protocol; "
                    "use tcl_bridge_sample.tcl or unset TCL_INTERP to run them")
    if not TCL_BRIDGE_PATH:
        pytest.skip("No Tcl bridge available and tcl_bridge_sample.tcl not found")
    # Verify tclsh is available
    if not shutil.which("tclsh"):
        pytest.skip("tclsh not found on PATH")
    # The real backend bridge requires tkscidb-beta, not plain tclsh.
    if "tcl_bridge_real" in os.path.basename(TCL_BRIDGE_PATH):
        pytest.skip("Contract tests use the per-call sample bridge; "
                    "unset TCL_BRIDGE_PATH or point it to tcl_bridge_sample.tcl")


def _call_bridge(endpoint: str, method: str = "GET", body: dict | None = None) -> dict | list:
    args = ["tclsh", TCL_BRIDGE_PATH, method, endpoint]
    if body is not None:
        args.append(json.dumps(body))
    result = subprocess.run(args, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        pytest.fail(f"Tcl bridge returned exit code {result.returncode}: {result.stderr}")
    return json.loads(result.stdout)


# ---------------------------------------------------------------------------
# Tests: databases
# ---------------------------------------------------------------------------

class TestTclDatabasesContract:
    def test_list_databases(self):
        _skip_if_no_bridge()
        data = _call_bridge("/api/databases")
        assert isinstance(data, list)
        assert len(data) >= 1
        for db in data:
            assert_database_schema(db)


# ---------------------------------------------------------------------------
# Tests: games list
# ---------------------------------------------------------------------------

class TestTclGamesListContract:
    def test_list_games(self):
        _skip_if_no_bridge()
        data = _call_bridge("/api/databases/masters/games")
        assert isinstance(data, list)
        assert len(data) >= 1
        for game in data:
            assert_game_summary_schema(game)


# ---------------------------------------------------------------------------
# Tests: search
# ---------------------------------------------------------------------------

class TestTclSearchContract:
    def test_search(self):
        _skip_if_no_bridge()
        result = _call_bridge("/api/searches", method="POST", body={
            "databaseId": "masters",
            "type": "advanced",
            "query": {},
        })
        assert_search_result_schema(result)

    def test_search_results(self):
        _skip_if_no_bridge()
        result = _call_bridge("/api/searches", method="POST", body={
            "databaseId": "masters",
            "type": "advanced",
            "query": {},
        })
        job_id = result["jobId"]
        data = _call_bridge(f"/api/searches/{job_id}/results")
        assert_search_results_schema(data)


# ---------------------------------------------------------------------------
# Tests: tree
# ---------------------------------------------------------------------------

class TestTclTreeContract:
    def test_tree_query(self):
        _skip_if_no_bridge()
        data = _call_bridge("/api/tree/query", method="POST", body={"moves": []})
        assert isinstance(data, list)
        assert len(data) >= 1
        for move in data:
            assert_tree_move_schema(move)


# ---------------------------------------------------------------------------
# Tests: analysis
# ---------------------------------------------------------------------------

class TestTclAnalysisContract:
    def test_analysis_start(self):
        _skip_if_no_bridge()
        result = _call_bridge("/api/analysis/start", method="POST", body={
            "fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            "multiPv": 3,
            "depth": 5,
        })
        assert_analysis_start_schema(result)

    def test_analysis_job(self):
        _skip_if_no_bridge()
        result = _call_bridge("/api/analysis/start", method="POST", body={
            "fen": "start",
            "multiPv": 2,
            "depth": 3,
        })
        job_id = result["jobId"]
        data = _call_bridge(f"/api/analysis/{job_id}")
        assert_analysis_job_schema(data)


# ---------------------------------------------------------------------------
# Tests: game detail
# ---------------------------------------------------------------------------

class TestTclGameDetailContract:
    def test_game_detail(self):
        _skip_if_no_bridge()
        data = _call_bridge("/api/games/g-001")
        assert_game_detail_schema(data)