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
   extension. **Caveat (tried 2026-07-22):** skipping 36 bytes alone does NOT
   realign the move bitstream - the first move byte at game-stream offset 36
   still decodes to an impossible move (e.g. game 757 byte 0x21 ->
   `MoveNumberLookup[0x21]=0x15` -> `doQueenMove(0, OFFSET(4,0))`, a 4-file
   horizontal queen move that is blocked by pawns in the start position, so
   `doQueenMove` returns a null move -> "null move at count 1"). Sweeping
   skip sizes 28/36/44/48 all leave all 606 games corrupted. So the move
   stream is NOT at a simple byte offset after the 36-byte position block;
   the Chess960 move encoding/alignment needs reverse-engineering by
   matching decoded byte sequences against `grenke_freestyle_2026.pgn`
   move sequences. The 8-byte extension decode (step 1) is still correct and
   verified; only the move-alignment piece is open.
4. **Verify** by converting `twic1639_grenke_freestyle_open.cbv`: the 606
   corrupted count should drop to ~0, and decoded moves should match
   `grenke_freestyle_2026.pgn`.
5. Then settle the Convention A vs B castling-destination question by
   comparing a decoded off-e-file castling move against the ground-truth PGN.

### Move-encoding lead (2026-07-22)

A standalone encoder probe (scidb's `cbh::Encoder` driving a single DAda
game) compared scidb's encoded move bytes against the `.cbv`'s bytes and
found that **ChessBase's Chess960 move encoding uses the SAME
`MoveNumberLookup` as scidb** - the move bytes are not a different
encoding scheme, they are scidb's bytes plus a side-dependent offset:

  - white move 1 (d4): scidb byte `0x0b`, .cbv byte `0x21` = `0x0b + 22`
  - black move 2 (d5): scidb byte `0x0c`, .cbv byte `0xf6` = `0x0c - 22`

i.e. `raw = InverseMoveNumberLookup[logicalCode] + count + (white ? +22 : -22)`
holds for the opening moves. Game 757's first two moves are confirmed `d4 d5`
by the exact +22/-22 match. (An earlier note guessed game 757 was not the PGN's
first game; the namebase-matching tool later confirmed game 757 IS PGN game 1,
Carlsen-Khalafova - see the update below.)

### Move-encoding update (2026-07-22): same logicalCode mapping, evolving count cipher

The `list_cbv_headers` tool confirmed `.cbv` game 757 = PGN game 1
(Carlsen-Khalafova, `1.d4 d5 2.f3 Nf6 3.g4 a5 4.a4 e6 ...`, 55 plies). A
standalone encoder probe (scidb `cbh::Encoder` + `Board::parseMove`) encoded
the full 44-pline prefix (castling `O-O-O` at ply 45 needs the Chess960
variant to parse) and the bytes were diffed against `.cbv` game 757's move
bytes move-by-move.

**Definitive result:** ChessBase's Chess960 move encoding uses the **SAME
`MoveNumberLookup` and the SAME logicalCode->move mapping as scidb**. For
every ply, `MoveNumberLookup[(.cbv_byte - count_i) & 0xff]` decodes to exactly
the PGN move (verified across 44 plies; e.g. ply 0 `0x21-22=0x0b->0x7c->d4`,
ply 2 `0x2a-33=0x09->0x83->f3`). The ONLY difference is the `count`:

  - scidb: `count = move_index` (0, 1, 2, ...).
  - ChessBase: `count` is an **evolving per-move value** with seed 22 for
    this game: 22, 235, 33, 152, 241, 50, 188, 19, 218, 171, 49, 165, 237,
    29, 142, 20, 159, 239, 248, 150, ... .

So this is purely a **count-cipher** problem, not a re-encoding problem:
the decoder just needs to track ChessBase's evolving count instead of the
move index.

**The count-evolution rule is NOT a simple function** of the prior count,
byte, logicalCode, or `InverseMoveNumberLookup[logicalCode]`:
linear-congruential `(a*count + b*byte + c) mod 256` (tested all a,b,c on
the whole game and on white/black sub-streams), running sum, running XOR,
and two-term byte combinations all fail. The seed (22) may be position- or
game-derived (the DAda 8-byte extension's 2 trailing bytes are `03 8a`, not
obviously 22). Cracking the cipher likely needs either the ChessBase binary
(CBASE16) or correlating the count sequence across many games with known
moves (encode each with scidb, derive `count_i = .cbv_byte - Inv[logicalCode_i]`,
search for the evolution rule).

This is the last unknown for the Chess960 CBH decoder: the move->logicalCode
mapping is solved (it is scidb's own), the 8-byte position extension is
decoded, and only the count cipher remains. A diagnostic encoder probe
(`src/probe_encode960.cpp`, untracked) and `list_cbv_headers` (committed)
are the tools to continue this.

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

### Count cipher CRACKED (structure) (2026-07-23)

The count cipher's **structure is now fully determined** by a
multi-game correlational analysis (no binary disassembly needed). The
residual is just recovering the byte-function `H` as a lookup table.

**Model (definitive):** the ChessBase "count" is a 2-byte stream-cipher
state, not a move index and not a simple PRNG.

  - State after move `p`:  `state_p = (count_p, lc_p)`  where `lc_p` is
    move `p`'s logicalCode (scidb's `MoveNumberLookup` mapping, verified
    identical to ChessBase).
  - Transition:  `count_p = H(count_{p-1}, lc_{p-1}, lc_p)`
    i.e. the next count is a fixed byte-function of the previous count,
    the previous move's logicalCode, and the current move's logicalCode.
  - Seed (constant per Chess960 start position, NOT per-game):  `count_0 =
    f(lc_0) = H(S, L_init, lc_0)`  with constant `(S, L_init)` derived from
    the position.  For the DAda start position this gives, e.g.:
    `d4 (lc 0x7c) -> 22`, `e4 (lc 0x80) -> 160`, `0x84 -> 1`, `0x61 -> 210`,
    `0x69 -> 238`, `0x78 -> 197`  (one count0 per distinct first move; the
    seed is the same for every game of the same start position).
  - Encoding (same as scidb, only `count` differs):
    `raw_p = InverseMoveNumberLookup[lc_p] + count_p   (mod 256)`

**Decoder algorithm:** read `raw_p`; the decoder already knows
`(count_{p-1}, lc_{p-1})`. For each *legal* move (whose `lc` it can
compute from the tracked position), candidate `count_p =
H(count_{p-1}, lc_{p-1}, lc)`; accept the move for which
`raw_p == InverseMoveNumberLookup[lc] + count_p`. Then advance state to
`(count_p, lc)`. (This is the same try-each-legal-move loop scidb's
CBH decoder already uses; it just needs ChessBase's `H` instead of
`count = move_index`.)

**How each wrong hypothesis was ruled out (by cross-game correlation):**

  - *Pure PRNG / position-seeded keystream:* REJECTED. Two games from the
    same DAda position playing the same opening `1.d4 d5` share
    `count_0=22, count_1=235` but diverge at ply 2 once the moves differ
    (game 757 `2.f3` -> count2=33; game 758 `2.Bb4` -> count2=213). A
    move-independent keystream would be identical regardless of moves.
  - *`count_p = F(count_{p-1}, raw_p)` (ciphertext feedback):* REJECTED.
    Game 760 ply 20 (`b3`, lc 0x73) and ply 68 (`Bxh7`, lc 0x43) both hit
    `(count=195, raw=0xbc)` but yield different next counts (88 vs 186).
    Same (count, raw) -> different result => the cipher keys on the
    *plaintext* logicalCode, not the raw byte.
  - *`count_p = H(count_{p-1}, lc_p)` (2-input, current move only):*
    REJECTED on the full corpus (224/3339 inconsistencies). It is
    consistent only within small same-round subsets.
  - *`count_p = H(count_{p-1}, lc_{p-1}, lc_p)` (3-input, state =
    (count, prev_lc)):* **ACCEPTED.** Over 64 cleanly-aligned DAda games
    (3805 plies, 3490 distinct 3-input keys) there are only 2
    inconsistencies, both traced to a 2-game insertion that shifts the
    cbv<->PGN alignment around PGN games 14-19 (the `list_cbv_headers`
    player-name pairing, not naive sequential indexing, is needed to
    harvest a fully clean corpus). With proper alignment the model is
    exact.

**Form of `H`:** no simple closed form was found. Exhaustively tested and
rejected: linear `(a*count+b*lc_prev+c*lc+d) mod 256`; XOR/add/sub;
`LUT[...]` and `InvLUT[...]` 1-D table over every combination of the
inputs; rotations/ARX with one and two constants; multiplication; CRC-8
(all 256 polynomials, both shift directions, feeding raw/logicalCode);
nested double-LUT forms `LUT[g(count,lc_prev)] op lc`; and separable
`T(count,lc_prev) op lc`.  `H` is a genuine 3-input byte substitution.

**Recovery status:** 3488 entries of the `H` table and the `count_0=f(lc0)`
seed table (5 opening first-moves) are recovered in
`src/count_cipher_H.json` from the 64 aligned DAda games. To produce a
*general* decoder the remaining work is:
  1. Properly align ALL DAda games via `list_cbv_headers` (player-name
     matching) instead of sequential indexing, to harvest a clean, large
     corpus (~67 games * ~60 plies ~ 4000 samples, plus other start
     positions for their own seed tables).
  2. Recover `H` as a full lookup table (the decoder only ever needs
     entries `(count_{p-1}, lc_{p-1}, lc_p)` that actually arise; a few
     thousand aligned games fill the practically-needed entries, or the
     ChessBase `CBASE16` binary yields the exact 256^3 algorithm).
  3. Recover the per-position seed `(S, L_init)` (equivalently the
     `count_0 = f(lc_0)` table) for each Chess960 start position; this is
     a small 256-entry table per position.
  4. Wire `H` + the seed into `cbh_game_decoder.cpp`'s move loop in place
     of `count = move_index`.

### Universality + alignment (2026-07-23)

Both open structural questions are now settled by bulk correlation over all
10 Chess960 start positions in the fixture (535 PGN games, 8571 cbv games):

**`H` is universal across start positions (strong evidence; pending decoder
validation).** Aligned by player last-name + 36-byte position block
(`list_cbv_headers` for names; FEN per PGN game via `src/probe_encode_many`,
which now reads a FEN per line and emits the 28-byte position block). After
iterative majority-clean (285 clean games = the true PGN<->cbv overlap; the
other 232 PGN games have no cbv counterpart -- they share 1-7 opening plies
by coincidence then diverge), EVERY position has **0 internal
inconsistencies**, and over the 15506 distinct `(count, lc_prev, lc)` keys:
  - **277 keys appear in >=2 start positions** (up to 8 positions sharing one
    key; 52 keys in >=3 positions) -- i.e. real cross-position overlap, not a
    vacuous 0-conflict on disjoint key sets.
  - **0 conflicts among those 277 shared keys (100% agreement).**
Corroboration: on the *raw* (pre-clean) data there were 938 shared keys with
343 cross-position conflicts, and **all 343 vanished** once the 232
misaligned games were dropped (their count trajectories diverged at ply
2-8 -- the classic wrong-game signature), leaving clean cross-position
agreement. Caveat: 277 shared keys is modest, so the **decoder fixture run
(step 3) is the definitive validation**; the claim is "consistent with
universality" until then. The cipher is position-independent to the extent
that the start position only determines which moves are legal (their
logicalCodes); `H0`/`g` themselves carry no position parameter.

Universality statistics are recorded in `src/count_cipher_universal.json`
under `universality_stats`.

### Decoder validation attempt (2026-07-23)

A board-free walk (at each byte, find `count_c` with `(prev_count,
lc_prev, LUT[(raw-count_c)])` in `H0`/`g`) was used to test coverage
without wiring the real decoder:

  - **Model confirmed on the 284 clean games.** Game 757's scidb plies
    0..43 are fully consistent with `H0` (`count_0=g[lc0]=22`, recurrence
    holds for all 44 plies); the 284 clean games have 0 conflicts and `H0`
    covers every non-castling triple arising in them.
  - **Castling is partially covered.** `H0` already contains **281 castling
    entries** (lc 0x09/0x0a) from start positions whose king is on the e-file
    (there scidb `parseMove("O-O"/"O-O-O")` works because the king moves
    exactly 2 squares). For DAda (king on the b-file) `parseMove` returns
    null -- `isCastling()` is false when the Chess960 king moves <2 squares
    (O-O-O = b1->c1) -- so those castlings were never harvested (e.g. game
    757 ply 44 O-O-O: `(193,0x42,0x0a)` is absent from `H0`).
  - **Board-free walk cannot validate the ~321 no-PGN games.** It greedy-
    picks the first candidate at ambiguous moves (291 ambiguous moves total);
    without board legality it mis-resolves, so it *underestimates* coverage
    (only 128/284 clean games match their PGN lc-sequence under greedy; the
    other clean games diverge at an ambiguous move and then gap). The 284
    clean games are nonetheless validated by construction (their triples are
    in `H0`).

**Conclusion:** the count-cipher *structure* is validated (correct on all
284 clean games). A real fixture run (`606 -> ~0`) still needs: (1) the actual
decoder with board-legality disambiguation (the try-each-legal-move loop),
(2) a denser `H0`/`g` (more fixtures or the `CBASE16` binary) so the no-PGN
games' triples are covered, and (3) fixing scidb's Chess960 castling
`parseMove` (king-moves-<2-squares) so DAda-style castlings can be harvested
and decoded. The castling `parseMove` bug is a *pre-existing scidb* issue,
separate from the count cipher itself.

### CBASE16 binary RE + castling root-cause (2026-07-23)

**Binary located.** ChessBase 16 lives in `Update_x64.exe` (NSIS) >
`CBase16.exe` (24 MB, PE32+, x64). Extracted to `/tmp/cb16/update/`.
`MoveNumberLookup` is at file offset `0x12e13c0` -> VA `0x1412e27c0` (.data),
byte-identical to scidb's table; `InverseMoveNumberLookup` at VA
`0x1412e26c0` (immediately before it). Codec init routines (each does
`lea rax,[rip+disp] < MoveNumberLookup/Inverse; mov [obj+0x78],rax;
mov [obj+0x68],0`  i.e. table-ptr at obj+0x78, count at obj+0x68):
  - decoder variants: `0x14086de00`, `0x14086e910`, `0x14086f310`
  - encoder: `0x140870c60` (uses the inverse table)
The per-move count evolution lives in the big jump-table dispatch that
follows each init (`movzx eax,[obj]; and eax,0x3f; ... jmp rcx` via a
handler table at e.g. `0x140000000+0x86f2c8`). The handlers set
`[obj+0x78]` to piece-specific sub-tables per move type. **Extracting the
exact `H0`/`g` algorithm requires per-handler tracing of this state
machine -- coordinates recorded here for resumption; not yet complete.**
Full disassembly cached at `/tmp/cb16.asm` (objdump -d -M intel).

**Negative result (2026-07-23):** the codec routines above are NOT the CBH
Chess960 cipher decoder. Traced the per-move common routines called by the
handlers -- `0x140870680` (2-bytes/move), `0x1408707e0` (1-byte/move),
`0x1408701a0` -- and `0x140870c60` (encoder). All do the lookup as
`lc = MoveNumberLookup[raw - count]` with `count = obj+0x6c`, and **every
write to `obj+0x6c` in the codec region is either `inc` (count++) or a bulk
struct-copy** (grep `mov/add/inc/xor/sub DWORD PTR [(rbx|rcx)+0x6c]` in
0x14086xxxx-0x14087xxxx). So these decoders use `count = move_index`, not
the H0 cipher -- they decode some *other* ChessBase format that shares
`MoveNumberLookup`. The empirical H0 cipher (validated on 284 games, count
*not* a linear function of move_index) must therefore live in a different
code path not yet located: either a pre-decryption layer that rewrites the
raw bytes before this standard decoder runs (so the stored byte
`InvLUT[lc]+H0_count` becomes `InvLUT[lc]+move_index` for the move_index
decoder), or a separate codec module/binary. **Resumption:** (a) find the
pre-decrypt layer by searching for code that reads the stored byte and the
H0-style count and rewrites the stream before the move decoder; (b) or
check the other CBase16 codec entry points / the SView3/SView4 DLLs / the
CBV archive codec for a second `MoveNumberLookup` user with a non-trivial
count evolution. The decoders at `0x14086de00/0x14086e910/0x14086f310` and
encoder `0x140870c60` are ruled OUT for the cipher.

**Crypto layer located (2026-07-23).** CBase16.exe contains a dedicated
crypto subsystem (strings in `.data`): `CBCryptoManager`, `MSCryptoManager`,
`CryptoManager`, `RequestStreamCryptInfoCommand`, `StreamCryptInfoReplyCommand`
(class-name strings at file `0x1323804`/`0x1323854`, VA `0x141324c04`/
`0x141324c54`; RTTI/registration refs at `0x140c489a5`). This is almost
certainly the home of the H0 stream cipher: a **decrypt pass over the .cbg
move buffer before the move_index move decoder reads it** -- which is why the
move decoder can use `inc count` (= move_index) while the stored bytes are
`InvLUT[lc]+H0_count` (decrypt rewrites them to `InvLUT[lc]+move_index`).
scidb's CBV codec is a pure archive extractor (no transform -- confirmed,
`src/db/cbv/cbv_codec.cpp`), so the H0 bytes are genuinely on-disk and the
decrypt must be ChessBase's. **Resumption:** trace `CBCryptoManager`'s
decrypt/stream method from its vtable (RTTI at `0x140c489a5`) to recover
the exact `H0`/`g` algorithm; the per-move `G(count,raw)` feedback
(empirically 203/204 consistent) is the expected shape of the decrypt's
keystream evolution. Note `StreamCryptInfo*` may instead be the
playchess-server stream crypto -- verify the .cbg path actually invokes
`CBCryptoManager` before assuming it.

**Final binary-RE conclusion (2026-07-23): the H0 cipher is NOT in
CBase16.exe.** Traced the full read>decode path: the .cbg game-load
dispatcher `0x1408cacd0` > pre-decode setup `0x1408c4be0` (mallocs a
0xfffe buffer at obj+0xe8, fills it via `0x140c786e0`/`0x140c78440`)>decoder init `0x14086de00`/`0x14086e910`/`0x14086f310` > per-move
routines `0x140870680`/`0x1408707e0`/`0x1408701a0` (variants 1-2) and
`0x14086d710`/`0x14086da30` (variant 3, the compressed path via
decompressor `0x140890370`). (a) Every per-move routine does
`lc = table[raw - obj+0x6c]` and **all writes to `obj+0x6c` are `inc` or a
struct-copy** 4> i.e. `count = move_index`. (b) `0x140c786e0` is a thin
wrapper over IAT imports (`0x140e0e0e8`/`0x140e0de20`, ReadFile-style)
4> it is a plain file read, **no decrypt** of the buffer. So CBase16.exe
would NOT decode the H0 bytes -- meaning this .cbv was produced by a
different encoder (standard ChessBase uses move_index, which is why scidb
decodes the 7359 non-chess960 games fine; the 606 chess960 games use a
non-standard encoder with the H0 cipher). Extracting the exact H0 algorithm
would require disassembling *that* encoder (an older/different ChessBase
build or a third-party CBV writer), not CBase16.12. **The empirical H0
model (validated on 284 clean games) remains the operative description of
this file's encoding** and is the basis for scidb's decoder. Path forward:
build the decoder from the recovered `H0`/`g` tables (not more CBase16
RE), plus fix scidb Chess960 castling legality.

**Castling `parseMove` root cause.** `isCastling()` is just a bit set by
`Move::genCastling`, so the failure is upstream: `Board::prepareMove`
returns empty because `longCastlingIsLegal()` is false at the castling ply
(e.g. game 757 ply 44 O-O-O). `prepareMove`'s Chess960 branch requires
`m_castleRookCurr[queenSide]==to && canCastleLong && longCastlingIsLegal()`.
So the blocker is a scidb **Chess960 long-castling legality** discrepancy
(likely Convention A/B king-path / attacked-square check), a *pre-existing
scidb* bug independent of the count cipher. Fix point:
`Board::longCastlingIsLegal()` (and the short-side twin) in
`src/db/db_board.cpp` around line 2044 for Chess960 positions
(`isChess960Position()`).

**Net status.** The count cipher itself is cracked and validated. The two
remaining items are both substantial and *orthogonal* to the cipher:
  - (binary) finish tracing the CBASE16 dispatch to extract the exact
    `H0`/`g` (eliminates table sparsity -> the path to a general, gap-free
decoder); coordinates above.
  - (scidb) fix Chess960 castling legality so castling moves can be
    harvested into `H0` and decoded.

**The seed `count_0 = g(lc_0)` is also universal.** Merging the per-position
first-move seed tables gives a single `g` with **0 conflicts** across
positions (11 distinct first-move logicalCodes observed so far, each one
count0: e.g. `d4(0x7c)->22`, `e4(0x80)->160`, `0x78->153`, `0x61->210`,
`0x69->238`, `0x73->163`, `0x7b->220`, `0x84->37`, `0x87->1`, `0x09->168`,
`0x60->128`).

**Final model (universal, position-independent):**

```
  count_0 = g(lc_0)                          # universal seed table
  count_p = H0(count_{p-1}, lc_{p-1}, lc_p)  # universal 3-input byte fn
  raw_p   = InverseMoveNumberLookup[lc_p] + count_p   (mod 256)
```

The decoder tries each legal move `lc` (it knows the position, hence each
move's `lc`), computes candidate `count_p = H0(count_{p-1}, lc_{p-1}, lc)`,
and accepts the move where `raw_p == InvLUT[lc] + count_p`. For ply 0 it uses
`count_0 = g(lc)` to disambiguate (or brute-forces the ~20 legal first moves
and keeps the branch that decodes the whole game).

**Artifacts:**
  - `src/count_cipher_universal.json` -- recovered universal `H0` (15506
    entries) and `g` (11 entries), plus the model spec.
  - `src/probe_encode_many.cpp` (+ built binary) -- per-FEN bulk encoder for
    harvesting samples; reads `<FEN>\t<SAN>...` per line, emits
    `POS=<28-byte pos hex> | <scidb move bytes>`.
  - `src/list_cbv_headers` -- cbv game headers (White/Black/Round) for
    PGN<->cbv name alignment.

**Remaining for a working decoder (step 3-4):**
  - `H0` (15506 entries) and `g` (11 entries) are sparse. For a *general*
    decoder, either (a) densify from more aligned data / other fixtures, or
    (b) extract the exact `H0`/`g` algorithms from the `CBASE16` binary (no
    gaps). `g` needs all legal first-move `lc` per position (~20) -- 11 now.
  - Wire `H0`+`g` into `cbh_game_decoder.cpp`; verify on the fixture
    (`606 corrupted -> ~0`, moves match the PGN). Ply 0 can be brute-forced
    if `g[lc]` is unknown.
  - Risk: ~321 of the 606 cbv chess960 games have no PGN counterpart, so
    some of their `(count,lc_prev,lc)` triples may be absent from the
    current `H0`; expect occasional gaps until `H0` is densified or taken
    from the binary.

**Tooling added:** `src/probe_encode_many.cpp` (compiled binary
`src/probe_encode_many`) feeds SAN move-lists from stdin (fixed DAda FEN)
and emits scidb move-bytes per game, for bulk `(cp,lc_prev,lc)->cn`
sample harvesting. Build: see the g++ invocation captured from
`make -n probe_encode960.o` (same flags) then link against
`db/libdb.a mstl/libmstl.a util/libutil.a sys/libsys.a -ltcl8.6 -ltk8.6 -lz`.


---

## Phase 5 Part D — Count cipher decoder wiring (2026-07-25)

The count cipher has been wired into the CBH decoder. The implementation is
structurally complete but the first-match candidate selection needs refinement
(see Remaining below).

### What was implemented

1. **CountCipher class** (`src/db/cbh/cbh_count_cipher.{h,cpp}`):
   - Loads H0 (95340 entries) and g (22 entries) from
     `src/count_cipher_universal.json` at runtime
   - Static singleton (file-scope static in `cbh_decoder.cpp`); loaded once,
     no per-instance overhead
   - Minimal JSON parser (no external dependencies)

2. **36-byte position block** (`Decoder::setupStartPosition`):
   - Detects 36-byte Chess960 position blocks (vs 28-byte standard/scidb)
   - Sets `m_useCipher = true` only for 36-byte blocks (real ChessBase files)
   - Parses the 8-byte extension to override castling rook squares via
     `Board::setCastleShort(color, square)` / `setCastleLong(color, square)`
   - scidb-produced Chess960 files (28-byte) use standard encoding (no cipher)

3. **Cipher-based move decoding** (`Decoder::decodeMove`):
   - Refactored: `decodeMove` determines `lc` + `decodeCount`, then calls
     `dispatchMove` (extracted from the original switch)
   - For cipher mode: tries each candidate lc (0-255), checks
     `LUT[(raw - H0_count) & 0xff] == lc`, accepts first match
   - Cipher state: `m_cipherCount`, `m_lcPrev`, `m_cipherActive` (per-game)
   - Exception handling: catches assertion failures from invalid moves and
     converts to `DecodingFailedException` (game marked corrupted, no crash)

4. **Board API**: `setCastleShort(color, square)` / `setCastleLong(color, square)`
   moved from private to public (needed for Chess960 extension parsing).

5. **Position API**: added non-const `board()` accessor and castling flag
   members (`m_wshrt`, `m_wlong`, `m_bshrt`, `m_blong`) for extension parsing.

### Current results

| Test | Result |
|------|--------|
| `verify_cbh_write` (all 5 steps) | ✅ PASSED (exit 0) |
| `cdb2sci` on twic1639 fixture | ✅ 7970 written, 601 corrupted (5 Chess960 decoded) |
| Standard chess games | ✅ Unaffected |
| scidb-produced Chess960 | ✅ Unaffected (28-byte, standard encoding) |
| Real ChessBase Chess960 | ⚠️ 5/606 decoded; rest fail due to sparse H0 table + ambiguous matches |

### Remaining work

1. **H0 table wrong entries** (root cause): The combined H0 table (100K entries
   from 37 fixtures) has wrong entries from misaligned games in other fixtures.
   These wrong entries crowd out correct entries at the same state. For example,
   state (18, 0x1c) has 7 H0 entries, but NONE match the raw byte — the correct
   lc is not among the 7 because a wrong entry took its place. The twic1639
   re-harvest (606 games, last-name alignment) found 559 disputed keys where
   games disagree. Only 13 involve castling; the rest are from misaligned games
   or encoding differences. Adding twic1639 entries to the combined table makes
   things WORSE (7969 vs 7970) because the wrong entries from other fixtures
   conflict with the correct twic1639 entries.

2. **Deep look-ahead** (implemented, limited impact): The InvLUT fallback now
   does a 20-step H0 look-ahead to disambiguate candidates. The correct
   candidate follows a unique H0 path; wrong candidates diverge quickly.
   But the impact is limited because H0 coverage is only 33%, so the next
   state also likely misses H0.

3. **Solution paths**:
   - Rebuild H0 from scratch: twic1639 first (trusted), then other fixtures
     trimmed against it. This eliminates wrong entries from other fixtures.
   - Extract H0 algorithm from CBASE16 binary (100% coverage, no alignment
     issues). Binary was previously extracted to /tmp/cb16/ but cleaned up.
   - Fix chess960 castling in probe_encode_many to resolve the 13 castling
     disputes and improve harvest quality.

4. **Variation cipher state**: Push/Pop token handling for cipher state
   needs re-adding (save/restore on variation enter/exit).


### Phase 5 Part E — Try-and-see, look-ahead analysis, and table experiments (2026-07-25)

Several decoder improvements and H0 table experiments were tested. All failed to
improve beyond 5/606. Key findings:

1. **330 of 603 games have ALL correct H0 entries in the combined table**, yet
   only 5 decode. The issue is NOT missing entries but **ambiguous matches**
   (numMatches >= 2): the decoder picks the first valid candidate without
   look-ahead, picks wrong, and the cipher state diverges.

2. **Decode stats** (from instrumentation): fast=11770 (81.2%), miss=593 (4.1%),
   ambig=2111 (14.6%). Ambiguous matches are 3.6x more common than H0 misses.

3. **H0 look-ahead on ambiguous matches makes things WORSE** (1/606 vs 5/606).
   Wrong H0 entries from other fixtures bias the look-ahead toward wrong
   candidates — the wrong candidate's cipher state has more (wrong) H0
   coverage, giving a higher look-ahead score.

4. **Try-and-see approach** (full decodeMove look-ahead) also doesn't help: the
   depth-1 fallback fails quickly (score 1-2) because H0 coverage is 33%.

5. **Reducing table size kills coverage**: twic1639-only table (38K) gives 0/606,
   majority-vote table (31K) gives 0/606, filtered table (38K) gives 5/606.
   The combined table's 100K entries are CRITICAL for coverage. The path
   forward is to INCREASE coverage, not reduce it.

6. **H0 is NOT mathematically decomposable**: XOR/ADD of 1-D tables, 2-input
   combinations (a^b, a+b, b^c, etc.) — all have >58% conflict rates. H0 is a
   genuine 3-input byte substitution with no simple closed form.

7. **CBASE16 binary is no longer available** and the status doc concludes the H0
   cipher is NOT in CBase16.exe anyway (it uses count=move_index, not H0).
   The chess960 encoder that uses the H0 cipher is a different code path.

### Path forward (priority order)

1. **Re-acquire CBASE16 binary and extract H0 algorithm** (highest impact):
   The ChessBase 16 binary contains the exact H0/g cipher algorithm.
   Previous RE located the codec routines (VA `0x14086de00/0x14086e910/
   0x14086f310`, encoder `0x140870c60`) but concluded the cipher lives
   in a separate code path. Extracting the algorithm gives 100% H0
   coverage with no alignment or harvesting issues.
   - Binary was at `/tmp/cb16/update/CBase16.exe` (24 MB PE32+ x64)
   - `MoveNumberLookup` at file offset `0x12e13c0` (VA `0x1412e27c0`)
   - `InverseMoveNumberLookup` at VA `0x1412e26c0`
   - Per-move count evolution in jump-table dispatch after codec init

2. **Rebuild H0 from scratch with twic1639 as trusted** (medium impact):
   Re-harvest ALL 37 TWIC fixtures using the improved alignment
   (TWIC PGN with last-name matching), starting with twic1639
   (606 games, best alignment). Other fixtures are trimmed against
   twic1639's entries. This eliminates wrong entries from misaligned
   games in other fixtures.
   - Expected: ~50K entries from twic1639 + ~50K from other fixtures
   - Challenge: 559 disputed keys require resolution

3. **Fix chess960 castling in probe_encode_many** (low impact):
   Only 13/559 disputes involve castling. Fixing the off-e-file
   castling encoding would resolve those 13 disputes but wouldn't
   significantly improve the decode rate.

4. **Try-and-see with backtracking** (research):
   At each H0 miss, try each legal candidate and decode the next
   N moves. Accept the candidate whose subsequent moves all decode
   successfully. This doesn't need H0 but is very expensive (O(N^M)
   where M is the number of H0-miss moves in a game).

## BREAKTHROUGH (2026-07-26): ChessBase 26 IS the H0 encoder — working oracle established

**The H0 cipher is ChessBase 26's own encoder for chess960 games in classic
CBH format.** Proven by round-trip byte comparison:

1. ChessBase 26.8 (extracted from `ChessBase26Setup_x64.msi`, runs under
   Wine 10.0 in unregistered mode, network blocked via LD_PRELOAD guard)
   opens `twic1639_grenke_freestyle_open.cbv` and decodes ALL chess960
   games correctly (verified: game 758 = Carlsen-Khalafova, DAda position,
   incl. `23. O-O-O` — the exact game+castling scidb could not decode).
2. Re-encoding the same game (Append Games of the ChessBase-exported PGN
   into a fresh classic-CBH database) produces a **byte-identical** .cbg
   record (flags `0x4a000062`, 36-byte setup, move stream through `a895`).

**Consequences:**
- TWIC CBV files are written by current ChessBase (not a third-party tool).
- The H0 decoder AND encoder both exist in CBase26.exe. The single
  InvLUT-referencing encoder (`0x140211270`) uses count=move_index, yet the
  on-disk output is H0 — so **H0 is a post-encode / pre-decode byte-stream
  transform** gated by the game-header "newer format" flag `0x08000000`
  (chess960 games carry flags `0x0a000000` = `0x08000000|0x02000000`).
- We now have a **perfect oracle**: craft any PGN -> ChessBase encodes ->
  read .cbg bytes. H0 harvesting with 100% correct alignment (no majority
  voting, no disputed keys), unlimited volume, all 960 positions.

**Environment notes:** Xvfb :99 + xdotool drives the GUI; clipboard via
xclip (Copy Game yields PGN). Unregistered mode allows creating classic
CBH databases and Append Games import. `2CBH` is CB26's new default
format (unchecked what it writes for chess960).

**Next:** bulk-generate random chess960 games across all 960 positions,
import in chunks, harvest H0/g densely, validate decoder on the 606 TWIC
games; then locate the `0x08000000`-gated transform statically and verify
the extracted algorithm against oracle pairs.
