# scidb-beta Long-Range Plan — Revised for Workstreams 6-8

**2026-09-05: Media playback withdrawn.** The media panel and board-sync
integration are removed. `.cms`/`.cbm` playback is blocked until the formats
are fully understood. Return to reverse engineering; historical completion
claims below do not represent current support. Experimental sources and
uncommitted work are preserved in `media-console/experimental-panel/`.

*Revised 2026-08-27: workstreams 1-7 done; workstream 8 (ChessBase 2CBH)
mostly done — moves, player names, results decoded, `2cbh2pgn` converter
working; remaining items listed in the table row and
`2CBH_FORMAT_DESIGN.md`.*

## Status

| Phase | Status | Notes |
|-------|--------|-------|
| 1 — Production deployment with real persistence | **Done** | Committed: Postgres/Redis/S3 store, Terraform, CI/CD baseline. |
| 2 — Security, performance, observability | **Done** | Committed: auth lockdown, CORS, rate limits, audit logging, structured logging, metrics, engine sandboxing. |
| 3 — Feature modal completeness | **Done** | Committed with Phase 4: 18 endpoints + 2 shape fixes, Tcl-first dispatch, Store fallback. |
| 4 — Complete C++ backend integration | **Done** | Merged into Phase 3. |
| 5 — Chess960 + unencoded (bit-31) CBH reverse engineering | **Chess960 decode done (8571/0); bit-31 guiding-text entries parsed as text documents; plain bit-31 game decode still blocked - no such fixture has ever been observed, re-confirmed by a wider scan (2026-09-06)** | Part A shipped; GRENKE PGN + `.sci` fixtures acquired; 36-byte position block implemented (2026-08-03); Chess960 decode resolved via the Chess960 LUT (2026-08-16, 8571/0 on fixture); bit-31 entries parsed as text documents (2026-08-27). Widened the scan to every classic `.cbh`/`.cbg` fixture on the machine (30 databases, up from 2): 100+ bit-31 records found, 100% guiding text, 0 real games (2026-09-06, `docs/re/cbh-bit31-unencoded.md`, supersedes the earlier 59-record/`CHESS960_STATUS.md` scan). Along the way, fixed a real (if silent) bug: `Codec::doDecoding()`'s move-list accessor unconditionally called `startDecoding()` on guiding-text records, throwing on every lookup instead of early-returning like its sibling overload already did. A real unencoded game has still never been observed locally; producing one would need live ChessBase experimentation under Wine, not attempted. |
| 6 — Media playback (libmpv) | **Done** | In-process libmpv player (`src/tcl/tcl_media.cpp`: `::mpv::*`, X11 output embedded with `--wid`, observed properties read from an event-fed cache so polling is instant, Tk's X error handler preserved across mpv's lifetime); tkvlc and the Python IPC bridge removed. Lessons: the board follows the video through `ResolveOwner` (the lesson's own positions decide the owning game, since the `.cbm` manifest sometimes names the neighbouring game) and `SyncBoardGoto` verifies every jump. Still open: decoding the `.cbm` owner index itself. |
| 7 — Correspondence chess support | **Done** | ICCF ratings/titles/IDs, ccsnt/cclk/cemt move info, TimeControl export, CCG format design, notation panel display, game table ICCF columns, corr clock widget, auto ccsnt timestamp, corr game manager panel, menu wiring + gamebar corrclock, ICCF XFCC SOAP client + credential storage + sync UI + auto-submit. 9 commits, 12 files, ~1,640 lines. |
| 9 — Classic `.cba` annotation-type coverage | **Types 0x07/0x09/0x13/0x16/0x17/0x18/0x24 decoded, plus 0x22 medals at their recorded nodes; 0x13 quotations fully decoded including the embedded move blob (17/17 records, 1,650 plies cross-validated); 0x14/0x15/0x23 payloads preserved in comments, display semantics unresolved** | Full census: `docs/re/cba-annotation-coverage.md`. 0x09 (training/quiz questions): `docs/re/cba-training-annotation-format.md`, 344/344 fixture records. 0x13 (game quotation) — header AND the embedded quoted-game move blob both solved and shipped (2026-09-06): 2-byte-per-move words under the fifth CBH atlas table with the ply index subtracted per byte, replayed to the `0x4000` end marker, SAN cross-validated against python-chess for every record (`docs/re/cba-quotation-format.md`; eleven earlier passes' single-byte-token model was the blocker, live CBase26 debugging never needed). 0x22 medals: decoded at the recorded move (distinguishing tactical/strategic blunders); 0x23/0x14/0x15 display payloads preserved as labeled comments, semantics unresolved (`docs/re/cba-display-annotations.md`). Import-only: the CBH writer still emits only 0x02/0x82/0x03/0x04/0x05. |
| 8 — ChessBase 2CBH (CB 17+) format reverse engineering | **Done except two fixture-blocked items — moves, players, events+sites (.2lid slot array), results, dates, rounds (0x5a/0x5c), ECO, Elo, .2cba annotations (containers, NAGs, clock, eval), .2cba quotations with move replay, variations with validated marker pairing; full-scale conversion 863,538 games / 0 errors, 99.5% real event+site names; remaining: Chess960 type-2 records, .2lcd tree semantics (both fixture-blocked)** | Fixture `LumbrasGigaBase_OTB_ELO2400` (863,538 games). Move16 decoding via the runtime table dumped from a live CBase26 process (2026-08-27), packed and embedded (`src/db/2cbh/`). Player ID == the `.2lid` slot ordinal (signature-record walk); real names emitted. Game result = index byte 0x58 low 2 bits (validated 2,748/2,748). Date: 3-byte LE packed at index 0xBC, `day(5)|month(4)<<5|year(12)<<9` (2,842/2,862 exact). ECO: index @0x80 = `128*(base+1)` (0 exceptions / 57,146 twin pairs); sub-letter not stored in the file. Annotations: `.2cba` item grammar solved and implemented (`src/db/2cbh/2cbh_annotations.{h,cpp}`); nested RAV walk verified 81/81. The `.2lgd` = the parent database's stale statistics file. Elo: SOLVED — plain u16 LE at index 0x60 (White) / 0x70 (Black), same convention as classic .cbh. Remaining: Chess960 start positions in 2CBH (the LUT-960 solution was classic CBH only). Details: `2CBH_FORMAT_DESIGN.md`; converter `src/db/2cbh/2cbh2pgn.cpp`; RE artifacts in `docs/ghidra_2cbh/`. |
| 10 — CQL 6.2 engine and pattern index | **In progress** | Official CQL 6.2 embedded as `src/cql6` (branch `cql6-port`: library, feed from Scidb databases, async Tcl glue `::scidb::cql6::*`; hardening gate = file lockdown, ASan/UBSan/TSan clean, fuzzed feed). Next: trusted/normalised feed, lazy per-position features, multi-script evaluation, then the precomputed pattern index for library searches: see `PATTERN_INDEX_PLAN.md`. Old CQL engine stays. |
| 11 — Play against an engine | **Proposed** (not started) | Scidb has an analysis-only engine layer (`src/app/app_uci_engine.cpp`, `app_winboard_engine.cpp`: `go infinite`/depth/time/mate; strength, skill-level and pondering settings are already sent; game-style `go wtime btime winc binc` exists only as a comment) and no play mode. Needed: a play search mode with `bestmove` callbacks, a clock (increments, flag fall), a game loop (human move validation, takeback, resign, draw offers, automatic draws: checkmate, stalemate, threefold, fifty-move, insufficient material), strength settings (Elo limit, skill, depth/time), saving the game with proper PGN headers. Reference implementations (studied; findings and a recommended first version in `PLAY_AGAINST_ENGINE_RESEARCH.md`): Scid and ScidvsPC `tcl/tools/sergame.tcl` (serious game), `tacgame.tcl`, ScidvsPC `comp.tcl` (engine tournaments), Scid `enginecomm.tcl` (async engine layer), in `~/src/chess/scid-code` and `~/src/chess/scidvspc-code`. Open decisions: build in the C++ engine layer (recommended: UCI and WinBoard, async, reuses the engine list and settings) or on the blocking Tcl driver `ai-engine.tcl`; first-version scope (clocks, strength, takeback/draws, save). |

---

## Phase 3+4: Feature Modal Completeness + Native Backend Integration

**Status:** Done (committed in `f3b25e5` and `2f70b33`).

This phase implemented all missing REST endpoints so every frontend modal
works against a running backend, while wiring as many endpoints as possible
to the native scidb C++/Tcl engine. See `ADAPTER_CONTRACT.md` and commit
history for details.

**Strategy**

- **Endpoint-first, not mock-first.** Define the contract in
  `ADAPTER_CONTRACT.md`, then add each endpoint to `runtime_adapter.py` once.
- **Read endpoints:** try the Tcl bridge first; fall back to `Store` seed
  data (MemoryStore/PostgresStore) when Tcl is unavailable. Cache with TTL
  and invalidate on mutations.
- **Mutation endpoints:** require the Tcl bridge and a writable database.
  Return **HTTP 503** when unavailable. Never silently mock a mutation.
- **Async jobs:** import, export, convert, maintenance, prep reports all run
  as background jobs with progress via `GET /api/jobs/:id` and the WebSocket
  event bus.

### Gap analysis

The frontend `HttpScidbApiClient` already calls these paths. Missing backend
endpoints are marked **MISSING**; shape mismatches are marked **MISMATCH**.

| # | Method | Path | Status |
|---|--------|------|--------|
| 1 | GET | `/databases` | OK |
| 2 | POST | `/databases` | OK |
| 3 | GET | `/databases/:id/games` | OK |
| 4 | GET | `/databases/:id/games?page=&limit=&sort=&order=&query=` | MISMATCH (add pagination) |
| 5 | POST | `/tree/query` | OK |
| 6 | POST | `/searches` | OK |
| 7 | GET | `/searches/:id/results` | OK |
| 8 | DELETE | `/searches/:id` | MISSING |
| 9 | GET | `/engines` | OK |
| 10 | POST | `/analysis/start` | OK |
| 11 | GET | `/analysis/:id` | OK |
| 12 | POST | `/analysis/:id/stop` | OK |
| 13 | POST | `/opening-info` | MISSING |
| 14 | POST | `/explorer` | MISSING |
| 15 | POST | `/explorer/elo` | MISSING |
| 16 | POST | `/explorer/historical` | MISSING |
| 17 | GET | `/games/:id/pgn` | MISSING |
| 18 | GET | `/games/:id` | OK (minor shape fix) |
| 19 | PATCH | `/games/:id` | MISSING |
| 20 | POST | `/games/:id/variations` | MISSING |
| 21 | POST | `/games/:id/moves/:moveId/comments` | MISSING |
| 22 | POST | `/databases/:id/import` | MISMATCH (add JSON variant) |
| 23 | POST | `/databases/:id/export` | MISSING |
| 24 | GET | `/jobs/:id` | OK |
| 25 | DELETE | `/jobs/:id` | MISSING |
| 26 | POST | `/jobs/:id/cancel` | MISSING |
| 27 | GET | `/indexes/:type` | MISSING |
| 28 | GET | `/eco` | MISSING |
| 29 | GET | `/repertoires` | MISSING |
| 30 | POST | `/prep/reports` | MISSING |
| 31 | GET | `/players?q=` | MISSING |
| 32 | GET | `/players/:id/card` | MISSING |
| 33 | POST | `/players/:id/prep` | MISSING |
| 34 | POST | `/maintenance/jobs` | MISSING |
| 35 | GET | `/maintenance/reports/:id` | MISSING |
| 36 | POST | `/crosstables/query` | MISSING |

**18 missing endpoints** + **2 shape mismatches** + **1 import variant**.

### Implementation waves

#### Wave 1 — Job lifecycle + search cancel (Store-backed)

- `DELETE /api/searches/:id`
- `DELETE /api/jobs/:id`
- `POST /api/jobs/:id/cancel`
- `POST /api/databases/:id/export` (creates export job)

#### Wave 2 — Index browser + ECO (read-only seed data)

- `GET /api/indexes/:type`
- `GET /api/eco`

#### Wave 3 — Player center + repertoire

- `GET /api/players?q=`
- `GET /api/players/:id/card`
- `POST /api/players/:id/prep` (creates prep job)
- `GET /api/repertoires`
- `POST /api/prep/reports` (creates prep job)

#### Wave 4 — Maintenance + crosstable

- `POST /api/maintenance/jobs` (creates maintenance job)
- `GET /api/maintenance/reports/:id`
- `POST /api/crosstables/query`

#### Wave 5 — Game viewer + editor

- `GET /api/games/:id/pgn`
- `GET /api/games/:id` (shape fix: add `comment` to moves)
- `PATCH /api/games/:id` (mutation → 503 without writable backend)
- `POST /api/games/:id/variations` (mutation → 503)
- `POST /api/games/:id/moves/:moveId/comments` (mutation → 503)

#### Wave 6 — Explorer reshaping

- `POST /api/explorer` (proxy to Lichess, reshape to `ExplorerData`)
- `POST /api/explorer/elo`
- `POST /api/explorer/historical`
- `POST /api/opening-info`

#### Wave 7 — Paginated games + import variant

- `GET /api/databases/:id/games` (add pagination)
- `POST /api/databases/:id/import-pgn` (JSON variant for programmatic import)

### Files to create / modify

**Create:**
- `opening-report/tests/test_tcl_bridge_real_mutations.py`

**Modify:**
- `opening-report/runtime_adapter.py` — add 18 endpoints + request models + cache invalidation
- `opening-report/tcl_bridge.py` — add `BridgeError`, 20+ bridge methods, error propagation
- `opening-report/tcl_bridge_real.tcl` — add handlers, writable db support, slot isolation
- `opening-report/db/store.py` — add `list_namebase`, `list_eco`, `list_players`, `get_player_card`, `list_repertoires`, `query_crosstable`
- `opening-report/db/models.py` — add `Repertoire` model (optional for Postgres)
- `opening-report/src/api/client.ts` — sync if any path mismatch remains
- `opening-report/src/types/index.ts` — minor shape fixes
- `opening-report/tests/test_adapter_contract.py` — contract tests for all new endpoints
- `opening-report/tests/test_tcl_bridge_real.py` — real-backend tests
- `opening-report/ADAPTER_CONTRACT.md` — document new schemas
- `opening-report/TCL_BRIDGE.md` — document new handlers, writable db, protocol changes
- `opening-report/requirements.txt` — add `python-chess` for PGN parsing

### Tcl bridge protocol changes

1. **Distinguish error from fallback.** Add `BridgeError` in `tcl_bridge.py`;
   `{"error": ...}` from Tcl becomes an exception, not a silent fallback.
2. **Writable database registration.** Add `SCIDB_DATABASE_READONLY` env var;
   mutation endpoints check it and return 503 if read-only.
3. **Slot isolation.** Reserve slots: 0 game detail, 6 crosstable, 7 maintenance,
   8 editor mutations, 9 tree queries.
4. **Async progress.** For v1 use no-op progress callbacks; job progress comes
   from the adapter job store + WebSocket events.

### Verification gate

```bash
# No backend env
unset TCL_INTERP TCL_BRIDGE_PATH SCIDB_DATABASE REDIS_URL DATABASE_URL S3_BUCKET
pytest opening-report/tests/test_adapter_contract.py -v
pytest opening-report/tests/ -v --timeout=60

# With real backend
export TCL_INTERP=/home/michael-g-thomas/src/chess/scidb-code.codex/src/tkscidb-beta
export TCL_BRIDGE_PATH=/home/michael-g-thomas/src/chess/scidb-code.codex/opening-report/tcl_bridge_real.tcl
export SCIDB_DATABASE=/path/to/writable.sci
export SCIDB_DATABASE_READONLY=0
pytest opening-report/tests/test_tcl_bridge_real.py opening-report/tests/test_tcl_bridge_real_mutations.py -v

# Frontend
npm run lint
npx tsc --noEmit
npx vitest run
npx playwright test src/e2e/workspace.spec.ts
```

### Risks / trade-offs

1. **Writable database concurrency.** Multiple ECS replicas writing the same
   `.sci` file would corrupt it. v1 runs a single writer replica for mutations.
2. **PGN is read-only in scidb.** Mutations require `.sci/.si4`; the convert
   endpoint handles PGN → `.sci`.
3. **Explorer shape mismatch.** The frontend expects richer `ExplorerData`
   than raw Lichess returns; reshaping is required and seed fallback is used
   when Lichess is unreachable.
4. **Game editor mutations return 503 without backend.** The frontend must
   handle this gracefully (show "backend required" rather than silently losing
   data).

---

## Phase 5: Chess960 + Unencoded (bit-31) CBH Reverse Engineering

**Status:** Part A done; 36-byte position block implemented (2026-08-03);
Chess960 decode resolved via the Chess960 LUT (2026-08-16, 8571/0 on the
fixture); unencoded (bit-31) still blocked on fixtures.

**Goal:** resolve the remaining ChessBase format TODOs. Split into safe
shippable pieces (no fixtures) and probe-gated pieces that need real
ChessBase-generated `.cbh`/`.cbg`/`.cbv` fixtures.

**Convention decision:** scidb uses **file-based castling destinations**
(Convention B) for Chess960, matching ChessBase output. Short castling always
places the king on the g-file and the rook on the f-file; long castling
places the king on the c-file and the rook on the d-file. An earlier sub-agent
change to king-relative (Convention A) destinations was reverted.

### Part A — Safe shippable pieces (done)

| # | Deliverable | File | Change |
|---|-------------|------|--------|
| A1 | Precise unencoded-game error | `src/db/cbh/cbh_codec.cpp` | `"unencoded game not supported (CBH bit 31 set, offset …)"` |
| A2 | De-duplicate position setup | `src/db/cbh/cbh_decoder.cpp`, `cbh_decoder.h`, `cbh_game_decoder.cpp` | `setupStartPosition()` helper; size guard |
| A3 | Off-e-file Chess960 round-trip test | `src/verify_cbh_write.cpp` | `verifyChess960OffFileKingCastling()` locks in Convention B behavior |
| A4 | `m_isChess960` skips `fixBadCastlingRights()` | `src/db/cbh/cbh_decoder_position.cpp` | `Position::setup(BitStream&, bool)` |

**Verification:**
```bash
make -C src verify_cbh_write && ./src/verify_cbh_write   # exit 0
make -C src probe_cbh_chess960 && make -C src scan_db_chess960
```

### Part B — Fixture acquisition (done as far as possible)

Real ChessBase-generated `.cbh`/`.cbg`/`.cbv` fixtures remain unavailable
because ChessBase does not offer a free/trial writer and the read-only
ChessBase Reader / ChessBase Light cannot create or convert databases.

The best available substitutes are:

| Fixture | Purpose | Location |
|---------|---------|----------|
| ChessBase live PGN | Ground-truth SAN / FEN / results | `opening-report/tests/fixtures/grenke_freestyle_2026.pgn` |
| Native scidb database | Fast, queryable reference | `opening-report/tests/fixtures/grenke_freestyle_2026.{sci,scg,scn}` |
| 10-game subset | Fast smoke tests | `opening-report/tests/fixtures/grenke_subset_10.{pgn,sci,scg,scn}` |
| `generate_sci.tcl` | Regenerate `.sci` from PGN | `opening-report/tests/fixtures/generate_sci.tcl` |

### Part C — Probe-gated reverse engineering (partially done)

**Status 2026-08-03:** the 36-byte position block is **implemented and
verified** (`src/db/cbh/cbh_decoder.cpp` `setupStartPosition` reads 36 bytes
and applies the extension's rook squares via the 2-arg
`Board::setCastleShort/Long(color, square)`). The decode rate on the real
`twic1639_grenke_freestyle_open.cbv` fixture is **8571 written / 0
corrupted** (all 606 chess960 games move-exact vs PGN). The decode uses the
Chess960 lookup table (`Chess960MoveNumberLookup[256]`) with the move index
as the count — see `CHESS960_STATUS.md` "RESOLVED (2026-08-16)". Unencoded
(bit-31) games remain blocked.

**Fixture requirements:**

| Fixture | Purpose |
|---------|---------|
| ChessBase 16/17-generated `.cbh`/`.cbg` with king off the e-file | Confirm how the encoder represents off-e-file castling moves |
| bit-31 game ("guiding text" / training file) | Characterize the unencoded (plain) format |
| ChessBase-exported PGN for the same king-off-e-file game | Ground-truth move comparison |

**Decision tree after probes:**

- **36-byte block confirmed?** — **DONE**: parsing implemented with the exact
  proved layout.
- **Off-e-file castling token characterized?** — **DONE (2026-08-16).** The
  encoder now emits the `0xeb` castle descriptors and promotion packing that
  ChessBase uses, plus the 36-byte position block and LUT-960 inverse.
- **Unencoded (bit-31) format characterized?** Implement plain-format parsing
  in `cbh_codec.cpp` before normal decoding. Otherwise keep A1's precise
  "not supported" error.
- **H0 count-cipher coverage gap (501 corrupt games)?** — **RESOLVED
  (2026-08-16).** Chess960 decode is a 256-byte LUT swap, not a count
  cipher: `lc = Chess960MoveNumberLookup[raw] - move_index`. The decoder
  now uses the LUT directly (8571/0 on the fixture).

### Files to modify (conditional)

| File | Condition |
|------|-----------|
| `src/db/cbh/cbh_decoder.cpp` | ~~36-byte format confirmed~~ **done** — `setupStartPosition` reads 36 bytes |
| `src/db/cbh/cbh_decoder_position.cpp` | ~~Parse extra 8 bytes~~ **done** — handled in `setupStartPosition`; still open for off-e-file castling token |
| `src/db/cbh/cbh_encoder.cpp` / `cbh_encoder_position.cpp` | ~~Off-e-file castling token characterized~~ **done** — emits `0xeb` castle/promo descriptors + 36-byte block + LUT-960 inverse |
| `src/db/cbh/cbh_codec.cpp` | unencoded (bit-31) format characterized |

### Verification gate

```bash
# Part A (no fixtures)
./src/verify_cbh_write
python3 scripts/analyze_grenke_fixtures.py \
  opening-report/tests/fixtures/grenke_freestyle_2026.pgn

# Part C (requires real ChessBase fixtures)
./src/probe_cbh_chess960 /path/to/real_fixture.cbh
./src/scan_db_chess960 /tmp/decoded.sci
# Compare decoded PGN to ChessBase-exported PGN for king-off-e-file castling
./src/verify_cbh_write   # after any Part C changes
```

---

## Suggested execution order

1. **Workstreams 1-4** (cloud deployment, security, feature modal
   completeness, backend integration) — done and committed.
2. **Workstream 5** (Chess960) — decode done (8571/0, 2026-08-16);
   bit-31 guiding-text entries parsed as text documents (2026-08-27).
   The full plain bit-31 game decode remains open but is no longer
   fixture-blocked: ChessBase 26 runs under Wine (workstream 8 setup).
3. **Workstream 6** (media playback via tkvlc/libVLC) — done.
4. **Workstream 7** (correspondence chess) — done.
5. **Workstream 8** (ChessBase 2CBH) — mostly done: Move16 move decoding,
   player names (`.2lid` slot ordinal = player ID), results (index byte
   0x58 low 2 bits), and the `2cbh2pgn` converter (300k games, 0
   failures) shipped.  Remaining, in order: (a) date/ECO index fields,
   (b) the `.2cba` annotation payload, (c) Chess960 start positions (the
   960-position table + LUT are already dumped), (d) the `cb2::Codec`
   `DatabaseCodec` subclass for GUI integration, modeled on the CBV
   codec.  Details: `2CBH_FORMAT_DESIGN.md`.

---

## Workstream 8: ChessBase 2CBH (CB 17+) Reverse Engineering

**Status:** mostly done — see `2CBH_FORMAT_DESIGN.md` for the complete
format specification.

| Piece | State |
|-------|-------|
| Move16 move decoding | Done — runtime table dumped from a live CBase26 process (Wine + ptrace), packed and embedded in `src/db/2cbh/cb2_move16_table.cpp`; validated on 200k+ games |
| Player names | Done — `.2lid` slot ordinal == the player ID; signature-record walk implemented in `2cbh2pgn` |
| Game result | Done — index byte 0x58 low 2 bits (0 = 0-1, 1 = draw, 2 = 1-0); validated 2,748/2,748 |
| Game-record mapping | Done — index `@0x08` = the `.2cbg` offset (the `.2cbg` is in insertion order; deleted games leave unreferenced records) |
| `2cbh2pgn` converter | Done — 300k games, real names + results, 100% legal replay |
| Date/ECO index fields | Open — byte 0x81 partially maps the ECO letter; the date is packed elsewhere |
| `.2cba` annotation payload | Open — the per-game records are located via index `@0x10`; payload TBD |
| Chess960 start positions | Tables dumped (960 × 128 bytes); wiring pending |
| `cb2::Codec` GUI integration | Not started — conventional `DatabaseCodec` subclass (CBV codec as the template) |

---

## Cross-cutting concerns

- **Tests:** every new endpoint gets a contract test; every new bridge
  handler gets a real-backend test that skips gracefully without `TCL_INTERP`.
- **Documentation:** update `ADAPTER_CONTRACT.md`, `TCL_BRIDGE.md`,
  `README.md`, and `CHESS960_STATUS.md` as each wave lands.
- **Migrations:** additive only; no destructive schema changes.
- **Rollout:** feature flags where possible; single writer replica for v1
  mutations.

---

*Plan revised after parallel `glm-5.2:cloud` architect subagent planning for
Phases 3, 4, and 5.*
