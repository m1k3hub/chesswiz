# scidb-beta Adapter Contract

This document defines the JSON schema contract between the web frontend and
the runtime adapter (or any backend that implements the same API, such as the
Tcl bridge or a future native C++ bridge). Both `tests/test_adapter_contract.py`
and `tests/test_tcl_bridge_contract.py` validate these schemas.

## Endpoints

### GET /api/databases

Returns an array of `Database` objects.

```json
[
  {
    "id": "masters",
    "name": "Master Games",
    "format": "SCI",
    "games": 2400000,
    "readOnly": true
  }
]
```

**Database schema:**

| Field      | Type    | Required | Description                        |
|------------|---------|----------|------------------------------------|
| `id`       | string  | yes      | Opaque database identifier         |
| `name`     | string  | yes      | Human-readable name                |
| `format`   | string  | yes      | `SCI`, `SI3`, `CBH`, `CBV`, `PGN`  |
| `games`    | integer | yes      | Total game count                   |
| `readOnly` | boolean | yes      | Whether the database is read-only |

### POST /api/databases

Creates a new database. Request body:

```json
{ "name": "My DB", "format": "PGN", "games": 0, "readOnly": false }
```

Returns a `Database` object (with a generated `id`).

### GET /api/databases/:id/games

Returns an array of `GameSummary` objects.

**GameSummary schema:**

| Field       | Type    | Required | Description              |
|-------------|---------|----------|--------------------------|
| `id`        | string  | yes      | Opaque game identifier   |
| `white`     | string  | yes      | White player name         |
| `whiteElo`  | integer | yes      | White Elo rating          |
| `black`     | string  | yes      | Black player name         |
| `blackElo`  | integer | yes      | Black Elo rating          |
| `event`     | string  | yes      | Event name                |
| `site`      | string  | yes      | Site/location             |
| `date`      | string  | yes      | `YYYY.MM.DD` format       |
| `result`    | string  | yes      | `1-0`, `0-1`, `½–½`, `*` |
| `eco`       | string  | yes      | ECO classification code   |

### POST /api/searches

Submits a search. Request body:

```json
{
  "databaseId": "masters",
  "type": "advanced",
  "query": { "white": "carlsen" }
}
```

Returns a search job reference:

```json
{ "jobId": "search-abc123", "status": "complete", "total": 1 }
```

| Field    | Type    | Required | Description                                      |
|----------|---------|----------|--------------------------------------------------|
| `jobId`  | string  | yes      | Search job identifier                            |
| `status` | string  | yes      | `pending`, `running`, `complete`, `error`, `cancelled`, `stopped` |
| `total`  | integer | yes      | Number of matching games                         |

### GET /api/searches/:id/results

Returns the results of a completed search.

```json
{
  "jobId": "search-abc123",
  "status": "complete",
  "total": 1,
  "games": [ { "id": "g-001", "white": "Carlsen, Magnus", ... } ],
  "query": { ... }
}
```

### POST /api/tree/query

Returns the opening tree for a position.

```json
[
  {
    "san": "d4",
    "uci": "d2d4",
    "games": 126420,
    "score": 52.8,
    "white": 37,
    "draw": 42,
    "black": 21,
    "eco": "A45"
  }
]
```

**OpeningMove schema:**

| Field   | Type           | Required | Description              |
|---------|----------------|----------|--------------------------|
| `san`   | string         | yes      | SAN move notation        |
| `uci`   | string         | yes      | UCI move notation        |
| `games` | integer        | yes      | Game count for this move |
| `score` | number         | yes      | Score percentage         |
| `white` | integer        | yes      | White wins               |
| `draw`  | integer        | yes      | Draws                    |
| `black` | integer        | yes      | Black wins               |
| `eco`   | string         | yes      | ECO code                 |

### POST /api/analysis/start

Starts engine analysis. Request body:

```json
{ "fen": "rnbqkbnr/...", "multiPv": 3, "depth": 20 }
```

Returns:

```json
{ "jobId": "analysis-abc123", "status": "running" }
```

### GET /api/analysis/:id

Returns the current analysis state.

```json
{
  "jobId": "analysis-abc123",
  "status": "running",
  "fen": "rnbqkbnr/...",
  "depth": 15,
  "multiPv": 3,
  "lines": [
    { "pv": "e2e4 e7e5", "eval": "+0.35", "depth": 15 }
  ],
  "nodes": 18000000,
  "nps": 1200000
}
```

**AnalysisJob schema:**

| Field     | Type    | Required | Description                                      |
|-----------|---------|----------|--------------------------------------------------|
| `jobId`   | string  | yes      | Analysis job identifier                          |
| `status`  | string  | yes      | `pending`, `running`, `complete`, `stopped`, `unknown` |
| `fen`     | string  | yes      | Current FEN                                      |
| `depth`   | integer | yes      | Current search depth                             |
| `multiPv` | integer | yes      | Number of PV lines                                |
| `lines`   | array   | yes      | Array of AnalysisLine                            |
| `nodes`   | integer | yes      | Nodes searched                                   |
| `nps`     | integer | yes      | Nodes per second                                 |

**AnalysisLine schema:**

| Field   | Type    | Required | Description         |
|---------|---------|----------|---------------------|
| `pv`    | string  | yes      | Principal variation |
| `eval`  | string  | yes      | Evaluation string   |
| `depth` | integer | yes      | Depth of this line  |

### GET /api/games/:id

Returns the full detail of a single game.

```json
{
  "id": "g-001",
  "headers": { "White": "Carlsen, Magnus", "Black": "Nepomniachtchi, Ian", ... },
  "moves": [
    {
      "id": "m-1",
      "san": "e4",
      "uci": "e2e4",
      "fen": "rnbqkbnr/...",
      "color": "w",
      "ply": 1,
      "nags": [],
      "annotations": [],
      "variations": []
    }
  ],
  "pgn": "[Event \"...\"]\n..."
}
```

**GameDetail schema:**

| Field     | Type   | Required | Description                |
|-----------|--------|----------|----------------------------|
| `id`      | string | yes      | Game identifier            |
| `headers` | object | yes      | PGN header tags            |
| `moves`   | array  | yes      | Array of EditorMove        |
| `pgn`     | string | yes      | Full PGN text              |

**EditorMove schema:**

| Field        | Type    | Required | Description                |
|--------------|---------|----------|----------------------------|
| `id`         | string  | yes      | Move identifier            |
| `san`        | string  | yes      | SAN notation               |
| `uci`        | string  | yes      | UCI notation               |
| `fen`        | string  | yes      | FEN after this move       |
| `color`      | string  | yes      | `w` or `b`                 |
| `ply`       | integer | yes      | Half-move number           |
| `nags`      | array   | yes      | NAG codes                  |
| `annotations` | array | yes      | Annotations                |
| `variations`  | array | yes      | Sub-variations             |

## WebSocket endpoints

### /api/ws/events

Streams job progress events as JSON objects:

```json
{
  "type": "job.progress",
  "jobId": "import-abc123",
  "jobType": "import",
  "progress": 50,
  "total": 100,
  "timestamp": 1234567890.123
}
```

### /api/ws/analysis/:jobId

Streams analysis updates for a specific job:

```json
{
  "type": "analysis.update",
  "jobId": "analysis-abc123",
  "status": "running",
  "depth": 15,
  ...
}
```

## Running the contract tests

### Runtime adapter tests

```bash
pip install -r requirements.txt
pytest tests/test_adapter_contract.py -v
```

### Tcl bridge tests (when a bridge is available)

```bash
TCL_BRIDGE_PATH=/path/to/tcl_bridge pytest tests/test_tcl_bridge_contract.py -v
```

If `TCL_BRIDGE_PATH` is not set or the executable is not found, all Tcl bridge
tests are skipped.