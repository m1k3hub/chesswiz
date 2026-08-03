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
| Internet chess play (ICC/Lichess/Chess.com/ChessBase style) | Play center | WebSocket `/play`, `POST /play/match`, `POST /play/move`, `POST /play/resign` |

## First implementation slice

1. Convert `opening-report/` into a TypeScript/Vite app without changing the current report behavior.
2. Introduce a typed `ApiClient` with mock and HTTP implementations.
3. Add a workspace state model: active database, active game, current position/FEN, selected panel, filters, report job.
4. Implement the database rail and game switcher against mock data first.
5. Move board state, notation, opening explorer, report, tactics, and game viewer behind feature modules.
6. Add a runtime adapter endpoint for the existing Python opening-report proxy.
7. Add WebSocket job events for imports, reports, maintenance, and engine analysis.
8. Replace mock providers one capability at a time with C++/Tcl-backed handlers.

## Internet chess server (online play)

Add a live-play capability so scidb-beta can host and join real-time chess games over the internet through the same scid-style board used for analysis — ICC, Lichess, Chess.com, and ChessBase Playchess are the reference UX targets. The board, move entry, clock, and notation must be identical whether the opponent is local, a server bot, or a remote human, so the play experience is a *mode* of the existing board, not a separate widget.

### Scope and game lifecycle

- Supported formats: unlimited/blitz/rapid/bullet correspondence, Chess960, and custom start positions (FEN/PGN seed).
- Match types: casual, ranked/rated, tournament, simul (one player vs. many), and engine-assisted analysis-free rated play.
- Lifecycle: seek/graph challenge → match → play → finish (mate/draw/resign/timeout/disconnect/adjudication) → stored game archived into a scidb database as PGN.

### Architecture

```text
Browser Play Center
  ├─ scid-style ChessBoard (shared with analysis mode)
  ├─ Move/clock/offer controller
  ├─ Seek graph + challenge list + game list
  └─ WebSocket play channel
       │
  ├─ Play service (WebSocket /play)
  │    ├─ matchmaker, rating, seek graph, challenge/accept
  │    ├─ move validation (server-authoritative), clock, offers
  │    ├─ anti-cheat (move-time heuristics, engine-detection hooks)
  │    └─ game archival → PGN → scidb database
  │
  └─ Optional federation bridge
       ├─ ICC/Lichess/Chess.com API + OAuth (play-through proxy)
       └─ Playchess/ChessBase network connector
```

Server is the source of truth for move legality, clocks, and results; the client is a thin renderer that submits intents and renders streamed state. Reconnect and resync after dropped WebSocket is required.

### Board integration rules

- The Play Center reuses `features/board/ChessBoard` and the scid move-entry path (click-click, drag, SAN/UCI entry). No board fork.
- A `playMode` flag on workspace state switches the board from analysis mode (free move, takeback, engine) to play mode (only legal moves, no takeback, clock running, engine disabled in rated games).
- Arrows, highlights, and last-move markers behave the same as analysis mode; promotion, draw offers, resign, and rematch are first-class board-adjacent controls.
- Clocks render beside the board and in the notation rail; flag-fall ends the game.
- Game chat (optional), watchers/spectators, and PV-less eval-only spectator mode for rated games.

### API and events

- `POST /play/seek` — create a seek (time control, variant, rated, color, rating range).
- `POST /play/challenge/:user` — direct challenge.
- `POST /play/match/:id/accept|decline` — accept/decline.
- `POST /play/match/:id/move` — submit a move (UCI/SAN); server validates and broadcasts.
- `POST /play/match/:id/offer` — draw/abort/rematch/takeback (casual only) offers.
- `POST /play/match/:id/resign` — resign.
- WebSocket `/play` — match updates, opponent moves, clock ticks, offers, chat, and terminal events (checkmate, stalemate, draw, flag, disconnect, adjudication).
- `POST /play/match/:id/archive` — store finished game as PGN into a chosen scidb database.
- Federation bridge: `POST /federations/:provider/connect` (OAuth handshake), `GET /federations/:provider/seeks`, `POST /federations/:provider/play` — proxy games through a configured external server when enabled.

### Rating, pairing, and integrity

- Glicko-2 per format and variant; provisional games; rating floors/ceilings configurable.
- Matchmaker pools by time control, variant, rating band, and seek freshness; tournament brackets supported.
- Anti-cheat: server-side move-time and blur-loss heuristics, optional Stockfish-correlation screening for rated games, and a review queue with adjudicator actions.
- Disconnect handling: grace window (configurable per time control), auto-flag/resign on timeout, and resync on reconnect using match state snapshot.
- Fair-play: no engine assistance in rated games (engine inspector disabled in `playMode` rated), move premove/lag compensation, and abort/adjourn rules.

### Security and operational rules (online play)

- WebSocket auth via the same OIDC session token; per-match authorization enforced server-side.
- Rate-limit seeks, challenges, and moves; per-user concurrent game cap.
- Clocks are server-authoritative; never trust client clock values for results.
- Sanitize chat; optional per-match chat disable and reporting.
- Audit moves, offers, disconnects, and adjudications; archive all rated games.
- Isolate federation bridges behind separate OAuth credentials and per-provider rate limits; never proxy untrusted game state into the scidb runtime without validation.

### Federation (optional) bridge

The first release ships scidb-native play. Federation bridges to ICC, Lichess, Chess.com, and Playchess are optional, gated behind provider OAuth and admin approval, and treated as untrusted input — moves from external servers are validated against the scidb rules engine before rendering or archiving.

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
6. **Online play (scidb-native):** Play Center, scid-style board in play mode, seek graph, match lifecycle, server-authoritative clocks/moves, Glicko-2, anti-cheat, game archival to PGN.
7. **Federation (optional):** ICC/Lichess/Chess.com/Playchess OAuth bridges behind admin approval; treated as untrusted input.
8. **Production hardening:** auth, quotas, observability, object storage, AWS/Cloudflare deployment manifests, browser and adapter contract tests.

## Definition of done for the first release

- A user can upload/open a database, browse games, open a game on the board, edit a variation, search by player/position/material, inspect the opening tree, generate an opening report, and export PGN from a browser.
- A user can create a seek, accept a challenge, play a real-time game (including Chess960) on the same scid-style board used for analysis, with server-authoritative clocks and move legality, and archive the finished game as PGN into a scidb database.
- Federation bridges to external servers (when enabled) let a user connect an external account and play through scidb-beta, with external game state validated before rendering or archiving.
- Long-running work has visible progress, cancellation, and retry states.
- The frontend can run against mock data, the opening-report proxy, or the production runtime adapter through environment configuration.
- The same Dockerized API/runtime contract can be deployed on AWS, while the SPA can be served from either AWS CloudFront/S3 or Cloudflare Pages.
