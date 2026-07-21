"""Tests for the TclBridge client module.

These tests verify that ``tcl_bridge.TclBridge`` correctly:
  - Detects when the bridge is available / unavailable.
  - Calls the bridge subprocess and parses JSON responses.
  - Returns ``None`` on errors (bad exit code, timeout, missing path).
  - Routes each public method to the correct endpoint.

The tests use the bundled ``tcl_bridge_sample.tcl`` so they run without a
real scidb backend.
"""

import asyncio
import os
import json

import pytest

from tcl_bridge import TclBridge

_SAMPLE_BRIDGE = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "tcl_bridge_sample.tcl",
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def bridge(monkeypatch):
    """Return a TclBridge pointed at the sample script."""
    if not os.path.isfile(_SAMPLE_BRIDGE):
        pytest.skip("tcl_bridge_sample.tcl not found")
    # Force per-call script mode; ignore any persistent-backend env vars.
    monkeypatch.delenv("TCL_INTERP", raising=False)
    monkeypatch.delenv("SCIDB_DATABASE", raising=False)
    monkeypatch.delenv("SCI_DATABASE", raising=False)
    monkeypatch.setenv("TCL_BRIDGE_PATH", _SAMPLE_BRIDGE)
    return TclBridge(path=_SAMPLE_BRIDGE, timeout=10)


@pytest.fixture
def disabled_bridge(monkeypatch):
    """Return a TclBridge with no path (disabled)."""
    monkeypatch.delenv("TCL_BRIDGE_PATH", raising=False)
    monkeypatch.delenv("TCL_INTERP", raising=False)
    return TclBridge(path="", timeout=5)


# ---------------------------------------------------------------------------
# Tests: availability
# ---------------------------------------------------------------------------

class TestBridgeAvailability:
    def test_available_when_path_exists(self, bridge):
        assert bridge.is_available() is True

    def test_unavailable_when_path_empty(self, disabled_bridge):
        assert disabled_bridge.is_available() is False

    def test_unavailable_when_path_does_not_exist(self):
        b = TclBridge(path="/nonexistent/path/to/bridge", timeout=5)
        assert b.is_available() is False


# ---------------------------------------------------------------------------
# Tests: endpoint calls
# ---------------------------------------------------------------------------

class TestBridgeCalls:
    def test_list_databases(self, bridge):
        data = asyncio.run(bridge.list_databases())
        assert isinstance(data, list)
        assert len(data) >= 1
        assert data[0]["id"] == "masters"

    def test_list_games(self, bridge):
        data = asyncio.run(bridge.list_games("masters"))
        assert isinstance(data, list)
        assert len(data) >= 1
        assert data[0]["white"] == "Carlsen, Magnus"

    def test_get_game(self, bridge):
        data = asyncio.run(bridge.get_game("g-001"))
        assert data is not None
        assert data["id"] == "g-001"
        assert "headers" in data
        assert "moves" in data
        assert "pgn" in data

    def test_get_game_not_found_returns_error(self, bridge):
        # The sample script exits with code 1 for unknown games.
        data = asyncio.run(bridge.get_game("nonexistent"))
        # _call returns None on non-zero exit code
        assert data is None

    def test_search(self, bridge):
        result = asyncio.run(bridge.search({
            "databaseId": "masters",
            "type": "advanced",
            "query": {"white": "carlsen"},
        }))
        assert result is not None
        assert result["status"] == "complete"
        assert result["total"] == 1

    def test_search_empty_filter(self, bridge):
        result = asyncio.run(bridge.search({
            "databaseId": "masters",
            "type": "advanced",
            "query": {"white": "nonsense"},
        }))
        assert result is not None
        assert result["total"] == 0

    def test_tree_query(self, bridge):
        data = asyncio.run(bridge.tree_query({"moves": []}))
        assert isinstance(data, list)
        assert len(data) >= 1
        assert data[0]["san"] == "d4"

    def test_start_analysis(self, bridge):
        result = asyncio.run(bridge.start_analysis({
            "fen": "start",
            "multiPv": 2,
            "depth": 5,
        }))
        assert result is not None
        assert result["status"] == "running"
        assert "jobId" in result

    def test_workspace(self, bridge):
        data = asyncio.run(bridge.workspace())
        assert data is not None
        assert data["activeDatabaseId"] == "masters"


# ---------------------------------------------------------------------------
# Tests: disabled bridge returns None
# ---------------------------------------------------------------------------

class TestDisabledBridge:
    def test_list_databases_returns_none(self, disabled_bridge):
        assert asyncio.run(disabled_bridge.list_databases()) is None

    def test_list_games_returns_none(self, disabled_bridge):
        assert asyncio.run(disabled_bridge.list_games("masters")) is None

    def test_search_returns_none(self, disabled_bridge):
        assert asyncio.run(disabled_bridge.search({"type": "advanced", "query": {}})) is None

    def test_tree_query_returns_none(self, disabled_bridge):
        assert asyncio.run(disabled_bridge.tree_query({"moves": []})) is None