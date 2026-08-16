# Research: Chess960 count-cipher coverage gap (scidb CBH/CBV decoder)

> **RESOLVED (2026-08-16).** The "H0 count cipher" documented below does not
> exist. ChessBase 26 decodes Chess960 games with a dedicated 256-byte lookup
> table (`CBase26.exe` VA `0x141a799c0`) and the plain move index as the count:
> `lc = Chess960MoveNumberLookup[raw] - move_index`. The H0/F tables were the
> *empirical shadow* of re-deriving `lc` through the wrong (standard) table.
> The decoder now uses the LUT directly: **8571/8571 games decode, 606/606
> chess960 games move-exact vs PGN.** The encoder (2026-08-16) now writes the
> inverse — 36-byte position block, LUT-960 inverse, `0xeb` castle/promotion
> descriptors — so scidb-produced Chess960 CBH files round-trip with real
> ChessBase. See `CHESS960_STATUS.md`
> "RESOLVED (2026-08-16)" for the full write-up. The sections below are kept
> as the historical record of the (superseded) count-cipher investigation.

## Summary

The 501 remaining "corrupted" Chess960 games on the Grenke `.cbv` fixture are **not**
position-block, castling, or XOR-encryption problems. They are **H0 count-cipher table
coverage gaps**: at a specific `(count_prev, lc_prev, lc, ply)` cipher state the game's
next move has no H0-consistent candidate (or no unambiguous one), the decoder's
continuation-walk tie-check fails, and the game is discarded with `DecodingFailedException`.
The count-cipher **model is fully validated** (`count_p = H0(count_{p-1}, lc_{p-1}, lc_p, p)`,
`raw_p = InvLUT[lc_p] + count_p`, seed `count_0 = g(lc_0)`); what is missing is table
**coverage** for the game-specific count-chain states real TWIC games reach but the
~5,760-game synthetic oracle corpus did not. Because H0 is a genuine nonlinear 4-input byte
function with count keys that are game-specific, cross-game coverage is inherently sparse —
the table is already at its practical limit of 440,295 entries and further fixture harvests
regress rather than help.

## Findings

### 1. What the 501 failures actually are — H0 table coverage gaps, not castling/XOR/alignment

- The fixture now decodes at **8070 written / 501 corrupted**, down from 606 corrupted, and
  the 501 are explicitly characterized as "H0 table coverage gaps (…), not position-block
  or castling issues." [CHESS960_STATUS.md](CHESS960_STATUS.md) "Remaining implementation work for Part C" (2026-08-03).
- The 36-byte position block is fully implemented and verified; the move-stream alignment
  issue is solved by the cipher. [CHESS960_STATUS.md](CHESS960_STATUS.md) "Decoded: the 8-byte Chess960 position extension".
- **Not XOR-encryption:** XOR-encrypted games (CBH bit 31 = `0x80000000`) throw a separate
  precise `DecodingFailedException("encrypted game not supported …")` at
  `src/db/cbh/cbh_codec.cpp:2472–2478`. The Chess960 games carry flags `0x0a000000`
  (`0x08000000 | 0x02000000`, i.e. "newer format" + chess960), **not** bit 31, so none of the
  501 are the XOR path. [CHESS960_STATUS.md](CHESS960_STATUS.md) "XOR Encryption" and "BREAKTHROUGH".
- **Not off-e-file castling:** only **13/559** disputed H0 keys involve castling
  (`lc` 0x09/0x0a); castling is orthogonal to the count gap and the table already holds
  ~281+ castling entries. There is a *separate pre-existing scidb* bug
  (`Board::longCastlingIsLegal()` / short-side twin, around `src/db/db_board.cpp:2044`)
  that breaks Chess960 castling *legality* in some off-e-file positions — it limits castling
  harvest/decode but is independent of the count cipher. [CHESS960_STATUS.md](CHESS960_STATUS.md) "Castling parseMove root cause".
- **Not alignment/stream position:** the cipher handles 0xeb 3-byte moves, Push/Pop tokens,
  and bracketed moves; misalignment was the *harvesting* problem, not the decode gap.
  [CHESS960_STATUS.md](CHESS960_STATUS.md) "0xeb multi-byte moves", "Bracketed moves".

### 2. Failure-state classification (from the documented NO_MATCH analysis)

The decoder-side "NO_MATCH" debug analysis (2026-07-27) precisely enumerates the gap:
- **472 NO_MATCH errors at 398 unique states** across the failing games.
- **322 unique `(count_prev, lc_prev, ply)` triples** are the actual missing key space.
- **56 states carry multiple raw-byte values** (different games reach the same cipher
  state with different next moves), so the same missing key can strand many games.
- Failures **cluster at plies 3–13** (71 at ply 6, 52 at ply 7, 50 at ply 8) — i.e. the
  gap is in early/mid-opening count-chain states, the exact class the synthetic corpus
  (plies 10–40) under-samples.
  [CHESS960_STATUS.md](CHESS960_STATUS.md) "NO_MATCH analysis: exact failure states identified".

### 3. The failure mechanism: sparse coverage AND ambiguity, not just missing entries

Instrumentation from the decoder run shows the gap has two coupled causes:
- `fast=11770 (81.2%)`, `miss=593 (4.1%)`, `ambig=2111 (14.6%)` — **ambiguous matches are
  ~3.6× more common than hard H0 misses**. [CHESS960_STATUS.md](CHESS960_STATUS.md) "Phase 5 Part E".
- 330/603 games have **all** correct H0 entries present yet only 5 decode: the ambiguity
  walk picks the first candidate without enough look-ahead, picks wrong, and the cipher
  state diverges. [CHESS960_STATUS.md](CHESS960_STATUS.md) "Phase 5 Part E".
- Raising the miss limit 12→999 changes nothing — every remaining failure is a
  "no matching move" well-separated tie-check failure (`bestScore - secondScore < 1`).
  [CHESS960_STATUS.md](CHESS960_STATUS.md) "Decoder-based H0 harvest" (2026-07-28).
- **Critical caveat on the metric:** the 8070/501 written/corrupted count measures only
  *thrown* `DecodingFailedException`, **not** correctness. A move-accuracy audit found the
  exact-move-match rate for written Chess960 games is 0–9 of 85–305 verified (~97–100% of
  written Chess960 games contain wrong moves), because the ambiguity continuation-walk
  mis-picks with a sparse table. Standard chess in the same CBV stays 100% correct.
  [CHESS960_STATUS.md](CHESS960_STATUS.md) "Move-accuracy audit + CBV-aligned harvest results" (2026-08-05).

### 4. The count-cipher model is settled and the table is at its practical ceiling

- Model: `count_0 = g(lc_0)`; `count_p = H0(count_{p-1}, lc_{p-1}, lc_p, p)` (ply as 4th
  input dropped table conflicts from 12.5% to ~0%); `raw_p = InvLUT[lc_p] + count_p`; H0 is
  additive `count_p = count_{p-1} + F(lc_{p-1}, lc_p, p)`. Validated end-to-end against the
  ChessBase 26.8 oracle (5702/5760 strict-consistent games). [CHESS960_STATUS.md](CHESS960_STATUS.md) "COUNT CIPHER FULLY REVERSE-ENGINEERED".
- H0 is not decomposable (XOR/ADD/1-D-LUT all >58–98% error) and its keys are
  game-specific, so **cross-game coverage is inherently sparse**; "table-coverage harvesting
  from this single fixture cannot produce move-accurate Chess960 decode."
  [CHESS960_STATUS.md](CHESS960_STATUS.md) "Phase 5 Part E" and "Move-accuracy audit".
- The JSON table is confirmed at **`H0_entries: 440295`** in
  `src/count_cipher_universal.json` (4-tuple keys `countPrev,lcPrev,lc,ply`), plus `g_count0`
  (22 entries), `P1`, `P2`. The loader
  `src/db/cbh/cbh_count_cipher.cpp` / `.h` parses exactly this shape; the decoder
  `src/db/cbh/cbh_decoder.cpp` `decodeMove`/`resolveCipherCount`/`walkContinuation` consume it.

### 5. Why the table cannot be meaningfully extended by more PGN/TWIC harvesting

Every harvesting avenue has been tried and its failure mode identified:
- **scidb-encoder synthetic harvest is provably useless** — `Encoder::encodeMove`
  (`src/db/cbh/cbh_encoder.cpp`) writes `raw = InvLUT[lc] + move_index`, so chained counts
  equal `move_index` at every ply (a tautology). 13,938 such entries produced 0 improvement
  and were reverted. `scripts/harvest_dada_oracle.py` documents this negative result and
  must not be used as-is. [CHESS960_STATUS.md](CHESS960_STATUS.md) "Synthetic-harvest negative result" (2026-08-05).
- **TWIC/PGN harvesting misaligns on variations** — the PGN has only main-line moves, the
  raw stream includes Push/Pop variations, so byte-by-byte comparison produces wrong
  entries (27 regressions permissive, 4 strict). [CHESS960_STATUS.md](CHESS960_STATUS.md) "Harvesting alignment challenge".
- **CBV-aligned harvests regress** — permissive (+26,919 → 8043/528, WORSE), bracketed
  (+830 → 8079/492), strict (+355). Only the decoder-side verified harvest (+331) and
  loose-PGN (+945 → 8070/501) helped and then converged. [CHESS960_STATUS.md](CHESS960_STATUS.md) "Move-accuracy audit" and "PGN alignment harvest".

### 6. Oracle table-filling is empirically ruled out (2026-08-15)

**This is the definitive test of route 2, and it FAILED.** A full clean-oracle pipeline
was built and run end-to-end, and the result was a regression, confirming that the
table-coverage approach is bounded by sparsity + ambiguity and **cannot** achieve
move-accurate Chess960 decode.

What was done (scripts left in-repo for reference):
- **ChessBase 26.8 under Wine, network-blocked** via an LD_PRELOAD shim
  (`/tmp/netblock.so`, blocks AF_INET/AF_INET6, allows local IPC so Wine runs).
- **Oracle round-trip proven working:** ChessBase opened a command-line PGN, created a
  classic `*.cbh` database, appended **534 clean (mainline-only, ≤20-ply) Grenke games**, and
  scidb's own `probe_cbh_chess960 --dump-moves` read the H0-encoded bytes back.
  (`scripts/emit_clean_pgn.py` emits the clean PGN; `scripts/harvest_oracle.py` harvests;
  artifacts `/tmp/oracle.cbh`, `/tmp/oracle.cbg`, `/tmp/grenke_clean_20.pgn`.)
- **Harvest:** 3,580 new H0 entries derived from the clean games (494/534 aligned; only 35
  conflicts with the existing table → alignment/lc were essentially correct).
- **Decode re-measure** (cdb2sci, authoritative metric):

  | | written | corrupted |
  |---|---|---|
  | baseline | 8070 | **501** |
  | +3,580 clean entries | 8052 | **519 (worse)** |

- **Root cause:** reading `src/db/cbh/cbh_decoder.cpp:390-680`, the decoder's fast path
  accepts a *single* H0 candidate with **no legality check**, and ambiguous (2+) candidates
  are scored by continuation-walk depth + a legality check that is **skipped for castling**.
  Adding entries *increases* candidate counts, so it creates new ambiguity at states that
  were cleanly single-candidate → the continuation-walk tie-check mis-picks. More table data
  cannot resolve this; it only shifts misses into ambiguity.

**Consequence:** the only path to move-accurate decode is to **extract the F/lc algorithm
from CBase26.exe** (route 1, the complete fix — eliminates both sparsity and ambiguity).
A decoder-side legality-gating change was tested (2026-08-15) and is a **NO-OP** (see
"Decoder-side legality-gating — TESTED, NO-OP" below) — it cannot help, because the wrong
picks are among legal moves (ambiguity), which legality cannot resolve. Do **not** re-attempt
oracle/TWIC/PGN table-filling into `count_cipher_universal.json`, and do **not** re-attempt
legality-gating as a fix.

## Highest-value next step (priority order)

1. **Extract the H0/F algorithm from the ChessBase 26 binary** — the only path to 100%
   gap-free coverage with no alignment/harvesting issues. The 2026-07-26 BREAKTHROUGH proved
   **CBase26.exe is the H0 encoder** (byte-identical re-encode of game 758 including `O-O-O`),
   gated by game-header flag `0x08000000`. The F increment (`count += F(lc_prev, lc, ply)`,
   one LUT lookup + one add) is the expected shape. Concrete resumption coordinates:
   Ghidra/winedbg breakpoints `cbase26+0x20c080 / +0x20f170 / +0x20fd00`; decompiled per-move
   decode `0x140210e10` (cipher-ON branch), encoder `0x140211270`, dispatch `0x14020c080`.
   Previous negative result ("not in CBase16.exe") does **not** apply — CBase26 is a
   different binary and was shown to be the H0 writer. [CHESS960_STATUS.md](CHESS960_STATUS.md) "BREAKTHROUGH", "BINARY RE + DECODER ANALYSIS", "Path forward".
2. **~~Targeted oracle generation for the missing states~~ — TESTED AND RULED OUT
   (2026-08-15).** The clean-oracle round-trip above proved the pipeline works, but the
   +3,580-entry harvest regressed decode (8070/501 → 8052/519). Table-filling is bounded by
   intrinsic sparsity + ambiguity and cannot reach move-accurate decode. Do not re-attempt.
   The oracle remains valuable only as a **ground-truth generator** (clean PGN / validation
   harness), not as a table-filler.
3. **Fix scidb Chess960 castling legality** (`Board::longCastlingIsLegal()` / short twin,
   `src/db/db_board.cpp:2044`) so off-e-file castling moves can be harvested into H0 and
   decoded — low impact on the 501 count (only ~13 castling disputes) but unlocks correct
   castling in the ~100 already-decodable games. [CHESS960_STATUS.md](CHESS960_STATUS.md) "Castling parseMove root cause".

Concrete code/data actions that follow from the evidence:
- Do **not** further harvest the TWIC fixture into `count_cipher_universal.json` — it
  regresses and converges at 8070/501.
- Do **not** re-attempt oracle/TWIC/PGN table-filling (empirically ruled out 2026-08-15;
  see Findings §6). Use the oracle only for ground truth / validation.
- Revert/keep `scripts/harvest_dada_oracle.py` as documentation only (proven negative).
- Extend the decoder so a "no matching move" at a missing state is recorded to a side log
  (count_prev, lc_prev, lc candidates, ply, raw) to drive targeted oracle generation — the
  NO_MATCH instrumentation pattern from 2026-07-27 already exists to build on.
- The decisive metric must be **move-exactness vs PGN**, not written/corrupted, since
  ~97–100% of written Chess960 games currently decode to wrong moves.

## Sources

- **Kept:** `CHESS960_STATUS.md` — the authoritative, dated engineering log (2026-07-21→08-05)
  covering model validation, NO_MATCH classification, harvest results, and binary RE
  coordinates. Primary evidence for this brief.
- **Kept:** `src/count_cipher_universal.json` — confirmed `H0_entries: 440295`, 4-tuple H0
  keys, `g_count0`(22), `P1`, `P2`; the actual table state.
- **Kept:** `src/db/cbh/cbh_count_cipher.{h,cpp}` and `src/db/cbh/cbh_decoder.cpp`
  (decodeMove / resolveCipherCount / walkContinuation) — confirm the wired model and the
  ambiguity/continuation-walk failure point.
- **Kept:** `scripts/h0_gap_class.py`, `harvest_cbv_aligned.py`, `harvest_cbv_correct.py`,
  `harvest_strict.py`, `harvest_dada_oracle.py` — the classifier and the (partly negative)
  harvest toolchain this investigation relied on.
- **Added (2026-08-15):** `scripts/emit_clean_pgn.py` (clean mainline-only Grenke PGN),
  `scripts/enumerate_missing_h0.py` (fresh missing-state enumeration), `scripts/harvest_oracle.py`
  (clean-oracle harvest, proves the negative result in Findings §6).
- **Kept:** `LONG_RANGE_PLAN.md` — Phase 5 status: "36-byte block done; H0 coverage gap
  deferred indefinitely; XOR blocked."
- **Dropped:** scidb SourceForge help pages (Database formats / Chess variants / CQL) — generic
  format documentation, no H0-cipher content.
- **Dropped:** TalkChess "CBH file format" thread — classic CB9/CB10 move-index encoding
  (count=move_index, single-byte table); does **not** cover the Chess960 H0 cipher and even
  notes CB10-era CBH "doesn't work for chess960 games."

## Gaps

- ~~Could not run `h0_gap_class.py`~~ **RESOLVED (2026-08-15):** fresh run against the fixture
  gives 59 PGN-matched games; first-gap move classes P=16, N=16, B=13, R=5, Q=4, O-O-O=3,
  K=1, O-O=1 — **castling is not the dominant gap** (4/59), pawns/minor pieces dominate, split
  between missing-key (0-cand) and ambiguity (multi-cand).
- **Fresh missing-state enumeration (2026-08-15):** the true fillable space at the current
  table is ~20,480 (count_prev,lc_prev,lc,ply) 4-tuples, growing with ply — far larger than the
  stale "322 triples". 4-tuple model is deterministic in-table; F is *not* a pure 3-input
  function (6,402/433,804 ambiguous triples). Confirms table sparsity is fundamental.
- The exact H0/F algorithm is **not** recovered; it exists in CBase26.exe's
  `0x08000000`-gated transform. Resuming the binary RE (breakpoints
  `cbase26+0x20c080/0x20f170/0x20fd00`) is the only path to 100% coverage — this is now the
  active route (the oracle table-filling alternative is empirically ruled out, Findings §6).

## Binary RE status (started 2026-08-15)

Environment: `CBase26.exe` (32 MB, Wine) imported into Ghidra 12.0.4 at
`/tmp/ghidra_cb26/proj/CB26`; full disassembly cached at `/tmp/cb26_full.asm` (279 MB);
prior decompiles in `/tmp/ghidra_cb26/decompile{,_2}.log`. RE tooling: `gdb`, `winedbg`,
`objdump` available. ChessBase 26.8 runs under Wine, network-blocked (LD_PRELOAD shim),
with a working encode oracle (`/tmp/oracle.cbh`, 534 clean games).

**Decompiled byte path (confirms the doc's prior finding that the H0 transform is a
separate layer from the standard decoder):**
- Decode per-move: `FUN_140210e10` (decompiled in decompile.log). Reads a byte, applies
  `table[raw] - count` (mode 1, `param_1+0xb6!=0`) or `table[raw-count]` (mode 0); `0xeb` =
  3-byte move, `0xec+` = tokens. Uses `count` at `param_1+0x6c`, table ptr at `param_1+0x78`.
- Encode byte-write: `FUN_140212450` (decompiled in decompile.log). Writes
  `M[count]` (mode 1) or `M[0]+count` (mode 0); 0xeb multi-byte path via `FUN_140212630`.
- Move-type dispatch: `FUN_14020c080` (jump table on `*param_1 & 0x3f`), per-piece sub-tables
  `DAT_141a78xc0`. Encoder main: `FUN_140211270`.

**New finding (2026-08-15):** even with clean oracle data, F = (count_p - count_prev)&0xff is
NOT a pure 3-input function of (lc_prev, lc, ply): 322/6,950 triples (4.63%) are ambiguous
(`scripts/analyze_f.py`). So the H0 count update genuinely depends on count_prev (a 4-input
function); it cannot be collapsed to a compact additive F table from data alone.

**Next concrete step (not yet done):** dynamic tracing under `winedbg` — breakpoint the
encode/decode byte-write site and capture (count_prev, lc_prev, lc, ply → count_p, raw)
for a known clean game, to recover the actual H0 count-update function empirically.
This is the decisive step but is a substantial, uncertain effort (Wine GUI + tracing).
- It is not measured how many of the 501 are *ambiguity*-loss vs *missing-key* loss at the
  current 440,295-entry state; the 2026-07-27 instrumentation (472/398/322) predates the last
  +945-entry merge and should be re-run if the decoder-side legality-gating improvement is
  pursued. *(Note: legality-gating itself is a proven no-op — see below — so this re-run is
  only informative about the ambiguity/missing split, not a fix path.)*

**Decoder-side legality-gating — TESTED, NO-OP (2026-08-15).** Made the decode fast path
reject a single H0 candidate that dispatches to an ILLEGAL move (fall through to the full
scoring path), gated every candidate by legality. Result: **zero measurable effect** —
written/corrupted unchanged (8070/501), move-exactness unchanged (0/84 exact vs PGN), and
`probe_dump_moves` diff showed *no game's* decoded moves changed. The chess960 fast-path
single candidates are all already legal; the wrong/truncated decodes come from **ambiguity
among LEGAL moves**, which legality cannot resolve (the ambiguous/miss paths already apply
`checkMove`). Reverted. Conclusion: there is no quick legality win; the decoder already uses
legality where it matters, and it cannot disambiguate without a complete table (F algorithm,
route 1).

## MAJOR FINDING (2026-08-15): F is a deterministic 3-input function — but the decoder cannot use it

**Theoretical breakthrough:** `count_p = count_{p-1} + F(lc_{p-1}, lc_p, ply)` where **F is a pure
deterministic 3-input function**. Among clean-oracle trusted samples, F is **100% deterministic**
(2241/2241; `scripts/analyze_f_clean.py`). The earlier "322 ambiguous triples" were `lc` noise
(scidb's `lc` wrong for ~5% of moves), NOT genuine count_prev dependence. **Consequence:** the
440,295-entry 4-input H0 table is a redundant encoding of F, repeated across ~256 count_prev
values (~196× redundancy). Recovered via majority vote from the table (`scripts/build_f_table.py`,
436,367 triples) and from clean-oracle games (`scripts/build_f_clean.py`, 6,628 unanimous).

**But the decoder cannot use it:** completing the count table via F **regresses** decode in every
variant (F-first: 8020/551; H0-first F-fallback: 8047/524; strict clean-only F: 8045/526 — all
vs baseline 8070/501). Root cause: F (or any table completion) adds candidates, which the
decoder's fast path grabs or which create ambiguity that `walkContinuation` cannot resolve
(tie-check `bestScore-secondScore<1` fails). The bottleneck is the decoder's ambiguity
resolution, not table coverage. ChessBase decodes these same games correctly, implying it uses
a direct `lc=table[raw]-count` method (with a deterministically-tracked count) that scidb's
search-based approach does not replicate — recovering that exact method (static RE, route 1) is
the remaining path. All data-driven table-completion and legality-gating approaches are now
ruled out; reverted.

Recovered F tables: `src/f_table.json` (clean-oracle unanimous, 6,628 triples; see
`scripts/build_f_clean.py` for the merged 436,367 variant).
