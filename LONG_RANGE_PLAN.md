# scidb-beta Long-Range Plan — Revised for Phases 3+4+5

*Revision after committing Phase 1 + Phase 2 (ec40d0e).*

## Status

| Phase | Status | Notes |
|-------|--------|-------|
| 1 — Production deployment with real persistence | **Done** | Committed: Postgres/Redis/S3 store, Terraform, CI/CD baseline. |
| 2 — Security, performance, observability | **Done** | Committed: auth lockdown, CORS, rate limits, audit logging, structured logging, metrics, engine sandboxing. |
| 3 — Feature modal completeness | **Done** | Committed with Phase 4: 18 endpoints + 2 shape fixes, Tcl-first dispatch, Store fallback. |
| 4 — Complete C++ backend integration | **Done** | Merged into Phase 3. |
| 5 — Chess960 + XOR-encrypted CBH reverse engineering | **Chess960 decode done (8571/0), XOR blocked** | Part A shipped; GRENKE PGN + `.sci` fixtures acquired; 36-byte position block implemented (2026-08-03); Chess960 decode resolved via the Chess960 LUT (2026-08-16, 8571/0 on fixture); XOR still blocked on encrypted game pairs. |

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

## Phase 5: Chess960 + XOR-Encrypted CBH Reverse Engineering

**Status:** Part A done; 36-byte position block implemented (2026-08-03);
Chess960 decode resolved via the Chess960 LUT (2026-08-16, 8571/0 on the
fixture); XOR still blocked on real ChessBase fixtures.

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
| A1 | Precise encrypted-game error | `src/db/cbh/cbh_codec.cpp` | `"encrypted game not supported (CBH bit 31 set, offset …)"` |
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
as the count — see `CHESS960_STATUS.md` "RESOLVED (2026-08-16)". XOR
encryption remains blocked.

**Fixture requirements:**

| Fixture | Purpose |
|---------|---------|
| ChessBase 16/17-generated `.cbh`/`.cbg` with king off the e-file | Confirm how the encoder represents off-e-file castling moves |
| Encrypted + unencrypted game pair | Characterize XOR keystream |
| ChessBase-exported PGN for the same king-off-e-file game | Ground-truth move comparison |

**Decision tree after probes:**

- **36-byte block confirmed?** — **DONE**: parsing implemented with the exact
  proved layout.
- **Off-e-file castling token characterized?** Adjust the encoder to emit
  the same representation ChessBase uses (different token, multi-byte move,
  or ordinary king move with implicit rook update).
- **XOR keystream characterized?** Implement decryption in `cbh_codec.cpp`
  before normal decoding. Otherwise keep A1's precise "not supported" error.
- **H0 count-cipher coverage gap (501 corrupt games)?** — **RESOLVED
  (2026-08-16).** Chess960 decode is a 256-byte LUT swap, not a count
  cipher: `lc = Chess960MoveNumberLookup[raw] - move_index`. The decoder
  now uses the LUT directly (8571/0 on the fixture).

### Files to modify (conditional)

| File | Condition |
|------|-----------|
| `src/db/cbh/cbh_decoder.cpp` | ~~36-byte format confirmed~~ **done** — `setupStartPosition` reads 36 bytes |
| `src/db/cbh/cbh_decoder_position.cpp` | ~~Parse extra 8 bytes~~ **done** — handled in `setupStartPosition`; still open for off-e-file castling token |
| `src/db/cbh/cbh_encoder.cpp` / `cbh_encoder_position.cpp` | Off-e-file castling token characterized |
| `src/db/cbh/cbh_codec.cpp` | XOR keystream characterized |

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

1. **Phase 3+4** is done and committed.
2. **Phase 5 Part A** is done and committed.
3. **Phase 5 Part B** (fixtures) is done as far as possible; the 36-byte
   position block is implemented and verified.
4. **Phase 5 Part C** 36-byte work is done and Chess960 decode is resolved
   (2026-08-16, 8571/0 via the Chess960 LUT). Remaining: XOR encryption
   (blocked on fixtures). Keep the C++ changes minimal and do not alter the
   established Convention B castling destinations without fixture-backed
   proof.
5. **Future work** (after fixtures): characterize the off-e-file castling
   token and the XOR keystream; implement only what is proved by real
   `.cbh` data.

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
