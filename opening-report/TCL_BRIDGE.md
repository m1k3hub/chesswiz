# Tcl Bridge

The Tcl bridge connects the scidb-beta runtime adapter to the existing scidb
Tcl command layer during the migration to a native C++ backend.

## Overview

```text
  Browser SPA  →  runtime_adapter.py  →  tcl_bridge.py  →  tcl_bridge_real.tcl  →  tkscidb-beta
```

When `TCL_BRIDGE_PATH` is set, the runtime adapter routes database, game,
search, tree, and analysis endpoints through the Tcl bridge. If the bridge is
unavailable or returns an error, each endpoint falls back to in-memory mock
data so the UI keeps working during development.

Two bridge implementations are included:

* **`tcl_bridge_sample.tcl`** — pure-Tcl mock data (no backend needed). Useful
  for frontend development and contract tests.
* **`tcl_bridge_real.tcl`** — talks to the real scidb C++/Tcl backend via the
  compiled `tkscidb-beta` interpreter. Requires a built scidb binary.

## Persistent interpreter mode (real backend)

Set three environment variables:

```bash
export TCL_INTERP=/home/michael-g-thomas/src/chess/scidb-code.codex/src/tkscidb-beta
export TCL_BRIDGE_PATH=/home/michael-g-thomas/src/chess/scidb-code.codex/opening-report/tcl_bridge_real.tcl
export SCIDB_DATABASE=/path/to/your/database.pgn
```

`TCL_INTERP` must point to the compiled scidb Tcl interpreter
(`src/tkscidb-beta` after running `make -C src tkscidb-only`).
`SCIDB_DATABASE` is the database that will be opened automatically.
Supported formats: `.pgn`, `.gz`, `.zip`, `.sci`, `.si3`, `.si4`.

`tcl_bridge_real.tcl` also needs the scidb **ECO file** (`eco.bin`) for the
native opening-tree integration. It is searched in this order:

1. `$SCIDB_ECO_PATH` (explicit override)
2. `$SCIDB_SHAREDIR/data/eco.bin`
3. `<TCL_INTERP>/../share/scidb-beta/data/eco.bin`
4. `/usr/local/share/scidb-beta/data/eco.bin`
5. `/usr/share/scidb-beta/data/eco.bin`
6. `<TCL_INTERP>/data/eco.bin` (development source-tree layout)

If the ECO file cannot be found, the bridge still works for databases, games,
and searches, but opening-tree queries fall back to the adapter's mock data.

Start the adapter:

```bash
python3 runtime_adapter.py
```

Verify the backend connection:

```bash
curl http://127.0.0.1:5001/api/health
# expect: {"status":"ok", ..., "tclBridge":"active"}

curl http://127.0.0.1:5001/api/databases
curl http://127.0.0.1:5001/api/databases/sample/games
curl http://127.0.0.1:5001/api/games/g-1
```

## Per-call script mode (sample / legacy)

The bridge can also be invoked once per request:

```bash
tclsh <bridge_path> <METHOD> <ENDPOINT> [JSON_BODY]
```

### Examples

```bash
# List databases
export TCL_BRIDGE_PATH=./tcl_bridge_sample.tcl
tclsh $TCL_BRIDGE_PATH GET /api/databases

# List games in a database
tclsh $TCL_BRIDGE_PATH GET /api/databases/masters/games

# Get a single game
tclsh $TCL_BRIDGE_PATH GET /api/games/g-001

# Run a search
tclsh $TCL_BRIDGE_PATH POST /api/searches '{"type":"advanced","query":{"white":"carlsen"}}'

# Query the opening tree
tclsh $TCL_BRIDGE_PATH POST /api/tree/query '{"moves":[]}'

# Start analysis
tclsh $TCL_BRIDGE_PATH POST /api/analysis/start '{"fen":"start","multiPv":3,"depth":20}'
```

### Response contract

The bridge must print exactly one JSON value to stdout and exit with code 0
on success. On failure, it should exit with a non-zero code (the adapter treats
this as an error and falls back to mock data).

The JSON schemas match those documented in `ADAPTER_CONTRACT.md`.

## Configuration

| Variable | Purpose |
|---|---|
| `TCL_BRIDGE_PATH` | Path to the Tcl bridge script (`tcl_bridge_sample.tcl` or `tcl_bridge_real.tcl`) |
| `TCL_INTERP` | Path to the compiled scidb Tcl interpreter (`tkscidb-beta`) for persistent mode |
| `SCIDB_DATABASE` | Default database to open at startup (used by `tcl_bridge_real.tcl`) |
| `SCIDB_ECO_PATH` | Optional explicit path to `eco.bin` for native opening-tree support |
| `SCIDB_SHAREDIR` | Optional scidb share directory; `data/eco.bin` is loaded from it |

When `TCL_INTERP` is set together with `TCL_BRIDGE_PATH`, the adapter spawns
the interpreter once and keeps it alive for fast JSON-line RPC.
When only `TCL_BRIDGE_PATH` is set, the adapter falls back to the one-shot
subprocess protocol.
When neither is set, the adapter uses mock data exclusively.

## Health check

The `/api/health` endpoint reports whether the Tcl bridge is active:

```json
{
  "status": "ok",
  "version": "0.1.0",
  "tclBridge": "active"
}
```

## Sample bridge

`tcl_bridge_sample.tcl` is a pure-Tcl implementation that returns hardcoded
sample data. It includes a minimal JSON encoder and parser (no external Tcl
packages required) so it runs with any `tclsh` 8.6+.

## Real backend bridge

`tcl_bridge_real.tcl` is loaded by `tkscidb-beta` and uses the actual scidb
Tcl command layer (`::scidb::db::*`, `::scidb::view::*`, `::scidb::game::*`).
It currently implements:

* listing/opening databases (`/api/databases`)
* listing games (`/api/databases/:id/games`)
* fetching a single game with PGN/moves (`/api/games/:id`)
* advanced/material/rating/CQL searches (`/api/searches`, `/api/searches/:id/results`)
* opening-tree via `::scidb::tree::*` for **any position** (`POST /api/tree/query`)
* workspace state (`/api/workspace`)

For the opening tree, `tcl_bridge_real.tcl` loads the ECO file at startup,
replays the requested move list on a scratch game slot, runs
`::scidb::tree::update`/`finish`/`fetch`, and converts the rows into
`OpeningMove[]`.  If the ECO file is missing or the native query errors, the
endpoint returns `{"__scidb_fallback": true}` so the adapter serves its mock
tree data.

## Tests

```bash
# Bridge client tests
pytest tests/test_tcl_bridge.py -v

# Contract tests (use the sample bridge automatically)
pytest tests/test_tcl_bridge_contract.py -v

# To test against the real backend bridge:
TCL_INTERP=/path/to/src/tkscidb-beta \
TCL_BRIDGE_PATH=./tcl_bridge_real.tcl \
SCIDB_DATABASE=/path/to/db.pgn \
pytest tests/test_tcl_bridge_contract.py -v
```
