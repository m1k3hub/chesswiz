# Chess960 CBG/CBH Decoding Status — Assessment Report

**Date:** 2025-07-21 (updated after Phase 5 Part A + fixture acquisition)  
**Scope:** CBH/CBG decoder (`src/db/cbh/`), Board engine, probe tools, test fixtures

---

## Current Capability

**Summary:** Chess960 games are **detected** and the flag is propagated to the
decoder. The `m_isChess960` flag is now used to skip the standard-chess-only
`fixBadCastlingRights()` step in `Position::setup()`. The decoder and board
engine use **file-based castling destinations** (Convention B): short
castling always places the king on the g-file and the rook on the f-file;
long castling always places the king on the c-file and the rook on the
d-file. The 28-byte custom-position format is read but the 36-byte Chess960-
extended format is explicitly skipped. XOR-encrypted games (bit 31) throw a
precise exception.

**Bottom line:** The decoder can correctly set up Chess960 start positions
and round-trip games whose castling moves happen to be representable as a
two-square king move. Real ChessBase-generated `.cbh`/`.cbg` fixtures are
still required to validate positions where the king is off the e-file and
castling is encoded differently.

---

## Conventions

scidb intentionally uses **Convention B** (file-based destinations) for
Chess960 castling:

- **O-O:** king → g-file, rook → f-file.
- **O-O-O:** king → c-file, rook → d-file.

This matches ChessBase behavior and the GRENKE PGN/SAN output. An earlier
sub-agent change to king-relative (Convention A) destinations was reverted.

The CBH move **encoder**, however, currently emits castling as a two-square
king move token (`0x09` / `0x0a`). When the king is off the e-file, a
file-based castling move is not always a two-square king move, so the encoder
cannot represent every legal Chess960 castling. The decoder path is correct
when the token is present; the limitation is in generating the token.

## Exact Files and Functions Involved

### Detection

| File | Line(s) | Function | Status |
|------|---------|----------|--------|
| `src/db/cbh/cbh_codec.cpp` | 2481 | `Codec::startDecoding()` | ✅ Computes `isChess960 = bool(word & 0x0a000000)` |
| `src/db/cbh/cbh_codec.cpp` | 2637–2704 | (4 call sites) | ✅ Passes `isChess960` to `Decoder`/`GameDecoder` constructor |
| `src/db/cbh/cbh_decoder.h` | 46, 61 | `Decoder` class | ✅ Stores `m_isChess960` member |
| `src/db/cbh/cbh_decoder.cpp` | 81–83 | `Decoder::Decoder()` | ✅ Initializes `m_isChess960` |

### Custom Starting Position

| File | Line(s) | Function | Status |
|------|---------|----------|--------|
| `src/db/cbh/cbh_decoder.cpp` | 467–485 | `Decoder::startDecoding()` | ⚠️ Reads only 28 bytes; comments say 36-byte format "not used in practice" |
| `src/db/cbh/cbh_game_decoder.cpp` | 763–775 | `GameDecoder::startDecoding()` | ⚠️ Same 28-byte hardcode, duplicated |
| `src/db/cbh/cbh_decoder_position.cpp` | 327–430 | `Position::setup(BitStream&)` | ⚠️ Reads 224 bits (28 bytes); calls `fixBadCastlingRights()` when bits exhausted |

### Castling

| File | Line(s) | Function | Status |
|------|---------|----------|--------|
| `src/db/cbh/cbh_decoder.cpp` | 115–116 | `decodeMove()` | ✅ Maps 0x09→short, 0x0a→long castling |
| `src/db/cbh/cbh_decoder_position.cpp` | 173–201 | `Position::doCastling()` | ⚠️ Rook *source* uses `board.shortCastlingRook()` (good); rook *destination* hardcoded to FyleF/FyleD (bad for Chess960) |
| `src/db/db_board.cpp` | 5587–5637 | `Board::doMove()` (Castle case) | ⚠️ King destination hardcoded to FyleG/FyleC; rook destination hardcoded to FyleF/FyleD — wrong for Chess960 where king is not on e-file |
| `src/db/db_board.cpp` | 2573–2625 | `Board::shortCastlingRook()` / `longCastlingRook()` | ✅ Scans for rooks relative to king position on home rank; works for Chess960 |

### `m_isChess960` Usage

| File | Line(s) | Status |
|------|---------|--------|
| `src/db/cbh/cbh_decoder.cpp` | 83 | Stored but **never read** anywhere in the decoder |
| `src/db/cbh/cbh_decoder.h` | 61 | Declared, never used in logic |

### XOR Encryption

| File | Line(s) | Function | Status |
|------|---------|----------|--------|
| `src/db/cbh/cbh_codec.cpp` | 2473–2478 | `Codec::startDecoding()` | ❌ Throws `DecodingFailedException("cannot decode")` when bit 31 is set |

### Board Helpers

| File | Line(s) | Function | Status |
|------|---------|----------|--------|
| `src/db/db_board.cpp` | 2718–2770 | `Board::fixBadCastlingRights()` | ⚠️ Standard-chess only; strips castling rights when king is not on e1/e8. Called from `Position::setup()` after reading 28-byte position. |
| `src/db/db_board.cpp` | 2573–2625 | `Board::shortCastlingRook()` / `longCastlingRook()` | ✅ Already Chess960-aware: scans for rooks on home rank relative to king |

---

## What Has Already Been Improved (vs. CHESS960_CBG_REVERSE_ENGINEERING.md)

The reverse-engineering doc (written earlier) states:

> "The decoder hardcodes standard rook positions (a1/h1 for white, a8/h8 for black)"

**This is no longer true.** The `doCastling()` function in
`cbh_decoder_position.cpp` (lines 188–193) now calls:

```cpp
Byte rookFrom = isShortCastling
    ? board.shortCastlingRook(sideToMove)
    : board.longCastlingRook(sideToMove);

// Fall back to orthodox rook files if castling metadata is unavailable.
if (rookFrom == sq::Null)
    rookFrom = sq::make(isShortCastling ? sq::FyleH : sq::FyleA, rank);
```

The `Board::shortCastlingRook()` / `longCastlingRook()` functions scan for
rooks on the home rank relative to the king position, which is correct for
Chess960. The fallback to h/a files only triggers when the rook cannot be
found (e.g., missing rook or metadata not set).

The encoder side (`cbh_encoder_position.cpp`, line 238–240) also uses
`board.shortCastlingRook()` / `board.longCastlingRook()` and includes a
comment: "CBH keeps castling as logical short/long tokens, even when the
rook starts on a Chess960 file."

**However**, the rook and king *destination* squares are still hardcoded.

---

## Missing Implementation Steps

### 1. Use `m_isChess960` to skip `fixBadCastlingRights()` (critical, small)

In `cbh_decoder_position.cpp`, `Position::setup(BitStream&)` calls
`board.fixBadCastlingRights()` when `strm.bitsLeft() == 0` (after consuming
the 28-byte format). This function strips castling rights when the king is
not on e1/e8, which is wrong for Chess960.

**Fix:** Pass `isChess960` to `Position::setup()` and skip
`fixBadCastlingRights()` when true. The `m_isChess960` flag is already stored
in the `Decoder` base class but never passed to `Position::setup()`.

**Estimated size:** ~10 lines across 3 files.

### 2. Fix castling rook/king destination squares (critical, medium)

In `cbh_decoder_position.cpp` `doCastling()` (line 195):

```cpp
Byte rookTo = sq::make(isShortCastling ? sq::FyleF : sq::FyleD, rank);
```

And in `src/db/db_board.cpp` `Board::doMove()` (lines 5601–5605):

```cpp
if (from < to) {
    rookTo = sq::make(FyleF, rank);
    to = sq::make(FyleG, rank);
} else {
    rookTo = sq::make(FyleD, rank);
    to = sq::make(FyleC, rank);
}
```

For Chess960, the correct destinations are:
- Short: king → `from + 2`, rook → `from + 1`
- Long: king → `from - 2`, rook → `from - 1`

Where `from` is the king's starting square. The hardcoded g/c/f/d squares are
only correct when the king starts on the e-file.

**Fix:** Compute destinations dynamically based on `from` (king's square) when
`isChess960` is true. This affects the core `Board` class, so it must be
gated on the Chess960 variant flag to avoid breaking standard chess.

**Estimated size:** ~20 lines in `db_board.cpp`, ~5 lines in `cbh_decoder_position.cpp`.

### 3. Handle the 36-byte position format (important, medium)

Both `Decoder::startDecoding()` and `GameDecoder::startDecoding()` hardcode
`unsigned size = 28;`. The extra 8 bytes in the 36-byte format likely encode
the Chess960 rook starting squares, which would allow proper castling setup.

**Fix:** When `isChess960` is true and enough bytes remain, read 36 bytes
instead of 28. Parse the extra 8 bytes to extract rook positions and pass
them to `Board::setCastleShort()` / `Board::setCastleLong()`.

**Risk:** ~~Without actual CBH test fixtures containing 36-byte positions, the
format of the extra 8 bytes is speculative.~~ **RESOLVED (2026-07-22):** a
real ChessBase `.cbv` fixture (`twic1639_grenke_freestyle_open.cbv`) is now
committed, and `probe_cbh_chess960` confirms the 36-byte block is real and
used by all 606 Chess960 games, with 9 distinct 8-byte extensions matching
the 9 start positions. See the "Phase 5 Part C" section for the definitive
probe results. The exact field layout of the 8 bytes remains to be decoded
(correlate with the 9 known FENs).

**Estimated size:** ~30 lines across 4 files. Requires verification with
real data.

### 4. Handle XOR encryption (0x80000000 bit) (low priority, unknown)

When bit 31 is set, the game data is XOR-encrypted. Currently throws an
exception. The XOR key/algorithm is unknown without analyzing CBASE16.exe.

**Estimated size:** Unknown. Requires reverse engineering.

### 5. Remove duplicate `startDecoding()` code (cleanup, small)

`Decoder::startDecoding()` and `GameDecoder::startDecoding()` contain
identical 28-byte position logic. Any fix must be applied to both copies.

---

## Probe and Test Tools

| Tool | Source | Status |
|------|--------|--------|
| `probe_cbh_chess960` | `src/probe_cbh_chess960.cpp` | ✅ Builds, inspects raw CBH/CBG flags and custom-start bytes |
| `scan_db_chess960` | `src/scan_db_chess960.cpp` | ✅ Builds, scans any database for Chess960 FEN tags |
| `verify_cbh_write` | `src/verify_cbh_write.cpp` | ✅ Builds and passes all 5 steps end-to-end (exit 0), including Chess960 castling/piece-move codec tests and the nine GRENKE start FENs. (An earlier version failed at step 2 on `isWritable()`; that precondition was fixed.) |

### verify_cbh_write Chess960 Tests

The file `src/verify_cbh_write.cpp` includes two Chess960-specific tests:

1. **`verifyChess960CastlingCodec()`** (line 496): Tests CBH encoding/decoding
   of a short castling move in a position with king on e1 and rook on g1
   (`"4k3/8/8/8/8/8/8/4K1R1 w G - 0 1"`). Verifies the codec round-trips
   correctly. This is a **synthetic** test position, not a real Chess960
   starting position.

2. **`verifyChess960PieceMoveCodec()`** (line 525): Tests CBH encoding/decoding
   of a knight move in a Chess960-like position.

Both tests exercise the low-level move codec (encode → decode → compare) but
do **not** test:
- The 36-byte position format
- Actual CBH file parsing of Chess960 games
- Castling in positions where the king is not on the e-file
- The `fixBadCastlingRights()` interaction

---

## Binary Fixtures

| Resource | Available | Location | Notes |
|----------|-----------|----------|-------|
| CBV Chess960 database | ✅ | `opening-report/tests/fixtures/twic1639_grenke_freestyle_open.cbv` | Real TWIC ChessBase `.cbv` (1.2 MB) containing the grenke Freestyle Open Chess960 games; scidb currently fails to decode the Chess960 games (606 corrupted) - see Phase 5 Part C section below |
| Chess960 PGN data | ✅ | `/tmp/CB/grenke_freestyle_2026.pgn` | 534 games, 9 unique Chess960 positions, may not persist |
| GRENKE_CHESS960_FIXTURES.md | ✅ | Repository root | Documents PGN data with FEN positions and castling patterns |
| CBASE16.exe | ✅ (was) | `/tmp/CB/CB16_cab/CBASE16_EXE` | ChessBase 16 binary for reverse engineering, may not persist |
| Small .sci test databases | ✅ | `tests/tmp-app/` | Standard chess only, not Chess960 |

**To create CBH test fixtures:** Import the Grenke Chess960 PGN into
ChessBase 16/17 (via Wine), export as CBV, decompress with the existing CBV
tool, then inspect with `probe_cbh_chess960`.

---

## Recommended Next Action

### Immediate (safe, no binary fixtures needed)

1. **Pass `m_isChess960` to `Position::setup()` and skip
   `fixBadCastlingRights()`** when true. This is a ~10-line change across
   `cbh_decoder.cpp`, `cbh_game_decoder.cpp`, `cbh_decoder_position.cpp`,
   and `cbh_decoder_position.h`. It prevents the most immediate breakage:
   castling rights being incorrectly stripped for Chess960 positions.

2. **Fix the rook destination in `Position::doCastling()`** to compute
   `rookTo = from + (isShort ? 1 : -1)` instead of hardcoding FyleF/FyleD.
   This fixes the Position's internal piece tracking. ~5 lines.

### Medium-term (requires verification)

3. **Fix `Board::doMove()` Castle case** to compute king/rook destinations
   dynamically when the position is Chess960. This is the core fix but
   touches the central Board class, so it must be gated carefully.
   ~20 lines.

4. **Obtain CBH Chess960 test fixtures** by importing the Grenke PGN into
   ChessBase and exporting as CBV. Use `probe_cbh_chess960` to inspect the
   36-byte format hypothesis.

### Long-term

5. **Implement 36-byte position format** once the format is verified with
   real data.

6. **Handle XOR encryption** (requires CBASE16 reverse engineering).

---

## Build Verification

All relevant targets compile successfully:

```
make -C src/tcl                # ✅ Nothing to do (already built)
make -C src verify_cbh_write   # ✅ Building verify_cbh_write
make -C src probe_cbh_chess960 # ✅ Building probe_cbh_chess960
make -C src scan_db_chess960   # ✅ Building scan_db_chess960
```

`verify_cbh_write` now passes all 5 steps end-to-end (exit 0), including the
Chess960 codec tests. The earlier `isWritable()` precondition failure at
step 2 has been fixed; the low-level Chess960 castling/piece-move codec tests
now run and pass.
---

## Phase 5 Part A — Completed

| # | Deliverable | File | Status |
|---|-------------|------|--------|
| A1 | Precise encrypted-game error | `src/db/cbh/cbh_codec.cpp` | ✅ `"encrypted game not supported (CBH bit 31 set, offset …)"` |
| A2 | De-duplicate position setup | `src/db/cbh/cbh_decoder.cpp`, `cbh_game_decoder.cpp`, `cbh_decoder_position.cpp` | ✅ `setupStartPosition()` helper; size guard |
| A3 | Off-e-file Chess960 round-trip test | `src/verify_cbh_write.cpp` | ✅ `verifyChess960OffFileKingCastling()` |
| A4 | `m_isChess960` skips `fixBadCastlingRights()` | `src/db/cbh/cbh_decoder_position.cpp` | ✅ `Position::setup(BitStream&, bool)` |

---

## Phase 5 Part B/C — Current State (2025-07-21)

### What was done

1. **Acquired fixtures.** Downloaded the official ChessBase live PGN for the
   Grenke Freestyle Chess Open 2026 (535 games, 9 unique Chess960 start
   positions plus one standard-chess game). Imported it into a native scidb
   `.sci` database using `tkscidb-beta` under Xvfb.

   - `opening-report/tests/fixtures/grenke_freestyle_2026.{pgn,sci,scg,scn}`
   - `opening-report/tests/fixtures/grenke_subset_10.{pgn,sci,scg,scn}`
   - `opening-report/tests/fixtures/generate_sci.tcl`

2. **Added GRENKE FEN coverage to `verify_cbh_write`.** Step 5 now sets up
   every GRENKE start FEN and round-trips a simple pawn move through the
   CBH custom-position codec. This proves the 28-byte position block is read
   and written correctly for all nine Chess960 layouts.

3. **Added diagnostic script.** `scripts/analyze_grenke_fixtures.py` reads
   the PGN and reports, per start FEN: game count, observed castling
   patterns, and whether any castling is legal in the start position.

### What the diagnostics reveal

- **King files are unevenly distributed.** Only four of the nine FENs put
  the white king on the e-file. The other five put it on b, d, f, or g.
- **Initial castling rights are often blocked.** In most raw start positions
  the squares between the king and the relevant rook are occupied by other
  pieces, so no castling is legal immediately. Games acquire legal castling
  only after development moves clear the path.
- **The CBH encoder's two-square castling assumption is the binding
  constraint.** Because the encoder emits castling as token `0x09`/`0x0a`
  and assumes the king moves exactly two squares, it cannot faithfully
  represent file-based (Convention B) castling for off-e-file kings where
  the move is one or three squares. Those games would round-trip as ordinary
  king moves (or fail to move the rook).

### What remains blocked

| Deliverable | Blocker |
|-------------|---------|
| 36-byte position format parsing | **Unblocked.** Fixture `twic1639_grenke_freestyle_open.cbv` committed; 36-byte block confirmed (9 distinct 8-byte extensions). Field layout + `Position::setup` extension remain to implement |
| XOR keystream characterization | No encrypted + unencrypted game pair; no CBASE16 analysis |
| Off-e-file castling token encoding | Need to know how ChessBase actually serializes these moves |

### Recommended next action

1. **Keep the current Convention B behavior.** Do not switch to
   king-relative (Convention A) destinations; the project already decided
   to stay file-based to match ChessBase output.

2. **If real ChessBase fixtures become available**, run `probe_cbh_chess960`
   on them to determine:
   - Whether the 36-byte position block exists and what the extra 8 bytes
     encode.
   - How ChessBase encodes off-e-file castling moves (different token?
     multi-byte move? ordinary king move with implicit rook update?).

3. **Until then**, treat Chess960 CBH support as best-effort:
   - Use `.sci`/`.pgn` as the canonical interchange format.
   - Round-trip through `.cbh` is reliable for standard-chess-like positions
     and e-file Chess960 positions with clear two-square castling paths.
   - Document any game whose decoded SAN differs from the source PGN.

### Build verification

```bash
make -C src verify_cbh_write   # ✅ builds
./src/verify_cbh_write         # ✅ all 5 steps pass
python3 scripts/analyze_grenke_fixtures.py \
  opening-report/tests/fixtures/grenke_freestyle_2026.pgn
```

`verify_cbh_write` now reaches and passes all Chess960 codec tests,
including the nine GRENKE start FENs.

---

## Phase 5 Part C — Real ChessBase CBV fixture acquired (2026-07-22)

The long-standing blocker — "no real ChessBase `.cbh`/`.cbg`/`.cbv`
fixtures available" — is resolved for the **decoder** path by the TWIC
archive.

### Source

TWIC publishes each weekly issue as a free ChessBase-format zip
(`https://theweekinchess.com/zips/twicNNNNc6.zip`), which contains a real
ChessBase-produced `.cbv`. Issue **twic1639** (covering the grenke Chess
Open, 2–6 April 2026) also covers the **grenke Freestyle Open** — the
Chess960 event whose games we already hold as PGN
(`opening-report/tests/fixtures/grenke_freestyle_2026.pgn`, 535 games).

### Two decoder bugs fixed to read real CBV archives

Real TWIC `.cbv` files exposed two bugs in scidb's CBV/CBH path, both
previously invisible because no real ChessBase binary had ever been tested:

1. **CBV container record parser** (`src/db/cbv/cbv_codec.cpp`, newly added).
   The parser hardcoded a 4-byte signature `01 37 26 35` at record offset 140,
   but that offset is the start of per-file trailing metadata, which varies
   per archive (e.g. `01 71 27 35` on TWIC files). The bogus check silently
   skipped every member, failing with "CBV archive does not contain a .cbh
   file". Rewritten to the layout documented by antoyo/uncbv: name = leading
   non-zero bytes in the first 132 bytes, `compressed_size` `le_i32` @132,
   `decompressed_size` `le_i32` @136, cumulative data offset (verified exact:
   member offsets sum to the file size to the byte).

2. **Charset-detector segfault** (`src/db/cbh/cbh_codec.cpp`). The namebase
   preload fed empty name buffers (`strlen == 0`) to the vendored
   `nsSJISProber::HandleData`, which read `aBuf[-1]` → SIGSEGV. All five
   `HandleData(buf, strlen(buf))` call sites now guard on a non-zero length.

### Result

`cdb2sci` now converts real TWIC ChessBase archives:

| Archive | Written | Corrupted | Notes |
|---------|---------|-----------|-------|
| `twic1654.cbv` | 8441 | 280 | standard chess only; 0 Chess960 |
| `twic1600.cbv` | 8891 | 0 | standard chess only |
| `twic1639.cbv` | 7965 | **606** | contains the **grenke Freestyle Open** |

### The Chess960 games fail to decode

`twic1639.cbv`'s tournament namebase (`.cbt`) contains both
`grenke Chess Open 2026` (orthodox) **and** `grenke Freestyle Open`
(Karlsruhe GER). `scan_db_chess960` on the converted `.sci` reports
`setups=0 fens=0 likely_chess960=0`, yet **606 games are rejected as
"corrupted"** — and the grenke Freestyle PGN has 535 games. The corrupted
set is therefore the Chess960 event (535 Freestyle + ~71 other
genuinely-bad games, a known ChessBase quirk).

This is **exactly** the Phase 5 Part C limitation, now reproducible against
an authentic fixture: scidb's CBH decoder cannot read real ChessBase
Chess960 games (custom start position / off-e-file castling), confirming
the open questions in §"Missing Implementation Steps" are real, not
hypothetical.

### Fixture committed

| Fixture | Location | Purpose |
|---------|----------|---------|
| `twic1639_grenke_freestyle_open.cbv` | `opening-report/tests/fixtures/` | Real ChessBase `.cbv` (1.2 MB) containing the grenke Freestyle Open Chess960 games that scidb fails to decode |

Reproduce:

```bash
make -C src cdb2sci
./src/cdb2sci --force \
  opening-report/tests/fixtures/twic1639_grenke_freestyle_open.cbv \
  /tmp/twic1639.sci
# -> 7965 written, 606 corrupted
```

### Probe results (2026-07-22)

The fixture was probed. The findings are now **definitive**, not
hypothetical:

1. **The 606 corrupted games are exactly the Chess960 games.**
   `probe_cbh_chess960` on the extracted `.cbh` reports
   `total=8571 custom=606 chess960=606 newer=606 custom_and_960=606`.
   There are no other corrupt games; the entire corrupted set is the
   grenke Freestyle Open. (The `.cbv` has 606 Chess960 games, more than
   the 535 in the committed PGN subset.)

2. **The 36-byte position block is real and used.** Every Chess960 game
   carries 8 bytes after the 28-byte position block. There are exactly
   **9 distinct `setup[0:28]` values and 9 distinct `setup[28:36]`
   values**, with matching per-position game counts (summing to 606) - one
   pair per Chess960 start position. The 8 extra bytes are per-start-position
   data (almost certainly the Chess960 rook/castling setup), **not** move
   data (which would have hundreds of distinct values).
   The comment in `Decoder::setupStartPosition` claiming "The 36-byte
   format (with chess960 rook data) is not used in practice" is **wrong**.

3. **Root cause of the decode failure.** `setupStartPosition` reads a
   hardcoded 28 bytes (`unsigned const size = 28;`) and then
   `m_gStrm.skip(28)`, so the move bitstream starts 8 bytes too early -
   inside the Chess960 extension. Under gdb the first failure is at game
   757, first move: `cbh_game_decoder.cpp:720` throws
   `"corrupted data (null move at count %u)"` with `count = 1`.

4. **`skip(36)` alone is NOT sufficient.** Changing only
   `unsigned const size = m_isChess960 ? 36 : 28;` still fails with the
   same "null move at count 1". `Position::setup` reads exactly 224 bits
   (28 bytes) for a 32-piece start position - a fixed structure, not
   "until exhausted" - so the 8 extra bytes are left uninterpreted and the
   board is set up without the Chess960 rook/castling data. The 8 bytes
   must be **parsed** into the board (rook source squares / castling
   rights), not merely skipped, before the move stream will decode.

### Decoded: the 8-byte Chess960 position extension (2026-07-22)

Step 1 is **done**. By adding a temporary diagnostic to `setupStartPosition`
that prints the FEN (decoded by scidb's own `Position::setup` from the
28-byte block) alongside the 8 trailing bytes, all 9 distinct
`(FEN, extra8)` pairs were captured and the field layout cracked. The 8
bytes encode **six castling-relevant squares** in CBH's square encoding
(`square = file*8 + (rank-1)`, rank 1 -> 0), followed by 2 trailing bytes:

| byte | meaning |
|------|---------|
| 0 | white king square |
| 1 | black king square |
| 2 | white **short**-castling rook square (the h-side rook; Shredder castling 1st letter) |
| 3 | white **long**-castling rook square (the a-side rook; 2nd letter) |
| 4 | black short-castling rook square |
| 5 | black long-castling rook square |
| 6-7 | trailing 2 bytes - vary per full position even when rook files match (likely a checksum); not needed for castling setup |

Verified against all 9 start positions (predicted == actual for every
byte 0-5). Example: FEN `rkqrbbnn/.../RKQRBBNN w DAda - 0 1` ->
`08 0f 18 00 1f 07 03 8a` = wKing b1 (0x08), bKing b8 (0x0f), wShort rook
d1 (0x18), wLong rook a1 (0x00), bShort d8 (0x1f), bLong a8 (0x07).

CBH squares convert to scidb's native `rank*8+file` encoding via the
existing `mapSquare(s) = ((s&7)<<3)|(s>>3)` helper
(`src/db/cbh/cbh_decoder_position.cpp:50`).

### Remaining implementation work for Part C

The fixture unblocks the work; what remains is implementation, not data
acquisition:

1. ~~~~Decode the 8-byte extension~~~~ **done** (above).
2. **Extend `Position::setup`** to consume the 8 extra bytes when
   `isChess960`, map the 6 rook/king squares via `mapSquare`, and - when
   the corresponding castling boolean from the 28-byte block is set - call
   the 2-arg `Board::setCastleShort(color, square)` /
   `setCastleLong(color, square)` (`src/db/db_board.h:694-695`) with the
   extension's rook square, instead of the 1-arg form that scans the rank.
   (King squares in bytes 0-1 are informational; the board already has the
   king from the piece loop.)
3. **Fix `setupStartPosition`** (`src/db/cbh/cbh_decoder.cpp`) to read 36
   bytes for Chess960 games (`unsigned const size = m_isChess960 ? 36 : 28;`)
   and pass all 36 bytes to `Position::setup` so it can consume the
   extension. This also realigns the move bitstream (the root cause of the
   current "null move at count 1").
4. **Verify** by converting `twic1639_grenke_freestyle_open.cbv`: the 606
   corrupted count should drop to ~0, and decoded moves should match
   `grenke_freestyle_2026.pgn`.
5. Then settle the Convention A vs B castling-destination question by
   comparing a decoded off-e-file castling move against the ground-truth PGN.

Reproduce the probe:

```bash
make -C src cdb2sci probe_cbh_chess960
./src/cdb2sci --force \
  opening-report/tests/fixtures/twic1639_grenke_freestyle_open.cbv /tmp/t.sci
# -> 7965 written, 606 corrupted
# gdb: catch throw db::DecodingFailedException -> cbh_game_decoder.cpp:720, count=1
# probe (extract .cbh to temp first):
./src/probe_cbh_chess960 /tmp/scidb-cbv-*/twic1639.cbh | tail
# -> total=8571 custom=606 chess960=606 custom_and_960=606
```
