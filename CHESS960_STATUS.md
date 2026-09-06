# Chess960 CBG/CBH Decoding Status — Assessment Report

**Date:** 2025-07-21 (updated 2026-08-16 after Chess960 decode resolution)  
**Scope:** CBH/CBG decoder (`src/db/cbh/`), Board engine, probe tools, test fixtures

---

## Current Capability

**Summary:** Chess960 games are **detected** and the flag is propagated to the
decoder. The `m_isChess960` flag is used to skip the standard-chess-only
`fixBadCastlingRights()` step in `Position::setup()`. The decoder reads the
**36-byte Chess960 position block** (28-byte custom-start format + 8-byte
castling-squares extension) and applies the extension's rook squares with the
2-arg `Board::setCastleShort/Long(color, square)` calls. The decoder and board
engine use **file-based castling destinations** (Convention B): short castling
always places the king on the g-file and the rook on the f-file; long castling
always places the king on the c-file and the rook on the d-file. Real Chess960
move streams are decoded via the **Chess960 lookup table**
(`Chess960MoveNumberLookup[256]`, extracted from CBase26.exe VA `0x141a799c0`)
with the plain move index as the count: `lc = LUT960[raw] - move_index`.
Unencoded games (bit 31) throw a precise exception.

**Bottom line:** The decoder reads real ChessBase `.cbh`/`.cbv` Chess960
archives and decodes the move stream via the Chess960 LUT. On the
`twic1639_grenke_freestyle_open.cbv` fixture the decode rate is **8571 written /
0 corrupted**; all 606 chess960 games are move-exact vs PGN. See
"RESOLVED (2026-08-16)" below for the full write-up. (The earlier
"count cipher" / H0-table framing in the sections below is superseded — it
was the empirical shadow of re-deriving `lc` through the standard LUT.)

**Encoder (2026-08-16):** The CBH encoder now writes ChessBase-compatible
Chess960: a 36-byte position block (28-byte start + 8-byte castling
squares extension), the LUT-960 inverse for move tokens, and `0xeb`
castle/promotion descriptors. `verify_cbh_write` round-trips Chess960 games
end-to-end (castling, off-e-file kings, promotions, GRENKE start FENs).

---

## Conventions

scidb intentionally uses **Convention B** (file-based destinations) for
Chess960 castling:

- **O-O:** king → g-file, rook → f-file.
- **O-O-O:** king → c-file, rook → d-file.

This matches ChessBase behavior and the GRENKE PGN/SAN output. An earlier
sub-agent change to king-relative (Convention A) destinations was reverted.

The CBH move **encoder** now emits Chess960 castling as the `0xeb` descriptor
tokens (`(4,16)` O-O-O white, `(12,48)` O-O white, `(5,215)` O-O-O black,
`(13,247)` O-O black) and promotions as the `0xeb` packing
(`X1=(piece<<4)|(toFile<<1)|color`, `X2=(fromFile<<3)|(color?0xC6:0x01)`),
matching the decoder. The encoder writes a 36-byte position block and uses the
LUT-960 inverse for move tokens, so scidb-produced Chess960 CBH files
round-trip with real ChessBase.

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
| `src/db/cbh/cbh_decoder.cpp` | 1090–1140 | `Decoder::setupStartPosition()` | ✅ Reads 36 bytes for Chess960 (`posSize = m_isChess960 && remaining>=36 ? 36 : 28`); passes the 28-byte part to `Position::setup` and applies the 8-byte extension's rook squares via the 2-arg `Board::setCastleShort/Long` |
| `src/db/cbh/cbh_game_decoder.cpp` | 763–775 | `GameDecoder::startDecoding()` | ✅ Delegates to the shared `setupStartPosition(tags)` |
| `src/db/cbh/cbh_decoder_position.cpp` | 327–430 | `Position::setup(BitStream&)` | ✅ Reads 224 bits (28 bytes); skips `fixBadCastlingRights()` when `isChess960` |

### Castling

| File | Line(s) | Function | Status |
|------|---------|----------|--------|
| `src/db/cbh/cbh_decoder.cpp` | 115–116 | `decodeMove()` | ✅ Maps 0x09→short, 0x0a→long castling |
| `src/db/cbh/cbh_decoder_position.cpp` | 173–201 | `Position::doCastling()` | ✅ Rook *source* via `board.shortCastlingRook()`/`longCastlingRook()`; Convention B file-based destinations (king→g/c, rook→f/d) |
| `src/db/db_board.cpp` | 5587–5637 | `Board::doMove()` (Castle case) | ✅ Convention B file-based destinations; `shortCastlingRook()`/`longCastlingRook()` scan the home rank |
| `src/db/db_board.cpp` | 2573–2625 | `Board::shortCastlingRook()` / `longCastlingRook()` | ✅ Scans for rooks relative to king position on home rank; works for Chess960 |

### `m_isChess960` Usage

| File | Line(s) | Status |
|------|---------|--------|
| `src/db/cbh/cbh_decoder.cpp` | 1106 | ✅ Used in `setupStartPosition` to select 36-byte position size and gate the Chess960 LUT decode (`m_useCipher`) |
| `src/db/cbh/cbh_decoder_position.cpp` | 327 | ✅ Passed to `Position::setup` to skip `fixBadCastlingRights()` |
| `src/db/cbh/cbh_decoder.h` | 61 | ✅ Declared and consumed by the decoder |

### Unencoded (bit 31) Games

| File | Line(s) | Function | Status |
|------|---------|----------|--------|
| `src/db/cbh/cbh_codec.cpp` | 2472–2478 | `Codec::startDecoding()` | ✅ Throws `DecodingFailedException("unencoded game not supported (CBH bit 31 set, offset …)")` when bit 31 is set. Bit 31 = plain (unencoded) data, not the standard LUT encoding; NOT encryption (that is the separate `.cbz` DES archive). |

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

**Note (2026-08-03):** the decoder no longer hardcodes the rook/king
destination squares — it uses Convention B file-based destinations and,
for real Chess960 archives, reads the exact rook squares from the 8-byte
position extension (see "Missing Implementation Steps" below).

---

## Missing Implementation Steps

**Status 2026-08-03: items 1-3 and 5 are DONE.** Item 4 (XOR) is still
blocked. The Chess960 decode gap is **RESOLVED** (2026-08-16) — it was a
256-byte LUT swap, not a count cipher (see "RESOLVED (2026-08-16)" below).

### 1. Use `m_isChess960` to skip `fixBadCastlingRights()` — DONE

In `cbh_decoder_position.cpp`, `Position::setup(BitStream&, bool isChess960)`
skips `board.fixBadCastlingRights()` when `isChess960` is true (previously it
was called when `strm.bitsLeft() == 0`). This is Phase 5 Part A item A4.

### 2. Fix castling rook/king destination squares — DONE

`Position::doCastling()` and `Board::doMove()` (Castle case) now use
Convention B *file-based* destinations: short → king g-file / rook f-file,
long → king c-file / rook d-file. The rook *source* is derived from
`Board::shortCastlingRook()`/`longCastlingRook()` (scans the home rank), and
for real Chess960 archives the decoder additionally reads the exact rook
squares from the 8-byte extension (see item 3).

### 3. Handle the 36-byte position format — DONE

`Decoder::setupStartPosition()` reads 36 bytes for Chess960 (`posSize =
(m_isChess960 && remaining >= 36) ? 36 : 28`), passes the 28-byte part to
`Position::setup`, and applies the 8-byte extension's rook squares (bytes
2-5) via the 2-arg `Board::setCastleShort/Long(color, square)`. Verified
against the ground-truth FENs (see the "Remaining implementation work for
Part C" section).

### 4. Handle unencoded (bit 31) games — still blocked

When bit 31 is set, the game data is stored *unencoded* (plain format), not the
standard LUT encoding. Currently throws a precise exception. The plain format is
unknown without a bit-31 game (e.g. a "guiding text" / training file). This is
NOT encryption — the separate `.cbz` archive is the DES-encrypted (password-gated)
format.

### 5. Remove duplicate `startDecoding()` code — DONE

`GameDecoder::startDecoding()` delegates to the shared `setupStartPosition()`
from the `Decoder` base class; the 36-byte position logic lives in one place.

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

### Done (2026-08-03)

1. **Pass `m_isChess960` to `Position::setup()` and skip
   `fixBadCastlingRights()`** — DONE (`A4` in Phase 5 Part A).
2. **Fix the rook destination in `Position::doCastling()`** to use
   `Board::shortCastlingRook()/longCastlingRook()` with Convention B
   file-based destinations — DONE.
3. **Fix `Board::doMove()` Castle case** for Chess960 file-based
   destinations — DONE (Convention B).
4. **Obtain CBH Chess960 test fixtures** — DONE
   (`twic1639_grenke_freestyle_open.cbv` committed).
5. **Implement 36-byte position format** — DONE (2026-08-03):
   `setupStartPosition` reads 36 bytes and applies the extension.

### Remaining

6. **Handle unencoded (bit 31) games** — blocked on a bit-31 game fixture
   (e.g. a "guiding text" / training file). Bit 31 = plain data, not encryption.
7. **~~Close the H0 count-cipher coverage gap~~** — **RESOLVED (2026-08-16).**
   Chess960 decode is a 256-byte LUT swap, not a count cipher:
   `lc = Chess960MoveNumberLookup[raw] - move_index`. The decoder now uses
   the LUT directly (8571/0 on the fixture).
8. **~~Make the encoder write ChessBase-compatible Chess960~~** — **DONE (2026-08-16).**
   The encoder now writes a 36-byte position block (28-byte start + 8-byte
   castling extension), uses the LUT-960 inverse for move tokens, and emits
   `0xeb` castle/promotion descriptors. `verify_cbh_write` round-trips Chess960
   games end-to-end.

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
| A1 | Precise unencoded-game error | `src/db/cbh/cbh_codec.cpp` | ✅ `"unencoded game not supported (CBH bit 31 set, offset …)"` |
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

| Deliverable | Status |
|-------------|--------|
| 36-byte position format parsing | **Done** (2026-08-03). Field layout decoded; `setupStartPosition` reads 36 bytes and applies the extension's rook squares. Verified against ground-truth FENs. |
| Unencoded (bit 31) format characterization | **Blocked, empirically reconfirmed (2026-09-06)** — scanned every accessible real `.cbh`/`.cbg` pair on this machine (897,878 games total, including the 863,790-game LumbrasGigaBase OTB corpus): 67 bit-31 records found, **100% guiding text** (already handled by `decodeGuidingTextBody`), 0 real games. Per Morphy's cbh-format spec this bit "can also be set for games (very rarely, unknown effect)" — so this doesn't prove it's impossible, only that it hasn't occurred once in ~900k real games here. Bit 31 = plain data, not encryption. |
| Off-e-file castling token encoding | **Partial** — decoder reads real rook squares from the extension and uses Convention B (file-based destinations); the encoder's two-square castling assumption remains a limitation for off-e-file kings |
| H0 table coverage gaps (501 corrupt games) | **RESOLVED** (2026-08-16) — Chess960 decode is a 256-byte LUT swap, not a count cipher; `lc = Chess960MoveNumberLookup[raw] - move_index`. Fixture now 8571/0. |

### Recommended next action

1. **Keep the current Convention B behavior.** Do not switch to
   king-relative (Convention A) destinations; the project already decided
   to stay file-based to match ChessBase output.

2. **The 36-byte position block is implemented and verified.** If real
   ChessBase fixtures become available, run `probe_cbh_chess960` on them to
   confirm the off-e-file castling token encoding (does the encoder emit a
   distinct token, a multi-byte move, or an ordinary king move with implicit
   rook update?) and the unencoded (bit 31) format. As of 2026-09-06, every
   real bit-31 record found across all accessible databases is guiding text
   (see table above) — a real unencoded game (like the developer-noted
   "Big2010, #1964391, Giffard,Nicolas - Castagliola,Marina") has not turned
   up locally.

   **Live experiment attempted (2026-09-06):** drove ChessBase 26 under Wine
   headlessly (Xvfb + xdotool + screenshots) to test the hypothesis that an
   unusual piece count forces the plain-storage fallback. Entered a custom
   position with 8 white queens (`8/8/4k3/8/8/8/8/QQQQKQQQ w - - 0 1`) via
   Position Setup and saved it as a new game into a real ChessBase database
   (`template.cbh`, game #8573). Result: encoded normally
   (`word=0x40000021` — bit 30 set for the custom start position, bit 31
   **not** set, size 0x21). This rules out "excess same-type pieces" as a
   trigger, at least for a position with no actual game moves played.
   The GUI-automation pipeline (Xvfb display, xdotool click/type driving
   the ribbon UI, FEN paste via X clipboard into Position Setup, the
   File>New / Ctrl+N / Save-prompt flow, and window-relative-coordinate
   screenshots) is now proven end-to-end and could be reused to test other
   hypotheses (e.g. an extremely long game hitting `GameInfo::MaxPlyCount`,
   or importing/repairing a corrupted game) in a future session — the
   documented gotcha is that `import -window root` screenshots are in
   absolute screen coordinates while `xdotool --window <id>` expects
   window-relative ones (offset by the window's Y position, 26px in this
   session's WM-less Xvfb setup); mixing the two silently misdirects clicks.

3. **Chess960 decode is resolved** (2026-08-16). The "count cipher" was a
   256-byte LUT swap: `lc = Chess960MoveNumberLookup[raw] - move_index`
   (table at CBase26.exe VA `0x141a799c0`). The decoder now uses the LUT
   directly — 8571/0 on the fixture, 606/606 chess960 games move-exact.
   See "RESOLVED (2026-08-16)" below.

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

**Status 2026-08-03: the 36-byte position block is fully implemented and
verified.** The move-stream alignment issue described in the old caveat below
was resolved by the count cipher (H0 model); the fixture now decodes at
8070/501 (the 501 remaining are H0 table coverage gaps, not 36-byte alignment).

1. **Decode the 8-byte extension** — **done** (above).
2. **Extend `setupStartPosition` to consume the 8 extra bytes** — **done**
   (`src/db/cbh/cbh_decoder.cpp:1090-1140`). When `isChess960 && posSize==36`,
   the extension's rook squares (bytes 2-5) are mapped via `cbhToScidb` and
   applied with the 2-arg `Board::setCastleShort(color, square)` /
   `setCastleLong(color, square)` calls, overriding the 1-arg scan. King
   squares (bytes 0-1) are informational. Verified against the ground-truth
   FEN: for the Carlsen-Khalafova game (`FEN "... DAda ..."`, white king on
   b1), ext[2]=0x18→d1 (white kingside rook), ext[3]=0x00→a1 (white queenside
   rook), ext[4]=0x1f→d8 (black kingside), ext[5]=0x07→a8 (black queenside) —
   all match the Shredder-FEN castling rights.
3. **Fix `setupStartPosition` to read 36 bytes** — **done**. `posSize =
   (m_isChess960 && m_gStrm.remaining() >= 36) ? 36 : 28;`. The 28-byte part
   is passed to `Position::setup(bstrm, isChess960)`; the caller reads the
   extension directly from `m_gStrm.data() + 28`. `m_useCipher` is set when
   `posSize == 36` (real Chess960), which gates the count-cipher decode.
   **Old caveat (2026-07-22, resolved):** skipping 36 bytes alone did not
   realign the move bitstream; that was the count-cipher problem, now solved.
4. **Verify** — **done**: `cdb2sci` on `twic1639_grenke_freestyle_open.cbv`
   yields 8070 written / 501 corrupted (down from 606 corrupted). The
   remaining 501 are H0 table coverage gaps (see the count-cipher sections
   below), not position-block alignment errors.
5. Convention A vs B castling — scidb uses Convention B (file-based
   destinations); the decoder reads the real rook squares from the extension
   and `Board::doCastling`/`Position::doCastling` compute file-based
   destinations, matching ChessBase output.

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

### Synthetic-harvest negative result (2026-08-05)

Attempted to close the coverage gap by synthetically generating DAda-class
opening corpora (plies 10-40) and harvesting H0 entries from scidb's own
encoder output (`scripts/harvest_dada_oracle.py`, via `probe_encode_many`).
FAILED, and the mechanism is now proven:

- `Encoder::encodeMove` (src/db/cbh/cbh_encoder.cpp) writes
  `raw = InvLUT[lc] + move_index`. The H0 cipher is a *separate* byte-stream
transform that exists only inside ChessBase 26.8's encoder (gated by the
game-header "newer format" flag `0x08000000`).
- Chaining counts from scidb's encoded bytes therefore yields
  `count == move_index` at every ply — a tautology. Harvested entries are
  move-index counts mislabeled as H0 counts: noise.
- Verified: 13,938 such entries merged 2026-08-05 gave 0 decode improvement
  (8070/501 unchanged); merge was reverted (`count_cipher_universal.json`
  restored from the pre-dada backup).
- The *only* working oracle is ChessBase 26.8 under Wine (see the 2026-07-26
  BREAKTHROUGH section below): bulk-generate DAda-class games to ply 10-40
  with the fixture's actual first-move distribution, then harvest from those
  .cbg bytes. For the correct TWIC-vs-scidb offset math, follow
  `scripts/harvest_h0_fverified.py`, not harvest_dada_oracle.py.

### Move-accuracy audit + CBV-aligned harvest results (2026-08-05, evening)

A move-level audit (probe_dump_moves + python-chess vs the Grenke PGN)
established the true decode-quality metric: **the 8070/501 "written/corrupted"
counts measure how many games throw DecodingFailedException, NOT correctness.**
Checked three ways (lastname-pair, position+name, position+name+round): the
exact-move-match rate for Chess960 games in the fixture is 0-9 of 85-305
verified — i.e. ~97-100% of written Chess960 games contain wrong moves. Even
games that never hit an H0 table gap decode wrong, because the ambiguity
continuation-walk mis-picks with a sparse table. Standard chess in the same
CBV remains 100% correct (median 83 plies vs PGN).

CBV-aligned harvesting (489 of 534 PGN games matched to CBV games by
lastname+round, vs 59 via the old naive index assumption) was tried with
three strengths:
1. Permissive (derived chain, add-only): +26,919 entries -> 8043/528, WORSE (-27).
   Hidden drift: 93/396 matched games contain variation tokens (Push/Pop)
   that a 1:1 walk misreads, silently poisoning derived counts.
2. Strict all-or-nothing (verified-every-ply): +355 entries from 23 games,
   too conservative to matter.
3. Bracketed (gap entries only between verified neighbor plies): +830 entries,
   8079/492 (+9 written, -24​ lost, +33 gained). Still 0% exact vs PGN.

Conclusion: table-coverage harvesting from this single fixture cannot produce
move-accurate Chess960 decode. The 440K-entry table state is the best
maintained state; further marginal harvests trade regressions for noise.

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

## COUNT CIPHER FULLY REVERSE-ENGINEERED (2026-07-26, afternoon)

### The model (validated end-to-end)

```
count_0  = g(lc0)                                  // 22-entry universal seed
count_p  = H0(count_{p-1}, lc_{p-1}, lc_p, p)      // 4-input function, p = 0-based ply
raw_p    = InvLUT[lc_p] + count_p        (mod 256)
```

- H0 has **439,009 harvested entries** from the CB26 oracle (5760 generated
  games, all 960 positions, byte-exact UCI alignment incl. castling segments
  and underpromotions). Strict true-path walk: **5702/5760 (99.0%)**.
- Adding the ply `p` as 4th input dropped conflicts from 12.5% (3-input) to ~0.

### 0xeb multi-byte moves (~0.3% of plies: promotions AND ordinary moves)

```
b0 = InvLUT[0xeb] + cnt                        // marker (same move-chain count)
b1 = InvLUT[X1] + P1(cnt, X1, p+1),  X1 = (promo-2)<<6 | to     // promo=2 for non-promotions
b2 = InvLUT[X2] + P2(c1, X2, p+2),   X2 = from
```

- P1: 1240 entries, P2: 1342 entries, ~0 conflicts. Separate functions from H0.

### Bracketed moves (~0.03% of plies)

Some moves are encoded `[M, X1..Xk, M]` (k=1..3): the move byte repeated
around k cipher-transparent X bytes (unexplained; not checksums, not
alternative SAN). Decoder recovers via the prev-byte-repeat pattern.

### Game end

- Final Pop token: `InvLUT[0xff] + moveNumber` where moveNumber = plies/2
  (NOT the cipher count).
- Up to 8 unexplained trailing bytes may precede the final Pop (odd counts 1/3/5/7).

### Decoder (src/db/cbh/cbh_decoder.cpp, cbh_count_cipher.cpp)

Fast path (unique H0 candidate) → bracket recovery → ambiguity/miss scored by
a board-aware continuation walk (full `Board::checkMove` legality; margin rule).
Defensive per-game exception catch. Decode rates:
- Oracle corpus: **3273/5760 (57%)** — losses are move+move ambiguity ties.
- TWIC 606 chess960: **~100/606 (16%)** — losses are table-coverage gaps
  (real-game chain states vs synthetic-corpus states).

### Why the table can't generalize; the endgame

H0 is NOT: affine mod 256, XOR-affine (GF(2) per-bit), decomposable into
XOR-of-1D-tables (all >98% error). It is a genuine 4-input nonlinear byte
function, and its count-chain keys are game-specific, so cross-game coverage
is inherently sparse. **Extracting the H0 algorithm from CBase26.exe (the
`0x08000000`-gated byte-stream transform) is the only path to 100%.**
Breakpoints from the previous session: `cbase26+0x20c080/+0x20f170/+0x20fd00`.

### Structural refinement (same day)

The 4-input H0 is additive: **count_p = count_{p-1} + F(lc_{p-1}, lc_p, p)
(mod 256)** with F deterministic at 99.84% (residuals = bracket-game tail
misalignment). The count chain is a running sum of a 3-input increment.
F does not decompose further (not F=A(lcPrev,lc)+B(lc,p), not
F=A(lcPrev)+B(lc)+C(p), not affine/XOR-affine). For the binary RE this means
the encoder likely does `count += F(lcPrev, lc, ply)` per move — one
table lookup + one add; the F table (or its generator) lives in CBase26.exe.

## BINARY RE + DECODER ANALYSIS (2026-07-27)

### Ghidra MCP decompilation of CBase26.exe

Ghidra MCP headless server (v5.0.0) loaded CBase26.exe for decompilation.
Key functions decompiled:

- **0x14020c080** (BP1 decode): Jump-table dispatch on game type (low 6 bits
  of decoder object's first 16-bit word). 24 cases, 22 unique + default.
  Sets MoveNumberLookup at [obj+0x78] in prologue. Cipher flag [obj+0xb6]
  initialized to 0, set to 1 in various cases.

- **0x140210e10** (per-move decode): Reads raw byte, applies cipher based on
  [obj+0xb6]:
  - Flag == 0 (cipher OFF): `lc = MoveNumberLookup[(raw - count) & 0xff]`
  - Flag != 0 (cipher ON): `lc = MoveNumberLookup[raw] - count`
  Where count at [obj+0x6c] is incremented by 1 (move_index) by the calling
  function (0x140210760 / 0x140210bc0).

- **0x140211270** (encoder): Same jump-table structure. Sets InvLUT at
  [obj+0x78]. Different cases use different LUT variant pairs:
  - Case 0: 0x141a782c0 (InvLUT) / 0x141a783c0 (MoveNumberLookup)
  - Case 4: 0x141a78cc0 / 0x141a78dc0
  - Case 8: 0x141a794c0 / 0x141a796c0
  Each case pair is 0x200 apart (256-byte encode table + 256-byte decode table).
  Encoder also uses count=move_index (just `inc` by 1).

- **0x140212450** (per-move encode): Writes `raw = InvLUT[lc] + count` (cipher
  OFF) or `raw = InvLUT[count + lc]` (cipher ON). Tokens (Push/Pop) encoded as
  `InvLUT[0xfe/0xff/0xec] + count`.

### Key finding: decoder count is move_index, not H0

All three decode functions (BP1/BP2/BP3) and the encoder use `count =
move_index` (incremented by 1 per move). There is NO F(lcPrev, lc, ply)
computation in the decode/encode path. This means either:

1. The H0 transform is a SEPARATE byte-stream transform applied between
   file I/O and the decoder (gated by 0x08000000), OR
2. The H0 count artifact arises from a table difference (chess960 uses a
   different LUT variant than standard chess)

### H0 cipher effect on TWIC decoding

Test: disabling the H0 cipher (using move_index for chess960):
- With H0 cipher: **8065 written, 506 corrupted** (100 chess960 games decoded)
- Without H0 cipher: **7965 written, 606 corrupted** (0 chess960 games decoded)
- The H0 cipher helps exactly 100 games and hurts none.
- The 100 helped games have F ≠ 1 for some moves, requiring the H0 table.
- The 506 remaining failures are H0 table coverage gaps.

### F function period discovery

F(lcPrev, lc, ply) has **period ≥ 106 in ply** (100% deterministic at N=112,
99.87% at N=96, max ply in data = 105). This means the F table is finite:
at most 256 × 256 × 128 = 8M entries, but the actual domain is much smaller
(426K harvested entries). The period boundary is between 100 and 112.

### F function structure analysis

- F is NOT additively separable: F(lp,lc,p1) - F(lp,lc,p2) ≠ constant
- F is NOT XOR separable: F(lp,lc,p1) XOR F(lp,lc,p2) ≠ constant
- F does NOT depend on (lp XOR lc) or (lp + lc) alone
- F takes all 256 values with ~uniform distribution (0.4% each)
- At ply=1: 219 unique F values across 461 entries
- Conclusion: F is a genuine 3-input nonlinear byte function

### Lookup table atlas in CBase26.exe

Tables at 0x141a78000+ in .data section, paired 256-byte encode/decode:
```
0x141a782c0: InvLUT (encode, case 0)       ← referenced by encoder 0x1402112da
0x141a783c0: MoveNumberLookup (decode, c0)  ← referenced by decoder 0x14020c11e
0x141a784c0: InvLUT variant (case 1 enc)
0x141a785c0: MoveNumberLookup variant (c1)   ← referenced at 0x14020c2d4
0x141a786c0: (case 2 encode)
0x141a787c0: (case 2 decode)                 ← referenced at 0x14020c68b
...
```
Each game-type case uses its own LUT pair. Chess960 might use a different
case than standard chess, which would explain the "H0 count" as a table
difference rather than a count cipher.

### Next steps

1. **Determine which game-type case chess960 uses** — compare the LUT variant
   for that case with the standard MoveNumberLookup. If they differ, the "H0
   count" is actually `InvLUT_variant[lc] - InvLUT_standard[lc]` (independent
   of move history), which would be much simpler than a 3-input F function.

2. **Verify with oracle PGN** — extract PGN for TWIC game 757 via CBase26,
   encode with scidb (move_index), compare with raw TWIC bytes. If they
   match, the encoding IS move_index (no H0 transform). If they differ, the
   difference reveals the H0 transform.

3. **Search for the 0x08000000-gated transform** — 83 `and eax, 0x08000000`
   instructions found in .text, concentrated in 0x140fbxxxx-0x14110xxxx.
   Decompile functions in this range to find the byte-stream transform.

4. **Dynamic tracing via winedbg** — restart CBase26 under winedbg, set
   breakpoints at per-move decode (0x140210e10), trace count values for a
   chess960 game to verify whether count=move_index or count=H0.

## H0 MODEL VERIFIED + TWIC PGN HARVEST (2026-07-27, evening)

### H0 encoding model confirmed against real TWIC data

Extracted PGN for TWIC game 757 (Carlsen-Khalafova) from CBase26 via clipboard.
Compared scidb-encoded bytes (move_index model) with raw TWIC bytes:

**All 21 moves match the H0 model perfectly:**
```
ply  scidb  twic   diff   lc    mi_cnt  h0_cnt  h0_table  match
  0  0x0b   0x21   0x16   124        0      22    g=22      ✓
  1  0x0c   0xf6   0xea   124        1     235    H0=235    ✓
  2  0x0b   0x2a   0x1f   131        2      33    H0=33     ✓
  ...
```

The formula: `H0_count = (twic_raw - scidb_raw + move_index) & 0xff`
gives the exact H0 count for every move. This **definitively confirms**:
- TWIC bytes are H0-encoded (raw = InvLUT[lc] + H0_count)
- The H0/g table values are correct
- H0_count ≠ move_index for most moves (F ≠ 1)

### TWIC 1639 PGN downloaded

Downloaded from `https://theweekinchess.com/zips/twic1639g.zip` (7.6MB, 17233 games).
Contains all 606 chess960 games with `[Variant "Chess960"]` header.
All 606 games align 1:1 with the CBH database by (White, Black, Round).

### Harvesting attempt: 29K new entries but alignment issues

Harvested 29,578 new H0 entries from TWIC games by comparing scidb-encoded
bytes with raw TWIC bytes. However, adding these entries made decoding WORSE
(533 corrupted vs 506 baseline), indicating some entries are wrong due to
stream misalignment (0xeb multi-byte moves, tokens, castling encoding
differences between scidb and ChessBase).

**Root cause of misalignment:** The scidb encoder and ChessBase may encode
some moves differently (e.g., castling, 0xeb parameter bytes), causing the
byte-by-byte comparison to desynchronize. The harvest_count_cipher.py script
from the previous session handles this properly with a walk-based alignment,
but it needs to be adapted for TWIC games.

### Path forward for H0 table expansion

1. **Fix stream alignment** — adapt harvest_count_cipher.py to use the TWIC
   PGN + raw bytes, with proper handling of 0xeb triples, Push/Pop tokens,
   and castling encoding differences.

2. **Verify each entry** — only accept H0 entries where:
   - The scidb and TWIC streams are perfectly aligned (no skipped bytes)
   - The computed H0_count is consistent with the running sum model
   - The move is legal on the board

3. **Iterative harvesting** — harvest from TWIC, rebuild, test. If decode
   rate improves, the entries are correct. If it degrades, identify and
   remove the problematic entries.

4. **Alternative: targeted oracle generation** — use CBase26 to generate
   synthetic games that specifically produce the missing (count_prev,
   lc_prev, lc, ply) states. This avoids alignment issues but requires
   GUI automation.

### Harvesting alignment challenge (2026-07-27, continued)

Attempted to harvest H0 entries from TWIC PGN + raw CBH bytes for all 606
chess960 games. Three approaches tried:

1. **Byte-by-byte comparison** (29K entries): 27 regressions — wrong entries
   from stream misalignment at variation tokens (Push/Pop).
2. **2-move lookahead** (28K entries): 4 regressions — better but still wrong
   entries passing the weak verification.
3. **Strict F-consistency** (390 entries): 4 regressions — 34K entries
   rejected because F values don't match existing table, confirming the
   alignment is fundamentally broken for most games.

**Root cause:** The scidb encoder produces a main-line-only byte stream
(no variations). The TWIC raw bytes include Push/Pop-delimited variations.
When the streams diverge at a variation, byte-by-byte comparison produces
wrong H0 entries. The search for "expected lc" in the TWIC stream can't
distinguish true matches from false ones (any byte matches any lc with
some H0_count).

**Proper solution:** Use the scidb decoder's internal state to identify
H0 misses. The decoder handles all alignment (tokens, 0xeb, variations).
When it fails at a miss, log (count_prev, lc_prev, ply, raw_byte). Then
use the PGN to determine the correct lc at that ply and compute:
`H0_count = (raw_byte - invLUT[lc]) & 0xff`.

Challenge: the decoder's `count` includes variation moves, so converting
count → main-line ply requires tracking the Push/Pop nesting level. This
can be done by logging the cipher count (which only advances for moves,
not tokens) and matching it to the PGN's main-line ply.

### Alternative approach: targeted oracle generation

Instead of harvesting from TWIC (which has alignment challenges), generate
synthetic games via CBase26 that specifically produce the missing H0 states.
The oracle generates clean games (no variations), so alignment is trivial.
The key is generating games that reach the specific (count_prev, lc_prev,
lc, ply) states that real TWIC games need.

This requires:
1. Identifying the missing states (from the 506 failing games)
2. Generating games that produce those states
3. Harvesting with the proven harvest_count_cipher.py script

### NO_MATCH analysis: exact failure states identified (2026-07-27, late)

Ran decoder with debug to identify the exact (raw_byte, count_prev, lc_prev,
ply) states where the 506 failing games hit "no matching move":

- 472 NO_MATCH errors at 398 unique states
- 322 unique (count_prev, lc_prev, ply) combinations
- 56 states have multiple raw byte values (different games reach the same
  cipher state but with different next moves)
- Failures cluster at ply 3-13 (71 at ply 6, 52 at ply 7, 50 at ply 8)

### Why PGN-based harvesting fails: ply mismatch

The decoder's `ply` (move index) includes variation moves. The PGN only has
main-line moves. When a game has variations before the NO_MATCH point,
the decoder's ply > PGN's main-line ply. This causes the harvest to use
the wrong lc from the PGN, producing wrong H0 entries (1765 conflicts).

The conflict count (1765 vs 286 new entries) confirms the ply mismatch is
systematic — most harvested entries are wrong because they use the wrong
move from the PGN.

### Path forward: oracle generation

The proven approach (harvest_count_cipher.py with synthetic oracle games)
works because:
1. Oracle games have no variations → scidb and CB streams align perfectly
2. The harvest script handles alignment with the walk() function
3. No ply mismatch

To fill the 322 missing states, generate targeted synthetic games via
CBase26 that produce specific (count_prev, lc_prev, ply) states. This
requires finding chess960 positions and move sequences that reach the
target states. The scidb encoder can verify the move sequence produces
the right lc chain before generating with the oracle.

### Decoder-based H0 harvest: +331 entries → 8067/504 (2026-07-28)

Implemented side-table harvesting directly in the decoder: when the
continuation walk resolves a miss and finds a well-separated winner
(bestScore - secondScore ≥ 1), the verified H0 entry is collected.

**Method:**
- `CBH_HARVEST=1` env var enables collection of verified entries
- Entries are (count_prev, lc_prev, lc, ply) → count pairs
- Only new (non-conflicting) entries are merged

**Results (3 bootstrap iterations):**
- Iteration 1: +286 new entries → 8067/504 (+2 games)
- Iteration 2: +44 new entries → 8067/504 (no change)
- Iteration 3: +1 new entry → converged

**Conflict analysis:** 97 harvested entries conflict with the existing
table. F-value differences are completely random (not systematic),
confirming the conflicts are wrong candidates picked by the walk, not
a systematic difference in the H0 model. Table values are trusted.

**Miss limit:** Raising from 12 to 999 had no effect — all 504 failures
are "no matching move" (well-separated check fails), not "too many misses".

**Remaining 504 failures** all fail at the continuation walk tie check
(bestScore - secondScore < 1), where no candidate has H0-consistent
continuation. These require H0 entries that can only be obtained from
oracle generation or binary RE of the CBase26 transform function.

### PGN alignment harvest: +945 entries → 8070/501 (+5 games) (2026-07-28)

Implemented loose-verification TWIC PGN harvest: walk game-by-game,
predicting exact raw bytes at known-F moves (anchors), extracting H0
counts at unknown-F moves via raw byte search. Key realization: the FEN
must not use Shredder-FEN castling format ("DAda") — use standard "KQkq"
for scidb's probe_encode960.

**Method:**
- For each move: if F known → predict exact byte and search stream
- If F unknown → search stream for byte b where LUT[(b-cc)&0xff]==lc
- Extract cc=(b-InvLUT[lc])&0xff as the H0 count
- Verify via next known-F anchor (implicit chain verification)

**Results:**
- +945 new H0 entries (0 conflicts in 605 games, 1 in first pass)
- 8070 written (+5 vs baseline), 501 corrupted (-5)
- Converged after 1 iteration (subsequent iterations yield 0 new entries)

**Coverage:** H0 table now 440,295 entries. Remaining 501 corrupt games
fail at specific (count_prev, lc_prev, ply) states that no TWIC game
covers in a decodable prefix. Oracle generation needed for those.

## GATE-TRANSFORM DECOMPILE (2026-08-16, deepsek/ghidra)

Full Ghidra 12.0.4 headless auto-analysis of CBase26.exe (823 s) + targeted
decompile of all 77 `and eax,0x08000000` sites and the 4 known decode/encode/
dispatch functions. Dump: `/tmp/ghidra_cb26/decompile_gate.log` (81 functions).

**Decisive result: the `0x08000000`-gated region is a dead end for the H0
transform.** All 77 `and eax,0x08000000` sites are trivial flag-clearing
destructors:

```c
if ((*(uint *)(obj + OFF) & 0x8000000) != 0) {
  *(uint *)(obj + OFF) &= 0xf7ffffff;      // clear bit 27
  SString::~SString((SString *)(obj + STR_OFF));  // free optional field
}
```

`0x08000000` (bit 27) is a "field-is-present / newer-format" flag; the 77 sites
are the destructors that free the associated optional field. None reads/writes a
byte stream or touches the LUT atlas / count field. This **contradicts** the prior
hypothesis that the H0 transform is "a separate byte-stream transform gated by
0x08000000" — the gate sites are destructors, not a transform.

**Count is move_index, not H0.** Byte-pattern scan of `.text` for writes to
`[reg+0x6c]` (the count field): 18 `inc [reg+0x6c]` (all in decode/encode region,
each a plain increment-by-1), 0 `add [reg+0x6c], F(...)`, 0 `sub`. Confirmed in the
decode calling function `FUN_140210bc0` (`inc dword ptr [rbx+0x6c]` at 0x140210c77)
and the per-move decode `FUN_140210e10` / encode `FUN_140212450`. There is **no**
`count = count_prev + F(lc_prev, lc, ply)` computation anywhere in the decode/encode
path or the gate region.

**The cipher flag `[obj+0xb6]` is a LUT-application mode, not H0:**
- cipher OFF: `lc = LUT[(raw - count) & 0xff]`  (count subtracted before lookup)
- cipher ON:  `lc = LUT[raw] - count`           (count subtracted after lookup)

This is a different way of applying the move_index count, not the H0 count cipher.

**Open discrepancy:** the per-move encoder `FUN_140212450` (cipher ON) emits
`raw = InvLUT[count + lc]` with `count = move_index`, which is **not** scidb's
verified `raw = InvLUT[lc] + H0_count`. So the H0 transform is applied either
before/after the per-move encoder (a separate pass not yet located), or by a
different component, or gated by a different flag (e.g. chess960 `0x02000000`,
not `0x08000000`).

**Next step:** locate the byte-stream transform by a different signal — functions
that loop over a byte buffer AND reference the LUT atlas `0x141a78xxx` AND maintain
a running byte accumulator, or are gated by `0x02000000` (chess960) rather than
`0x08000000`. The `0x08000000`-gated region is now ruled out.

## DYNAMIC TRACE: THE H0 CIPHER IS A LUT SWAP — SOLVED (2026-08-16)

gdb trace of live CBase26.exe (sandbox wineprefix, pid attached, base 0x140000000,
no ASLR) at FUN_14020c080 (dispatch) / /+0x116 (seed) / FUN_140210e10 (per-move
decode) while opening Grenke Freestyle games from `/tmp/all.cbh` (535-game oracle):

- DISPATCH: `type_word=0x4a` → **case 10**, cipher flag set to 1 in the case body.
- SEED: `count_init = 0`. Per-move: **`count = move_index` (increments +1 per
  move)** — NO history-dependent count chain exists in live decode.
- Decode LUT selected for chess960: **`0x141a799c0`** (NOT the standard
  `0x141a783c0`). Decode formula (cipher-ON branch of FUN_140210e10):
  `lc = LUT960[raw] - move_index (mod 256)`.
- Encode pair `0x141a798c0` verified to be exactly InvLUT of the decode table.

Offline replay validation (`lc = LUT960[raw] - mi`):
- Oracle `/tmp/all.cbh`: 534/534 games structurally clean, exactly one 0xff
  terminator each, 804 0xeb-triple moves.
- **Real TWIC corpus** (extracted `twic1639.cbh` from the
  `twic1639_grenke_freestyle_open.cbv` fixture with a Python port of
  `cbv_codec.cpp`): **606/606 chess960 games decode to clean streams, single
  0xff terminator each**, 896 0xeb moves. Game 757 lc stream begins
  `124,124,131,...` — byte-exact vs the hand-verified table above.

**Consequence (rewrites the count-cipher sections below):** the chess960 H0/F
"count cipher" documented in this file is an *empirical shadow* of the LUT-960
decode. The harvested `H0(count_prev, lc_prev, lc, ply) -> count` table is what
`count = raw - InvLUT_std[lc]` computes when `lc` was genuinely produced by
`LUT960[raw]-mi`; its sparse 4-input structure falls out of re-deriving lc
through the wrong (standard) table. There is no F algorithm to extract from the
binary beyond the 256-byte LUT at 0x141a799c0.

**Engineering follow-up (decoder fix):** for `isChess960 | 0x02000000` games,
decode with Chess960_MoveNumberLookup + count=move_index instead of the H0
table path. Expected: 8070/501 → ~8571/0 on the fixture (castling legality
bug at db_board.cpp:2044 then becomes the only chess960 decoder-side defect).
Extracted tables: `/tmp/chess960_lut.h` (decode LUT + InvLUT), hex dump
`/tmp/chess960.lut`. Trace script: `/tmp/trace_cbase26.gdb`; raw capture:
`/tmp/trace_hits.log`. Ghidra re-import project: `/tmp/ghidra_cb26/CB26`;
gate-region decompiles: `/tmp/ghidra_cb26/decompile_gate.log` (deepsek — its
"no 0x08000000 transform in codec" negative is consistent: the codec gates on
the game-type word, not the header bit; the 0x08000000 sites are unrelated
flag-masking).

  *Validation tightened (2026-08-16, post-watchdog): re-ran with real
  assertions — both corpora: 100% 0xff termination, 0 0xeb-overrun errors,
  and ZERO mid-stream tokens >= 0xec in all 1140 games (the fixture's
  chess960 games contain no variations, so Push/Pop never appears).*

## RESOLVED (2026-08-16): Chess960 decode is a LUT swap, not a count cipher

**Final state: 8571/8571 games decode (0 corrupted); 606/606 chess960 games
move-exact vs PGN (0 wrong moves).** The only remaining difference is scidb's
SAN output omitting the `+`/`#` check/mate suffix (cosmetic, pre-existing,
unrelated to decode).

### The model

ChessBase 26 decodes Chess960 games (game-type word `0x4a`, dispatch case 10)
with a dedicated 256-byte lookup table and the plain move index as the count:

```
lc = Chess960MoveNumberLookup[raw] - move_index   (mod 256)
```

- Decode LUT: CBase26.exe VA `0x141a799c0` (extracted to
  `Chess960MoveNumberLookup[256]` in `src/db/cbh/cbh_decoder.cpp`).
- Encode LUT: VA `0x141a798c0`, verified to be the exact inverse.
- The standard `MoveNumberLookup` (VA `0x141a783c0`) is *not* used for
  chess960; every other 256-byte permutation in the binary differs from it in
  ~150–170 of 256 positions (essentially random), so no variant is a
  constant-shift of the standard table.

The previously harvested H0/F "count cipher" (440,295 entries in
`src/count_cipher_universal.json`) is the *empirical shadow* of this decode:
`count = raw - InvLUT_std[lc]` computed when `lc` was genuinely produced by
`LUT960[raw] - mi`. Its sparse 4-input structure falls out of re-deriving `lc`
through the wrong (standard) table. There is no F algorithm in the binary
beyond the 256-byte LUT.

### The 0xeb special move (castling / promotion)

In chess960, `0xeb` is used *only* for castling (872/896 corpus occurrences)
and promotions (24/896). The two parameter bytes decode with the same LUT and
the same count as the marker byte (`FUN_140212eb0`):

```
X1 = Chess960MoveNumberLookup[b1] - count
X2 = Chess960MoveNumberLookup[b2] - count
```

- **Castling** — `(X1,X2)` is one of four fixed descriptors:
  `(4,16)` O-O-O white, `(12,48)` O-O white, `(5,215)` O-O-O black,
  `(13,247)` O-O black. Destinations are fixed (Convention B: king→g/c,
  rook→f/d); the rook source comes from the position.
- **Promotion** — `X1 = (piece<<4) | (toFile<<1) | color`,
  `X2 = (fromFile<<3) | (color ? 0xC6 : 0x01)`, where `color` is 1=white/0=black
  and the piece nibble is 0=Q, 1=R, 2=B, 3=N. Squares are CBH-numbered
  (`file*8 + rank-1`), matching `doMove()`'s `mapSquare()`.

### Piece-tracking bugs fixed (the last 155 failures)

scidb's `Position` maintains a hand-mirrored `pieces[]`/`pieceCount[]` table
(separate from the `Board`) used only to resolve `lc` tokens to specific
pieces. Three bugs in the `0xeb` path corrupted it:

1. **`doCastling` king piece-walk** — `doMove(piece::King, 0, offs, ...)`
   computed `to = from + offs`, which for an off-e-file king lands on the
   rook's square and clobbered `pieceCount[rookFrom]` (→0), selecting the
   wrong rook. Fixed by reading the king square directly.
2. **`doCastling` swap case** — when king and rook are adjacent
   (king f1/g1, rook g1/f1), `kingTo == rookFrom`, so the
   `pieceCount[kingTo] = 0` write clobbered `pieceCount[rookFrom]` again.
   Fixed by reading `rookNum` before any `pieceCount` write.
3. **Promotion square numbering** — from/to were emitted in scidb square
   numbering but `doMove()` applies `mapSquare()` expecting CBH numbering.
   Fixed by emitting CBH-numbered squares.

### Encoder (2026-08-16)

The write side is now the exact inverse of the decode model, so scidb-produced
Chess960 CBH files round-trip with real ChessBase:

- 36-byte position block (28-byte start + 8-byte castling extension with
  king/rook squares in CBH `file*8+rank` numbering).
- Move tokens via the LUT-960 inverse: `raw = InvLUT960[lc + move_index]`.
- `0xeb` castling descriptors and promotion packing (see above).
- `0x0a000000` game flag; the `notDerivableFromChess960()` rejection removed.

`verify_cbh_write` passes all steps (round-trip + Chess960 castling/promotion
codec checks).

### Commits

- `e069f30` feat(chess960): decode via ChessBase LUT-960 + move_index
- `9656b35` fix(chess960): complete decode — 8571/0 on fixture
- `2f6149f` chore(chess960): remove debug instrumentation
- `0f2e912` feat(chess960): make CBH encoder write ChessBase-compatible Chess960

### Artifacts

- `src/db/cbh/cbh_decoder.cpp` — `Chess960MoveNumberLookup[256]` + the
  direct decode + `0xeb` castle/promo handling.
- `src/db/cbh/cbh_decoder_position.cpp` — `doCastling` piece-tracking fix.
- `/tmp/chess960_lut.h`, `/tmp/chess960.lut` — extracted tables (hex).
- `/tmp/trace_cbase26.gdb`, `/tmp/trace_hits.log` — live-trace script/capture.
- `/tmp/ghidra_cb26/CB26` — re-imported Ghidra project;
  `/tmp/ghidra_cb26/decompile_gate.log` — gate-region decompiles.
