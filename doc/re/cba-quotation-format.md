# .cba annotation type 0x13 (game quotation) — header solved

Status: 2026-09-06. Header grammar validated on all 17 real records in the
cbm168 fixture, cross-checked against the actual historical games they
quote (players, tournament, site, date, round, result all match public
record). No public documentation of this type exists; Morphy's
`annotations.md` lists it as "not done yet".

Method: extracted all 17 raw payloads, hand-derived the player-name framing
by byte inspection, then had `agy` extend it to the full header and
cross-validate every field against the real, identifiable historical games
these quotations cite (see evidence table below) — using
`src/db/cbh/cbh_decoder.cpp` as a reference for the expected shape of the
embedded quoted-game move blob.

## Grammar

Record payload (after the 6-byte `.cba` annotation header):

```
u16 BE   total_length       == the annotation length (redundant framing check)
u16 BE   name_count         always 2 (white, black)

-- white name:
u16 BE   lang               0 = English/default in the fixture
u8       len
bytes[len]  name             "Last,First"

-- black name (note: only a 1-byte language field here, unlike white's 2-byte one):
u8       lang
u8       len
bytes[len]  name

u8       flag               unknown, 0 in the fixture
u16 BE   white_elo          0 if unrated / pre-Elo era
u16 BE   black_elo
u16 BE   eco_raw            same packing as the classic .cbh index ECO field:
                             eco_index = (eco_raw >> 7) & 0x1ff (see convertEco
                             in cbh_codec.cpp - independently rediscovered here)

u8       event_len
bytes[event_len]  event_name

u8       site_lang
u8       site_len
bytes[site_len]  site_name

u16 BE   pad
3 bytes BE  packed_date     year = v>>9, month = (v>>5)&0xf, day = v&0x1f
                            (identical packing to setDate in cbh_codec.cpp)
u8       time_mode
u8       tournament_type    2=Match, 3=Tournament(RR), 4=Swiss (observed)
u16 BE   nation_id
u16 BE   category
u16 BE   total_rounds
u8       subround
u8       round
u8       result             0=0-1, 1=1/2-1/2, 2=1-0, 3=*
u16 BE   medals

-- remainder of the record: the quoted game's own move stream
```

Two formulas in this header (ECO packing, date packing) are byte-identical
to formulas already implemented independently for the classic `.cbh` index
(`convertEco`/`setDate` in `cbh_codec.cpp`) — strong internal corroboration
that the header layout hypothesis is correct, since they were derived from
this record type's data alone before comparing to the existing code.

## Historical cross-check (17/17 records)

Every quotation resolves to a real, identifiable game with the correct
date/result, e.g.:

| Players | Event / Site | Date | Round | Result |
|---|---|---|---|---|
| Kan – Capablanca | Moscow | 1936.05.14 | — | 0-1 |
| Karpov – Korchnoi | World Championship 29th, Baguio City | 1978.07.18 | 32 | 1-0 |
| Karpov – Kasparov | World Championship 32th-KK2, Moscow | 1985.09.03 | 2 | 1/2-1/2 |
| Carlsen – Anand | World Championship, Sochi | 2014.11.08 | 11 | 1-0 |
| Caruana – Carlsen | Norway Chess 3rd, Stavanger | 2015.06.16 | 2 | 1-0 |
| Polgar – Topalov | FIDE-Wch, San Luis | 2005.09.28 | 6 | 0-1 |
| Steinitz – Lasker | St Petersburg 1895/96 | 1895.12.13 | 4 | 1-0 |

(Full 17-record table in the session's scratch artifacts.)

## The embedded move blob (not decoded)

The quoted game's own moves follow the header directly, with no separate
4-byte `.cbg`-style framing (flags byte + 3-byte size) — the boundary is
just "rest of the annotation record". The first bytes of the blob are
**static across independent games sharing an opening** — e.g. every record
starting `1.e4 e5 2.Nf3 Nc6` begins with the identical 4 bytes `df 93 6c d8`
regardless of which quoted game it is — which is exactly what the existing
per-ply rolling cipher (`cbh_count_cipher.*`, keyed by move count from a
fresh start) would produce if the quoted game's cipher state is reset to
the beginning, i.e. this blob is presumed to reuse the standard `.cbg`
move encoding starting fresh (not the .cbg file's own running count from
elsewhere in that file).

This was not implemented in this pass: replaying it would need constructing
a `GameDecoder` over a synthetic stream (real blob bytes prefixed with a
synthetic all-zero 4-byte flags/startpos word, since `startDecoding()`
expects that framing) and converting the resulting move indices to SAN.
The header alone already delivers the practical value (identifying what
game is being cited); decoding the actual quoted moves is a clean,
separable follow-up.

### Attempted and reverted (2026-09-06)

Tried exactly the approach above: nested `GameDecoder` over
`[00 00 00 00] + blob`, looping `decodeMove()` (mainline only,
`skipVariations=true`), printing SAN via `Board::prepareForPrint` +
`Move::printSAN`. It ran without crashing (after fixing a `printSAN`
precondition — needs `prepareForPrint` called on the **pre-move** board,
captured before `decodeMove()` mutates the decoder's position) but produced
**the same single move, `1.g4`, for every one of the 17 records** regardless
of actual content, then immediately failed to decode a second move. Since
17 structurally distinct blobs cannot legitimately all start with the exact
same first move, this is a framing bug, not real data — most likely the
synthetic 4-byte prefix is wrong (either the wrong length, or real `.cbg`
per-game data has a different/no such prefix and `startDecoding()`'s first
`uint32()` read needs to consume something else), or the cipher's initial
`count` seed isn't actually 0 for an embedded quotation. Reverted rather
than ship plausible-looking wrong data. Next attempt should compare a
**known real quoted game's expected opening** (e.g. record 11 is
Caruana–Carlsen, Berlin Defence, so bytes should decode to `1.e4 e5 2.Nf3
Nc6 3.Bb5`) against the raw blob bytes/cipher output byte-by-byte to find
the actual framing offset, or use Ghidra to trace CBase26's own quotation-
rendering code path.

## Decoder implementation (2026-09-06)

`src/db/cbh/cbh_game_decoder.{h,cpp}`: `decodeQuotation()` parses the header
fields (skipping the embedded move blob) and renders:

```
Quoted game: <white> - <black>, <event>, <site> (<date>), round <n>, <result>
```

as a post-move text comment, via the same `appendTextAnnotation` path used
for 0x18/0x09. Player/event/site strings are decoded through the game's
UTF-8 codec (consistent with how ordinary comments are decoded) since names
may contain diacritics not present in the fixture sample. Fails safe on any
grammar mismatch: skips the record without desynchronizing the rest of the
annotation stream.

Verified: all 17 fixture records produce exactly one `Quoted game:` comment
each (17/17, matching the census); text output cross-checked by hand against
real chess history; `verify_cbh_write` round-trip passed; app suite 31/31.

## Open items

- The quoted game's own moves are parsed structurally (offset/length known)
  but not decoded to SAN — a real but separable follow-up.
- ECO/nation/category/tournament-type/medals fields are decoded but not
  rendered in the comment text (kept the change minimal); available in the
  header if a future pass wants richer output.

### Second attempt and revert (2026-09-06, later same day)

Tried the fix implied by the first attempt's own diagnosis: instead of a
synthetic `[00 00 00 00] + blob` prefix (which the first attempt used and
which shifts every real byte by 4), feed the raw blob directly into a
nested `GameDecoder` with an **empty** annotation stream (avoids the
`m_moveNo` constructor read touching the shared outer `.cba` stream) and
let `startDecoding()` consume the blob's own leading bytes as the real
`uint32` flags word, exactly as it does for a standalone `.cbg` record.

This is a real improvement over the first attempt — using
`GameDecoder::doDecoding(uint16_t* moves, unsigned length, Board&
startBoard)` (the same flat, annotation-free API `Line::printMove` uses in
production) and replaying with `Board::makeMove(uint16_t)` — but it is
**not sufficient**: on the `cbm168`/`CBM168.cbh` fixture it decoded cleanly
for a while, then hit a hard `M_ASSERT(from == to)` in
`Board::makeMove(Square, Square, ...)` (`db_board.cpp:6875`) — a board/move
desync partway through a real quotation blob, not a graceful decode
failure. `M_ASSERT` in this build aborts rather than throwing, so this is
**worse** than the first attempt's silently-wrong-but-stable output: it can
crash the app on real annotation data. Reverted immediately; the working
tree is back to the header-only `decodeQuotation()` from the commit above
(no move decoding attempted).

What this rules out: the blob is not simply "no header at all, moves start
at byte 0 with a fresh cipher" (first attempt's assumption) NOR simply "a
literal standalone `.cbg`-style record with its own leading flags word and
nothing else special" (this attempt's assumption) — at least not
uniformly across all quotation records. Something about the ongoing
board/cipher state desyncs partway through, which could mean: the flags
word *is* there but the move encoding beyond it still depends on outer
per-game cipher continuation state (contradicting the "reset to fresh
start" hypothesis noted above, which was inferred only from static leading
bytes, not verified move-by-move); or castling-rights/en-passant state
needs to be seeded from the citing game's actual position at the point of
citation rather than a bare standard start; or the blob has a still-
different framing entirely (e.g. a length-prefixed sub-record ChessBase's
own quotation renderer parses differently from a bare `.cbg` game).

Next attempt should not guess a third framing blindly. Recommended
approach: use Ghidra to trace CBase26.exe's own quotation-rendering code
path (a PyGhidra project "CBase26" already exists at `~/ghidra_projects`,
per the RE tooling notes) to find the actual function that decodes this
blob and read its framing directly, rather than continuing to infer it
from the `.cbg` format's known shape. Any future attempt MUST validate
move-by-move against the known Caruana–Carlsen Berlin Defence opening
(record 11: `1.e4 e5 2.Nf3 Nc6 3.Bb5 ...`) before trusting output past the
first move or two, and should add a legality/board-consistency check
per decoded move (not just catch `mstl::exception`, since `M_ASSERT`
violations in this build do not throw) so a desync fails safe instead of
crashing.

### Third attempt and revert (2026-09-06, later still) — reframes the problem

Two genuinely new, confirmed findings, no code changes kept (reverted; the
tree is back to the header-only `decodeQuotation()`):

**1. The blob byte-offset computation is confirmed correct.** Hex-dumped
the raw bytes at the header parser's own computed blob start for the
Caruana–Carlsen record: `df 93 6c d8 f8 59 0d c6 c2 ec 0a 5a a3 48 e6 98`
— exactly matching the earlier "static leading bytes" observation. The
grammar/offset hypothesis in this doc is not the problem; something else
is.

**2. The "cipher" framing in this doc is the wrong model for classical
(non-Chess960) decode — it's much simpler.** Re-reading
`Decoder::decodeMove` (`cbh_decoder.cpp`) line by line: the complex H0/seed
table machinery (`resolveCipherCount`, `s_cipher`, `pushCipherState`) is
used **only** when `m_useCipher` is true, i.e. Chess960 games. For a
classical game (`m_useCipher == false`, which a quotation of a standard
game is), the decode is a plain additive scheme:

```cpp
lc = MoveNumberLookup[Byte(rawByte - count)];
```

where `count` is just the 0-based move index, incremented by one per
decoded move. There is no "cipher state" to reset for a fresh start in
this path — the only free variable is the **starting value of `count`**.
Feeding the blob through a bare `Decoder` with `count` seeded at 0
(matching the doc's "reset to a fresh start" hypothesis) decodes `0xdf` at
count=0 to a nonsense move (`g4` from the start position) for every
record tried, regardless of the record's real opening — i.e. **seed 0 is
demonstrably wrong**, not merely unlucky. This was verified two different
ways (both reverted): a nested-`GameDecoder` version and a bare-`Decoder`
version calling the same `decodeMove` directly with `count=0`; both
produce the same wrong first move.

This reframes the open problem precisely: it is **not** a framing/offset
question (settled, see finding 1) and **not** really a "cipher" question
(there's no cipher to get right in the classical path) — it is purely
**"what is the correct starting value of `count` for an embedded
quotation blob?"** The most likely candidate, not yet tested safely: the
ply number of the citing move in the *outer* game at the point of
citation (i.e. the quotation's own encoder continues the outer game's
move-count sequence rather than resetting it, despite the doc's earlier
"fresh start" inference from static leading bytes — the static-bytes
observation only rules out a *per-game-content-dependent* seed, not a
*constant or position-derived* one).

**Safety note for whoever tries this next:** brute-forcing `count` by
replaying candidate seeds through `Board::makeMove`/`prepareForPrint` is
dangerous, not just wrong-output-prone — `Board::prepareForPrint`
(`db_board.cpp:1347`) throws `mstl::precondition_violation_exception` for
a large fraction of garbage decodes from wrong seeds, and this exception,
while catchable in principle, was observed escaping through to the Tcl
layer and silently killing the *entire* `toPGN` call for the game being
tested (not just the one quotation) when the replay loop wasn't
sufficiently guarded — losing output for unrelated, unaffected games in
the same test run. Any brute-force approach must either (a) wrap every
single per-move operation (`makeMove`, `prepareForPrint`, `printSAN`,
`doMove`) in its own `catch (mstl::exception const&)`, independently, not
just the outer loop, or (b) validate at the raw `lc` (logical code) level
using `MoveNumberLookup` and a legality table **before** ever constructing
a `Move`/`Board::makeMove` call, avoiding the precondition-throwing APIs
during search entirely. Approach (b) is recommended — it's also much
faster (256 candidate seeds × ~20 plies of pure table lookups, no board
object churn) and inherently exception-free. Ghidra-tracing CBase26's own
quotation-replay code (as recommended above) to read the seed directly is
still the most reliable path and avoids brute-forcing altogether.

### Fourth attempt (2026-09-06, later still) — exhaustive brute force, both remaining hypotheses conclusively ruled out

Built and ran the safe brute-force approach (b) above, then extended it: a
temporary `Decoder::bruteForceQuotationSeed()` tried every one of the 256
possible starting values of `count` against real quotation records pulled
live from the `cbm168`/`CBM168.cbh` fixture (16 distinct records recovered
via a throwaway Tcl probe driving `::scidb::db::load` + `::scidb::game::load`
+ `::scidb::game::toPGN`, with a temporary `fprintf` in `decodeQuotation()`
dumping each record's citing ply and raw blob bytes). Two safety layers
were used per the note above: `lc >= 0xec` (Push/Pop/Skip token) rejection,
and *also* calling the real `Decoder::decodeMove()` (not a hand-rolled
byte walk) so multi-byte cases such as ambiguous-pawn-promotion codes,
which read extra bytes directly from `m_gStrm`, are handled exactly as
production does — an earlier version of this harness that read bytes by
hand mis-handled these and threw spurious `unexpected end of stream`
exceptions that escaped uncaught, exactly the hazard the previous attempt
warned about; wrapping every `decodeMove()` call in `catch (mstl::exception
const&)` and rejecting on any exception fixed this.

**Harness validated with a positive control** before trusting any negative
result: fed the harness 40 real raw bytes captured from an ordinary
(non-quotation) game's move stream in the same database, decoded via the
existing, already-correct production path. Result: **exactly 1 of 256
seeds decoded cleanly (seed 0), and it was the expected one** — ordinary
`.cbg` game streams are known to start `count` at 0. This confirms the
harness neither over- nor under-accepts.

**Finding 1 — the "seed = citing ply" hypothesis is conclusively false,
independent of any decode attempt.** Multiple *different* quotations in
this fixture, cited from wildly different points in their respective
citing games (0-based ply 5, 15, 16, 19, 49, 226, 559 — captured directly
from `m_moveNo` at the `decodeQuotation()` call site, which is exactly the
citing move's 0-based ply index; see `getAnnotation(node, int(count) - 1)`
in `cbh_game_decoder.cpp`), quote the **same** underlying game (recognizable
by identical event/date and, notably, byte-for-byte identical raw blob
bytes for as many bytes as the shorter of the two records covers — e.g.
Caruana–Carlsen at ply 5, Polgar–Kasimdzhanov's Berlin-opening citations at
plies 15/16, and Carlsen–Anand at ply 49 all begin
`df 93 6c d8 f8 59 0d c6 c2 ec ...`). If `count`'s starting value depended
on the citing ply, encoding the *same* quoted moves from *different* citing
positions would necessarily produce *different* raw bytes (since
`raw = InverseMoveNumberLookup[lc] + count`). It doesn't — the bytes are
identical. This is a structural proof requiring no move-decode success at
all, and it survives independent of everything below.

**Finding 2 — no fixed global constant seed works either, and the model
breaks almost immediately.** Ran the validated harness against all 16 real
quotation blobs from the fixture, requiring 15 consecutive legal
`Token_Move` results (a bar the positive control cleared easily at 15/15).
**Zero of the 256 seeds produced even a single clean decode for any of the
16 records.** The single best result over all seeds × all records was 3
consecutive legal moves (seed 209, one record) — most seeds for most
records fail at move 1 or 2. This rules out "reset to a fixed constant
count" (0 or otherwise) as cleanly as Finding 1 ruled out "seed = citing
ply" — not a wrong-seed problem, a wrong-model problem.

**Combined, these two findings exhaust the entire realistic seed-search
space** (constant vs. citing-context-derived) using the real production
decode machinery, not a simplified reimplementation. The doc's standing
model — "reuses the standard `.cbg` per-move decode, `count` free variable,
fresh start" — is now disproven in both of its natural specializations.
Something more fundamental is different: either the move-token table
itself differs for embedded quotations (a different `MoveNumberLookup`,
analogous to how Chess960 games use `Chess960MoveNumberLookup` and a
different formula entirely), or there actually is additional framing/a
sub-header immediately before the move bytes that has not been identified
(consistent with the second attempt's suspicion of "a length-prefixed
sub-record ChessBase's own quotation renderer parses differently from a
bare `.cbg` game" — not yet tested because the *classical* per-move formula
was assumed correct up to the seed).

All debug/experimental code from this attempt was reverted; the working
tree is unchanged from the header-only `decodeQuotation()`.

**Recommended next step, now sharper than before:** Ghidra-trace
CBase26.exe's actual quotation-move-replay function (not the PGN-tag
dispatch table already found while solving 2CBH Elo — a different,
unrelated function) to read the real table/formula/framing directly,
rather than continuing to assume it must be a variant of the classical
per-move scheme. Given the classical scheme is now ruled out in every
constant/derived-seed form, the quotation replay most likely calls into
either the Chess960 decode path (a different table, independent of
whether the quoted game is actually Chess960) or a third, not-yet-seen
table/routine dedicated to quotations — either is a concrete, falsifiable
hypothesis Ghidra can answer directly, rather than more brute forcing.

### Fifth attempt (2026-09-06, later still) — Ghidra: found a 16-table variant dispatch, quotation table still unidentified

Followed the recommended next step: traced `decode_caller`/`permove_decode`/
`dispatch_CBH` (`FUN_140210bc0`/`FUN_140210e10`/`FUN_14020c080` — the exact
addresses already named in `cbh_decoder.cpp`'s Chess960 comment as the
breakpoints used to find `Chess960MoveNumberLookup`) via PyGhidra against
the existing analyzed `CBase26` project (`~/ghidra_projects/CBase26`).

**Housekeeping note:** the stale reference script at
`docs/ghidra_2cbh/decompile2cbh_run.py` opens the project with
`PROJ_DIR="~/ghidra_projects"` — one directory level too shallow (the real
project root is `~/ghidra_projects/CBase26`, i.e. `ProjectLocator` wants
`(path=~/ghidra_projects/CBase26, name=CBase26)`). Copying that script's
constant literally fails with a misleading `FileNotFoundError: Project
"CBase26" not found`, which looks like project corruption but isn't -
worth fixing in that script if anyone reuses it as a template.

**Finding: a 16-distinct-table move-decode dispatch, not just
classical-vs-Chess960.** `decode_caller`'s only real (non-data) xref is
from `FUN_14020f170`, which switches on `*param_1 & 0x3f` (a 6-bit
variant/flags field read from the decoder's state object) and, for each
of 22 case values (0-0x15 plus 0x3f), stores a *different* 256-byte table
pointer into the object before calling `decode_caller` - e.g. case 10
stores `&DAT_141a799c0`, which is exactly the already-known
`Chess960MoveNumberLookup` address. Several cases alias the same table
(12/16, 13/17, 14/18, 15/19/0x3f), giving **16 distinct table addresses**
in the range `0x141a783c0`-`0x141a7a7c0` (stride `0x200`), plus an
implicit default (case 0 leaves the object's pre-existing table pointer
untouched).

Like `Chess960MoveNumberLookup`, these tables are runtime-built - all-zero
in the static `.exe` image, confirmed by reading them directly from the
Ghidra-analyzed program. Dumped all 16 from a **live** CBase26.exe process
under Wine by extending `scripts/dump_cbase26_tables.py`'s existing
ptrace technique to the range `0x141a783c0`-`0x141a7a9c0` (9,728 bytes).
Every one of the 16 is a valid permutation of 0-255 (i.e. all are
structurally plausible `MoveNumberLookup`-style tables, not padding/
unrelated data). **Case 0's table is byte-for-byte identical to scidb's
own classical `MoveNumberLookup`** (first 16 bytes: `a2 95 43 f5 c1 3d 4a
6c 53 83 cc 7c ff ae 68 ad`, matching exactly) - strong corroboration both
that the dispatch-table reading is correct and that scidb's classical
table is the right one for case 0.

**This does not close out the quotation blob.** The previous fork already
disproved "classical table (case 0), any of 256 seeds" via real
move-legality checking. This pass reveals **15 other tables that have
never been tried** (cases 1-9, 11-21 - everything except case 0/classical
and case 10/Chess960), any of which is a live, concrete candidate for
whatever table a quoted-game blob actually uses. A cheap proxy filter
(reject `lc >= 0xec` for the first several bytes, `count` seeds 0-19) was
tried as a fast triage across all 16 tables but is **far too weak to be
useful** - a spurious 16-byte "clean" run over random table/seed
combinations occurs by chance often enough (dozens of hits across the
sweep) that it cannot discriminate a real decode from noise. Testing these
15 tables properly needs the same rigor as the previous fork's harness:
the real `Decoder::decodeMove()`/`dispatchMove()` and actual board
legality checking (via `mstl::exception`-guarded per-move calls, never
raw `Board::makeMove`/`prepareForPrint` without per-call isolation - see
the safety note above), which requires wiring a C++ test harness, not
achievable in this pass's remaining time.

**Next concrete step:** extend the previous fork's validated brute-force
harness (real `Decoder::decodeMove()`, per-move exception isolation,
positive-control-verified) to try **all 16 dispatch tables × 256 seeds**
against the 16 real quotation blobs, not just the classical table. The
table byte arrays themselves are cheap to re-obtain (live ptrace dump per
above, ~10s once CBase26 is running under Wine) or can be hardcoded from
this session's dump if reproducibility is a concern. If none of the 16
tables + any seed produces a clean decode either, that's a much stronger
signal the blob isn't a `MoveNumberLookup`-family scheme at all (i.e. a
genuinely different formula/framing, not just a different table) and the
next step would shift to finding the *quotation-specific* caller of
whichever table is eventually implicated, or a completely distinct
decode function elsewhere in CBase26 not yet located.

No code changes in this pass; all Ghidra/dump scripts were scratch work
under `/tmp`, not committed. Working tree unchanged except this doc entry.

### Sixth attempt (2026-09-06, later still) — exhaustive 19-table × 256-seed brute force: conclusively negative

Executed the previous attempt's recommended next step. Extended
`scripts/dump_cbase26_tables.py` with a `variant_tables.bin` region
(`0x141a783c0`, `0x2600` bytes — covering all 16 dispatch-table addresses
identified previously plus a few extra slots for margin) and live-dumped
19 distinct 256-byte tables from a running CBase26.exe under Wine. Table 0
matched scidb's classical `MoveNumberLookup` byte-for-byte; table 11
matched `Chess960MoveNumberLookup` byte-for-byte — both exact matches,
confirming the dump addresses/stride are correct.

Extracted all real quotation move blobs directly from the `cbm168`
fixture set (`Data Collect/CBM168.cbh`, `168Strategy.cbh`,
`168Move by Move.cbh`, `168Training.cbh`) via a temporary debug print in
`decodeQuotation()` dumping each blob's raw hex — 15 records recovered,
including the Caruana–Carlsen (Berlin) record used as the standing
verification target in earlier attempts.

Built a scratch brute-force harness (`quot_bruteforce.cpp`, not committed)
linking the real production `Decoder`/`Encoder` classes directly via a
temporary `cbhTestSetTableOverride()` hook and a
`decodeEmbeddedMovesTest(moves, length, seed)` entry point (both reverted
after this pass), rather than a hand-rolled reimplementation.

**Critical harness bug found and fixed before trusting any result:**
`Position::doMove()` (`cbh_decoder_position.cpp`) does **not** throw on an
illegal decoded move — it silently returns `Move::empty()`. The standing
assumption (that `dispatchMove()`'s move-construction throws on illegal
geometry, making a `try`/`catch` around each move sufficient) is false.
An earlier version of this pass's harness that only checked for thrown
exceptions reported spurious 64/64 "clean" decodes for table 0 at many
seeds — directly contradicting the fourth attempt's finding that table
0/any-seed maxes out at 3 consecutive legal moves. The fix: treat a
returned empty `Move` as decode failure too, not just a caught exception.
After the fix, table 0's results **exactly reproduced** the fourth
attempt's numbers (e.g. seed 209 on the Karpov–Kortschnoj-shaped blob
again tops out at 3 moves) — strong confirmation the harness is now
correctly calibrated. (Anyone reusing `Decoder`/`Position` for future
legality-checked brute forcing must apply the same empty-move check.)

**Positive control:** encoded 16 real moves from the true start position
in one `Encoder` session (an Italian-Game-shaped sequence, no castling),
stripped the 4-byte size-placeholder header `startEncoding()` always
writes (headerless streams are exactly what `decodeEmbeddedMovesTest`
and the real quotation blob both are), sized the decode buffer exactly to
the encoded byte count, and required all 16 decoded move indices to match
the encoded ones exactly. **Passed.**

**Result: zero winners across all 19 tables × 256 seeds × 15 real blobs**,
requiring 15 consecutive legal moves per blob (same bar as the fourth
attempt). The best result over the *entire* search space was 5 consecutive
moves (one blob, table 2, seed 150); most (table, seed, blob) combinations
still fail at move 1-3, matching the shape of the earlier classical-only
negative result. This is a materially stronger and more complete negative
result than the fifth attempt's Ghidra findings alone: it proves not just
that a 16-table dispatch *exists*, but that **none of those 16 tables (nor
the 3 extra dumped for margin) work for the quotation blob under any of
the 256 possible starting counts**, using the real production decode
machinery with a validated legality gate.

**This effectively rules out the entire "quotation blob reuses some
`MoveNumberLookup`-family table with a free seed" hypothesis space.**
Also checked the quotation header's already-decoded `flag` byte (the byte
immediately preceding the two Elo fields) as a possible table/variant
selector per the standing recommendation to look there — it is `0` in
every one of the 15 recovered records, so it carries no discriminating
signal here (though this doesn't rule out a variant selector elsewhere in
the header that simply happens to be constant across this particular
fixture's records, all of which are standard, non-Chess960 games).

**Recommendation:** stop brute-forcing seeds/tables against this field.
Every combination in that space has now been tried exhaustively and
failed. The only remaining productive avenue is Ghidra: trace CBase26's
*actual quotation-rendering call site* forward from the confirmed
`decode_caller`/`dispatch_CBH` machinery (or backward from wherever the
0x13 annotation type is dispatched in the `.cba` reader) to find whatever
function actually replays a quotation's moves for display — it almost
certainly is not a `MoveNumberLookup`-table consumer at all, given how
thoroughly that entire family has now been eliminated. This is real,
targeted static-analysis work (find one specific function and read what
it does), not another parameter sweep. Absent that, this field should be
considered closed for now: header decoding ships and works; move replay
is a known, well-characterized permanent gap pending that specific
Ghidra trace.

All scratch code (`quot_bruteforce.cpp`, the `cbh_decoder.{h,cpp}` test
hooks, the `decodeQuotation()` debug prints) was reverted; the working
tree is unchanged except this doc entry and the `dump_cbase26_tables.py`
region addition (kept — legitimate, reusable, zero-risk dump tooling, not
a guess).

### Sixth attempt (2026-09-06, later still) — Ghidra call-site trace: two dead ends ruled out, real dispatch not yet found

Followed the recommendation above to trace CBase26's actual quotation-rendering
call site rather than sweep more parameters. Two concrete leads were chased
down and ruled out; the real dispatch function was not located within budget.

**Lead 1 — constant-CMP scanning across `.text`: too noisy to be useful.**
Scanned every `CMP`/`SUB` instruction in the binary for immediate operands
matching the annotation-type bytes already solved (`0x07, 0x09, 0x13, 0x16,
0x17, 0x18, 0x24`), on the theory that the general `.cba` item-type dispatch
would reference several of them together in one function. This produced ~19
functions referencing 3+ of these values, but every one decompiled was an
unrelated coincidental hit — a file-extension-string table (`param_2==0x13`
→ `"cbt"`), a hyperlink-type factory (`CBaseVideoLink`/`CBaseKeyLink`/
`CBaseAliasAudioLink` — a completely different "link type" enum that also
happens to use small integers including `0x13`), an ECO/country lookup
table, and a hard-disk-cache file-path builder. These small integers are
too common throughout a 15MB binary for this search strategy to isolate the
real dispatch; **not recommended as a technique for whoever continues this.**

**Lead 2 — `AnnoGameQuotationCmd` RTTI class: real class, wrong layer.**
Found via plain `strings` on the exe (`Gamequot.cpp` debug path, RTTI class
names `AnnoGameQuotationCmd`/`DeleteGameQuotationCmd`). Traced the
constructor (`FUN_1408f9d90`) to the class's actual vftable address
(`0x14122f210`, confirmed via direct disassembly — `LEA RAX,[0x14122f210]`)
and dumped all 20 virtual slots. It overrides exactly **two** slots from
its base `CBaseGameCommand` (vftable `0x14122c398`): slot 0 (destructor,
`FUN_1408282a0`) and slot 13 (`thunk_FUN_1409de920`, decompiled in full —
it's a *menu-enablement predicate*: checks a frame-window RTTI cast and a
bitmask flag comparison, returns bool, contains no stream/blob access at
all). **This class is a toolbar/menu "insert a game quotation" UI command,
not the annotation-record reader/renderer** — it has no decode logic
whatsoever. This rules it out cleanly and clarifies that the real
byte-stream parser (which must exist, given classical `.cba` records
clearly get *read back and rendered* when browsing an existing game) is
architected differently — most likely a generic, non-RTTI, switch-on-type-
byte function in the same family as `decode_caller`/`dispatch_CBH`
(already found and fully characterized for *move* decoding), rather than
one polymorphic class per annotation type.

**Not yet tried, concrete next steps for whoever continues:**
- Search for the generic `.cba`/annotation-stream *reader* (not the *insert
  command*) by tracing backward from a known call site instead of forward
  from a name: find where `decode_caller`/`dispatch_CBH` themselves are
  invoked from (their callers, not their callees) — the caller is almost
  certainly the general per-move/per-annotation stream walker, and the
  annotation-type dispatch is likely a sibling switch inside or adjacent to
  that same walker function, reachable by one hop from known-good addresses
  rather than a blind binary-wide scan.
- Alternatively, set a Ghidra/x64dbg breakpoint on `decode_caller` itself
  while manually opening a game containing a quotation in a live CBase26
  session under Wine, and inspect the call stack at that breakpoint — this
  sidesteps static analysis entirely and directly answers "does quotation
  rendering call this function at all, and if not, what calls happen
  instead" with certainty, which six passes of static guessing have not
  achieved. This is the most promising untried avenue.

No code changes. All working files from this pass were scratch (`/tmp/*`,
not committed). Tree unchanged from the prior commit.

### Eighth attempt (2026-09-06, later still) — live-debugging tooling groundwork, no call stack captured

Followed the recommended next step: attempt to breakpoint `decode_caller`
(`0x140210bc0`) live under Wine and read the call stack while opening a
quotation. This is genuinely useful negative tooling knowledge even though
no call stack was captured — the next attempt should start from here
instead of re-discovering the same friction.

**Confirmed working:**
- `winedbg` and `gdb` are both installed and usable in this environment.
- CBase26.exe's load base under Wine is a fixed `0x140000000` with no
  ASLR offset — Ghidra's static addresses (e.g. `decode_caller` at
  `0x140210bc0`) are directly usable as runtime breakpoint addresses, no
  translation needed. Confirmed via `/proc/<pid>/maps`.
- The database this fixture lives in (`cbm168/Data Collect/CBM168.cbh`)
  opens fine in CBase26's native UI via File → Open, typing the Wine path
  `Z:\media\michael-g-thomas\sas_mirror\fixt\cbm168\Data Collect\CBM168.cbh`
  directly into the file-open dialog's Name field (faster than
  browsing the tree). It renders WhiteElo/BlackElo columns natively — a
  nice incidental visual confirmation of the already-solved 2CBH Elo
  offsets, though this is a classical `.cbh` file so not the same code
  path.
- Xvfb display `:77` (already running, a dedicated headless instance from
  earlier RE work, distinct from the user's real desktop on `:0`) is safe
  to drive with `xdotool`/`import` for GUI automation without risking the
  user's actual session — confirmed by checking the target PID's
  `DISPLAY` env var in `/proc/<pid>/environ` before touching it. Do this
  check before ever attaching/killing a CBase26 process found via `ps`.

**Confirmed NOT working / genuine obstacles:**
- `gdb -p <pid>` attach to an *already-running* CBase26.exe fails outright:
  `kernel.yama.ptrace_scope=1` in this environment only permits a tracer to
  attach to its own descendants, and the already-running instance (left
  over from an earlier fork's session) is not a descendant of the shell
  doing the attaching. **Fix:** launch CBase26 as a child of gdb itself
  (`gdb --args <real-elf> CBase26.exe`), not attach after the fact.
- `wine`/`wine64` are POSIX shell script wrappers (`file` confirms), not
  ELF — gdb refuses to load them as the debuggee directly ("not in
  executable format"). **Fix:** trace the wrapper (`cat /usr/bin/wine64-stable`)
  to the real ELF it execs — in this environment
  `/usr/lib/x86_64-linux-gnu/wine/wine` — and pass *that* to `gdb --args`.
  This part worked: gdb successfully launched the real wine ELF as its
  child and it ran CBase26.exe within the same process (no further exec
  boundary to worry about).
- Setting the breakpoint *before* `run` fails with `Cannot access memory
  at address 0x140210bc0`, because Wine's PE loader hasn't mapped
  CBase26.exe's `.text` into the process yet at that point — gdb's normal
  "pending breakpoint" auto-resolution (which watches ELF `dlopen`/shared-
  library-load events) does **not** fire for Wine's own PE-image mapping,
  since that isn't a tracked ELF shared-library event. The breakpoint must
  be set *after* the module is mapped, which in practice means after the
  main window has appeared (10-20 seconds of Wine/DXVK/UI startup).
- Getting gdb to run the process, wait for it to finish initializing, and
  *then* set the breakpoint - without a fixed, reliable synchronization
  point - was not solved in this pass. Tried: sending `SIGINT` to the gdb
  process from a second shell after a fixed sleep, hoping gdb would
  interrupt the inferior and resume executing the rest of the command
  script (setting the breakpoint, then `continue`). This did not behave
  as hoped: the signal landed on an unrelated Wine-internal worker thread
  (`SIGUSR1`, part of Wine's own thread-suspension mechanism) rather than
  cleanly halting at a script-continuable point, and the batch-mode gdb
  session terminated (auto-answering "Quit anyway? Y" on the resulting
  prompt) instead of proceeding to the next command in the script.
  Backgrounding gdb with `nohup ... &` and re-signaling from a second
  shell command in this harness also proved fragile in its own right (one
  attempt silently failed to even start due to a heredoc/compound-command
  ordering mistake — worth writing the gdb command file and confirming it
  exists with a separate step before launching gdb, not inline in the same
  compound command).

**Concrete next steps, more specific than before:**
- Don't fight `SIGINT`-based synchronization. Use gdb's own `python`
  scripting inside the command file to block until the target module is
  mapped (poll `gdb.selected_inferior().read_memory(0x140210bc0, 1)` in a
  loop with `time.sleep`, wrapped in `try/except gdb.MemoryError`) before
  issuing `gdb.execute("break *0x140210bc0")` — this stays inside a single
  synchronous gdb session and avoids the cross-process signal-timing
  problem entirely.
- Alternatively, use `winedbg --gdb` (Wine's own built-in gdb-remote proxy)
  instead of attaching gdb directly to the wine ELF process — it's
  designed specifically for debugging the *guest* Windows process's
  address space and may handle the PE-mapping timing correctly out of the
  box, sidestepping the pending-breakpoint gap entirely. Not tried in this
  pass; worth trying first next time, before another custom gdb
  synchronization scheme.
- Once a breakpoint reliably lands: still need to identify which specific
  game in the ~700+-game `CBM168.cbh` fixture contains a quotation, to
  actually exercise the code path. Player-name search in CBase26's own
  "Players" filter dialog (typed "Polgar", "Kasimdzhanov" — both named in
  the prior fork's report as citing-game players) returned zero results
  in this pass, either because the dialog needs a different interaction
  (autocomplete list never populated, suggesting the typed text wasn't
  actually registering as a filter term) or the specific sub-file opened
  doesn't contain those exact games. Worth resolving this identification
  step *before* the next debugging attempt, e.g. by finding the true
  citing-game numbers directly from scidb's own already-correct header
  decode (needs the right `::scidb::db::open` invocation for a classical
  `.cbh` file - the generic one used elsewhere in this project's test
  suite is for `.sci`/`.si4` and rejects `.cbh` with "unsupported
  extension"; the classical-cbh-specific open command wasn't identified
  in the time available this pass).

No code changes. Working files were scratch (`/tmp/gdb_*.txt`, `/tmp/*.log`,
`/tmp/*.png`, `/tmp/find_quote_games.tcl`) and were not committed. All
CBase26/gdb processes spawned in this pass were killed cleanly before
finishing; the pre-existing CBase26 instance on Xvfb `:77` that this pass
found already running (and had to kill to gain ptrace access) was not
restored, since it held no unsaved state - it was the same idle
fixture-browsing instance from an earlier fork's session. Tree unchanged
from the prior commit except this doc update.

### Ninth attempt (2026-09-06, later still) — working breakpoint achieved via `winedbg --gdb --no-start`; no quotation triggered

Solved the exact blocker the previous pass hit (gdb's pending-breakpoint
mechanism never firing for Wine's PE-image mapping). The fix: don't attach
gdb to the Wine ELF process at all. Use `winedbg --gdb --no-start
<CBase26.exe path>` instead — `winedbg` launches the target itself, halts
it after Wine's own PE loader has already fully mapped the module (proven:
the reported stop address on first connect, e.g. `0000000140FB259C`, is
already inside CBase26's own `.text`), starts a gdb-remote server, and
prints the exact `target remote localhost:<port>` command. A plain `gdb -q`
connecting to that port can then set `break *0x140210bc0` (`decode_caller`)
immediately — no polling, no synchronization hack, no ELF/PE event
mismatch. `continue` resumes the target normally; the breakpoint is real
and armed (confirmed: process visibly running, no crash, CPU active) but
was never hit in this pass because no quotation was actually opened in the
UI. **This resolves the "no reliable synchronization point" problem the
last three passes were stuck on and should be the standard way to attach
for any future live-debugging pass on this codebase.**

Two safety/environment notes for whoever reuses this:
- **Always pass an explicit headless `DISPLAY`** (`DISPLAY=:<n> winedbg
  --gdb --no-start ...`). Without it, CBase26 inherits whatever `DISPLAY`
  the launching shell has — in one instance in this pass that was the
  user's own real desktop (`:0`), and a live GUI window nearly opened
  there unattended. Caught before any mouse/keyboard input was sent to it
  and killed immediately; no interaction with the user's real session
  occurred. Confirm via `cat /proc/<pid>/environ | grep DISPLAY` before
  ever touching a CBase26 process found via `ps`, per the existing rule
  in the eighth attempt above, and *also* explicitly export/prefix
  `DISPLAY` on every launch rather than relying on inherited environment.
- **The headless Xvfb screen must be tall, not just wide.** No window
  manager runs under a raw Xvfb server, so CBase26's windows get no
  decorations and cannot be moved, resized, or maximized — whatever
  height the app requests is what you get, clipped to the virtual
  screen's actual size with the excess simply unreachable. At
  `1400x900` the board/notation editor view was clipped after ~5 ranks
  with no way to reach the notation pane, the "File name" field of the
  Open dialog, or anything below the fold. Raising the virtual screen to
  `1920x2000` fixed this completely and is the size to start with next
  time.

Once a headless CBase26 instance was properly up (on `:251` at
`1920x2000`), extensive UI navigation was spent trying to locate a game
containing an existing `0x13` quotation to open, without success within
budget:
- Typing a Wine path (`Z:\...\CBM168.cbh`) directly into what was assumed
  to be the Open dialog's filename field, after `Alt+N`, unexpectedly
  opened an unrelated single-game file (`game_757`, a 2026 Carlsen game)
  instead — most likely `Alt+N` did not focus a filename field at all
  (no such field was ever visually confirmed) and `Return` simply
  activated whatever icon happened to be selected in the "My Databases"
  icon view at the time. This path-typing approach is unverified and
  should not be reused as-is; navigating the folder tree by clicking
  worked reliably where tried.
- Opened `CB Light Database.cbh` (14,831 games, historical 1851 London
  tournament onward) successfully via icon double-click, confirming the
  icon-view double-click / select-then-`Return` pattern **does** work
  once a window has real screen space (unlike the earlier `1400x900`
  attempts, where the same pattern appeared to silently fail — most
  likely because the target element was simply off-screen, not because
  the interaction technique was wrong).
- The `Ctrl+F` → "Advanced" → **Annotations** tab of the search-filter
  dialog was found and inspected in detail — it exposes `Text1`/`Text2`
  free-text search over annotation content, a `Symbols` field, and
  checkboxes for `Training`, `Multimedia`, `Pawn structure`, `Piece path`,
  `Variations`, `Critical Opening/Middlegame/Endgame Position`, etc., but
  **no dedicated "Game Quotation" checkbox or annotation-type selector**.
  A quotation-containing game cannot be isolated through this dialog by
  type; `Text1` free-text search might work if the right search string
  were known, but CBase26 renders a quotation as a clickable embedded
  sub-game widget, not literal searchable text, so there is no obvious
  string to search for.
- The `::scidb::db::load` + `::scidb::game::load` Tcl approach (used
  successfully by earlier forks for byte-level extraction) was retried to
  enumerate `CBM168.cbh` game-by-game looking for scidb's own
  `"Quoted game:"` decoded-comment marker, as a way to identify the
  citing game's number without touching CBase26's UI at all. Got as far
  as correctly loading the database and reading `::scidb::db::count total
  <path>` (717 games, matching prior forks' fixture description), but
  `::scidb::game::load <slot> <path> <variant> <index>` — note the
  argument order requires `<variant>` before `<index>`, `<slot>` must be
  in `0`-`8` (the app's fixed 9 editor slots; slot `9` segfaults
  immediately) — still segfaulted on the very first game after fixing
  those two mistakes; root cause not found (plausibly the same "editor
  GUI infrastructure not initialized" class of problem as the missing
  `pgn:$i`/`frame:$i` Tcl state seen when driving `app-pgn.tcl` headlessly
  in an unrelated debugging session earlier today — `game::load` may
  assume a built UI exists). Not resolved; abandoned in favor of the
  live-CBase26 UI route above.

**Honest final assessment after nine passes across static Ghidra analysis,
exhaustive brute-force decoding, and now live debugging tooling:** the
*hard* part of live-debugging (getting a reliable breakpoint on real
target code with a clean, reproducible attach procedure) is now solved and
documented above. The *remaining* blocker is entirely mundane — reliably
navigating CBase26's own GUI, headless, to a database and game known to
contain a `0x13` quotation, then triggering the annotation's render. This
is very likely solvable with more patient, incremental UI probing (one
action, one screenshot, verify, repeat — rather than chaining several
actions between screenshots as this pass sometimes did) now that the
`1920x2000`/no-WM clipping problem is understood, or by resolving the
`game::load` segfault to identify the target game programmatically instead
of hunting through the UI blind. Recommend one more pass specifically
scoped to "find and open a quotation-containing game and confirm the
annotation is visibly rendered" as its *only* goal (no debugging yet) —
proving the render is reachable before spending another attempt wiring up
the breakpoint dance around it. If that pass also fails to find a
renderable quotation, the next fallback is the `Text1` annotation search
with trial strings, or resolving the `game::load` segfault so scidb's own
already-correct header decode can name the exact citing game.

No code changes. All CBase26/winedbg/gdb processes and the dedicated Xvfb
displays (`:250`, `:251`) used in this pass were killed and cleaned up.
Working files were scratch (`/tmp/gdb_quot_bp.py`, `/tmp/gdb*_cmds.txt`,
`/tmp/gdb*_in` FIFOs, `/tmp/gdb*_out.log`, `/tmp/winedbg_out*.log`,
`/tmp/find_quote_games*.tcl`, `/tmp/quot_*.png`) and were deleted, not
committed. Tree unchanged from the prior commit except this doc update.

### Tenth attempt (2026-09-06, later still) — target identified without CBase26's UI search; render confirmed live; new headless-input finding

Scoped narrowly to the prior pass's own recommendation: find a
quotation-containing game and confirm it renders, nothing else (no
debugging).

**Target identified without touching CBase26's UI at all**, sidestepping
the blind search that stumped the eighth/ninth passes. Rather than
resolving the `game::load` segfault, used scidb's own already-working,
already-correct `decodeQuotation()` header decode via the *existing*,
already-headless-safe `::scidb::game::printHtml <database> <variant>
<gameIndex> <file> <flags>` command (no editor slot, no `game::load`, no
segfault — this command was already used successfully by earlier forks
for PDF export via the sibling `printPdf`) with
`Flag_Include_Variations|Flag_Include_Comments|Flag_Include_Annotation`
(`7`), looping every game in every `.cbh` fixture under
`/media/michael-g-thomas/sas_mirror/fixt/cbm168/` (27 files) and grepping
each game's rendered HTML for scidb's own `"Quoted game:"` marker text.
Found 13 real matches across 4 files in under two minutes of runtime.
**`Sinquefield Cup 2015.cbh`, game index 6 (0-based; row 7, 1-based UI),
White=Caruana Black=Carlsen, round 2** carries the standing target
quotation (Caruana-Carlsen, Norway Chess 2015, cited at 3...a6) and is a
small, easy-to-navigate 46-game file — a much better target than blindly
hunting through the 700+-game `CBM168.cbh`.

**Confirmed the quotation renders, live, in CBase26 itself** — this had
never actually been observed before this pass; every prior pass only had
scidb's own decode as evidence the text existed. Screenshot evidence: with
that game loaded, the notation pane shows `1.e4 e5 2.Nf3 Nc6 3.Bb5 a6`
directly followed by *"There is little wonder that Carlsen avoids the
Berlin after the recent defeat by Caruana's hands in `1-0 Caruana,F
(2805)-Carlsen,M (2876) Norway Chess 3rd Stavanger 2015 (2)`"* — with the
game-citation substring rendered in a visually distinct color (red/orange)
from the surrounding annotation prose. **This settles an assumption every
prior pass implicitly made and never verified: quotations do NOT render as
a separate embedded sub-board/sub-game widget.** They render as an inline,
distinctively-colored (and presumably clickable, though click-through was
not tested) hyperlink-style span *inside the flowing annotation comment
text*, indistinguishable in the extracted plain-text HTML from an
ordinary styled game citation. Every prior static-analysis
pass's search for a "quotation rendering function" or "quoted-game
sub-board widget" may have been searching for the wrong kind of UI
element; the real target is more likely a rich-text/hyperlink-run
formatter that colors a citation span and attaches a quoted-game reference
to it, closer in kind to how the *other* inline game-citation colored
spans in the same comment (e.g. the `0-1 Hellers,F (2520)-Shirov,A (2580)
Khanty-Mansiysk 2009` seen later in the same game's annotations) are
rendered — those are NOT `0x13` quotations (no separate annotation record
backs them; they're just colored text Marin typed/formatted directly), so
the two need to be distinguished carefully in any future Ghidra pass, but
they share a rendering mechanism worth investigating together.

**New environment finding, distinct from all prior tooling notes**: mouse
clicks (`xdotool click`/`mousedown`/`mouseup`, confirmed via `xdotool
getmouselocation` to land on the correct window/coordinates, with input
focus confirmed via `xdotool getwindowfocus`) are **not delivered** to
CBase26 windows under this project's headless Xvfb setup (no window
manager) — repeated clicks on live, focused, correctly-targeted dialogs
and grid rows produced zero visible effect across two independent fresh
CBase26 instances. **Keyboard input (`xdotool key`) works completely
reliably** the whole time (confirmed: `Tab`/`Return` operated a dialog's
default button, `Ctrl+Tab`/`Ctrl+Shift+Tab` cycled ribbon sub-tabs,
`F6` moved focus from the ribbon into the game-list grid, and
`Up`/`Down` moved the grid selection and live-loaded each selected game
into the notation/board panes). **Practical rule for any future pass
automating CBase26 under this headless setup: do not attempt mouse
clicks at all; drive everything via keyboard** (`F6` to reach the grid
from the ribbon, arrow keys to navigate rows, `Return`/`Space` to
act on a selection, `Ctrl+Tab` to change sub-tabs). This one insight
would have saved most of the wall-clock time burned in the eighth and
ninth passes and the first half of this one.

Also hit and worked around, in order: (1) a leftover CBase26 instance
from a prior pass's winedbg session, correctly left untouched (per the
"never interfere with another pass's debugging session" caution) in
favor of a fresh instance on a new display; (2) that fresh instance's
single-instance IPC silently routed a second `CBase26.exe <file>` launch
into the *first* (pre-existing, differently-sized) instance instead of
opening a new window, producing a window whose reported geometry
(`2560x1366`) didn't match the actual Xvfb screen (`1920x2000`) and
whose content was genuinely corrupted/blanked by an `xrefresh` recovery
attempt — resolved by killing both processes (DISPLAY confirmed `:251`,
not the real desktop, before touching them) and launching a **fully
fresh** CBase26 + fresh Xvfb display pair together; (3) a first-run
"Activate data abonnement" licensing/CAPTCHA dialog appeared on the
fresh instance (did not appear on the reused/already-activated instance
from prior passes) — dismissed via keyboard (`Tab` to the OK button,
which correctly surfaced "The serial number is not valid" without
blocking further use of the app, confirming the unactivated/trial state
doesn't gate database browsing).

No code changes; nothing to commit besides this doc update. Xvfb displays
`:252`/`:253` and the CBase26 instance launched on `:253` (PID confirmed
via `/proc/<pid>/environ` to be on `:253`, not the real desktop, before
killing) were cleaned up. Scratch files (`/tmp/find_quote_target*.tcl`,
`/tmp/gq_*.html`, `/tmp/*.png` screenshots) were deleted, not committed.

**Recommended next step**: a Ghidra pass targeting the rich-text/hyperlink
run-formatting code that colors and attaches citation metadata to a span
within rendered comment text (not a "quotation widget" or "quoted-game
sub-board" as previously assumed) — searching from the annotation-dispatch
angle used successfully for other `.cba` types, now anchored to a
concrete, confirmed-renderable target: `Sinquefield Cup 2015.cbh` game
index 6 (0-based), the `3...a6` position. A live-debugging pass (now that
the keyboard-only input rule is known and the target is concrete) is also
far more tractable than before: breakpoint `decode_caller` per the ninth
pass's `winedbg --gdb --no-start` recipe, then use keyboard-only
navigation (`F6`, arrow keys, `Return`) to select this exact game and step
to `3...a6` to trigger the render and capture whatever call stack
actually fires.
