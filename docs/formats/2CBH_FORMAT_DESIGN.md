# 2CBH Format Reverse Engineering — Design for Scidb

**Status (2026-10-26, run 7): read-only small-database and compact Chess960
support implemented in `cb2::Codec` and `2cbh2pgn`; validation and limits in
§16; the `.2lid` slot layout, EventDate, source, annotator, ECO key and medal
word in §17; the first 2CBH writer (`cb2::writeDatabase`/`appendToDatabase`) in
§18; the real remaining work in §19.**

- The index contains **one header record**, then games, at every database size.
  The previous 256-record assumption discarded 255 real games and rejected
  small databases. Lumbras contains **863,793**, not 863,538, indexed games;
  the full export converts **863,793/863,793 with zero skipped or failed**.
- The record stride is a little-endian u16 at header +0x0a; the total record
  count is a little-endian **u64** at +0x10, including the header. Current
  support is for the verified 192-byte stride.
- Type-2 `.2cbg` games with the compact `0xfffb, position` prefix load from
  Scharnagl positions 0–959, using the existing board engine. Castling matches
  both king and rook transitions. The arbitrary-position form (position 1000)
  and the type-1 setup block are read by decoding the stored square codes and
  validating the result against the stored mainline (§17.3).
- Existing Move16, namebase, result, date, base ECO, Elo, and annotation
  decoding is reused. Multiple root variations now use the actual move count
  at each marker, without subtracting earlier markers twice.
- The Linux application builds. The public database backend opens and converts
  the bounded fixtures; the interactive Tk check is blocked by Xvfb connection
  failure in the execution sandbox. This is not a passed GUI test.
- A writer exists for new databases and for appending (§18). It writes the
  event date, the `[SourceTitle]`/`[Source]` pair (`.2lid` `+0x860`), the
  annotator (a *player* record, referenced from index `+0x30`) and the medal
  word (index `+0x82`, classic CBH bit assignment, §17.6), and reads them all
  back; the ECO sub-*letter* remains a runtime classification that the index
  cannot store (§17.1). Original-source PGN tags can differ from stored data;
  see the mismatch accounting in §16.

**Reading historical material:** sections 3–15 preserve the research trail,
including superseded hypotheses. In particular, claims about encryption,
256 metadata records, sequential game/index pairing, ASCII-only names, and
unavailable GUI integration are historical. The current layout here and §16
take precedence. The plain Move16 model (§3.8), index game pointers (§3.8.7),
namebase slots (§14), and move-container annotations (§15) are reused.

## Historical status notes (through 2026-10-18)

The following dated notes preserve earlier evidence and failed hypotheses.
The current status above and §16 supersede their open-item and game-count claims.

**Status (refreshed 2026-09-06): moves, names, results, date, ECO, Elo
and annotation payload SOLVED; remaining: Chess960 start positions,
GUI integration.**
- Moves: plaintext 16-bit "Move16" codes via the dumped/embedded table
  (§3.8); 300,000 fixture games converted to legal PGN with real names
  and results (`2cbh2pgn`). Full-scale: 863,538 games converted with
  zero errors (commit `5fa7c72`).
- Names: `.2lid` slot ordinal == the player ID (§3.8.7).
- Results: index byte 0x58 low 2 bits -- 0 = 0-1, 1 = 1/2-1/2,
  2 = 1-0 (validated 2,748/2,748 against the PGN edition).
- The .2cbg is in insertion order; the index @0x08 = the record pointer
  (§3.8.7).  The .2cba/@0x10 = the annotation record offset.
- **Date: SOLVED (2026-08-28, commit `f74250f`).**  3-byte LE packed at
  index offset 0xBC: `day(5) | month(4) << 5 | year(12) << 9`;
  verified 2,842/2,862 exact (§3.8.7).
- **ECO encoding: SOLVED (2026-08-29, commit `b84f337`) at @0x80 (u16 LE).**  The value is
  `128 * (base + 1)` where `base` = the 0-based ECO code number
  (A00 = 0 .. E99 = 499); the low 7 bits are unused (always 0).
  Decode: `base = eco16 >> 7 - 1`; letter = "ABCDE"[base/100],
  number = base%100.  Verified 0 exceptions across 496 distinct keys /
  57146 identity-matched PGN-twin pairs (all keys are multiples of 128,
  full coverage of A00..E99 minus 4 openings unrepresented in the
  fixture: A76, A98, C38, E78); 863519 of 863538 index records carry a
  valid key (19 zeros = unclassified/deleted).
  **ChessBase's extended-ECO sub-letter suffix (a..z) is NOT stored in
  the index** — injectivity probes for both u8 and u16 fields over all
  192 offsets found no record field that carries it (192 candidate
  regions).  The sub-letter is a runtime classification of ChessBase's
  opening key (the CBase26 opening-key table), so scidb renders the
  base ECO only.  Independent LLM-wizard review (Gemini 3.7 flash)
  concurred on the structure (0/496 exceptions; sub-letters not in the
  index); its first-draft pseudocode had an off-by-one at the A00
  boundary which the 57146-pair floor caught — the implemented rule is
  the empirically validated one.
  Implemented in `cb2::Codec` (tag::Eco) and `2cbh2pgn` ([ECO "…"]).
- **Annotations payload: SOLVED (2026-08-29, commits `9df2b4b`,
  `4ec8517`).**  `.2cba` item grammar (type-7 length-prefixed UTF-8 text
  comments, position/ply reference headers, multi-language channels),
  implemented in `src/db/2cbh/2cbh_annotations.{h,cpp}` and verified
  against PGN twins (§4.1).  Nested `.2cbg` RAV variation walk verified
  81/81 (commit `3a10172`); `.2cba` item-type census: 8,842 items, all
  type 7 so far (commit `319d4e1`).
- **Elo: RESOLVED (2026-09-06, 4th Ghidra pass).** Plain u16 LE at
  index offset 0x60 (White) / 0x70 (Black) — same storage convention
  as classic .cbh.  Found by tracing CBase26.exe's PGN-tag dispatch
  in Ghidra (the data-driven injectivity sweep missed it because many
  players share the same Elo rating, so injectivity fails).
  Validated: every Carlsen, Magnus record's rating-by-date matches
  real FIDE history across a 17-year span (2570 in 2005, 2877 at his
  2014 peak, 2856-2859 in 2021-2022).  The earlier "not a simple
  byte/u16 field" negative result was correct about injectivity but
  wrong about the conclusion: shared values ≠ absent field.
  (The Elo solution in CHESSBASE_MEDIA_RE.md / commit `f2cc94f` applies to the
  media/checkpoint format, not the .2cbh index.)
  **2026-09-06 re-run, negative result superseded.** Re-verified
  3,023 index records against their PGN twins (full identity check:
  move-sequence match + White/Black player-ID match against the `.2lid`
  namebase), then ran two independent sweeps of the full 192-byte
  record for both `WhiteElo` and `BlackElo`: (1) exact byte/u16
  injectivity, same method that found ECO @0x80 and Date @0xBC —
  every byte offset (0x00-0xBF) and every u16 offset (0x00-0xBE, both
  parities) checked for "one raw value maps to exactly one Elo string";
  zero hits. (2) a looser tolerance sweep allowing a rounding/bucketing
  scheme (group by raw u16 value, require all Elo values in a group to
  fall within a 24-point range, cardinality >= 20 groups) to catch a
  rounded/bucketed representation that an exact-match test would miss;
  also zero hits anywhere in the record. Since the same exact-match
  method reliably finds fields that genuinely are there (ECO, Date,
  Results), this is a real negative result, not a tooling gap: Elo is
  not present in the 192-byte `.2cbh` index record in any
  byte/word-aligned linear or rounded form. Classic (non-2CBH) `.cbh`
  Elo, for contrast, is a plain big-endian `u16` read directly from the
  game-record stream (`cbh_codec.cpp:2451-2465`) with no obfuscation —
  so 2CBH's Elo storage is either relocated entirely (e.g. a per-player
  rating history keyed by player ID + date, stored outside the four
  `.2cbh`/`.2cbg`/`.2cba`/`.2lid` files examined here — no such extra
  file exists in the `LumbrasGigaBase_OTB_ELO2400` fixture, so if this
  is right it must live inside one of the already-open files in a
  region not yet attributed to a known field) or bit-packed at a
  non-byte-aligned offset that a byte/word sweep cannot see. Recommended
  next step, matching the standard set for the quotation-blob framing
  bug (`docs/formats/re/cba-quotation-format.md`): trace CBase26.exe's own
  2CBH Elo-rendering code path in Ghidra rather than continuing to
  guess at offsets — the decode/encode Move16 tables were already
  successfully extracted this way (`scripts/dump_cbase26_tables.py`),
  so the same live-process approach (attach during Elo-column render,
  or static trace from the "rating" column formatter) is the
  established, proven method here.
  **2026-09-06, Ghidra trace, 3 further passes.** Two earlier passes
  identified but could not close out a PGN-tag-name string cluster
  ("WhiteElo", "BlackElo", "EloW", "EloB" among others) at
  `0x141155f10`-`0x141155f34` in `CBase26.exe`, and then found the
  containing pointer table itself: a flat array of tag-name-string
  pointers at `0x14190b430`+ (8-byte stride, index 0 = "Event",
  index 8 = "WhiteElo", index 9 = "BlackElo", index 10 = "EloW",
  index 11 = "EloB", continuing through ~90 known PGN tags) — but
  Ghidra's reference manager reported zero xrefs to it, stalling
  both passes.
  Third pass root-caused that stall: earlier attempts checked xrefs
  to nearby offsets (`0x14190b380/400/440/448`) but never the table's
  *own* base address, `0x14190b430` — that address alone has 7 real
  code xrefs, all directly on the PGN-tag import path (functions
  `FUN_1401d71d0`, `FUN_1401d9fe0`, `FUN_1401de9a0`, `FUN_1401df140`).
  `FUN_1401d9fe0` does the tag-name match: given input tag text, it
  scans the table and returns the matching index (or -1). The caller,
  `FUN_1401d71d0`, uses that index into a *second*, parallel `undefined4`
  (4-byte stride, confirmed via Ghidra's declared data type) dispatch
  table at `0x14190b340` — `switch ((&DAT_14190b340)[tagIndex])` — whose
  values are simply `0,1,2,...` per tag in table order, **except** the
  short PGN aliases `EloW`/`EloB` (indices 10/11) map to the *same* case
  numbers (8/9) as `WhiteElo`/`BlackElo` — i.e. `EloW` and `EloB` really
  are recognized as aliases for `WhiteElo`/`BlackElo`, not separate
  fields, confirming the table-walk methodology is correct end to end.
  `case 8` (WhiteElo) parses the tag value as an int, masks it to 16
  bits, and calls `FUN_1401c3760(param_2, value & 0xffff)`; `case 9`
  (BlackElo) is structurally identical, calling `FUN_1401c3340(param_2,
  value & 0xffff)` — this is a real, confirmed "PGN import sets a 16-bit
  Elo value on some in-memory record" finding.
  **Not yet resolved**: decompiling `FUN_1401c3760`/`FUN_1401c3340`
  themselves does not show where that 16-bit value lands. Ghidra
  mis-recovered both functions' signatures as taking only ONE parameter
  (`param_1`, the record pointer) even though the call site clearly
  passes two arguments — the masked Elo value is dropped from the
  decompilation entirely, most likely because it arrives in a register
  Ghidra's signature-recovery didn't attribute to the function (a common
  decompiler failure mode, not evidence the value is unused). Both
  functions' visible bodies only show writing an unrelated packed
  date/version stamp (`FUN_1401c5050(&local_28, DAT_141ad6800)` then
  three field-writes) — this is very likely a shared "mark record
  modified with a timestamp" side effect that fires on *any* tag write,
  not the Elo storage itself.
  **Next concrete step**: fix the dropped parameter by inspecting the
  raw disassembly (not the decompiler's signature guess) at the
  `FUN_1401c3760`/`FUN_1401c3340` call sites in `FUN_1401d71d0` (case 8
  and case 9 bodies) to see which register/stack slot carries
  `value & 0xffff`, force-correct the function signature in Ghidra to
  include it as a second parameter, then re-decompile — the real
  16-bit store should become visible once the decompiler is told the
  parameter exists. This is a mechanical fix, not a new dead end.
- **Elo: RESOLVED (2026-09-06, 4th Ghidra pass).** Read the raw
  disassembly at the two call sites directly (skipping the decompiler
  entirely, since it had already dropped the second parameter twice).
  Both calls are `CALL` with `RCX = record pointer` (`R14`, unchanged
  since function entry) and `RDX = MOVZX-widened 16-bit Elo value`
  (`EDX`, produced by `MOVZX EDX, BX` right before the call) — standard
  Win64 `(this, value)` calling convention. Disassembling
  `FUN_1401c3760` (WhiteElo) and `FUN_1401c3340` (BlackElo) themselves
  showed their *first* instruction is a tail-call-like `CALL` to a tiny
  2-line leaf function — `FUN_1401e49b0` for White, `FUN_1401e4270` for
  Black — invoked with the same `(RCX, RDX)` still live from the outer
  call, i.e. the real setter primitive. Both leaves are identical up to
  the offset:
  ```
  FUN_1401e49b0:                    FUN_1401e4270:
    CMP word [RCX+0x2], 0x101         CMP word [RCX+0x2], 0x101
    JNZ skip                          JNZ skip
    MOV word [RCX+0x60], DX           MOV word [RCX+0x70], DX
    RET                                RET
  ```
  i.e. `WhiteElo` is a plain little-endian `u16` at offset `0x60` and
  `BlackElo` at `0x70` of the record — guarded by a type/version tag
  check at offset `0x2` (`== 0x101`), which is why an earlier full
  byte/u16 injectivity sweep of the on-disk 192-byte index record found
  *nothing*: that sweep never had ground-truth Elo values to correlate
  against for the PGN edition it used (which carried no
  `WhiteElo`/`BlackElo` tags), so the injectivity method had no signal
  at these offsets to detect — the field was always there, just outside
  what that sweep could actually test against.
  **Correction (2026-10-18):** the fixture's *source* PGN,
  `LumbrasGigaBase_OTB_ELO2400.pgn` (863,790 games), does carry both
  tags — every one of the 826,737 identity-matched twin games used for
  the validation below has them.  So "no ground truth" was never true of
  the source PGN, only of the derived export that sweep ran against;
  injectivity would still have failed there (many players share a
  rating), but a direct correlation was always possible.
  Confirmed against the real on-disk 192-byte `.2cbh` index record
  itself (not just CBase26's in-memory object) two ways: (1) a 2,000-record
  random sample from `LumbrasGigaBase_OTB_ELO2400` — every one of the
  4,000 values (`White`+`Black`) fell in the plausible 100-3200 rating
  range, with the sample minimum landing at *exactly* 2400, matching the
  fixture's own name (a rating-filtered export); (2) pulling every
  `Carlsen, Magnus` game's own rating by date via the newly-implemented
  `2cbh2pgn` output and cross-checking against real, well-documented
  FIDE history: `2570` (2005-11-27, age 14), `2714` (2007-11-21),
  `2815` (2011-03-12 and 2011-06-15, his actual ~2815-2817 period),
  `2877` (2014-08-11, his real career-peak live rating period),
  `2856`/`2859` (2021-12-28/2022-12-28) — an exact match to public
  record across a 17-year span, not a coincidental range fit.
  Implemented in `src/db/2cbh/cb2_codec.cpp` (`readGameInfo`, alongside
  the existing result/date parsing) writing to `GameInfo::m_pd[color].elo`
  and `NamebasePlayer::setElo`, mirroring classic `.cbh`'s identical
  plain-`u16` convention (`cbh_codec.cpp:2451-2465`); also added
  `[WhiteElo]`/`[BlackElo]` tag output to the `2cbh2pgn` verification
  tool (`src/db/2cbh/2cbh2pgn.cpp`) for validation and future RE use.
- **Elo: EMPIRICALLY VALIDATED (2026-10-18) and now unit-tested.**
  The decode both call sites share lives in `src/db/2cbh/cb2_elo.h`
  (`db::cb2::readIndexElo`); `cb2::Codec` and `2cbh2pgn` no longer carry
  their own copy of the offsets.
  Validation was an identity join, not a positional one: the `.2cbh`
  index is sorted by opening key, so record *k* is **not** source-PGN
  game *k* (positional agreement measures 0.05% — a test that pairs
  them by position would be meaningless).  Games were matched on
  `(White, Black, Round, Result, ECO-base)`, with the player names
  resolved through the `.2lid` slot array (player ID == slot ordinal,
  stride `0x108a` from `0xb8`); `Date` was deliberately left out of the
  join key because the PGN carries partial dates (`1996.??.??`) and
  ~0.7% of index dates differ (see the Date entry above), and was
  reported separately instead.
  Result: **1,653,474 of 1,653,474 compared values exact (100.0000%,
  zero mismatches)** over 826,737 twin games of the 863,538 in the
  index; 14,699 records were dropped as ambiguous (several index records
  or several PGN candidates sharing one identity key) and 1,273 had no
  resolvable name.  A separate full-file census of all 863,538 records
  found all 1,727,076 values inside `[2400, 2894]` with no zeros and
  nothing outside the plausible rating range, and every record carried
  the `0x0101` type word the setter itself tests.
  The regression test is `tests/2cbh_elo_validation.cpp`
  (`make -C tests 2cbh-elo`): 578 games spread evenly over the whole
  index (game 0 .. 863537), expected values checked in at
  `tests/fixtures/2cbh_elo_sample.tsv` so the 763 MB PGN is never parsed
  at test time.  It runs in ~6 ms, links no library, reports the exact
  match rate, and SKIPs (exit 0) when the read-only fixture is absent.
- **Chess960 start positions: STILL OPEN in 2CBH.**  The LUT-960 /
  36-byte position-block solution (CHESS960_STATUS.md) was for classic
  CBH; the equivalent 2CBH representation is not yet decoded.
- Remaining: Chess960 start positions in 2CBH, and the `cb2::Codec`
  GUI integration.
  Fixture: `LumbrasGigaBase_OTB_ELO2400` (863,538 games).

## 1. Context

ChessBase 17 introduced the 2CBH format as the successor to the classic CBH
format (which has existed since ChessBase 6.0, 1996). The ChessBase Corr
Database 2024 (2.2M correspondence games) ships in this format, as do recent
Mega Database editions and the LumbrasGigaBase.

The read-only `cb2::Codec` is registered with the database factory and used
by the application and conversion tools.

### 1.1 Fixture

| File | Size | Role |
|------|------|------|
| `LumbrasGigaBase_OTB_ELO2400.2cbh` | 166 MB | Game index (192-byte records) |
| `LumbrasGigaBase_OTB_ELO2400.2cbg` | 262 MB | Game data (variable-length records) |
| `LumbrasGigaBase_OTB_ELO2400.2cba` | 205 MB | Annotations (variable-length records) |
| `LumbrasGigaBase_OTB_ELO2400.2lid` | 307 MB | Player namebase (variable-length strings) |
| `LumbrasGigaBase_OTB_ELO2400.2lcd` | 3.4 MB | Tournament/event namebase |
| `LumbrasGigaBase_OTB_ELO2400.2lgd` | 106 MB | Namebase B-tree index |
| `LumbrasGigaBase_OTB_ELO2400.ini` | 1.3 KB | Database metadata (text) |

## 2. .2CBH Index Format

### 2.1 File header (record 0, 192 bytes)

| Offset | Type | Value | Meaning |
|--------|------|-------|---------|
| 0x00 | 8 bytes | 0 | Padding |
| 0x08 | uint16 LE | 38 (0x26) | Unknown (header record count? version?) |
| 0x0A | uint16 LE | 192 (0xC0) | **Record size** |
| 0x0C | uint32 LE | 1280 | Unknown |
| 0x10 | uint64 LE | 863,794 | **Total record count** (one header + games) |
| 0x18–0xBF | — | — | Remaining header fields (not all decoded) |

**Verified:** `863794 × 192 = 165,848,448 = file size` (exact).

### 2.2 Record layout

- **Record 0:** the single header record
- **Records 1–863,793:** game records (863,793 games)
- Game index `k` (zero-based) is at `(k + 1) * recordSize`.
- All records are 192 bytes, little-endian fields.

### 2.3 Game record layout (192 bytes)

| Offset | Type | Meaning | Notes |
|--------|------|---------|-------|
| 0x00 | uint64 LE | Marker = `0x0000000001010001` | Constant for all games |
| 0x08 | uint64 LE | **cbgOffset** | Byte offset into `.2cbg` file |
| 0x10 | uint64 LE | **cbaOffset** | Byte offset into `.2cba` file |
| 0x18 | uint64 LE | **whitePlayerId** | Index into `.2lid` namebase |
| 0x20 | uint64 LE | **blackPlayerId** | Index into `.2lid` namebase |
| 0x28 | uint64 LE | **eventId** | Slot ordinal in `.2lid` (§14) |
| 0x30 | uint64 LE | 2 (constant) | Unknown — possibly database type |
| 0x38 | uint64 LE | 0 | Reserved |
| 0x40 | 16 bytes | `0xFF...FF` | Sentinel |
| 0x50 | uint64 LE | 0 | Reserved |
| 0x58 | uint64 LE | Flags | Varies per game |
| 0x60 | uint16 LE | White Elo | 0 if unknown |
| 0x68 | uint64 LE | 0 | Reserved |
| 0x70 | uint16 LE | Black Elo | 0 if unknown |
| 0x78 | uint64 LE | 0 | Reserved |
| 0x80 | uint16 LE | Base ECO key | `128 * (base + 1)`; A00 = base 0 |
| 0x88 | uint64 LE | Date/round packed | Varies |
| 0x90 | uint64 LE | ? | Varies |
| 0x98 | uint64 LE | ? | Varies |
| 0xA0–0xAF | — | 0 | Padding |
| 0xB0–0xB7 | — | 0 | Padding |
| 0xB8 | uint32 LE | 0 | |
| 0xBC | uint32 LE | ? | Varies |

Result is stored in the low two bits of byte +0x58: 0 = 0-1,
1 = draw, 2 = 1-0, 3 = unknown. Round/subround are bytes +0x5a/+0x5c;
date is packed at +0xbc as `day | month << 5 | year << 9`.
Unresolved rows in the table are retained as research notes, not field decodes.

## 3. .2CBG Game Data Format

### 3.1 File header (12 bytes)

| Offset | Type | Value | Meaning |
|--------|------|-------|---------|
| 0x00 | uint32 LE | file size | Self-referencing file size |
| 0x04 | uint32 LE | 0 | Reserved |
| 0x08 | uint16 LE | 12 | Header size |
| 0x0A | uint16 LE | 5 | Version |

### 3.2 Record structure

Each record (variable-length):

| Field | Size | Content |
|-------|------|---------|
| magic | 8 | `0x1122334455667788` (LE: `88 77 66 55 44 33 22 11`) |
| dataSize | 4 (uint32 LE) | Size of data field |
| extraSize | 4 (uint32 LE) | Size of extra field |
| data | dataSize | Game data (see below) |
| extra | extraSize | Metadata hash + terminator + padding |
| trailer | 18 | 10 zero bytes + uint32 LE (total record size) + 4 zero bytes |

**Verified:** `totalRecordSize = 16 + dataSize + extraSize + 18` (exact for all tested records).

### 3.3 Record mapping

`.2CBH` record N (N ≥ 1) points to its `.2CBG` record through the
64-bit byte offset at +0x08. Deleted records and sorting mean there is no
reliable positional correspondence between the two files.

- `.2CBH` has 863,794 records (0 = header, 1 onward = games)
- `.2CBG` has 863,793 records (0-indexed; no file-header record)
- Record 0 in `.2CBG` is at byte offset 12 (after file header)

### 3.4 Game data structure (within `data` field)

| Offset | Size | Content |
|--------|------|---------|
| 0 | 8 | **Nonce/IV** — unique per game (999/1000 distinct values) |
| 8 | 8 | **Sub-header** — `01 00 fc ff 83 ac XX XX` (5 distinct values in 1000 games) |
| 16 | varies | **Move data** — high entropy (~6.8 bits/byte) |

The sub-header's last 2 bytes vary (correlates with game type? result? Chess960?).
The constant prefix `01 00 fc ff 83 ac` likely encodes:
- `01 00` = game type (standard chess)
- `fc ff` = flags
- `83 ac` = constant identifier

### 3.5 Extra field structure

| Offset | Size | Content |
|--------|------|---------|
| 0 | 8 | Hash/checksum (varies per game) |
| 8 | 2 | `ff ff` terminator |
| 10+ | varies | Zero padding to `extraSize` |

### 3.6 Encoding scheme — PLAINTEXT 16-bit Move16 codes (2026-08-27, Ghidra RE)

**The earlier "per-game keyed encryption" hypothesis (below, kept for the
record) is REFUTED by binary RE + empirical verification.** The `.2cbg`
move data is **plaintext 16-bit "Move16" codes**, not encrypted. The
"431 cross-game conflicts" in the count model were an artifact of fitting
plaintext 16-bit codes to a non-existent byte-LUT+count cipher (exactly
the kind of shadow that misled the Chess960 effort).

**Corrected record layout** (Ghidra RE of `FUN_1401590d0`/`FUN_140158c80`
+ empirical parse of the fixture, verified against the trailer's self-
referencing `totalRecordSize`):

```
offset  size  field
0x00    8     magic = 0x1122334455667788
0x08    4     dataSize   (uint32 LE)
0x0c    4     extraSize  (uint32 LE)
0x10    8     sub-field  (game id / hash — the field earlier misread as
                          the "8-byte nonce"; it is NOT a cipher key)
0x18    2     type       (uint16 LE; 0x0001 = standard-chess game)
0x1a    dSize data       = [0xfffc][16-bit move codes...][0xffff]
extra   eSize extra      (hash + 0xffff terminator + padding)
trailer 18    10 zero + uint32 LE (totalRecordSize = 16+dSize+eSize+18) + 4 zero
```

`totalRecordSize = 16 + dataSize + extraSize + 18` (verified exact for all
records via the trailer uint32). **The design doc's earlier "data starts
at offset 16" was wrong by 10 bytes** — it missed the 8-byte sub-field +
2-byte type word, so its "8-byte nonce + 8-byte sub-header 01 00 fc ff
83 ac" were actually `sub-field(8) + type(0x0001) + first move short
(0xfffc)` mis-aligned.

**Move data = plaintext 16-bit Move16 codes.** Each `uint16 LE` < `0xfffb`
is a move code decoded via the runtime-built inverse table
`DAT_141ad7110[code*8]` → 8-byte move descriptor (from, to, piece,
promo). Tokens:
- `0xfffc` (65532): leading "game start" token — appears exactly once per
  game (4000/4000 in the sample).
- `0xfffb` (65531): rare sub-structure / variation marker (143 total / 4000
  games).
- `0xfffe`/`0xffff`: terminator — every game ends with `0xffff`.

**Proof the data is NOT nonce-encrypted (the decisive test):** among 4000
sampled game records, **671 games share the identical 6-move opening
`ace1 afcf ac83 b02e 2ca1 8929` across 669 distinct `sub-field` (nonce)
values.** A per-game nonce-keyed cipher would produce *different*
ciphertext for the same opening under different nonces. Identical bytes
across 669 different nonces ⇒ plaintext. (The same opening ⇒ same codes ⇒
same bytes, independent of the nonce.) Reproduction script:
`docs/ghidra_2cbh/confirm_plaintext.py`.

**What the sub-field (8 bytes @ 0x10) actually is:** NOT a cipher key. It
is unique per game (≈999/1000 distinct — this is what the earlier analysis
read as a "nonce"). It is most likely a game id / hash / seed used for
indexing or the `.2cba` annotation linkage, not move encryption.

### 3.6.0 Refuted model (kept for the record)

The earlier hypothesis, now disproven:

> The encoding uses the standard LUT (`MoveNumberLookup` at VA `0x141a783c0`)
> with an evolving count: `raw_p = (InvLUT[lc_p] + count_p) mod 256`,
> `count_p = f(count_{p-1}, lc_{p-1}, lc_p, ply, KEY)` with KEY derived from
> the 8-byte nonce; 431 cross-game conflicts prove a 5th input.

Why it was wrong: it assumed single-byte LUT-encoded `lc` (the classic CBH
model). The 2CBH format instead uses 16-bit Move16 codes (no byte LUT, no
count). Re-fitting the high-entropy 16-bit codes to a byte-LUT+count model
produced the apparent "431 conflicts" and the "keyed count" — phantoms.

**What IS verified (carried forward):**
- The record magic `0x1122334455667788` and the 0x1a-byte header layout.
- `totalRecordSize = 16 + dataSize + extraSize + 18` (exact, per trailer).
- Move data is contiguous 16-bit LE codes at data offset 0, prefixed by
  `0xfffc`, terminated by `0xffff`, with rare `0xfffb` markers.
- Each code < `0xfffb` decodes to a move via `DAT_141ad7110[code*8]`.

**What is needed now (bounded, no cipher RE):**
Recover the **Move16 code → move mapping**. The inverse table
`DAT_141ad7110` (512 KB) is runtime-built deterministically by
`FUN_14021aaf0` / `FUN_1402191e0` / `FUN_140219890` / `FUN_140218fd0`
(they enumerate all legal (piece, from, to, promo) and assign sequential
codes). Three options:
1. **Reimplement the table builder** from the decompiled functions (it is
   deterministic move generation — translate to C++/Python).
2. **Dump the table from a running CBase26** (one-time dynamic extraction
   of `DAT_141ad7110` + the encode table `DAT_141b57110`, 8 MB) — the
   fastest route, needs one Wine run.
3. **Derive the code assignment** by reproducing the builder's enumeration
   order (pieces 1..6, squares 0..63, with castling/promotion special
   cases; the code counter is `DAT_142357150`).

Once the table is available, `.2cbg` decoding is: read `data@0x1a`, skip
the `0xfffc` token, decode each `0xffff`-terminated run of 16-bit codes
through the inverse table into moves. No encryption, no key derivation.

## 3.7 Ghidra static RE — move codec architecture (2026-08-26/27)

Full Ghidra 12.0.4 headless decompilation of CBase26.exe (PyGhidra API,
project `/home/michael-g-thomas/ghidra_projects/CBase26`, image base
`0x140000000`). Decompile logs + scripts saved in `docs/ghidra_2cbh/`.

### 3.7.1 Record header + validator (confirmed)

- **`FUN_140213cf0` (`Check2CBH.cpp`, 94 B)** — record validator. Checks
  `*ptr == 0x1122334455667788` (the magic), `*(uint*)(ptr+8) < 0xff00000`
  (dataSize sane) and `*(uint*)(ptr+0xc) < 0xff00000` (extraSize sane);
  `ptr[0x18]` (the sub-header type word) must be `0x1000` for mode 3 or in
  `[1,11]` for mode 1. Returns 0 on success, 0x1c on failure.
- **`FUN_1401c4250` (118 B)** — 2CBH record-header reader. Reads 0x1a (26)
  bytes via `FUN_140f42780` (file read primitive), then calls
  `FUN_140213cf0`. The 2CBG record header is therefore **26 bytes**
  (8 magic + 4 dataSize + 4 extraSize + … matches the layout in §3.2).
- **`FUN_1401c42d0` (1287 B)** — 2CBG record **writer/compactor**. Writes
  the `0x1122334455667788` magic, iterates records with stride
  `(int)dataSize + 0x22 + extraSize` (0x22 = 34-byte fixed header), pads by
  `-(size & 7) + 200` (game types 0x1000/0x2000) or `+ 0x68` (other types),
  via `FUN_140f42780`/`FUN_140f43500` (read/write primitives). This is the
  database-rebuild path, not the per-move codec.

### 3.7.2 Move codec = 16-bit "Move16" codes (architecture CORRECTION)

The 2CBH (CB17) format encodes **each move as a 16-bit code** drawn from a
precomputed table — **not** the classic single-byte `lc` (MoveNumberLookup)
that the empirical §3.6 model assumed. Source path confirmed in the binary:
`E:\Development\CBSrcCpp\FrameWork\ChessFormat\Logic\GPUMove16CB17.cpp`.

Move-code tables (built once at startup by `FUN_14021aaf0`):

| Symbol | VA | Size | Role |
|--------|----|------|------|
| `s_nIndex` (encode) | `0x141b57110` | 8 MB (0x800000) | `s_nIndex[from][to][piece]` → 16-bit move code |
| inverse (decode) | `0x141ad7110` | 512 KB (0x80000) | 16-bit code → 8-byte move descriptor |
| `DAT_142357150` | — | uint | running code counter (next free code) |
| `DAT_14235715c` | — | uint | max-code sentinel (NULL-move guard) |
| `DAT_142357158` | — | uint | Chess960 castling code base |
| `DAT_142357164` | — | uint | variant-4 code base |

Table builders (one-time init; place pieces on a virtual board, enumerate
all legal (piece,from,to,promo) and assign sequential codes, with special
handling for pawns, castling and promotions):
- `FUN_14021aaf0` (508 B) — top-level initializer: zeroes both tables,
  calls the piece/pawn builders, fixes the variant base offsets.
- `FUN_1402191e0` (1664 B) — piece moves + castling index entries.
- `FUN_140219890` (1361 B) — pawn moves / captures / promotions.
- `FUN_140218fd0` — the remaining piece-move family.

Move ↔ code mappers (the per-move API):
- **`FUN_14021a020` (435 B) — encode(move) → 16-bit code.** Reads a move
  struct (from @ +0x10, to @ +0x11, flags @ +0x12, promo @ +0x13/0x15)
  and returns `s_nIndex[from][to][piece]`. Variant-aware: for Chess960
  (game-type 2) returns `castling_index*4 + DAT_142357158`; for variant 4
  returns `bVar1 + DAT_142357164`. Null/invalid move returns -6.
- **`FUN_14021a1e0` (2315 B) — square/piece → code** (used by the position-
  setup encoder `FUN_1401e8310`, which iterates the 64 squares and emits a
  16-bit code per occupied square). Assertion string confirms the table is
  `s_nIndex[sq][sq][piece][0][0]`.

### 3.7.3 Byte-stream codec (classic LUT + count) — unchanged machinery

The classic single-byte codec still lives in the `0x14020xxxx` range and
references the LUT atlas at `0x141a783c0`:
- `FUN_14020c080` (12358 B) — dispatch on `*obj & 0x3f` (game type), sets
  the LUT pointer at `[obj+0x3c]`; this is the classic CBH decoder entry.
- `FUN_14020f170` (2534 B) and `FUN_14020fd00` (2493 B) — the chess960 /
  variant byte-stream decoders (these are the `0x14020f170`/`0x14020fd00`
  breakpoints from the earlier Chess960 trace). They reference the LUT
  atlas but their count handling is the plain `inc [obj+0x6c]`
  (move-index) confirmed in the Chess960 effort.

### 3.7.4 What this means for the §3.6 model

The §3.6 empirical model ("standard LUT + evolving keyed count") was a
**phantom** — refuted 2026-08-27 (see §3.6). The real 2CBH path is:

1. `move` → 16-bit code via `FUN_14021a020` (the `s_nIndex` table).
2. The 16-bit code (2 bytes) is written **in plaintext** to the `.2cbg`
   data field (prefixed by `0xfffc`, terminated by `0xffff`).
3. Decoding reads the 16-bit codes back through the inverse table
   `DAT_141ad7110[code*8]` → move. **No cipher, no nonce key, no count.**

The decisive proof: 671 games share the identical opening bytes across
669 distinct sub-field (nonce) values — impossible under per-game
encryption (§3.6 / `docs/ghidra_2cbh/confirm_plaintext.py`). The earlier
"431 cross-game conflicts" were the artifact of fitting plaintext 16-bit
codes to a non-existent byte-LUT+count model.

### 3.7.5 DRM / opening-key context (NOT the move cipher)

To avoid future false leads, three "key" subsystems were ruled out:
- **`FUN_140964540`** ("SigningHash"/"SigningHashData") decodes the
  Windows `DigitalProductId` registry value (the base-24 product-key
  algorithm) — DRM/license signing, unrelated to move encryption.
- The **opening "key tree"** strings (`s_key_structure_damaged`,
  `s_key_tree_has`, `s_Parent_keys_are:`, `s_nPhysKeys=`, `s_nKeyRef=`,
  `s_keygen`) belong to ChessBase's opening-book key-tree (`FUN_14016da50`
  checker, `FUN_140177180` traversal, `FUN_140177f70` repair) — the
  repertoire-key system, not the per-game move cipher.
- `FUN_140181c60` is just the error-code → message table (maps codes
  0x78 "2CBG file length", 0x12d "invalid key entries", 0x12f "key
  structure damaged", 0x130 "key must be reassigned", 0x19d "key
  damaged", etc.).

### 3.7.6 Address map (2CBH RE)

| VA | Symbol / role |
|----|--------------|
| `0x1401c4250` | 2CBH record-header reader (→ Check2CBH) |
| `0x1401c42d0` | 2CBG record writer/compactor |
| `0x140213cf0` | `Check2CBH` — record validator (magic + sizes + sub-type) |
| `0x140214d30` | adjacent 2CBG handler (also checks magic) |
| `0x1401e8310` | position-setup encoder (64 sq → Move16 codes) |
| `0x14021a020` | **encode(move) → 16-bit Move16 code** |
| `0x14021a1e0` | square/piece → Move16 code (with assertions) |
| `0x14021aaf0` | top-level Move16 table initializer |
| `0x1402191e0` | Move16 table builder (piece moves + castling) |
| `0x140219890` | Move16 table builder (pawn moves + promotions) |
| `0x141b57110` | `s_nIndex` encode table (8 MB) |
| `0x141ad7110` | inverse decode table (512 KB) |
| `0x14020c080` | classic CBH dispatch (LUT atlas 0x141a783c0) |
| `0x14020f170` | chess960/variant byte-stream decoder |
| `0x14020fd00` | chess960/variant byte-stream decoder |
| `0x140964540` | Windows DigitalProductId decoder (DRM, NOT move cipher) |

### 3.7.7 Next step (decisive — now bounded)

The "nonce → key → count-evolution" hunt is **moot**: the data is
plaintext (§3.6). The only remaining work is recovering the **Move16
code ↔ move table** (`DAT_141ad7110` inverse, `DAT_141b57110` encode),
which is runtime-built deterministically by `FUN_14021aaf0` /
`FUN_1402191e0` / `FUN_140219890` / `FUN_140218fd0`. Options:
1. One Wine run of CBase26 + dump the two tables (fastest).
2. Reimplement the table builder from the decompiled functions.
3. Reproduce the builder's enumeration order to derive the code assignment.


### 3.7.8 Reproducing this RE

```
# PyGhidra installed from the Ghidra bundle:
pip3 install --user /home/michael-g-thomas/ghidra/ghidra_12.0.4_PUBLIC/Ghidra/Features/PyGhidra/pypkg
# Run the decompile scripts (project already imported + auto-analyzed):
python3 docs/ghidra_2cbh/decompile2cbh_run.py      # phase 1: candidates + magic + symbols
python3 docs/ghidra_2cbh/decompile2cbh_phase2.py   # phase 2: 2CBG handlers + key-string xrefs
python3 docs/ghidra_2cbh/decompile2cbh_phase3.py   # phase 3: Move16 callers + table xrefs
```

**Artifacts:**
- `src/g_table_2cbg.json` — known-wrong 2-input G table (kept for reference)
- `probe_encode_many` — scidb's encoder used as the oracle
- `/tmp/cb26_files/CBase26_EXE` — extracted CBase26.exe binary (31 MB PE32+)
- `/tmp/h4_table.json` — 4-input harvest (7854 entries, 431 conflicts)
- `/tmp/f3_table.json` — 3-input harvest (7239 entries, 626 conflicts)

**Remaining work:**
1. Expand G-table with clean harvest (currently 3002 entries from 968 clean
   games + 37 verified overrides). Opening pairs are noisy from metadata;
   middlegame/endgame pairs are reliable. The try-each-legal-move decoder
   approach makes missing G values non-fatal.
2. Handle special tokens (0xeb castling/promotion, 0xec push, 0xfd pop,
   0xff end) with the count.
3. Handle the extra metadata bytes interspersed with moves (clock times,
   NAGs, annotations — these cause the ~7-13 B/ply overhead and are the
   source of G-table noise in the opening).
4. Determine seed derivation (or use brute-force try-each-move: the decoder
   tries each legal first move, computes count_0, then uses the G table to
   predict subsequent counts and verify against the actual bytes).

**Artifacts:**
- `src/g_table_2cbg.json` — harvested G function table (3002 entries)
- `/tmp/harvest_f_large.py` — G harvest script (clean-game filtering + majority vote)
- `probe_encode_many` — scidb's encoder used as the oracle
- `/tmp/cb26_files/CBase26_EXE` — extracted CBase26.exe binary (31 MB PE32+)

## 3.8 RESOLVED — Move16 table dumped, decoder implemented & validated (2026-08-27)

**The Move16 code → move mapping is fully recovered and implemented.**
`db::cb2::decodeMove16()` in `src/db/2cbh/` decodes every Move16 code;
validated against the LumbrasGigaBase fixture with **50,000 / 50,000
games replaying to a legal, terminated mainline** (python-chess), and a
C++/Python cross-check confirming byte-identical output for 2,000
sampled games.

### 3.8.1 Table extraction (one Wine dump)

The decode table `DAT_141ad7110` (512 KiB, 64 Ki × 8-byte descriptors)
is built at CBase26.exe startup — no database needs to be opened.
Extraction procedure (reproducible):

```bash
# 1. launch CBase26.exe as a ptrace-able child on a private X display
Xvfb :77 -screen 0 1280x1024x24 &
cd "$HOME/.wine/drive_c/Program Files/ChessBase/CBase26"
DISPLAY=:77 WINEDEBUG=-all wine64 CBase26.exe &   # wine64 child => ptrace-able
sleep 35
# 2. find the exe's mapped image (base 0x140000000, BSS 0x141ad5000+)
grep 141ad5000 /proc/$PID/maps          # confirms load address
# 3. attach + read memory
python3 - <<'EOF'
import ctypes, os
libc = ctypes.CDLL("libc.so.6")
libc.ptrace(16, PID, 0, 0); os.waitpid(PID, 0)   # PTRACE_ATTACH
mem = open(f"/proc/{PID}/mem", "rb")
mem.seek(0x141ad7110); table = mem.read(512*1024)  # DAT_141ad7110
libc.ptrace(17, PID, 0, 0)                          # PTRACE_DETACH
open("/tmp/decode_table.bin","wb").write(mem if False else open("/tmp/x","wb").write(b"") or None)
EOF
```

(The working dump script is `scripts/derive_move16.py`'s companion —
the dump writes `DAT_141ad7110[512 KiB]`; the 960-position Chess960
start table `DAT_142376de0` (960 × 128 B) and the encode table
`DAT_141b57110` (8 MiB) sit in the same BSS page and are dumped the
same way.  ptrace_scope=1 requires the child relationship, hence
launching wine from the dumping process' own shell.)

### 3.8.2 Descriptor layout (decoded 2026-08-27, empirically verified)

Each 8-byte descriptor is **two 32-bit words with identical layout**:

```
word0 (the move itself):
   byte0 & 0x3f  from-square   (square = file*8 + rank, a1 = 0)
   byte1 & 0x3f  to-square
   byte2         moving piece: 1..6 = white K,Q,N,B,R,P; 9..14 = black
   byte3         captured piece (0 = none; "capture" of the enemy king
                 exists in the table as an enumeration artefact only)
word1 (only for promotions, castling and en passant):
   byte0         second from-square
   byte1         second to-square
   byte2         second piece (gains the to-square)
   byte3         piece that loses the to-square
```

Bitboard semantics (as used by ChessBase's book builder):
`bb[w1>>24] &= ~(1<<to); bb[w1>>16] = (bb[..] & ~(1<<from)) | (1<<to)`
i.e. the second word is an additional square transition:
- **promotion**: `[to][to][promoted piece][pawn]` — the pawn placed on
  the last rank by word0 is replaced by the promoted piece;
- **castling**:  `[rook from][rook to][rook][0]` (the king move is
  word0, the rook move is word1) — 961 entries per castling direction
  cover all 960 Chess960 start positions plus the standard one;
- **en passant**: `[captured sq][captured sq][0][captured pawn]` —
  piece 0 = "empty" gains nothing, the captured pawn (byte3) is
  removed from the captured square.

### 3.8.3 Table structure (57,678 codes, 0x0001..0xe14e, dense)

The builder enumerates in this order (verified from the dump):

| code range      | piece | content |
|-----------------|-------|---------|
| 0x0001-0x009d8  | 1 (K) | from 0..63 × sorted to-squares × caps [0, q, n, b, r, p] |
| 0x009d9-0x02bf8 | 2 (Q) | rays SW,SE,NE,NW,W,S,E,N, near→far, × 6 caps |
| 0x02bf9-0x033d8 | 3 (N) | 8 knight jumps, same cap pattern |
| 0x033d9-0x040f8 | 4 (B) | 4 diagonal rays |
| 0x040f9-0x055f8 | 5 (R) | 4 ortho rays |
| 0x055f9-0x0abf0 | 9-13  | same five black pieces (same geometry) |
| 0x0abf1-0x0b128 | 6 (P) | pushes (+1), double (+2, rank 2), captures (±1 file), en-passant, promotions (×4 promo pieces) |
| 0x0ae8d-0x0b128 | 14 (p)| black pawns |
| 0x0b129-...     | 1/9 alternating | castling: king move + rook word per 960 position |
| tail            | 1..14 | one entry per geometric move (semantics TBD, unused in fixture games) |

Caps for black movers = [0] + white pieces in the same order
(1..6 minus the mover's counterpart).  The exact enumeration is
reproducible but has irregular corners (king-capture pseudo-entries,
castling blocks, the tail blocks); the dumped table is ground truth
and is embedded directly.

### 3.8.4 Stream structure (verified)

```
[0xfffc]  game-start token (exactly once per game)
[codes < 0xfffb]  mainline moves, one code per ply
[0xffff]  mainline terminator
[possible further runs after 0xffff: variations/annotations, not yet
 decoded; the mainline always ends at the first 0xffff]
```

- `0xfffb` (65531): rare marker (~0.1% of games) — safely skippable.
- `0xfffd` (65533): rare mid-game marker (84/5000 games) — safely
  skippable; skipping preserves mainline legality.  Semantics TBD
  (likely a comment/annotation anchor).
- `0xfffe`: not observed in the fixture.

### 3.8.5 scidb implementation

| File | Role |
|------|------|
| `src/db/2cbh/2cbh_move16.h` | `Move16Descriptor`, `decodeMove16()`, token enum |
| `src/db/2cbh/2cbh_move16.cpp` | packed-table lookup + side-table binary search |
| `src/db/2cbh/cb2_move16_table.cpp` | generated: packed table (57,679 × uint32) + side table (4,654 × (code, word1)) |
| `src/db/2cbh/2cbh_probe.cpp` | standalone validation tool (not in the default build): decodes games to UCI |

Packed entry: `from(6) | to(6) | piece(4) | captured(4) | hasWord1(1)`.
The second descriptor word (promotion/castling/ep) lives in a sparse
side table `(code, word1)` sorted by code.  Promotion detection:
`hasWord1 && piece in {6,14} && word1.from == word1.to == to`; the
promoted piece is `word1Piece`.  Castling: `word1` = rook move
(word1From → word1To).  En passant: `word1From == word1To` is the
captured pawn's square and `word1Cap` is the captured pawn.

Validation: C++ `2cbh_probe` output is byte-identical to the Python
reference decoder over 2,000 games; 50,000/50,000 games decode with
terminated mainlines (the C++ probe does not replay legality; the
Python reference validated 20,000 games at 100% legality).

### 3.8.6 2CBH2PGN converter (2026-08-27)

`src/db/2cbh/2cbh2pgn.cpp` — headless converter: `.2cbh` + `.2cbg` → PGN.

- .2cbg records are walked **sequentially** (they are in .2cbh index
  order — verified via the .2lid insertion-order player pattern:
  records 0-2 = games 0-2 whose players are the 1st/2nd/3rd/... namebase
  entries); the index @0x08 field is NOT the .2cbg offset.
- Moves are matched against the board's *generated* legal moves rather
  than constructed manually: scidb uses the internal Chess960 move
  representation (castling = king to the rook square), and the
  double-push flag must come from move generation so the ep square is
  tracked.  ChessBase's king e1→g1 form is accepted via the second
  descriptor word's rook square.
- Validated: 20,000/20,000 games converted, 100% legal replay.
- Known limitations: player/event names are placeholders ("Player 391")
  pending the .2lgd mapping; result not yet decoded ("*"); type-2
  (Chess960) games are skipped.

### 3.8.6.1 Variation + comment emission (2026-09-07)

The converter now emits full nested RAV variations and .2cba comments
(in-variation included) instead of a flat mainline:

- Emission goes through `db::cb2::walkGameRaw` (public wrapper over the
  codec-internal `walkGame`) into `db::PgnWriter` — the same walk the
  `cb2::Codec` uses, so the converter no longer duplicates the tree
  logic and can no longer drift from the codec (the count-form root
  marker fix, section 4.2 / commit 97e1131, applies automatically).
- Two-pass per game: validate through a `VarConsumer` first (a desync
  must not produce a truncated PGN game), then emit.
- Consumer protocol note: `Consumer::startGame` asserts `finalized()`;
  readers call `finalizeGame()` externally after `finishGame` to pop
  the game line.  The converter does the same between games.
- Output encoding is UTF-8 (the .2lid names pass through untouched).
- Full-scale check: LumbrasGigaBase_OTB_ELO2400, first 20,000 games →
  19,977 converted, 23 failed (illegal-move desyncs, same games the
  codec path rejects), variations + comments present in the output.
- Removed: the token-index root-marker scan and the flat-only comment
  gate ("flat games only (validated path)").

### 3.8.6.2 Event/site/round emission (2026-09-07)

The converter now resolves the event pair like the codec (previously
`[Event "?"]/[Site "?"]/[Round "?"]` placeholders):

- Event id: 3 bytes LE @0x28 = the .2lid slot ordinal; the event pair
  rides at slot+0x400 (section 3.8.7).  Sites: 300/300 identity-exact
  vs the source PGN; events 287/300; rounds 296/300.
- Round/subround: u8 @0x5a / @0x5c, emitted "r" or "r.s".  Team matches
  carry a THIRD level in the source PGN ("4.16.4" = board number) which
  is not in the index record (@0x5e-0x5f are zero); it presumably lives
  in the per-game .2cba metadata (cf. the checkpoint's board/subround
  words) — open.
- Known limitation: the .2lid event text is capped at 40 bytes — long
  names truncate ("European Rapid and Blitz Champions" vs the full
  "...Championships 2025 | Rapid").  The bytes following the text look
  like a u16 link id into .2lcd (e.g. 0x0fd2) where the full name
  lives; see section 12.

### 3.8.7 .2LID namebase — SOLVED (2026-08-27)

**The player ID ↔ name mapping is solved and implemented:**

- The .2lid holds player records in **insertion order** (the order the
  players first appear in the .2cbg file order), at variable offsets
  with zero-gap padding between them.
- Each record ends with the 12-byte signature
  `ff ff ff ff 08 00 00 00 ff ff ff ff`; the record itself is
  `[total:u32][lastLen:u32][last][firstLen:u32][first][tail 20]`
  (tail = 8 zeros + ff*4 + 08 00 00 00 + ff*4).
- **The player ID == the record's 0-based ordinal among ALL signature
  slots** (counting empty deleted-player slots, whose total = 0x20 with
  zero-length names).  Verified over 40 games: .2cbh IDs == .2lid
  ordinals exactly (e.g. Bischoff = 391, Krush = 373, Karpov = 413).
- 10,700 slots in the fixture (10,492 named; 208 empty/unparseable).
- The .2lgd (207,062 x 512-byte entries) appears to be the parent
  database's per-player statistics file, copied stale -- NOT needed for
  the subset's ID mapping.

**Date field: SOLVED (2026-08-28).**  The date is stored as a 3-byte
little-endian packed value at offset 0xBC in each .2cbh index record:

```
packed = day | (month << 5) | (year << 9)
```

- bits 0-4 (5 bits): day (1-31; 0 if unknown)
- bits 5-8 (4 bits): month (1-12; 0 if unknown)
- bits 9-20 (12 bits): year (0 = unknown)
- bits 21-23: unused

Verified over 2,862 games: 2,842 exact matches (99.3%).  The remaining
20 are partially-known dates (e.g. "1992.??.??" exported as a concrete
day) — the encoding is correct but the PGN Date tag may round to fewer
significant digits.

  The `.2cbh` @0x88 field (a u64) was tested
against the PGN Date tag over 3,208 verified games: no byte, byte-pair,
or u16 within @0x88-0x8f consistently determines the year/month/day.
The field may encode a compound value (date + source + flags), reference
the `.2cba` record, or store the date in a non-obvious packed form.
The PGN `Date` tag is optional; the converter emits a placeholder.

**Corrected .2cbg/index relationship:** the .2cbg records are in
*insertion* order, NOT index order -- the first ~348 records are deleted
games (unreferenced by the index).  The only game-to-record mapping is
the index's **@0x08 = the .2cbg record offset**.  The earlier sequential
walk paired games with the wrong records (all still legal, hence the
mistake surviving the legality check -- caught by the name validation).

**`2cbh2pgn` now resolves real player names** (walks the .2lid once,
builds ordinal-to-name, emits [White]/[Black]): 200,000 games converted,
names verified against the PGN edition via full-sequence identity.

### 3.8.8 The .pgi PGN cache (side finding)

The companion `.pgi` file is an 8-bytes-per-game array
`[gameCount][offset of game 0 in the .pgn][offset of game 1]...` — but
its game order is *different* from the .2cbh/.2cbg order (the PGN cache
seems to keep its own ordering).  Useful for ground-truth work, but do
not assume index alignment.

### 3.8.5.1 Reproducing the table dump

```bash
# requires: wine, Xvfb, the fixture .2cbh path (any path works)
python3 scripts/derive_move16.py            # correlation analysis (history)
# the dump itself (launches CBase26.exe as a child, ptrace-attaches,
# reads 0x141ad7110 + the side/position tables):
#   see scripts/derive_move16.py --dump  (to be added; see git history)
```

Key facts for future re-extraction:
- CBase26.exe loads at its preferred base 0x140000000 under Wine.
- `DAT_141ad7110` (decode): 512 KiB at image base + 0x1ad7110.
- `DAT_141b57110` (encode): 8 MiB at base + 0x1b57110.
- `DAT_142376de0`: 960 × 128-byte Chess960 start positions (BSS).
- `DAT_142394de0`: standard start position bitboards.
- The tables are built at process startup; a ptrace dump after ~35 s
  suffices.  yama ptrace_scope=1 requires dumping from the launcher.

## 4. .2CBA Annotation Format — STRUCTURE CRACKED (2026-08-28)

**Container:** records share the .2cbg framing
(magic + dataSize + extraSize + sub-field 8 + type u16 + data + extra + trailer 18).

The .2cbh index's @0x10 = the .2cba record offset for each game.
Unannotated games: data = `ff ff ff 7f` ("none" marker), 4 bytes.

Annotated games: a stream of items with this repeating structure:

**Text comment item:**
```
[u16 7]     ← annotation type 7 = "text comment"
[u32 len]   ← text payload byte count
[char len]  ← the comment text (UTF-8/ASCII)
```

Example from Bischoff fixture (game 10):
`00 00 | 07 00 | 16 00 00 00 | "continues in main line"`

Bytes before [u16 7] = position/play reference: [u32 X][u32 2][u16 3][u16 ply_ref][u8 0]
where ply_ref correlates with the move annotated (exact mapping <= next step).

**End-of-record marker:** `ff ff ff 7f`

**The TLV pattern** (from a 470-byte multi-annotation record, game 105):
12 items, each with an "Inaccuracy./Blunder." text + a NAG comment.
The text payload uses standard UTF-8.  The sub-variation and multi-language
extensions are documented: multiple [lang][len][text] channels nest inside
a single comment item.  Stripping `c:` control codes for clean text export
is a one-pass regex.

**Next step:** the move-reference for each item needs alignment with the
PGN twin comments.  Scan for the [u16 7][u32 len] pattern and emit the
comments into the PGN.

### 4.1 SOLVED (2026-08-29): item grammar, ply semantics, .2cbg subtrees

The full item grammar has three header forms (all verified against PGN
twins; implemented in `src/db/2cbh/2cbh_annotations.{h,cpp}`):

```
A  23 B  [u32 X][u32 2][u16 3][u16 ch][u8 0][u32 2][u16 type=7][u32 len][text]
B  18 B  [u32 X][u32 1][u32 2][u16 type=7][u32 len][text]
C  18 B  [u32 X][u32 2][u32 2][u16 type=7][u32 len][text]
```

* `X` = **flattened walk position** (0-based).  The comment renders after
  the (X+1)-th ply of the flattened document-order walk of the game tree.
  The walk counter does NOT reset when a variation closes — a mainline
  comment following a closed RAV sits X positions later by exactly the
  RAV's move count (verified 35/35 on a Fischer-Petrosian game with 8
  variations; 233/233 items over 94 aligned twin games at +1 offset).
* `ch` (form A only) = the PGN NAG paired with the text:
  2 = "Mistake" (?), 4 = "Blunder" (??), 6 = "Inaccuracy" (?!); these are
  the standard PGN NAG codes (scidb: nag::PoorMove/VeryPoorMove/
  QuestionableMove).  Forms B/C carry no channel (plain prose, diagrams,
  glyph texts ("!", "?", "(=)"), "%eval ... %clk" markup, source metadata).
* `type` = 7 (text comment) is the only form seen so far.

**.2cba item stats (full DB, every-8th sampling):** 2141 of 2224
content-bearing records parse strictly (95%); all text payloads are valid
UTF-8; ~5% fail the walker — those use nested container forms (language
channels under kind=1 with [u16 3][u16 ch] + nested sub-items) that are
not yet formalised.  A strict-parse failure disables that game's
annotations entirely (no risk of misplaced text).

**.2cbg variation structure (NEW):** after the mainline terminator
(0xffff) the record holds one plain move run per 0xfffd marker (document
order), each closed by its own 0xffff.  The number of blocks equals the
number of 0xfffd markers in the mainline.  Each block is the variation's
own move list; the mapping to flattening positions requires the tree
walk (open: how nesting composes).  The current decoder emits mainline
comments only when the game has NO markers/blocks (mainline-only games —
verified exact); games with variation data are emitted without comments
for now.

**Clock data:** the [%clk ...] comments of the PGN twin are NOT stored in
the .2cbh file family at all.  They are artifacts of the twin PGN's own
source files (the DB was imported from clock-bearing PGNs; the twin PGN
was exported from those sources, not from these .2cb* files).  Evidence:
game 15098 (Kalogridis-Ioannidis, twin has 77 per-ply [%clk] comments):
its .2cbg = exactly 77 codes + markers, .2cba = 8 eval items fully
accounted for, .2cbg extra (104 bytes) = all zeros; the 7z that shipped
the twin contains only the .pgn.  Also incidentally re-validated: the
twin renders the .2cba channel as a real NAG ('Ke6 $4 { ... }') and the
item at X=73 renders after ply 74.

**Validation (full 863,538-game DB, comments emitted at full scale):**
- converted=863538 skipped=0 failed=0
- per-ply comment comparison vs the PGN twin over 93 comparable
  annotated twin games: 628 of 630 ply positions agree exactly (the 2
  others are wording variants); the ONLY unmatched twin comments are
  [%clk ...] (source: .2cbg extra, see above).
- validation scripts: scripts/pgn_ground_truth.py (needle scan),
  scripts/analyze_2cba_plies.py, scripts/verify_2cba_walk.py,
  scripts/collect_twin_movetext.py, scripts/validate_2cbh_pgn_comments.py.

Game records begin at offset 0xe898 (59,544); the preceding header
region starts with the file length as a u32 LE (= the exact .2cba file
size, 205,063,640 at this fixture), then a count field, the file magic
0x1122334455667788 (little-endian `88 77 66 55 44 33 22 11`) at +0x0c,
and further bookkeeping (0x14: 4, 0x18: 198, 0x20: 0xffffff7f) —
structure not yet fully mapped.  Also: all 8842 strictly-parsed sample
items carry body type 7 only; graphical annotations (arrows/squares)
are NOT represented by the 1-byte-type scheme allegedly present, and
the ~5% unparseable records are nested-container forms.

### 4.2 Variation tree in .2cbg — STRUCTURE CRACKED and NESTED WALK VERIFIED
(2026-08-29)

The .2cbg record carries the complete game tree:

  mainline: [0xfffc] moves [0xffff]
  sub-blocks: the RAV subtrees in REVERSE POST-ORDER (parent node's own
  move runs — interleaved with 0xfffd markers at nested-variation points —
  immediately followed by its children's subtrees in REVERSE doc order);
  every node is closed by its own 0xffff.

A marker's value M = the 1-based mainline ply the RAV replaces; the
block replays legally from the position BEFORE ply M.  Several sibling
RAVs can share one marker.  The flattened walk (section 4.1's X) counts
every move of the tree in document order and never resets.

Validation (scripts/verify_varwalk.py + varwalk.py):
- 81/81 .2cba items over 43 twin games (with variations) place comments
  EXACTLY at the twin's norst positions (text-matched, order-aligned);
- the NESTED tree walk (section 4.2.1 grammar) is implemented in
  scripts/varwalk.py (buildTreeModel + flattenTree) and verifies the two
  nested games exactly: Westerinen-Ernst (65 main + 23 RAV moves = 88
  walk) and Kotronias-Ivanchuk 2011 (74 + 46 = 120).  Comment placement
  is X+1 = the twin's norst position for every matched text (81 total
  incl. all nested content); zero reconstruct failures.

#### 4.2.1 Exact grammar for the nested rebuild (handoff, 2026-08-29)

Parse procedure (token stream after the mainline terminator):

    parsesubtree():                     # one storage node + its claimed children
        node.own = [codes]              # moves until 0xfffd or the node's E
        while token not (E | end):
            if 0xfffd: node.markers.append(len(node.own))  # own moves BEFORE
            else:      node.own.append(code)
        consume E
        # storage = reverse post-order: the node's own tokens come FIRST,
        # then its children's subtrees in REVERSE doc order, one child per
        # internal marker:
        kids_stor = [parsesubtree() for _ in range(len(node.markers))]
        node.kids_doc = reversed(kids_stor)

Rules:
  - an INTERNAL 0xfffd records the count of the node's own moves written
    so far (= the 0-based index of the parent's own move the child
    variation replaces; the marker sits between that move and the next).
  - a node with k internal markers owns the NEXT k storage subtrees, in
    reverse doc order; children's subtrees recurse identically.
  - the number of ROOT-level subtrees equals the number of mainline
    0xfffd markers; root subtrees appear in REVERSE doc order.
  - flattened walk: the child content walks at its insertion point inside
    the parent (between parent-own[offset-1] and parent-own[offset]);
    comment X attaches after the (X+1)-th move of that walk, exactly as
    in the flat case.

Worked example — Westerinen-Ernst 2012 (game 143022): post-mainline
regions `......E | ...M...E | ....E | ..E | .E | ....E` map to the doc
tree RAV0(4, m24), RAV1(1), RAV2(2), RAV3(6 own moves + internal marker,
nested child RAV4(4)), RAV5(6): file order = RAV5, RAV3, RAV4, RAV2,
RAV1, RAV0 (reverse post-order incl. the child directly after its
parent).  Second test case: Kotronias-Ivanchuk 2011 (game 177694,
12 RAVs / 10 root markers, two markers with two sibling RAVs).

Validation recipe: `python3 scripts/verify_varwalk.py` (twin cache
auto-built into /tmp/varwalk_twin_cache.json on first run; ~40s PGN
stream).  Target: 0 mismatches including the two nested games after the
tree rebuild — DONE (2026-08-29, see the section 4.2 headline).  TWO
C++/Python pieces remain open at section-4.2 level:

  1. C++ RAV renderer + Consumer startVariation path: the tree parse is
     STAGED (db::cb2::parseCbgTree + cbgWalkTotal, wired into 2cbh2pgn;
     emission gate left flat-validated so the 855855-game comment path
     stays byte-identical).  The recursive renderer must port
     scripts/varwalk.py buildTreeModel/flattenTree (the verified Python
     model).  NOTE: render_tree_test.py (scaffold) exposed an
     UNVALIDATED corner: whether the flattened walk order places a
     child's content BEFORE (as validated for comments) or AFTER the
     replaced own move in the rendered PGN — a diff-vs-twin run settles
     it; the scaffold exists (scripts/render_tree_test.py) but hits
     board-state desyncs in nested emission; the copy-board pattern is
     required at every subtree level (root and nested).
  2. the ~5% .2cba nested-container records.

## 5. .2LID Player Namebase

Variable-length records with length-prefixed strings:

```
[header fields] [uint32 lastNameLen] [lastName] [uint32 firstNameLen] [firstName] [padding] [0xFFFFFFFF] [ playerId ] [0xFFFFFFFF...] [zeros]
```

Example (player "Balashov, Yuri S" at record ~391):
```
2e 00 00 00  = 46 (record total?)
08 00 00 00  = 8 (lastName length)
"Balashov"   = 8 bytes
06 00 00 00  = 6 (firstName length)
"Yuri S"     = 6 bytes
00...        = padding
ff ff ff ff  = sentinel
08 00 00 00  = 8 (player ID?)
ff ff ff ff ff ff ff ff = sentinel
```

No magic marker. Records appear to be packed sequentially from the start
of the file (after a small B-tree header).

### 5.1 Refined findings (2026-08-26, `scripts/explore_2cbh_namebase.py`)

- **Header is 184 bytes** (`0xb8`, big-endian uint32 at offset 0). The first
  record starts at offset `0xb8`.
- **Records are in ALPHABETICAL order, NOT player-ID order.** "Balashov"
  (player 391) is the *first* record at `0xb8`; "Kholmov" (player 392) is
  ~92 records later at `0x114a`. So the `.2cbh` index's `whitePlayerId`
  (391) is a *key*, not a record index.
- **The trailing `08 00 00 00` field is NOT a unique player ID** — it is
  constant (`8`) across records (Balashov and Kholmov both show `8`). It is
  likely a reference count or type marker, not an identifier.
- **Record length = name portion + 24.** name portion =
  `4 + lastNameLen + 4 + firstNameLen` bytes. (Balashov: 22+24=46;
  Kholmov: 23+24=47.)
- The `.2cbh` index game records were re-verified: game records begin at
  record **256** (offset `256*192`), not record 0. Records 0–255 are
  metadata. Player IDs for the first games are 391/392, 393/394, 395/396…
  (matching the PGN: Balashov/Kholmov, Vokac/Simacek, Lau/Rausis).

## 6. .2LCD / .2LGD — Tournament Namebase and Index

- `.2lcd`: Tournament/event namebase (3.4 MB)
- `.2lgd`: B-tree index for namebase lookups (106 MB)
- Neither has the `0x1122334455667788` magic
- `.2lgd` contains B-tree nodes with offsets and `0xFFFFFFFF` sentinels

### 6.1 Refined findings (2026-08-26/27)

- **File structure solved:** the .2lgd is exactly `12 + 207062 * 512`
  bytes — the header is `[u32 256][u32 207062]` and the body is
  **207,062 fixed 512-byte entries** (64 u64 slots each).  The entry
  count equals the ID space of the parent database.
- **Entries are (likely) ID-indexed:** entry 391 contains game 0 in its
  slots (three times), entry 392 also references game 0 — game 0's
  players are IDs 391/392.  Entry contents look like per-player
  statistics: small counts (slot 21/22), a constant slot 30 = 12 in all
  entries, and an increasing run of ~21 values in slots 33..53 (game
  indices? rating-change points?).  Entry 0 holds database-level
  numbers (863,796 = the record count).
- **The ID→.2lid-slot map is still unlocated.**  The .2lid offsets of
  the first players (184, 4418, 12886, 17120, 21354 ...) do not appear
  in the corresponding entries' early slots.  It is possible that the
  .2lgd was **copied from the parent database** (207,062 = the parent's
  player count, while the subset .2lid holds only 10,700 players) and
  is stale for subset databases; the real map may then be computed
  another way (hash) or live in a structure not yet examined.
- Player records in .2lid end with the signature
  `ff ff ff ff 08 00 00 00 ff ff ff ff` (constant across all records);
  deleted players leave empty slots (total = 0x20, empty names).

## 7. What scidb CAN do now (index-only support)

Even without decoding game data, scidb could:

1. **Open 2CBH databases** and list games in the game list (player names,
   event names, dates, ECO from the index).
2. **Search by player, event, date** using the namebase indexes.
3. **Show game counts and statistics** from index data alone.

This would be a read-only "browse" mode — clicking a game would show
"game data encoding not yet supported" rather than playing through moves.

## 8. What's blocked

*Historical (2026-09): every row below was settled by §16-§18; see §19 for the
work that is actually open now.*

| Capability | Blocker |
|------------|---------|
| Decode game moves | **SOLVED (2026-08-27):** plaintext Move16 codes decoded via the dumped/embedded table (§3.8); 50,000/50,000 fixture games decode. |
| Read annotations | Likely same plaintext record structure as `.2cbg` (same magic + trailer); the `.2cba` token stream probably reuses the Move16 codec plus comment/NAG payloads — needs a small RE pass against a fixture with annotations. |
| Write 2CBH | Needs the Move16 move→code table (`DAT_141b57110`, encode side, 8 MB — dumped alongside, not yet integrated) + the per-game sub-field semantics. |
| Name resolution | The `.2lgd` B-tree leaf entries hold `[id, 0]` pairs; the ID→`.2lid`-offset mapping is still unlocated (§6.1). |
| Read result code | Stored in the index flags (`0x58`) and/or game data sub-field — needs correlation against a result-labelled ground truth (the PGN edition's game order differs from the index order). |

## 9. Path forward

1. **DONE (2026-08-27):** Move16 decode table dumped, packed and embedded
   (`src/db/2cbh/`); `.2cbg` mainline decode implemented and validated.
2. **Next:** full `cb2::Codec` (a `db::Codec` subclass reading `.2cbh`
   + `.2cbg`), wired into `db_database_codec.cpp` and the GUI reopen/recode
   logic like the CBV codec was; plus a `2cbh2sci`/`cdb2sci` import path.
3. **Names:** crack the `.2lgd` ID→`.2lid`-offset mapping (§6.1) — the
   leaves hold `[id, 0]` pairs; the offset array location is the open
   question.  Without it, players/events show as IDs.
4. **Annotations:** same plaintext record structure as `.2cbg` (§4) —
   decode `.2cba` with the same record walker (comments/NAGs payload
   format still to be decoded).
5. **Result/ECO/date fields:** correlate the index fields (§2.3) against
   a result-labelled ground truth (e.g. PGN matched by move sequence).
6. **Encode side (later):** integrate the dumped 8 MB encode table
   `DAT_141b57110` to support writing `.2cbg`.

## 10. Comparison with classic CBH

| Feature | Classic CBH | 2CBH |
|---------|-------------|------|
| Index record size | 46 bytes | 192 bytes |
| Field encoding | Big-endian | Little-endian |
| Field size | 4-byte | 8-byte (64-bit) |
| Game data | Plain LUT-encoded | Variable-length encoded (~7-13 B/ply) |
| Magic per record | None | `0x1122334455667788` |
| Name length limits | Fixed (31 chars) | Unlimited |
| Result in index | Yes (flags bits 0-1) | Yes (+0x58 bits 0-1) |
| Record count in header | Yes (offset 6) | Yes (offset 0x10) |

---

## 12. .2LCD Event Namebase Notes (2026-08-28)

The .2lcd header = [u32 256][u32 827][u32 4096] (BE) — 827 events total.
The file contains German default strings ("Default Turnier", "Default
Quelle") at offsets 0x109c-0x131c. No plain-ASCII event names found for
the PGN event "Munchen Open" or "Cartak CZE" — the events may use a
compressed or indexed encoding distinct from the .2lid format.

The .2cbh @0x28 stores the event ID (integer). The .2lcd maps
event_id -> (event_name, site_name, event_date, etc.) in a similar
manner to the .2lid for players, but the record structure differs
(no signature terminator found).

### Structure (2026-09-07)

.2lcd is a multi-namebase container:

- Header: `[u32be version=1][u32be 827 entries][u32be 0x1000 table
  offset]`.
- 8 category records @0x1000, stride 0x80: Default Spieler (player),
  Default Turnier (tournament/event), Default Quelle (source/site),
  Default Kommentator, Default Mannschaften (teams), Default
  partietitle, Texttitel, Analysen.  Empty categories carry
  ff ff ff ff markers.
- Per category: a u32le ascending OFFSET TABLE (e.g. @0xa000 for the
  player category: 2, 11, 14, 15, 17, 19, ...) into a string pool, and
  the pools store BYTE-REVERSED strings (verified: 'tdimhcs' =
  'schmidt', 'ksvelbur' = 'rublevsk(?)', 'namsab' = 'basman',
  ' leahcim' = 'michael ').
- Bulk data (0xa000..EOF, ~13% printable) = the reversed player-name
  pool; event strings were NOT found in plain or reversed ASCII
  ('Munchen', 'Biel', 'Dortmund' absent), so the Turnier entries are
  further encoded (or referenced) differently.
- Relevance: the .2lid event text is capped at 40 bytes and the bytes
  after the text look like a u16 link id into .2lcd (e.g. 0x0fd2),
  where the full event name (and presumably event dates) live.
  Decoding the Turnier category would lift the 40-char truncation
  (see section 3.8.6.2) and possibly fix the 0.5% unresolved events.


---

## 14. .2lid Event/Site Namebase — SOLVED (2026-09-07, GLM pass in the scid-code project)

The `.2lid` is a fixed-slot array:

- stride `0x108a` (4234) bytes, slots start at `0xb8`; 72,578 slots = the
  file size exactly.  A 184-byte header prefixes the array (6 entity
  types, capacities [1024, 1120, 220, 1024, 314, 532] = 4234 per slot;
  counts: players = 10,700, events = 72,588, sources = 1, annotators = 1
  for the LumbrasGigaBase fixture).
- slot N + 0: the player record (player id = the slot ordinal — which is
  why the signature-record walk worked all along).
- slot N + 0x400: the event pair
  `[u32 x][u16 siteLen][site][u16 pad][u16 evLen][event][pad][u32 year]`
  — the event id = the SAME slot ordinal.  Player ids and event ids are
  independent dense counters over one slot array (slot 234 holds player
  'Kural, Jaroslav' AND event 'Munchen Open' simultaneously; the x
  field's 68 observed values [118..186] are not ids — a per-record
  sub-field census is open, ~1000 records per value).
- siteLen 0 is valid (site-less events); both lengths 0 = deleted
  slots (4,688 games, 0.5%, correctly left "?").  Text is Windows-1252
  (convert through the caller's encoding).
- The `.2lcd` (827 blocks × 4096 bytes = 3,387,392 exactly; header
  [1][827][4096] BE) is a default-namebase template + a checksum-ordered
  index with byte-reversed name fragments — NOT the event storage; a
  dead end for event names.

Validated against the source PGN (game 0 -> 'Munchen Open'/'Munchen
open', game 500000 -> 'World Rapid 2024'/'New York USA' — exact); an
independent player+year cross-check in this repo matched 44/50 sample
games exactly, with the remaining differences being genuine
same-player/same-year event ambiguity (the .2cbh's own event id is
authoritative there) and one site='?' rendering nuance.

scidb integration (this project): `cb2::Codec::doOpen()` walks the
event pairs, converts via the caller's encoding, and resolves the
index's event ids directly (the 'Event N' placeholders are gone).  The
round/subround fields (`0x5a`/`0x5c`, '7.5' style) were decoded in the
same pass and are set per game record.

## 15. .2cba Move Containers — SOLVED (2026-09-07, agy pass)

The `.2cba` item stream is a sequence of MOVE CONTAINERS:

    [u32 LE position][u32 LE count][count sub-items]

with four sub-item types:

- 2: text comment  `[u32 2][u16 lang][u32 len][text]`
- 3: NAG           `[u16 3][u16 nag][u8 0]` (5 bytes)
- 7: move time     `[u8 7][u8 0][u8 m][u8 s][u8 flags][u8 trailer]` (6 bytes)
- 0x21: engine eval `[u16 0x21][i16 centipawns][u32 depth]` (8 bytes)

The old parser misread `count` as a `kind` discriminator — that worked
only for the two common cases (count 1 = text; count 2 = nag + text)
and desynchronized or dropped data on standalone NAGs (4.35%), move
times (13.25% of containers include a time sub-item), engine
evaluations and 3-annotation containers.  The corrected walker parses
17,942/17,942 annotated records (100%) across the whole 205 MB .2cba
(verified with an independent full-file walk in this repo: 863,538
records, 0 failures, 94,116 containers).  Container variant census:
text 17.06%, nag+text 62.90%, text+time 13.25%, standalone nag 4.35%,
time-only 1.27%, nag+text+time 0.89%, text+eval 0.18%, eval-only 0.10%.


## 16. Small databases and Chess960 (2026-10-26)

### 16.1 Index framing: one header, independent of game count

Direct Ghidra MCP inspection of CBase26.exe confirms the layout independently
of the fixture-size inference:

- `0x1401aed70` constructs the index file handler with stride 0xc0, reads the
  header at file offset zero, and initializes a new file's record count to 1.
- `0x1401af060` reads an index record at `recordNumber * stride`.
  `0x1401af4d0` writes at the same offset. There is no 256-record adjustment.
- `0x1401e3ca0` reads the header's u16 stride at +0x0a.
  `0x1401e3cb0` reads the **u64** count at +0x10;
  `0x1401e44c0` writes that count. `0x1401af5b0` writes the header at record 0.

These addresses document observed format behavior; no decompiler listing is
part of the source distribution. Research output stays in ignored scratch.

`cb2_index.h` shares checked geometry between the codec, the converter, the
attributes probe, and the Elo regression test. Empty databases have one
192-byte record; one-game databases have two. Truncated files, unsupported
strides, inconsistent counts, and counts beyond the application's unsigned
ID space are rejected. The count/file-size check avoids integer overflow.
The existing Elo sample indices were shifted by +255 to keep testing the
same physical games and independent expected ratings.

### 16.2 Compact Chess960 setup and castling

For record type 2, the payload starting at record +0x1a is:

```
u16 LE  0xfffb
u16 LE  Scharnagl number (0..959)
u16 LE  0xfffc
        ordinary Move16 game tree
u16 LE  0xffff (each line's terminator)
```

The position writer at `0x1401e8310` emits this prefix and uses 1000 for
an arbitrary setup. Its caller `0x140211d50` emits 0xfffc after setup.
The existing reader at `0x1401590d0` confirms that numbers below 960 select
one of 960 starting boards and consume two words before the game stream.
It handles arbitrary setup separately; type 1 can also carry an explicit
setup. Those forms need real fixture coverage before implementation.

`prepareGame` constructs the start board and FEN tags before any consumer
starts. Scidb reserves ID 0, so Scharnagl 0 maps to internal ID 960.
The index preload records the start ID for the game list; both tree decoding
and consumer/export decoding start from the same board.

A castling descriptor must match the engine's king source/destination and
rook source/destination, and must resolve to a legal castling move. Merely
accepting either the king destination or rook source can silently select the
opposite castle: with king b1 and rooks a1/c1, a blocked long-castle descriptor
must not become the legal short castle. A regression test reproduced this
failure before the match was tightened. Other cases cover a stationary king,
a king/rook swap, and a one-square ordinary king move versus castling.

### 16.3 Variation correction and validation scope

Root markers already count **moves**, excluding prior markers. Their replaced
zero-based ply is `moveCount - 1`; subtracting the marker ordinal again shifts
the second and subsequent root variations. The synthetic two-root regression
covers alternatives to both the first white and first black moves. Missing
terminators and trailing variation data without matching roots are rejected.

Fixture copies and constructed subsets are under `tests/tmp-app/2cbh-re/`.
The 0/1/2/10/255/256/300 subsets contain the first N real index game records
from the copied Lumbras database, with a corrected header count and unchanged
copied sidecars. They are **constructed subsets, not new ChessBase exports**.
The Grenke database is an existing real one-game ChessBase export. Wine/Xvfb
startup restrictions prevented generating additional real fixtures.

`tests/test_2cbh.cpp` contains synthetic tests only. Its optional FEN oracle
checks all 960 positions against independent python-chess output; this proves
the position-number mapping, not 960 distinct ChessBase exports. The real
Grenke game independently matches all 55 mainline plies, the complete starting
FEN, and all ten requested metadata fields (including absent ECO).

Bounded subset move matches are 1/1, 2/2, 10/10, 255/255, 256/256, and 300/300;
all replay legally with python-chess. The empty subset opens and exports zero
games. Matching uses complete UCI mainlines plus player names, allowing only
prefix-compatible shortened names and reporting ambiguous metadata.
All ten requested fields, with ECO compared at its stored three-character
base, match for 1/1, 2/2, 10/10, 230/255, 231/256, and 274/300 games.
For 255 and 256 games the differing-field counts are White 4, Black 3,
Event 16, Round 3; for 300 they are White 4, Black 3, Event 17, Round 3.
Categories can overlap. Site, Date, Result, base ECO, and both Elo values
match throughout these subsets.

These differences must not be hidden by copying tags from the PGN into the
decoder. Raw records corroborate stored-data differences: zero-based game 35
stores event/site `Vladimir` while the source Event is `?`; game 54 stores
`Havana CUB` while the source Event is `?`; game 43 has round/subround bytes
0/0 while the source Round is `?.3`. Player examples contain already-shortened
stored names. Full ECO suffix letters are not decoded, as before.

The public `Database::loadGame` path also loads all 825 non-empty bounded
fixture entries: start boards, mainline lengths, and final piece placements,
turns, and castling rights match independent PGN replay. This complements
consumer-path conversion and directly exercises the editor's GameData decoder.

Full-scale export converts **863,793/863,793 games, skipped 0, failed 0**,
including 16,961 games with annotation items. This includes the 255 recovered
records and preserves the previous full-database success count.

An independent full-source join against 863,790 PGN games uses both normalized
player names and complete normalized mainline SAN, retaining all candidates.
It matches 830,123/863,793 exported games; 778,069 also match all ten fields
at base ECO, and 164,658 match the literal fields including ECO suffixes.
Among matched games, differing-field counts are Event 38,436, Round 12,775,
White 330, Black 308, Site 508, Date 10; Result, base ECO, and both Elo fields
have zero differences. Categories overlap. Another 33,670 games have no exact
name/SAN key match and remain unresolved by this join, not proven move errors.
Shortened names and alternative SAN spelling already explain some bounded
examples, whose independent UCI comparisons pass. No full-source equality
claim is made for unresolved games.

See the scratch `REPORT.md` for exact commands, backend validation, and
environment limits. No probabilistic model is used:
byte parsing and chess facts are determined by code and the board engine.

## 17. ECO key, event date, annotator, arbitrary setups (2026-10-26, run 6)

Offsets below were confirmed against CBase26.exe through the live Ghidra
session. Addresses are cited as evidence only; no decompiled code is part of
the source distribution.

### 17.1 The ECO key @0x80 carries a sub-variation number

`0x1401e3ba0` (getter) and `0x1401e4370` (setter) read/write the u16 at
record `+0x80` and clamp every value above `0xfa7f` to 0 ("no ECO"). The PGN
formatter `0x140c66e50` (used by the game writer for the `ECO` tag) decodes it
as

```
base = (key >> 7) - 1          // 0 = A00 .. 499 = E99
sub  = key & 0x7f              // 0 = none; rendered as "/01".."/99"
```

so a key of `B12` with sub-variation 34 renders as **`B12/34`**. The low
seven bits were "always zero" in the LumbrasGigaBase edition (863,519 keys)
and are still zero in the subsets, but they are *not* unused: they are the
sub-variation index Scidb's `Eco` class keeps in its 11-bit sub-code. The
`ECO` tag now carries the full form; `GameInfo::m_eco` keeps the base code
(the game list's Eco column has no room for the extension). `0xffca` in the
Grenke Chess960 fixture is the "no ECO" form, as that game has none.

A sub-letter (`B12a`) is *not* stored: the only textual extension the index
supports is the numeric `/NN` above (the letter is a runtime classification
of ChessBase's opening key, §34).

### 17.2 EventDate, source and annotator live in the `.2lid`

#### Slot layout

The `.2lid` is one slot array (stride `0x108a`, first slot at `0xb8`) and every
slot holds one record of each of the six namebases.  The six capacities in the
file header are the record sizes and sum to exactly the stride:

| Offset | Capacity | Namebase | Game index field |
|--------|----------|----------|------------------|
| `+0x000` | 1024 | players | `+0x18`/`+0x20` White/Black — and `+0x30`, the annotator (see below) |
| `+0x400` | 1120 | tournaments (events, with `.2lid` Site and EventDate) | `+0x28` |
| `+0x860` | 220 | sources | `+0x38` |
| `+0x93c` | 1024 | *unidentified* — zero in every fixture, not the annotator | — |
| `+0xd3c` | 314 | teams | `+0x40`/`+0x48` (White/Black team) |
| `+0xe76` | 532 | game titles | `+0x50` |

Each section is a namebase of its own: the index stores the *record ordinal*
of the wanted entry, and because the sections share the slot array that ordinal
is also the slot number.  CBase26's reference-repair function walks exactly
these six id fields with exactly these six libraries (and its sort keys resolve
`+0x30` through the annotator library and `+0x38` through the source library);
the field order also matches the classic CBH record (white, black, tournament,
annotator, source).

#### Event record (`+0x400`)

The event record at `slot*0x108a + 0xb8 + 0x400` is

```
u32  unknown (observed 118..186)
u16  siteLen, u16 pad
char site[siteLen]
u16  eventLen, u16 pad
char event[eventLen]
u32  packed date           // day(5) | month(4) << 5 | year(12) << 9
```

The packed date after the event text is the **`[EventDate]`** tag: the
Grenke fixture stores `0x0fd481` = 2026.04.01, exactly the value of its own
`EventDate` tag (the game itself is dated 2026.04.02). `cb2::Codec` now passes
it to `NamebaseEvent::insertEvent()`, so `GameInfo::eventDate()` and the
`EventDate` info tag are filled without a second source.

The 4-character federation strings at `+0x68`/`+0x74` (`FIDE` in the Grenke
record) are ChessBase federation names, not Scidb country codes, so they are
not mapped.

#### Source record (`+0x860`)

```
u32 total                       // = 20 + len1 + len2
u32 titleLen, char sourceTitle[]
u32 len,      char source[]
8 zero bytes
```

This is the game's source (`[Source]`), *not* the annotator.  Data-verified:
the Grenke fixture stores `playchess.com` / `ChessBase` and the Lumbras
fixture stores an empty title and `Codekiddy` — exactly the `[Source
"Codekiddy"]` of that database's own source PGN, which has no `[Annotator]`
tag at all.  `cb2::Codec` sets `tag::Source` from the second string (the first
one, `[SourceTitle]`, has no tag in this codebase) and `2cbh2pgn` emits it;
`cb2::WriteGame` writes the same record.

#### Annotator: index `+0x30` is a *player* id (`+0x000`)

ChessBase models the annotator as a person, so the per-game annotator
reference points into the player array, not into a separate annotator store:

* The genuine Grenke database has **no** annotator records anywhere — its
  `+0x93c` section is all zero and the header counts zero annotators — yet
  index `+0x30` is 2 for its only game, and CBase26's own game list shows
  `Annotator  ChessBase` for it.  The third player record of that database is
  exactly `ChessBase` (the PGN import created it), which is also why a
  one-game database reports three players.
* A synthetic database written with a distinct annotator name in the `+0x93c`
  section (`Annotator, Ann`) and the id of an unrelated player at `+0x30`
  (slot 0, `Alpha, Ann`) shows **`Alpha,A`** in CBase26's Annotator column, not
  the `+0x93c` string.  CBase26 resolves `+0x30` through the player namebase.

`cb2::Codec::getAnnotator()` therefore resolves `+0x30` through the player
map, `~0` (or an unnamed record) giving the empty annotator, and
`cb2::WriteGame` inserts the annotator name into the player list so that the
reference resolves.  The `+0x93c` section (capacity 1024) stays unidentified;
it is neither read nor written.

### 17.3 Arbitrary start positions (position 1000, and type 1 with setup)

The record stream of a game with a non-compact start position is

```
u16 0xfffb
u16 position                 // type 2 only; 0..959 compact, 1000 = arbitrary
    setup block              // only for 1000 or for type 1 with 0xfffb
u16 0xfffc
    Move16 mainline and variations
u16 0xffff
```

Reader `0x1401590d0` skips **four** bytes of setup block after `0xfffb`
(+ the position word for type 2) and then reads one Move16 code per occupied
square until a token `>= 0xfffb`: `buildSetupBoard()` mirrors that. Each code
is a piece placement: the descriptor's `to` square (file-major, as everywhere
in Move16) receives `piece`. The position writer `0x1401e8310` emits **six**
block bytes (`u16`, side to move, two bytes, filler) before the square codes,
so the reader accepts both widths and both sides to move and keeps the
interpretation whose mainline replays legally — the flags themselves are not
decoded, and no fixture with an arbitrary setup exists yet.

Castling rights are derived from the placement (king on its home rank with a
rook on the same rank), which is Scidb's Chess960 convention. The FEN tag is
emitted in Shredder form. Compact positions 0..959 (Grenke: 906) keep using
the existing `Board::setup()` path; the FEN of the fixture's start position
matches its `[FEN]` tag, and its castling descriptor
(`0xbf55`: king b1→c1, word1 rook a1→d1) resolves to the real castling move.

### 17.4 `dataSize` is the length of the data field at `+0x1a`

`dataSize` at record `+0x08` is the length of the data field, which starts at
`+0x1a` (right after the 26-byte record header: magic, dataSize, extraSize,
8-byte sub-field, 2-byte type word). The extra field follows the data. This is
byte-exact on the fixtures: e.g. subset300 game 0 has `dataSize` 46 and its
data runs from the `0xfffc` start token through the `0xffff` terminator in
exactly 46 bytes, with the u64 record-size trailer right after the 100-byte
extra field (`26 + dataSize + extraSize + 8`). The `.2cba` records behave the
same way (`dataSize` 4 for the `ff ff ff 7f` "no annotations" marker).
Subtracting the 10 header bytes would truncate every game.

### 17.5 Verification

- `cb2::Codec` on the Grenke fixture: `[EventDate "2026.04.01"]`,
  `[Annotator "ChessBase"]` (index `+0x30` = 2 -> player 2 = `ChessBase`) and
  `[Source "ChessBase"]` (index `+0x38` = 0 -> source section slot 0), plus the
  ten previously decoded fields, all equal to the source PGN.
- `2cbh2pgn` emits `[EventDate]`, `[Source]` and `[Annotator]` from the same
  records.  On the 300-game subset the only change against the run-5 output is
  300 `[Source "Codekiddy"]` lines (and 295 `[EventDate]` lines from run 6);
  no other tag and no move changed, and no game gained an `[Annotator]` (that
  database has annotator id 2, whose player slot is empty).  Grenke gains
  `[Annotator "ChessBase"]` and `[Source "ChessBase"]`.
- A database written by `cb2::writeDatabase` with a distinct source pair and a
  distinct annotator name, exported through `cdb2pgn` (i.e. through
  `Database::exportGame` -> `cb2::Codec::doDecoding`), comes back with
  `[Annotator "Annotator, Ann"]` and `[Source "ChessBase"]` on the first game
  and `[Source "TWIC"]` only on the second, and the public API reports the
  same annotator and medals (`Database::gameInfo(i).flags()`).
- CBase26 (Wine) lists a database written this way — see §19 for what could
  and could not be driven.
- `src/db/test_2cbh` (synthetic, 3,433 checks) passes; the optional 960-FEN
  oracle still matches all 960 positions.

### 17.6 Medals and game flags (index `+0x82`)

The u16 at record `+0x82` is the game's medal word, in the slot classic CBH
uses for the same word (bytes 37-38, immediately after the ECO key at 35-36).
CBase26 exposes it with a plain getter/setter pair (`0x1401e3d60` /
`0x1401e45b0` store the raw word, no clamping, no transformation — unlike the
ECO accessors on the neighbouring `+0x80`, which clamp), and the record
serializer writes it as a u16.

The bit assignment is the classic CBH one, which scidb already implements in
`src/db/cbh/cbh_codec.cpp`:

| Bit | GameInfo flag | Medal |
|-----|---------------|-------|
| 0 | `Flag_Best_Game` | best game |
| 1 | `Flag_Decided_Tournament` | decided the tournament |
| 2 | `Flag_Model_Game` | model game |
| 3 | `Flag_Novelty` | novelty |
| 4 | `Flag_Pawn_Structure` | pawn structure |
| 5 | `Flag_Strategy` | strategy |
| 6 | `Flag_Tactics` | tactics |
| 7 | `Flag_With_Attack` | attack |
| 8 | `Flag_Sacrifice` | sacrifice |
| 9 | `Flag_Defense` | defence |
| 10 | `Flag_Material` | material |
| 11 | `Flag_Piece_Play` | piece play |
| 12 | `Flag_End_Game` | endgame |
| 13 | `Flag_Blunder` | tactical blunder |
| 14 | `Flag_Blunder` | strategical blunder |
| 15 | `Flag_User` | user-defined |

Bits 13 and 14 are two flavours of one scidb flag, so writing `Flag_Blunder`
sets both.  `src/db/2cbh/cb2_flags.h` is the single definition: `cb2::Codec`
decodes with `cb2GameFlags()`, `cb2::WriteGame::medals` writes with
`cb2Medals()`, and the synthetic tests check all sixteen bits plus every one
of the 65,536 words.

Every genuine record in every fixture has `+0x82 == 0` (863,793 records in the
Lumbras database alone), so the assignment is inherited from classic CBH, not
derived from this format's data; the synthetic round trip is the acceptance
test.  Two neighbouring fields are *not* part of it:

* `+0x58` bits 2..7 — a six-bit value (getter `0x1401e3eb0` returns
  `byte >> 2`, setter `0x1401e46a0` stores six bits).  It is compared, with the
  result and byte `+0x59`, as a sort tie-breaker; it is zero in all 863,793
  Lumbras records, so nothing can be inferred about its bits.  Left unmapped.
* `+0xba` bits 0..2 — three single-bit flags with their own setters
  (`0x1401e4540`, `0x1401e4470`, `0x1401e4500`), zero everywhere.  Left
  unmapped.

## 18. Writer: `cb2::writeDatabase` / `cb2::appendToDatabase` (2026-10-26, run 6)

`src/db/2cbh/cb2_writer.{h,cpp}` writes the four files from
`mstl::vector<WriteGame>`:

| File | Content |
|------|---------|
| `.2cbh` | one 192-byte header record (`0x26` @+0x08, stride `0xc0` @+0x0a, `0x500` @+0x0c, u64 record count @+0x10) and one 192-byte record per game |
| `.2cbg` | 12-byte file header (`u64 file size`, `u16 12`, `u16 0x500`), then per game `magic | dataSize | extraSize=100 | 8-byte sub-field | type | payload | 100 zero bytes | u64 record size` |
| `.2cba` | as `.2cbg` with type `0x2000` and the four-byte `ff ff ff 7f` "no annotations" data |
| `.2lid` | 184-byte header (six capacities `1024/1120/220/1024/314/532` and their counts) plus one 4234-byte slot per ordinal: player record @+0, event/site/EventDate @+0x400, source @+0x860 (the unknown fourth section @+0x93c stays zero) |

`WriteGame` carries the PGN strings, the source pair (`sourceTitle`/
`source`), the annotator, the medal word, the Elo pair, a `Date`, a setup
selector (-1 = standard start, 0..959 = Scharnagl, 1000 + `fen` = arbitrary
setup, -2 = verbatim payload) and the Move16 token stream (built by
`encodeMoveStream()`, which encodes a legal line and keeps markers/variations
when the caller supplies them).

Index record fields written (all confirmed against CBase26's own accessors,
§17): `+0x00` = 1, `+0x02` = `0x0101`, `+0x08` `.2cbg` offset, `+0x10` `.2cba`
offset, `+0x18`/`+0x20` player ids, `+0x28` event id, `+0x30` annotator id
(`-1` = none), `+0x38` source id (`-1` = none), `+0x40`/`+0x48` = `-1` (teams),
`+0x50` game title (`-1`, unused), `+0x58` result, `+0x5a`/`+0x5c`/`+0x5e`
round levels, `+0x60`/`+0x70` Elo, `+0x80` = `128 * (base + 1)`, `+0x82` medals
(§17.6), `+0x8a` mainline moves, `+0xbc` packed date.

The annotator id is a *player* id: when a game names an annotator whose name is
not already a player, the writer appends that name to the player list (after
all real players, so existing ids stay stable) and stores its id at `+0x30` —
exactly what CBase26's PGN import does (§17.2).  The source pair goes into the
`+0x860` record of the source section, in the two-string grammar CBase26 writes
(`[u32 total = 20 + len1 + len2][len1][str1][len2][str2][8 zeros]`).
`appendToDatabase()` carries both back: it re-reads the source section and
resolves `+0x30` through the players it re-reads, and it preserves the medal
word.

Encoding uses the same embedded decode table as the reader: `encodeMove16()`
looks the candidate codes up by (from, to, moving piece) and verifies each one
by resolving it against the board's legal move list, so encode → decode → move
is exact for king moves, castling (both transitions), promotions, en passant
and double pushes. `findPlacementCode()` returns the `from == to` descriptor
the arbitrary-setup block needs.

`appendToDatabase()` reads the existing index, namebase and payloads, keeps the
payloads verbatim (setup prefix included) and rewrites the three files with the
new games appended, so ids and namebases stay consistent.

Round-trip verification (synthetic, no fixture data) in `tests/test_2cbh.cpp`:

* every legal move of eight positions (standard start, castling both sides,
  promotion, en passant, two Chess960 starts) survives encode → decode → resolve;
* every placement code (pieces 1..5/9..13 on all 64 squares, pawns on the 48
  legal ones) is found and decodes to a `from == to` descriptor;
* an explicit setup stream is accepted with two-, three- and four-word headers,
  for both sides to move, and refused when truncated;
* `writeDatabase()` output is read back through `readIndexLayout`,
  `prepareGame`, `walkGameRaw` and `parseCbaItems`: three games (standard with a
  variation, compact Chess960 906, arbitrary setup) round-trip with identical
  players, event/site/EventDate, date, round, result, base ECO, both Elo values,
  mainline length and final position, plus the annotator (as a player record),
  the `[SourceTitle]`/`[Source]` pair and the medal word; `appendToDatabase()`
  adds a fourth game and keeps all three of those of the earlier games.
* all sixteen medal bits map to their `GameInfo` flag and back, and each of the
  65,536 medal words keeps its flags when re-encoded (§17.6).

CBase26 (Wine) opens a database written this way and lists its games with the
right names, Elo, results, move counts, ECO, event, date and round (scratch
screenshots `cbase-open-written-db-*.png`). Two layout details were required
for that: the header record size `0x26` belongs at **+0x08** (not +0x00), and
the `.2lid` event record's leading word is its length `116 + siteLen +
eventLen` — with 0 there, CBase26 shows the wrong tournament name.  The
`Annotator` column it draws is resolved through the player namebase
(§17.2).  Whether CBase26 also *renders the moves* of a written game could not
be confirmed because the GUI cannot be driven reliably without a window
manager.

## 19. Open items (2026-10-26, run 7)

What §16-§18 do **not** cover, i.e. the real remaining work.  Everything else
in §8/§9 is historical and settled by now.

1. **The `+0x93c` namebase section (capacity 1024)** is unidentified.  It is
   all zero in every fixture, and CBase26 ignores a record written there, so it
   is neither read nor written.  It is one of the six namebases the file header
   declares, so it exists — but no data to identify it has been seen.
2. **Game titles (`+0x50`) and teams (`+0x40`/`+0x48`)** are known to be
   namebase references (capacities 532 and 314) but are never populated in the
   fixtures and are not written; scidb has no tag for a game title, so only
   `WhiteTeam`/`BlackTeam` could be exposed if a fixture with teams appeared.
3. **`+0x58` bits 2..7 and `+0xba` bits 0..2** are unmapped (§17.6); both are
   zero in all 863,793 Lumbras records, so no bit assignment can be derived
   from data.
4. **Writer integrity.** CBase26 opened the written databases and listed the
   games, but re-opening one of them in the same session once made it run its
   integrity-check/error report page instead of the list.  The trigger was not
   isolated (the same file had opened normally a few minutes earlier, and a
   second window of the session was also open on another database).  Related
   unknowns: the `.2lid` header's per-section counts and the trailing
   `{1,slot}` table are copied from the genuine fixtures and were never checked
   against a database CBase26 itself created with more than one namebase entry
   per slot.  Worth re-checking in a clean session before anyone relies on the
   writer.
5. **Medal bits come from classic CBH, not from 2CBH data** (§17.6).  Every
   genuine record has `+0x82 == 0`.  A database imported through CBase26 with
   medals set (PGN import cannot set them, so this needs the GUI) would settle
   it.
6. **Merging/`appendToDatabase` id spaces.** The writer keeps one dense id per
   section (id == slot), which is what the reader and CBase26 accept, but
   CBase26's own files have sparse ids, deleted slots and a free-chunk list; the
   writer never reuses a slot and always writes the same six free chunks.
7. **Chess960 `Variant`/castling flags in the setup block** are still
   interpreted by trial (§17.3): both sides to move and both block widths are
   accepted and the interpretation whose mainline replays legally is kept.
   No fixture with an arbitrary setup exists.
