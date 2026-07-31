# Online Play — Implementation Plan (scidb-beta Web Frontend)

> Detailed, actionable build plan for the internet chess server capability
> described in `WEB_FRONTEND_IMPLEMENTATION_PLAN.md` §"Internet chess server
> (online play)". This document is the engineering breakdown: data model,
> state model, file-by-file changes, server design, protocol, phases with
> exit criteria, tests, and risks.
>
> **In scope for v1:** scidb-native real-time play on the shared board.
> **Out of scope for v1:** federation bridges to ICC/Lichess/Chess.com/Playchess
> (Phase 8, behind admin approval).

## 1. Current state reconciliation

| Concern | Existing asset | Reuse for play |
|---|---|---|
| Board renderer | `src/features/board/ChessBoard.tsx` (chess.js, click-click, `ChessBoardHandle`) | Add a `playMode` prop; **no fork**. |
| State | `src/state/workspace.ts` (Zustand + persist, `window.ScidbWorkspace` bridge) | Add a `play` slice + `activePlayMode` flag. |
| WebSocket | `src/api/websocket.ts` (`ScidbWebSocketClient`, auto-reconnect/backoff) | Add `subscribeToPlay()` helper; new `/api/ws/play` path. |
| API client | `src/api/client.ts` (`ScidbApiClient`, `createApiClient()` mock+HTTP) | Add `play.*` methods to interface + both impls. |
| Auth | `src/api/auth.ts` (bearer token, `ensureFreshToken`), `config.ts` (OIDC opt-in) | Reuse; play requires auth when enabled. |
| Types | `src/types/index.ts` | Add play types. |
| Server | `runtime_adapter.py` (FastAPI, Redis bus, JWT verify, rate limit, engine pool) + `tcl_bridge.py`/`tcl_bridge_real.tcl` (async RPC to scidb C++) | Add `play_service.py` + routes + `/api/ws/play`; add a stateless `position/legal` bridge command for server-side move legality (no python-chess). |
| Job pattern | `JobCenter.tsx` subscribes to `/ws/events`, polls fallback | Play games register as a job-like entity for observability. |

**Nothing needs to be rewritten.** Play is a *mode* of the existing board and a *service* in the existing adapter.

## 2. Data model (canonical JSON)

All chess data normalized per the plan's rules (FEN, SAN, UCI, ply). Clocks are **server-authoritative**; clients never submit clock values for results.

### 2.1 Frontend types (`src/types/index.ts`, new `Play` namespace)

```ts
export type PlayVariant = 'standard' | 'chess960';
export type PlayTimeControl = {
  kind: 'unlimited' | 'rapid' | 'blitz' | 'bullet' | 'correspondence';
  baseSeconds: number;      // initial clock, 0 = unlimited
  incrementSeconds: number; // per-move increment
};
export type PlaySeek = {
  id: string;
  owner: PlayUser;          // null/anonymous for open seeks
  timeControl: PlayTimeControl;
  variant: PlayVariant;
  rated: boolean;
  color: 'w' | 'b' | 'random';
  ratingRange: [number, number] | null;
  startFen?: string;        // custom/Chess960 start
  createdAt: number;        // epoch ms
};
export type PlayUser = { id: string; name: string; rating: number; title?: string };
export type PlayMatchState = 'seeking' | 'paired' | 'playing' | 'finished';
export type PlayMatch = {
  id: string;
  variant: PlayVariant;
  timeControl: PlayTimeControl;
  rated: boolean;
  white: PlayUser;
  black: PlayUser;
  startFen: string;
  ply: number;              // moves played (0 = start)
  status: PlayMatchState;
  result: PlayResult | null;
  clocks: { whiteMs: number; blackMs: number };  // server snapshot at last event
  clockUpdatedAt: number;   // epoch ms of clock snapshot
  drawOfferSide: 'w' | 'b' | null;
  rematchOfferSide: 'w' | 'b' | null;
};
export type PlayResult =
  | { kind: 'mate'; winner: 'w' | 'b' }
  | { kind: 'resign'; winner: 'w' | 'b' }
  | { kind: 'timeout'; winner: 'w' | 'b' }
  | { kind: 'draw'; reason: 'agreement' | 'stalemate' | 'insufficient' | 'threefold' | 'fifty' | 'timeout-both' }
  | { kind: 'aborted' }      // no rated effect, too few plies
  | { kind: 'adjourned' };
export type PlayMove = { ply: number; san: string; uci: string; fen: string; clockMsAfter: number; latencyMs: number };
export type PlayEvent =
  | { type: 'seek.created'; seek: PlaySeek }
  | { type: 'seek.cancelled'; seekId: string }
  | { type: 'match.paired'; match: PlayMatch }
  | { type: 'match.move'; matchId: string; move: PlayMove; clocks: PlayMatch['clocks']; clockUpdatedAt: number }
  | { type: 'match.offer'; matchId: string; offer: 'draw' | 'rematch' | 'takeback'; side: 'w' | 'b' }
  | { type: 'match.offer.response'; matchId: string; offer: 'draw' | 'rematch' | 'takeback'; accepted: boolean }
  | { type: 'match.finish'; matchId: string; result: PlayResult; clocks: PlayMatch['clocks'] }
  | { type: 'match.chat'; matchId: string; side: 'w' | 'b'; text: string } // optional, rate-limited
  | { type: 'match.resync'; match: PlayMatch; moves: PlayMove[] };          // full state on reconnect
```

### 2.2 Server models (`play_service.py`, pydantic)

Mirror the above 1:1. `PlayMove`, `PlayResult`, `PlayMatch` as pydantic `BaseModel`s. **No `python-chess` dependency.** Server-side move legality is delegated to the **scidb C++ rules engine via a new stateless Tcl bridge command** (`position/legal`: input `{fen, uci?}` → output `{legal, san?, fen?, checkmate?, stalemate?, draw?}`). Per-match game state lives in Python as a FEN string; the bridge is a *stateless* legality oracle, so no per-match state is held in Tcl. **Server is the source of truth** — client-sent moves are *intents* validated against the server's current FEN via the bridge. Fallback if Tcl latency is unacceptable under load: a small hand-written pure-Python rules module (`play_rules.py`); Chess960 castling is the hard part and must be parity-tested against scidb C++.

## 3. Workspace state model (`src/state/workspace.ts`)

Add a `play` slice and an `activePlayMode` flag that the board reads:

```ts
export type PlayMode = 'analysis' | 'play';
export interface PlayState {
  activePlayMode: PlayMode;
  activeMatchId: string | null;
  seeks: PlaySeek[];          // open seeks the user can see
  mySeeks: PlaySeek[];         // this user's open seeks
  activeMatch: PlayMatch | null;
  connected: boolean;          // ws/play connection state
  pendingSeek: PlaySeek | null;
}
```

Add actions: `setPlayMode`, `setSeeks`, `upsertSeek`, `removeSeek`, `setActiveMatch`, `patchMatch`, `setPlayConnected`. The board component selects `activePlayMode` to switch behavior. The global bridge (`window.ScidbWorkspace`) gets `getPlayMode()`/`setPlayMode()` for parity with existing legacy modules.

**Persist rule:** do **not** persist `activeMatch` or `seeks` (they're session-only). Only persist `activePlayMode` if the user explicitly chose play; default `analysis`. Use a `partialize` on the persist middleware to exclude the volatile play fields.

## 4. Board mode integration (`src/features/board/ChessBoard.tsx`)

Goal: one board component, two modes. Concrete changes:

1. New prop `mode: PlayMode` (defaults `analysis`). Read from `useWorkspaceStore(s => s.activePlayMode)`.
2. **Analysis mode (current behavior, unchanged):** free move, takeback via `goToPly`, FEN paste/load, engine available.
3. **Play mode restrictions** (gated on `mode === 'play'`):
   - Only the side-to-move matching `activeMatch`'s current player may move; opponent moves are rejected locally before sending.
   - `goToPly`/takeback disabled; navigation is view-only replay of `activeMatch.moves` (no history mutation).
   - FEN load disabled (match position is authoritative).
   - `ChessBoardHandle.getMoves()` returns the match's move list, not a local editable history.
4. **External move application:** new `applyExternalMove(uci: string)` method on `ChessBoardHandle` for moves arriving over WebSocket. Reuses the existing `makeMove` path but skips the local-selection state.
5. **Clocks:** rendered beside the board (new `ClockWidget.tsx` in `features/play/`), driven by `activeMatch.clocks` + `clockUpdatedAt` (client interpolates between server snapshots; flag-fall is server-decided, not client).
6. **Offer controls:** draw/rematch/resign buttons in `features/play/MatchControls.tsx`, call play API.
7. **Promotion:** already handled by `makeMove` (`promotion: 'q'`); for play, surface a promotion picker (new `PromotionPicker.tsx`) — server enforces the chosen piece.

No board fork. No second renderer. The `playMode` flag is the entire seam.

## 5. Server design (`play_service.py` + routes in `runtime_adapter.py`)

### 5.1 Module: `play_service.py`

Pure-Python in-memory state + Redis for multi-instance fan-out. Single-process v1; horizontal scale deferred to Phase 7.

```python
class PlayService:
    def __init__(self, redis, clock_resolution_ms=100): ...
    async def create_seek(self, user, spec) -> Seek: ...
    async def cancel_seek(self, user, seek_id) -> None: ...
    async def accept_seek(self, user, seek_id) -> Match: ...   # pairing
    async def challenge(self, from_user, to_user_id, spec) -> Match: ...
    async def submit_move(self, match_id, user, uci) -> PlayEvent: ...
    async def offer(self, match_id, user, kind) -> PlayEvent: ...
    async def respond_offer(self, match_id, user, accept) -> PlayEvent: ...
    async def resign(self, match_id, user) -> PlayEvent: ...
    async def archive(self, match_id, database_id) -> str: ...  # returns job id
    async def resync(self, match_id) -> tuple[Match, list[PlayMove]]: ...
```

### 5.2 Server-authoritative rules

- Per-match state is a FEN string held in `PlayService` (no `chess.Board` object, no python-chess). On `submit_move(uci)`, the service calls the stateless bridge `position/legal {fen, uci}`; if `legal` is false → reject with `{type:'match.error', code:'illegal_move'}` (no state change). If legal, the service adopts the returned `fen`/`san` and checks `checkmate`/`stalemate`/`draw` to possibly finish the match.
- **Clock:** stored as `{whiteMs, blackMs}` at `clockUpdatedAt`. On each accepted move, decrement the mover's clock by `now - clockUpdatedAt`, add increment, set `clockUpdatedAt = now`. A background task flags games whose active clock hits 0 → emits `match.finish` `{kind:'timeout'}`. Client only *displays* interpolated time; never decides flag-fall.
- **Rated-game engine lock:** when `match.rated`, the runtime adapter refuses to start an analysis engine for the user while a rated match is active for that user (query the play service from the analysis endpoint). The frontend also disables `EngineInspector` in `playMode && rated`.
- **Anti-cheat (v1 heuristics):** per-user move-time variance, instant-move flag, and blur-loss (focus-out during opponent's move). Flagged games go to a review queue; no auto-ban. Stockfish-correlation screening is Phase 7.
- **Glicko-2:** `rating.py` (new) implementing Glicko-2 with per-(variant, timeControlKind) ratings, provisional period, configurable floors. Update on `match.finish` for rated games only.

### 5.3 REST endpoints (all under `/api/play`)

**Identity model:** anonymous play is allowed. When OIDC is enabled and a valid token is present, the user is authenticated (`PlayUser.id` = subject, with rating). When no token is present (or auth is disabled), the server issues an **ephemeral guest identity** per session (`PlayUser.id = 'guest-' + random`, `name = 'Guest-XXXX'`, rating = provisional default). **Rated games require an authenticated identity** — a guest seeking `rated:true` is rejected with 403 (`rated_requires_auth`); casual/unrated games accept guests. Guests are rate-limited more tightly than authenticated users.

| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/play/seek` | `{timeControl, variant, rated, color, ratingRange?, startFen?}` | `PlaySeek` |
| DELETE | `/play/seek/:id` | — | `{ok:true}` |
| GET | `/play/seeks` | — | `PlaySeek[]` (open seeks) |
| POST | `/play/challenge/:userId` | same as seek | `PlayMatch` (immediate pairing) |
| POST | `/play/match/:id/accept` | — | `PlayMatch` |
| POST | `/play/match/:id/decline` | — | `{ok:true}` |
| POST | `/play/match/:id/move` | `{uci}` | `PlayMove` + updated `clocks` |
| POST | `/play/match/:id/offer` | `{kind:'draw'|'rematch'|'takeback'}` | `{ok:true}` |
| POST | `/play/match/:id/offer/respond` | `{accept:boolean}` | `{ok:true}` |
| POST | `/play/match/:id/resign` | — | `PlayResult` |
| POST | `/play/match/:id/archive` | `{databaseId}` | `{jobId}` (PGN import job) |
| GET | `/play/match/:id` | — | `PlayMatch` (for reconnect/resync) |
| GET | `/play/me/rating` | — | `{variant, timeControl, rating, rd, vol}[]` |

Status codes: 403 `rated_requires_auth` (guest attempting rated), 403 `not_participant`, 429 on rate limit. Authenticated users get 401 only when a token is present but invalid/expired; absent token → guest identity (not 401).

### 5.4 WebSocket `/api/ws/play`

Single multiplexed channel per session. Auth: pass the access token as a `?token=` query param (validated on accept via `_get_auth_payload_sync`) — matches the existing pattern but query-based because browsers can't set WS headers. Reconnect triggers a `match.resync` from the server.

Client→server messages: `{type:'move', matchId, uci}`, `{type:'offer', matchId, kind}`, `{type:'offer.respond', matchId, accept}`, `{type:'resign', matchId}`, `{type:'chat', matchId, text}`, `{type:'ping'}`.
Server→client: the `PlayEvent` union above plus `{type:'match.error', code}` and `{type:'pong'}`.

Use the existing `_ws_receive_or_disconnect` + Redis-subscribe loop pattern from `/api/ws/events`. Anonymous WS: `?token=` absent → guest identity bound to the socket; a guest token is an opaque server-issued session id (not a JWT). Reconnect must re-present the same guest session id to reclaim the match (stored server-side, TTL = match lifetime + grace window).

## 6. Frontend file plan

| File | Status | Purpose |
|---|---|---|
| `src/types/index.ts` | edit | add `Play` namespace types |
| `src/state/workspace.ts` | edit | add `play` slice + `activePlayMode` + partialize |
| `src/features/board/ChessBoard.tsx` | edit | `mode` prop, `applyExternalMove`, play-mode restrictions |
| `src/features/board/PromotionPicker.tsx` | new | promotion piece chooser |
| `src/features/play/PlayCenter.tsx` | new | seek graph + challenge list + my games |
| `src/features/play/ClockWidget.tsx` | new | server-snapshot clock display |
| `src/features/play/MatchControls.tsx` | new | draw/rematch/resign/abort buttons |
| `src/features/play/PlayBoardPanel.tsx` | new | composes ChessBoard + ClockWidget + MatchControls |
| `src/features/play/usePlaySocket.ts` | new | hook wrapping `subscribeToPlay` → workspace slice |
| `src/features/play/glicko.test.ts` | new | rating math tests (mirror server) |
| `src/api/websocket.ts` | edit | add `subscribeToPlay()` |
| `src/api/client.ts` | edit | add `play.*` to `ScidbApiClient` + mock + HTTP impls |
| `src/components/Header.tsx` | edit | add "Play" nav entry → `setActivePanel('play')` |
| `src/features/engine/EngineInspector.tsx` | edit | disable when `activePlayMode==='play' && activeMatch?.rated` |

## 7. Server file plan

| File | Status | Purpose |
|---|---|---|
| `play_service.py` | new | in-memory matchmaker, matches, clocks, offers, guest identity |
| `rating.py` | new | Glicko-2 |
| `play_rules.py` | new (fallback) | pure-Python rules shim; only built if Tcl latency fails Phase 4 load test |
| `play_routes.py` | new | FastAPI APIRouter for `/api/play/*` |
| `play_ws.py` | new | `/api/ws/play` handler |
| `tcl_bridge.py` | edit | add stateless `position_legal(fen, uci?)` method |
| `tcl_bridge_real.tcl` | edit | add `position/legal` proc reusing scidb C++ legality (Chess960-capable) |
| `runtime_adapter.py` | edit | mount router + ws, gate rated-analysis via `PlayService.is_user_in_rated_match()` |
| `tests/test_play.py` | new | service + route tests (incl. guest rated-rejection) |
| `tests/test_play_ws.py` | new | protocol/resync tests |
| `tests/test_rating.py` | new | Glicko-2 property tests |
| `tests/test_position_legal.py` | new | bridge legality parity vs chess.js for standard + Chess960 starts |

## 8. Phase breakdown (tiny commits, each independently shippable)

Each phase has an exit criterion. No phase merges without its tests green.

### Phase 0 — Scaffolding & types
- Add `Play` types to `src/types/index.ts`.
- Add empty `play` slice to workspace (mode flag only), `setPlayMode`.
- Add `Play` nav entry in Header (opens empty panel).
- **Exit:** `npm run build` + `vitest` green; clicking "Play" shows an empty placeholder panel; `activePlayMode` toggles in DevTools.

### Phase 1 — Board play mode (no network)
- Add `mode` prop + `applyExternalMove` to `ChessBoard.tsx`; gate takeback/FEN-load in play mode.
- Add `PromotionPicker.tsx`.
- Add a local two-boards-on-one-screen "hotseat" dev mode (both sides played locally) to exercise play-mode restrictions without a server.
- Tests: `ChessBoard.play-mode.test.tsx` — opponent-side click rejected, takeback disabled, external move applied.
- **Exit:** hotseat game plays to completion; promotion picker works; analysis mode unchanged.

### Phase 2 — Mock API client + PlayCenter UI
- Add `play.*` methods to `ScidbApiClient` and the **mock** implementation (in-memory seeks/matches in the browser).
- Build `PlayCenter.tsx` (seek list, create-seek form), `ClockWidget.tsx`, `MatchControls.tsx`, `PlayBoardPanel.tsx`, `usePlaySocket.ts` (mocked, local).
- Wire hotseat→mock: creating+accepting a seek locally pairs a match; moves via mock.
- Tests: `PlayCenter.test.tsx`, `usePlaySocket.mock.test.ts`.
- **Exit:** two browser tabs can play a full game against the mock backend; clocks tick; resign/finish work; game appears in a local "my games" list.

### Phase 3 — Server: seeks + pairing (REST, no live play yet)
- `play_service.py` (seeks, accept→pairing, guest identity issuance), `play_routes.py` mounted, rate limits. Rated-seek rejection of guests (403 `rated_requires_auth`).
- HTTP `play.*` in `api/client.ts`.
- Tests: `test_play.py` (create/cancel/accept/challenge, auth, rate limit).
- **Exit:** `curl` against `/api/play/seek` + `/accept` returns a paired `PlayMatch`; frontend can create+accept over HTTP (moves still mocked locally).

### Phase 4 — Server: live moves + clocks over WebSocket
- Add stateless `position/legal` command to `tcl_bridge.py` + `tcl_bridge_real.tcl` (reuses scidb C++ legality; Chess960-capable). `play_ws.py` validates each move via the bridge oracle, runs server-authoritative clocks, emits `match.move`/`match.finish`, and sends `match.resync` on reconnect.
- `subscribeToPlay()` in `websocket.ts`; real `usePlaySocket` (replace mock).
- Tests: `test_play_ws.py` (illegal move rejected, clock decrements, timeout finishes, resync after drop).
- **Exit:** two real browser sessions play a live game through the adapter; dropping and reconnecting resyncs without desync; timeout flags correctly.

### Phase 5 — Offers, rematch, abort, chat
- Server offer/resign/abort endpoints + WS messages; `MatchControls` wired.
- Abort rules (too few plies, no rated effect); rematch creates a new match from same spec.
- Optional chat (rate-limited, sanitizable, per-match disable flag).
- Tests: `test_play_offers.py`.
- **Exit:** draw/rematch/abort/resign all work end-to-end; chat optional and off by default.

### Phase 6 — Ratings + archival
- `rating.py` Glicko-2; update on rated `match.finish`; `/play/me/rating`.
- `POST /play/match/:id/archive` → reuse existing PGN import pipeline (`/api/databases/:id/import`) as a job.
- Tests: `test_rating.py` (provisional, floors, draw), `test_play_archive.py`.
- **Exit:** rated games update ratings; finished game imports as PGN into a chosen database and shows in JobCenter.

### Phase 7 — Anti-cheat + engine lock + observability
- Move-time/blur heuristics → review queue (no auto-ban).
- Engine lock: analysis endpoint refuses start while user in rated match; `EngineInspector` disabled in rated play mode.
- Metrics: active matches, queue depth, avg move latency, timeouts, flagged games (extend `metrics.py`).
- Tests: `test_play_anticheat.py`, `test_engine_lock.py`.
- **Exit:** engine can't run during a user's rated game; flagged games appear in review; metrics scraped.

### Phase 8 — Federation bridge (optional, post-v1)
- Per-provider OAuth connectors behind admin approval; external moves validated against scidb rules before render/archive.
- **Exit:** (separate milestone, not a v1 release gate.)

## 9. Testing strategy

- **Unit:** chess rules + clock math in `play_service`, Glicko-2 in `rating.py` (property-based via `hypothesis`), board play-mode restrictions in `ChessBoard.play-mode.test.tsx`.
- **Contract:** a `play_contract.test.ts` runs the same scenarios against the mock client and the HTTP client (parity test), so mock and server stay equivalent — matches the plan's "adapter contract test suite" requirement.
- **Integration:** `test_play_ws.py` drives two WS clients through a full game incl. disconnect/resync.
- **E2E (Playwright):** extend `src/e2e/` with `play.spec.ts` — two contexts, create+accept seek, play to mate, assert board/clock/finish. Runs against the adapter in CI.
- **Load (manual, pre-release):** simulate N concurrent matches to validate clock task scheduling; not a CI gate.

## 10. Security & operations specifics

- WS auth via `?token=` query param validated on accept; reject if invalid/expired.
- Per-user: max 3 concurrent games, max 5 open seeks, move rate ≤ 20/s, chat ≤ 3/s.
- Clocks server-authoritative; never trust client clock for results.
- Sanitize chat text before broadcast (strip markup; length cap).
- Audit: seeks, pairings, moves, offers, resigns, disconnects, adjudications, archives.
- Persist rated-game archives ≥ 30 days; exportable as PGN.
- Engine lock enforced server-side (analysis endpoint) *and* client-side (disabled UI) — defense in depth.
- Rate-limit `/api/play/*` per the existing `_check_rate_limit` pattern.

## 11. Risks & open questions

| Risk | Mitigation | Owner |
|---|---|---|
| Clock drift between server snapshot and client display | Client interpolates only for display; flag-fall is server-decided. Acceptable jitter documented. | backend |
| WS reconnect desync | `match.resync` full-state + move replay on reconnect; client discards local history and adopts server state. | backend |
| Tcl bridge latency on the move path (one round-trip per move) | Bridge uses a persistent Tcl interp (async line protocol, no per-call spawn); expected sub-ms to low-ms locally. Load-test in Phase 4; if unacceptable, fall back to pure-Python `play_rules.py` (Chess960-castling parity-tested against scidb C++). | backend |
| Chess960 start FEN + castling-rights encoding parity (chess.js client vs scidb C++ server) | Generate start FEN server-side via scidb; client adopts it. Add a castling-encoding parity test (client `chess.js` and server bridge agree on legal castles for all 960 starts). | both |
| Guest identity reclamation across reconnect | Server stores guest session id → match mapping with TTL; client persists guest id in `sessionStorage` (not `localStorage`) for the match lifetime. | backend |
| Rated-game engine lock race (start analysis between match start and lock check) | Atomic check-and-start: play service holds a lock consulted by analysis start. | backend |
| Multi-instance horizontal scale (Phase 7+) | Redis bus already abstracted; per-instance match ownership via Redis. Out of v1. | backend |
| Premove/lag compensation | v1: no premove; document. Premove = Phase 7. | frontend |
| Federation trust boundary | v1: none. Phase 8 validates all external state against scidb rules before render/archive. | backend |

### Resolved decisions
1. **No `python-chess` dependency.** Server legality uses the scidb C++ rules engine via a new stateless `position/legal` Tcl bridge command; per-match state is a FEN string in Python. Pure-Python `play_rules.py` is the documented fallback if bridge latency is too high under load.
2. **Anonymous play is allowed** for casual/unrated games via ephemeral guest identities. Rated games require an authenticated (OIDC) identity.
3. **Correspondence games: deferred to post-v1.** v1 ships rapid/blitz/bullet/unlimited only; the clock task model assumes a game completes in one session (no adjournment/async moves needed). Correspondence is revisited in Phase 7+ when the job/adjourn model is generalized.
4. **Tournament/simul: deferred to post-v1.** v1 ships casual + rated seek/ladder play only; bracket pairing and one-vs-many simul are post-v1.
5. **Guest identity lifetime: match-scoped.** The guest session id is reclaimable only for the lifetime of the match it owns (server TTL = match duration + grace window); held client-side in `sessionStorage`, not `localStorage`. No cross-session guest reuse.

### Open questions (none blocking Phase 3; revisit before Phase 6)
- Anti-cheat threshold tuning (move-time variance cutoff, blur-loss count) — calibrate from a play-test dataset, not a priori. Phase 7.
- Premove/lag-compensation UX — out of v1; revisit Phase 7+ if competitive players ask.

## 12. Definition of done — Online play (v1, scidb-native)

- [ ] A user can create a seek, accept/challenge, and play a real-time game (standard + Chess960) on the same `ChessBoard` used for analysis.
- [ ] Clocks are server-authoritative; timeout/resign/mate/draw all end the game correctly.
- [ ] Disconnect → reconnect resyncs the match without desync.
- [ ] Rated games update Glicko-2 ratings and cannot run the engine inspector.
- [ ] Finished games archive as PGN into a chosen database via the existing import job pipeline.
- [ ] Mock and HTTP API clients pass the same contract test suite.
- [ ] Playwright `play.spec.ts` green in CI; `test_play*.py` green.
- [ ] Metrics, audit logs, and rate limits active.