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
