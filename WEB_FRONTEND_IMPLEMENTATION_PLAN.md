# scidb-beta Web Frontend — Implementation Plan

## Product direction

Build a cloud-ready chess database studio with the information density and working rhythm of ChessBase 26: a persistent command bar, database/library rail, board-centered analysis workspace, synchronized notation and move tree, and context inspectors instead of a marketing dashboard.

The existing `opening-report/` app is the first vertical slice. It already provides board navigation, FEN loading, opening explorer data, report generation, tactics, game viewing, and PGN-facing API hooks. The new frontend should preserve those behaviors while progressively replacing the static shell with typed API-backed modules.

## Target architecture

```text
Browser SPA / PWA
  ├─ Workspace shell (library, command bar, panels)
  ├─ Board + move tree + annotations
  ├─ Search / switcher / reports / player tools
  └─ API client + WebSocket event stream
       │
       ├─ Web adapter service (REST + WebSocket)
       │    ├─ auth, jobs, uploads, exports
       │    ├─ database/session orchestration
       │    └─ engine worker coordination
       │
       └─ scidb runtime adapter
            ├─ C++ database/library bridge
            ├─ Tcl command bridge during migration
            └─ Stockfish/UCI worker
```

Recommended frontend: TypeScript + React + Vite, with a small state layer (Zustand or equivalent), `chess.js` for client legality, and a dedicated board renderer that supports arrows, colored squares, Chess960, and piece themes. Keep the API boundary independent of the UI so the runtime can be hosted beside the app on AWS or Cloudflare.

## Capability-to-screen map

| scidb-beta capability | Web module | Core API surface |
|---|---|---|
| Open/create/close, `.sci`, `.si3`, `.cbh`, `.cbv`, PGN | Database manager | `GET/POST /databases`, `POST /databases/:id/import`, `POST /databases/:id/convert` |
| Paginated sortable game table | Game switcher | `GET /databases/:id/games` |
| PGN edit, variations, comments, marks, flags | Game editor | `GET/PATCH /games/:id`, `POST /games/:id/variations` |
| Advanced/material/rating/CQL search | Search center | `POST /searches`, `GET /searches/:id/results` |
| Working sets and switcher promotion | Working sets | `POST /working-sets`, `POST /working-sets/:id/promote` |
| Opening tree, W/D/L, ECO, reference DB | Opening tree | `POST /tree/query`, `GET /tree/:position` |
| Opening prep and repertoire | Repertoire studio | `GET /repertoires`, `POST /prep/reports` |
| Player dictionary, cards, opponent prep | Player center | `GET /players`, `GET /players/:id/card`, `POST /players/:id/prep` |
| Duplicate detection, ECO stats, compaction, strip | Maintenance | `POST /maintenance/jobs`, `GET /maintenance/reports/:id` |
| Tournament crosstables | Crosstable | `POST /crosstables/query` |
| UCI engine, PVs, eval, tablebases | Analysis inspector | WebSocket `/analysis`, `POST /engines/:id/start` |
| Namebases and ECO table | Index browser | `GET /indexes/:type`, `GET /eco` |
| Import/export progress | Job center | `GET /jobs/:id`, WebSocket `/events` |

## First implementation slice

1. Convert `opening-report/` into a TypeScript/Vite app without changing the current report behavior.
2. Introduce a typed `ApiClient` with mock and HTTP implementations.
3. Add a workspace state model: active database, active game, current position/FEN, selected panel, filters, report job.
4. Implement the database rail and game switcher against mock data first.
5. Move board state, notation, opening explorer, report, tactics, and game viewer behind feature modules.
6. Add a runtime adapter endpoint for the existing Python opening-report proxy.
7. Add WebSocket job events for imports, reports, maintenance, and engine analysis.
8. Replace mock providers one capability at a time with C++/Tcl-backed handlers.

## API and runtime rules

- Every long-running operation returns a job ID and streams progress.
- Use opaque database/game identifiers; never expose filesystem paths to browsers.
- Keep PGN import/export streaming and size-limited.
- Return normalized chess data: FEN, SAN, UCI, ply, variations, comments, NAGs, and annotations.
- Make search requests cancellable and paginated.
- Keep engine processes isolated per workspace with CPU, memory, and time limits.
- Add an adapter contract test suite so the Tcl bridge and future native C++ bridge return the same JSON.

## Deployment

### AWS

- CloudFront + S3 for the SPA.
- ECS/Fargate or App Runner for the API adapter.
- EFS or S3 for database files and import artifacts.
- SQS + ECS workers for imports, reports, maintenance, and exports.
- ElastiCache/Redis for job events and short-lived workspace state.
- RDS/PostgreSQL for users, metadata, permissions, and jobs.

### Cloudflare

- Pages for the SPA.
- Workers for API routing/auth and Durable Objects for workspace sessions/WebSockets.
- R2 for database files and exports.
- Queues for background jobs.
- A container host (Cloud Run, Fly.io, ECS, or a dedicated VM) for the native scidb runtime and Stockfish; Workers should not execute the C++/Tcl runtime directly.

### Both

Keep the frontend static and the API contract portable. Package the runtime adapter as a container with health checks, an object-storage abstraction, and an event-bus abstraction. This makes AWS the simplest full-stack target while Cloudflare remains a good edge/frontend layer.

## Security and operations

- OIDC login, workspace-scoped authorization, signed upload URLs, and short-lived export URLs.
- Validate PGN/FEN/CQL inputs server-side; sanitize comments before rendering HTML.
- Quotas for file size, concurrent jobs, engine time, and database storage.
- Audit imports, exports, deletes, maintenance, and sharing actions.
- Metrics: API latency, search duration, job queue depth, engine CPU, database size, and failed adapter calls.
- Backups and checksum validation for database artifacts.

## Milestones

1. **Workspace foundation:** shell, board, notation, FEN, current opening-report behavior, mock API.
2. **Database and games:** database manager, import/export jobs, sortable game switcher, game editor.
3. **Search and tree:** advanced/material/rating/CQL search, working sets, opening tree.
4. **Preparation:** repertoire, opening prep, player cards, opponent dossiers.
5. **Analysis and maintenance:** UCI engine, crosstables, duplicates, ECO stats, compaction.
6. **Production hardening:** auth, quotas, observability, object storage, AWS/Cloudflare deployment manifests, browser and adapter contract tests.

## Definition of done for the first release

- A user can upload/open a database, browse games, open a game on the board, edit a variation, search by player/position/material, inspect the opening tree, generate an opening report, and export PGN from a browser.
- Long-running work has visible progress, cancellation, and retry states.
- The frontend can run against mock data, the opening-report proxy, or the production runtime adapter through environment configuration.
- The same Dockerized API/runtime contract can be deployed on AWS, while the SPA can be served from either AWS CloudFront/S3 or Cloudflare Pages.
