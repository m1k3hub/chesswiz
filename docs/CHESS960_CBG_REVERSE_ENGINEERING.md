# Chess960/Fischer Random CBG Encoding — Reverse Engineering Status

## Problem Statement

Scidb's CBH/CBG decoder can **detect** Chess960 games but **cannot correctly decode** them.
The `isChess960` flag is computed but never used during move decoding. Two specific
failures make Chess960 games unplayable:

1. **Castling** — The decoder hardcodes standard rook positions (a1/h1 for white, a8/h8 for black), which is wrong for Chess960 positions where rooks start on arbitrary files.

2. **Custom starting position** — The decoder reads exactly 28 bytes for the position setup. The comment claims "The 36-byte format (with chess960 rook data) is not used in practice", but this may be incorrect for newer ChessBase versions.

## What We Know

### Game Header Format (First 4 Bytes of CBG Record)

The first `uint32` word of each game in the CBG stream encodes:

| Bits | Mask | Meaning |
|------|------|---------|
| 0-23 | `0x00ffffff` | Total game data size (including these 4 bytes) |
| 25 | `0x02000000` | **Chess960 / Fischer Random variant** |
| 27 | `0x08000000` | **Newer format flag** (possibly annotations/correspondence, possibly Chess960 position data) |
| 30 | `0x40000000` | **Custom starting position present** |
| 31 | `0x80000000` | **Unencoded (plain) data** — not the standard LUT encoding; used for "guiding texts"/training files. NOT encryption (that is the separate `.cbz` DES archive). scidb throws "unencoded game not supported" if set |

**Detection in scidb**: `isChess960 = bool(word & 0x0a000000);`
This checks both bits 25 and 27, meaning either bit being set triggers Chess960 mode.

### Custom Position Format (28 Bytes)

When bit 30 (`0x40000000`) is set, the next 28 bytes encode the starting position:

| Offset (bits) | Size | Meaning |
|-------|------|---------|
| 0-10 | 11 bits | ? (skipped by scidb) |
| 11 | 1 bit | Side to move (0=white, 1=black) |
| 12-15 | 4 bits | En passant file (0=none, 1-8=a-h) |
| 16-19 | 4 bits | ? (skipped) |
| 20 | 1 bit | Black can castle short |
| 21 | 1 bit | Black can castle long |
| 22 | 1 bit | White can castle short |
| 23 | 1 bit | White can castle long |
| 24-31 | 8 bits | Ply number (move number from start) |
| 32-287 | 256 bits | Board position (64 squares × 4 bits: piece type) |

### The Missing 8 Bytes (for Chess960?)

The code comment states: *"The 36-byte format (with chess960 rook data) is not used in practice."*

This is likely **wrong** for ChessBase 16/17. The extra 8 bytes presumably encode:
- Which rook is the "short castling" rook (for Chess960)
- Which rook is the "long castling" rook (for Chess960)

This would allow computing the correct rook positions for castling in Chess960 positions.

### Move Encoding

The move encoding uses a single byte per move (usually), XORed with the move count:

```cpp
unsigned decodedByte = MoveNumberLookup[rawByte - count];
```

This is identical in CBASE16 — the `MoveNumberLookup` table at offset `0x128bd20` in
`CBASE16_EXE` matches the scidb table exactly.

### Castling Encoding (Standard Chess)

| Decoded Value | Move |
|---|---|
| `0x09` | King-side castling (`doCastling(+2)`) |
| `0x0a` | Queen-side castling (`doCastling(-2)`) |

In standard chess, the king moves 2 squares right (short) or 2 squares left (long).
The rook positions are **hardcoded**:

```cpp
// Position::doCastling(Byte offs)
Byte rookFrom = sq::make(isShortCastling ? sq::FyleH : sq::FyleA, rank);  // h1/a1
Byte rookTo   = sq::make(isShortCastling ? sq::FyleF : sq::FyleD, rank);  // f1/d1
```

This is **incorrect for Chess960**, where the king and rook starting positions vary.

### What CBASE16.exe Contains

The ChessBase 16 binary (`CBASE16_EXE`, 23.8 MB) contains:

- **Classes**: `Chess960Position`, `Chess960MoveList`, `Chess960RetractList`
- **Strings**: `V_960_POS`, `V_RANDOM`, `chess960`, `fischerandom`, `UCI_Chess960`
- **RTTI**: Full vtable structures for the Chess960 classes
- **MoveNumberLookup table**: Identical to scidb (at RVA `0x128d520`)

The Chess960Position class likely overrides the position setup and castling logic.

### The `0x80000000` "Not Encoded" Flag

When bit 31 is set, the game data is stored *unencoded* (plain format), not the
standard LUT encoding. ChessBase uses this for "guiding texts" / embedded
training files whose text must be directly readable. It is NOT encryption —
the separate `.cbz` archive is the DES-encrypted (password-gated) format.
Scidb currently throws an exception rather than parsing this plain format.

## Recommended Next Steps

### Step 1: Obtain Chess960 Games in CBH Format

The most productive approach is to get actual Chess960 database files:
- Download a Chess960/Fischer Random database from ChessBase (e.g., the Chess960 database included with some Mega Database editions)
- Or create one in ChessBase 16 by entering Chess960 games and exporting to CBH
- Compare the PGN export with the raw CBG bytes

### Step 2: Compare PGN Export vs Raw CBG Bytes

Using ChessBase 16 to export specific Chess960 games to PGN, then examining the
corresponding CBG bytes:

1. Find a Chess960 game with castling in the database
2. Export it to PGN via ChessBase
3. Read the raw CBG bytes for that game
4. Decode the move bytes manually, comparing against the known PGN moves
5. This reveals exactly how castling is encoded

### New Local Probe

There is now a lightweight raw-file probe for CBH/CBG inspection:

```bash
cd src
make probe_cbh_chess960
./probe_cbh_chess960 /path/to/database.cbh
./probe_cbh_chess960 /path/to/database.cbh 20
```

What it reports:
- per-game CBG header word and decoded flags
- whether bits `0x02000000`, `0x08000000`, `0x40000000`, `0x80000000` are set
- the first 28 bytes after the header for custom-start games
- bytes `28..35` as a separate chunk when at least 36 bytes are available

This is intended to answer two questions quickly:
- do failing Chess960 samples actually carry an extended setup block?
- do the extra 8 bytes vary in ways that correlate with rook/castling layout?

### Step 3: Investigate the 36-Byte Position Format

The position setup code should be modified to check for the 36-byte format:

```cpp
if (word & 0x40000000) {
    unsigned size = 28;
    // If chess960 flag is set, try reading 36 bytes
    if (isChess960) {
        // Check if there are enough bytes for the extended format
        // The extra 8 bytes likely encode rook positions
        if (m_gStrm.remaining() >= 36) {
            size = 36;  // or detect based on word flags
        }
    }
    BitStream bstrm(m_gStrm.data(), size);
    m_position.setup(bstrm, isChess960);  // Pass chess960 flag to setup
    m_gStrm.skip(size);
}
```

### Step 4: Fix Castling for Chess960

In `cbh_decoder_position.cpp`, the `doCastling` function needs to:

1. Read the rook starting positions from the position setup (the extra 8 bytes)
2. Instead of hardcoding `sq::FyleA`/`sq::FyleH`, use the actual rook files from the starting position
3. Determine whether the castling is "short" (O-O) or "long" (O-O-O) based on which rook participates

### Step 5: Investigate the "Not Encoded" Flag (`0x80000000`)

Bit 31 means the game data is stored unencoded (plain format), not the standard
LUT encoding. To parse it, obtain a bit-31 game (e.g. a "guiding text" / training
file) and determine the plain format. This is NOT encryption — the `.cbz` archive
is the DES-encrypted (password-gated) format.

### Step 6: Fix move offset calculation for non-standard positions

Chess960 pawn numbers may not correspond to files a-h in the same way.
The current encoding assumes pawn 0 = a-file pawn, pawn 1 = b-file pawn, etc.
Verify this assumption holds for Chess960 starting positions.

## CBASE16 Binary Analysis

- **File**: `/tmp/CB/CB16_cab/CBASE16_EXE`
- **Size**: 23,814,584 bytes
- **Type**: PE32+ x86-64
- **Image base**: `0x140000000`
- **Sections**: `.text`, `.rdata`, `.data`, `.pdata`, `.rsrc`, `.reloc`
- **MoveNumberLookup table**: at file offset `0x128bd20` (RVA `0x128d520`), 256 bytes, identical to scidb
- **Code references to table**: 3 locations in `.text` section
- **Chess960 classes found**: `Chess960Position`, `Chess960MoveList`, `Chess960RetractList`
- **Key strings**: `V_960_POS`, `V_RANDOM`, `chess960`, `fischerandom`, `UCI_Chess960`

## Files Needing Modification

| File | Change Required |
|------|----------------|
| `src/db/cbh/cbh_codec.cpp` | Pass `isChess960` to position decoder; detect 36-byte format |
| `src/db/cbh/cbh_decoder.cpp` | Use `m_isChess960` in castling decoding; handle unencoded (bit-31) games |
| `src/db/cbh/cbh_decoder.h` | Add `m_rookFiles` or similar to store Chess960 rook positions |
| `src/db/cbh/cbh_decoder_position.cpp` | Fix `doCastling()` for Chess960; parse 36-byte position format |
| `src/db/cbh/cbh_decoder_position.h` | Add members for Chess960 rook positions |
| `src/db/cbh/cbh_game_decoder.cpp` | Same castling fix as decoder.cpp; handle unencoded (bit-31) games |

## Grenke Freestyle Chess Open 2026 — Chess960 PGN Data

Downloaded from: `https://liveserver.chessbase.com:6009/pgn/Grenke-Freestyle-Chess-Open-2026/0/0/all.pgn`

Local copy: `/tmp/CB/grenke_freestyle_2026.pgn`

### Statistics

- **535 games** across 9 rounds of the A-Open
- **8 unique Chess960 starting positions** (one per round)
- **470 games with castling moves** (O-O or O-O-O)
- All games use `[SetUp "1"]` and `[FEN "..."]` tags with Shredder-style Chess960 castling notation

### Chess960 Starting Positions Used

| Round | FEN Position | Castling |
|-------|-------------|----------|
| 1 | `rkqrbbnn/pppppppp/8/8/8/8/PPPPPPPP/RKQRBBNN w DAda - 0 1` | White: D+A, Black: d+a |
| 2 | `rnqnbkrb/pppppppp/8/8/8/8/PPPPPPPP/RNQNBKRB w GAga - 0 1` | White: G+A, Black: g+a |
| 3 | `nnbbrqkr/pppppppp/8/8/8/8/PPPPPPPP/NNBBRQKR w HEhe - 0 1` | White: H+E, Black: h+e |
| 4 | `rnbkqbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBKQBNR w HAha - 0 1` | White: H+A, Black: h+a |
| 5 | `nrbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/NRBQKBNR w HBhb - 0 1` | White: H+B, Black: h+b |
| 6 | `bnrqnkrb/pppppppp/8/8/8/8/PPPPPPPP/BNRQNKRB w GCgc - 0 1` | White: G+C, Black: g+c |
| 7 | `nrbbknqr/pppppppp/8/8/8/8/PPPPPPPP/NRBBKNQR w HBhb - 0 1` | (same castling as round 5) |
| 8 | `nbrqkrbn/pppppppp/8/8/8/8/PPPPPPPP/NBRQKRBN w FCfc - 0 1` | White: F+C, Black: f+c |
| 9 | (likely reuses position from earlier round) |

### PGN Format Notes

The PGN uses standard Shredder-style Chess960 FEN notation:
- `[SetUp "1"]` — marks game as having a custom starting position
- `[FEN "... w DAda - 0 1"]` — the castling field uses file letters (A-H) rather than KQkq
- `DAda` means: White can castle with D-file rook and A-file rook; Black same
- This is the same format that scidb's `Board::toFen(variant::Normal, Board::Shredder)` produces

### How This Relates to CBG Encoding

When ChessBase 16/17 creates a CBV archive containing these games:
1. The game header word will have `0x02000000` (Chess960 flag) set
2. The position setup will likely use the 36-byte format (28 bytes + 8 bytes for rook data)
3. Castling moves (O-O and O-O-O) will use the same move codes `0x09` and `0x0a`
   but with the king moving to the correct destination square for that position

To verify hypothesis #3, we need to:
1. Import these PGN games into ChessBase 16 (using Wine)
2. Export them as CBV
3. Decompress the CBV (we already have the tool for this)
4. Examine the raw CBG bytes for games with castling
5. Compare the binary move encoding against the known PGN moves

This is the next concrete step for reverse-engineering the Chess960 castling encoding.
