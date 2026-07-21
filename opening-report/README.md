# scidb-beta Web Frontend — Opening Report

A ChessBase 26-style opening report web application being migrated to a
TypeScript + React + Vite foundation while preserving the existing report
behavior.

## Quick start

```bash
cd opening-report
npm install
npm run dev        # http://localhost:8765 (or next free port)
```

The frontend falls back to its built-in mock API client when no backend is
running. To use the full REST + WebSocket adapter:

```bash
pip install -r requirements.txt
python3 runtime_adapter.py    # http://localhost:5001
```

Or with Docker:

```bash
docker compose up --build     # http://localhost:5001
```

The Vite dev server proxies `/api` to `http://localhost:5001` automatically
(see `vite.config.ts`).

## Scripts

| Script | Purpose |
|--------|---------|
| `npm run dev` | Vite dev server with HMR |
| `npm run build` | Production build into `dist/` |
| `npm run preview` | Preview the production build |
| `npm run lint` | ESLint over `.ts` / `.tsx` |
| `pytest tests/` | Python contract tests for the runtime adapter |
| `npm run test:e2e` | Playwright browser tests (requires `npx playwright install`) |
| `python3 runtime_adapter.py` | FastAPI runtime adapter (REST + WebSocket) on :5001 |
| `alembic upgrade head` | Run database migrations when DATABASE_URL is set |

## Runtime adapter

`runtime_adapter.py` is a FastAPI application that provides:

- **Lichess proxy** (integrated into the runtime adapter):
  - `GET /api/explorer/masters`, `GET /api/explorer/lichess`
  - `GET /api/game/{gameId}` (PGN export)
  - `GET /api/opening?play=...`

- **Mock REST API** (matching the frontend contract):
  - `GET /api/databases`, `POST /api/databases`, `GET /api/databases/{id}/games`
  - `POST /api/searches`, `GET /api/searches/{id}/results`, `DELETE /api/searches/{id}`
  - `GET /api/games/{id}`, `PATCH /api/games/{id}`, `POST /api/games/{id}/variations`
  - `POST /api/tree/query`
  - `GET /api/indexes/{type}`, `GET /api/eco`
  - `GET /api/repertoires`, `POST /api/prep/reports`
  - `GET /api/players`, `GET /api/players/{id}/card`, `POST /api/players/{id}/prep`
  - `POST /api/maintenance/jobs`, `GET /api/maintenance/reports/{id}`
  - `POST /api/crosstables/query`
  - `POST /api/analysis/start`, `GET /api/analysis/{id}`, `POST /api/analysis/{id}/stop`
  - `GET /api/workspace`, `GET /api/jobs/{id}`, `GET /api/health`

- **WebSocket endpoints**:
  - `/api/ws/events` — streams job progress events
  - `/api/ws/analysis/{job_id}` — streams engine analysis updates

- **Engine integration**:
  - `GET /api/engines` — list available UCI engines
  - `POST /api/analysis/start` accepts `engineId` and runs the selected engine
  - Place a Stockfish binary in `engines/stockfish/stockfish` or set `STOCKFISH_PATH`
  - Falls back to mock simulation when no engine binary is found

- **Tcl bridge integration**:
  - Set `TCL_BRIDGE_PATH` to a Tcl script/executable that speaks the JSON command protocol
  - Set `TCL_INTERP` to `src/tkscidb-beta` and `SCIDB_DATABASE` to a real `.pgn`/`.sci` file to use the actual scidb C++/Tcl backend via `tcl_bridge_real.tcl`
  - See `TCL_BRIDGE.md` for the command protocol and `tcl_bridge_sample.tcl` for a pure-Tcl example
  - When the bridge is unavailable, the adapter serves mock data

- **Persistence backends** (all optional; adapter uses in-memory defaults when unset):
  - `REDIS_URL` — job state, analysis state, rate limiting, event pub/sub
  - `DATABASE_URL` — PostgreSQL metadata, databases, games, users, audit logs
  - `S3_BUCKET`/`S3_ENDPOINT`/`S3_KEY`/`S3_SECRET` — object storage for import/export files
  - `DATA_DIR` — local disk fallback for file storage

- **Auth**:
  - Dummy/dev JWT validation when OIDC env vars are unset
  - Real RS256 OIDC JWT validation with `OIDC_ISSUER`, `OIDC_AUDIENCE`, `OIDC_JWKS_URI`
  - Optional token introspection with `OIDC_INTROSPECTION_URI`

- **CORS** configured for `http://localhost:8765` and `:8766`.

### Docker

```bash
docker compose up --build      # builds and runs on :5001
docker compose down            # stop
```

The Dockerfile uses `python:3.13-slim`, installs `requirements.txt`, and runs
uvicorn with a health check on `/api/health`.

### Contract tests

```bash
pytest tests/ -v
```

Tests cover databases, searches, analysis, tree, workspace, jobs, health,
import/convert, auth, validation, rate limiting, audit logging, store backends,
Tcl bridge contract, and adapter schema contracts.

## Migration status

The project is mid-migration from vanilla JS to TypeScript + React + Vite:

- **New stack** (`src/`)
  - `src/api/client.ts` — typed `ScidbApiClient` with HTTP + mock implementations.
  - `src/state/workspace.ts` — Zustand workspace store + legacy global bridge.
  - `src/components/Shell.tsx` — React workspace shell (header, rail, board/report panels).
  - `src/features/` — React feature modules:
    - `board/ChessBoard.tsx` — React chessboard with chess.js move validation.
    - `report/OpeningReport.tsx` + `ReportEngine.ts` — report generator.
    - `engine/EngineInspector.tsx` — UCI engine analysis panel with WebSocket streaming.
    - `database/DatabaseModal.tsx` + `ImportExportPanel.tsx` — database manager and import/export jobs.
    - `games/GameSwitcherModal.tsx` + `GameEditor.tsx` + `GameViewerModal.tsx`
    - `tactics/TacticsModal.tsx`
    - `search/SearchCenterModal.tsx` — advanced/material/rating/CQL search.
    - `tree/OpeningTreeModal.tsx` — position-specific opening tree.
    - `working-sets/WorkingSetsModal.tsx` — saved working sets.
    - `indexes/IndexBrowserModal.tsx` — namebase and ECO browser.
    - `repertoire/RepertoireStudio.tsx` — repertoire and opening prep.
    - `players/PlayerCenter.tsx` — player dictionary, cards, opponent prep.
    - `maintenance/MaintenanceCenter.tsx` — duplicate detection, ECO stats, compaction, strip.
    - `crosstable/CrosstableModal.tsx` — tournament crosstables.
    - `jobs/JobCenter.tsx` — global job progress center.
  - `src/App.tsx` / `src/main.tsx` — React entry point.
  - Unit tests in `src/api/client.test.ts`, `src/state/workspace.test.ts`,
    `src/lib/chess-helpers.test.ts`, `src/lib/validation.test.ts`,
    `src/features/report/report-helpers.test.ts`,
    `src/features/games/game-editor.test.ts`, `src/features/jobs/jobs.test.ts`,
    `src/features/working-sets/working-sets.test.ts`,
    `src/features/search/search-tree.test.ts`,
    `src/features/repertoire/repertoire.test.ts`,
    `src/features/players/player-center.test.ts`,
    `src/features/maintenance/maintenance.test.ts`,
    `src/features/crosstable/crosstable.test.ts`,
    `src/e2e/workspace.e2e.test.tsx`.
  - Backend tests: `tests/test_runtime_adapter.py`,
    `tests/test_adapter_contract.py`, `tests/test_tcl_bridge_contract.py`.

- **Removed legacy artifacts**: `proxy_server.py`, `public/js/`, `public/css/`, and `src/legacy-shell-bridge.ts` have been removed. All UI logic is in `src/`.

## Architecture

```text
opening-report/
├── index.html              # #root + Vite entry (no CDN deps)
├── package.json            # Vite, React, TypeScript, Zustand, oidc-client-ts
├── playwright.config.ts    # Playwright e2e configuration
├── vite.config.ts          # Dev server, /api proxy → :5001, code-splitting
├── tsconfig.json
├── runtime_adapter.py      # FastAPI REST + WebSocket adapter
├── requirements.txt        # Python deps for runtime adapter
├── Dockerfile              # Container for the runtime adapter
├── docker-compose.yml      # Docker Compose for local dev
├── docker-compose.prod.yml # Production Compose with Redis + object storage
├── ADAPTER_CONTRACT.md     # JSON API contract documentation
├── engines/                # UCI engine worker + Stockfish binary placeholder
│   ├── stockfish_worker.py
│   └── stockfish/README.md
├── tests/
│   ├── test_runtime_adapter.py
│   ├── test_adapter_contract.py
│   └── test_tcl_bridge_contract.py
├── infra/                  # AWS + Cloudflare deployment manifests
│   ├── aws/terraform/
│   └── cloudflare/
└── src/
    ├── main.tsx            # React bootstrap + API/workspace globals
    ├── App.tsx             # Renders Shell
    ├── components/         # Shell, Header, DatabaseRail, BoardPanel, ReportPanel, Modals
    ├── features/           # board, report, engine, database, games, search, tree, tactics, working-sets, indexes, repertoire, players, maintenance, crosstable, jobs
    ├── api/                # Typed API client
    ├── state/              # Zustand workspace store
    ├── lib/                # Chess helpers, type declarations
    ├── types/              # Shared domain types
    └── index.css           # Typography + workspace/modal styles
```

## API / runtime boundary

The client talks to the web adapter at `/api`. If the adapter is unavailable,
every call transparently falls back to the in-memory mock client so the UI keeps
working during development.

Environment variable for the build:

```bash
VITE_SCIDB_API_BASE=http://localhost:5001/api npm run build
```

## Notes

- The React feature modules use custom DOM events
  (`scidb:open-database-manager`, `scidb:open-game-switcher`,
  `scidb:open-search-center`, `scidb:open-opening-tree`,
  `scidb:generate-report`, `scidb:open-game-viewer`, `scidb:open-tactics`,
  `scidb:open-working-sets`, `scidb:open-job-center`, `scidb:open-maintenance`,
  `scidb:open-crosstable`, `scidb:open-index-browser`,
  `scidb:open-repertoire-studio`, `scidb:open-player-center`,
  `scidb:open-game-editor`)
  to keep the rail and board decoupled from modal implementations.
- OIDC auth can be enabled with `VITE_ENABLE_AUTH=true`, `VITE_OIDC_AUTHORITY`,
  `VITE_OIDC_CLIENT_ID`, and `VITE_OIDC_REDIRECT_URI`.
- The runtime adapter is a standalone container that can be deployed on
  AWS ECS/Fargate or any container host. The SPA is static and can be served
  from CloudFront/S3 or Cloudflare Pages.

## OIDC authentication

Frontend environment variables:

```bash
VITE_ENABLE_AUTH=true
VITE_OIDC_AUTHORITY=https://your-oidc-provider
VITE_OIDC_CLIENT_ID=your-client-id
VITE_OIDC_REDIRECT_URI=http://localhost:8766/auth/callback
```

Backend environment variables:

```bash
OIDC_ISSUER=https://your-oidc-provider
OIDC_AUDIENCE=your-client-id
OIDC_JWKS_URI=https://your-oidc-provider/.well-known/jwks.json
# Optional:
# OIDC_INTROSPECTION_URI=https://your-oidc-provider/introspect
```

When auth env vars are unset, the frontend shows a local avatar and the backend
accepts a dev-only dummy bearer token for local development.

## Persistence

```bash
# PostgreSQL + Redis + S3/R2 (production)
DATABASE_URL=postgresql+psycopg2://user:pass@localhost/scidb
REDIS_URL=redis://localhost:6379/0
S3_BUCKET=scidb-artifacts
S3_ENDPOINT=https://...r2.cloudflarestorage.com
S3_KEY=...
S3_SECRET=...

# Run migrations
alembic upgrade head

# Or use the production Compose file
docker compose -f docker-compose.prod.yml up --build
```

When persistence env vars are unset, the adapter keeps everything in memory.

## Tcl bridge

The runtime adapter can delegate database/game/search/tree operations to a
scidb Tcl backend via `TCL_BRIDGE_PATH`:

```bash
TCL_BRIDGE_PATH=./tcl_bridge_sample.tcl python3 runtime_adapter.py
```

See `TCL_BRIDGE.md` for the JSON command protocol and endpoint mapping.

## Deployment

See:
- `infra/aws/README.md` — Terraform for CloudFront + S3 + ECS + SQS + Redis + RDS.
- `infra/cloudflare/README.md` — Wrangler config for Pages + Workers + R2 + Queues.
- `docker-compose.prod.yml` — Production Compose with Redis and object-storage env vars.
- `.github/workflows/ci.yml` — CI for lint, typecheck, tests, build, and adapter contract tests.