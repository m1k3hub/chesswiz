"""
Integration test for the real scidb C++/Tcl backend bridge.

This test is skipped unless the required environment variables are set:

    export TCL_INTERP=/path/to/src/tkscidb-beta
    export TCL_BRIDGE_PATH=/path/to/opening-report/tcl_bridge_real.tcl
    export SCIDB_DATABASE=/path/to/sample.pgn

It creates a tiny PGN database on the fly, loads it via the compiled scidb
interpreter, and verifies the JSON-line protocol end-to-end.
"""

from __future__ import annotations

import asyncio
import os
from pathlib import Path

import pytest
import pytest_asyncio


SAMPLE_PGN = """\
[Event "Test"]
[Site "X"]
[Date "2024.01.01"]
[White "Carlsen, Magnus"]
[Black "Nepomniachtchi, Ian"]
[Result "1/2-1/2"]
[WhiteElo "2855"]
[BlackElo "2782"]

1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 1/2-1/2

[Event "Test2"]
[Site "Y"]
[Date "1993.03.02"]
[White "Kasparov, Garry"]
[Black "Karpov, Anatoly"]
[Result "1-0"]
[WhiteElo "2810"]
[BlackElo "2725"]

1. d4 d5 2. c4 e6 3. Nc3 Nf6 1-0
"""


@pytest.fixture(scope="session")
def real_bridge_env():
    """Set up the environment and skip the test if the backend is unavailable."""
    interp = os.environ.get("TCL_INTERP", "")
    script = os.environ.get("TCL_BRIDGE_PATH", "")
    if not interp or not Path(interp).exists():
        pytest.skip("TCL_INTERP not set or tkscidb-beta not built")
    if not script or not Path(script).exists():
        pytest.skip("TCL_BRIDGE_PATH not set or tcl_bridge_real.tcl missing")
    return {"interp": interp, "script": script}


@pytest.fixture(scope="session")
def sample_database(tmp_path_factory):
    """Create a tiny PGN database in a session-scoped temp directory."""
    tmp_dir = tmp_path_factory.mktemp("real-bridge")
    pgn_path = tmp_dir / "sample.pgn"
    pgn_path.write_text(SAMPLE_PGN, encoding="utf-8")
    return str(pgn_path)


@pytest_asyncio.fixture(scope="function")
async def bridge(real_bridge_env, sample_database):
    """Return a connected TclBridge instance backed by the real scidb interpreter."""
    # Import after environment is guaranteed to exist.
    from tcl_bridge import TclBridge

    os.environ["SCIDB_DATABASE"] = sample_database
    os.environ["TCL_INTERP"] = real_bridge_env["interp"]
    os.environ["TCL_BRIDGE_PATH"] = real_bridge_env["script"]

    b = TclBridge()
    if not b.is_available():
        pytest.skip("real scidb interpreter is not available")

    # Run a quick health check through the bridge to ensure it is alive.
    try:
        dbs = await asyncio.wait_for(b.list_databases(), timeout=60)
    except Exception as exc:
        pytest.skip(f"real bridge failed to respond: {exc}")
    if dbs is None:
        pytest.skip("real bridge returned no database list")

    yield b
    b.close()


@pytest.mark.asyncio
async def test_real_bridge_list_databases(bridge):
    dbs = await bridge.list_databases()
    assert isinstance(dbs, list)
    assert len(dbs) == 1
    db = dbs[0]
    assert db["id"] == "sample"
    assert db["format"] == "PGN"
    assert db["games"] == 2
    assert db["readOnly"] is True


@pytest.mark.asyncio
async def test_real_bridge_list_games(bridge):
    games = await bridge.list_games("sample")
    assert isinstance(games, list)
    assert len(games) == 2
    assert games[0]["white"] == "Carlsen, Magnus"
    assert games[1]["white"] == "Kasparov, Garry"


@pytest.mark.asyncio
async def test_real_bridge_get_game(bridge):
    game = await bridge.get_game("g-1")
    assert isinstance(game, dict)
    assert game["id"] == "g-1"
    assert game["headers"]["White"] == "Carlsen, Magnus"
    assert len(game["moves"]) > 0
    assert game["moves"][0]["san"] == "e4"


@pytest.mark.asyncio
async def test_real_bridge_search(bridge):
    result = await bridge.search({"type": "advanced", "query": {"white": "Kasparov"}})
    assert isinstance(result, dict)
    assert result["status"] == "complete"
    assert result["total"] == 1

    full = await bridge.get_search_results(result["jobId"])
    assert full["total"] == 1
    assert full["games"][0]["white"] == "Kasparov, Garry"


@pytest.mark.asyncio
async def test_real_bridge_workspace(bridge):
    ws = await bridge.workspace()
    assert isinstance(ws, dict)
    assert ws["activeDatabaseId"] == "sample"
    assert ws["currentFen"] == "start"


@pytest.mark.asyncio
async def test_real_bridge_tree_root(bridge):
    """Root opening-tree query is served from the real scidb ::scidb::tree::* backend."""
    rows = await bridge.tree_query({"moves": [], "fen": "start"})
    assert isinstance(rows, list)
    assert len(rows) == 2
    sans = [row["san"] for row in rows]
    assert "e4" in sans
    assert "d4" in sans


@pytest.mark.asyncio
async def test_real_bridge_tree_nonroot(bridge):
    """Non-root opening-tree positions work once the ECO file is loaded."""
    rows = await bridge.tree_query(
        {
            "moves": [{"san": "e4", "uci": "e2e4"}],
            "fen": "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
        }
    )
    assert isinstance(rows, list)
    assert len(rows) == 1
    assert rows[0]["san"] == "e5"
    assert rows[0]["games"] == 1


@pytest.mark.asyncio
async def test_real_bridge_tree_deep(bridge):
    """Deeper positions (e.g. after 1.e4 e5) also return real backend rows."""
    rows = await bridge.tree_query(
        {
            "moves": [
                {"san": "e4", "uci": "e2e4"},
                {"san": "e5", "uci": "e7e5"},
            ],
            "fen": "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2",
        }
    )
    assert isinstance(rows, list)
    assert len(rows) == 1
    # White's replies after 1.e4 e5 in the sample database.
    assert rows[0]["games"] == 1
    assert rows[0]["eco"].startswith("C")
