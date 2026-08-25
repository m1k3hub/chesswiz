# 2CBH Format Reverse Engineering — Design for Scidb

**Status:** Index format decoded. Move encoding uses standard LUT with an evolving
count, but the count evolution is a per-game KEYED function that depends on
the 8-byte nonce. The data IS genuinely encrypted (not a LUT swap like
Chess960). Binary RE of CBase26.exe is needed to recover the key derivation.
Fixture: `LumbrasGigaBase_OTB_ELO2400` (863,538 games).

## 1. Context

ChessBase 17 introduced the 2CBH format as the successor to the classic CBH
format (which has existed since ChessBase 6.0, 1996). The ChessBase Corr
Database 2024 (2.2M correspondence games) ships in this format, as do recent
Mega Database editions and the LumbrasGigaBase.

scidb currently has **zero** 2CBH support — `format::fromString()` only
recognises `cbh`, `cbf`, `cbv`, `sci`, `si3`, `si4`, `pgn`.

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
| 0x10 | uint32 LE | 863,794 | **Total record count** (header + games) |
| 0x14–0xBF | — | 0 | Padding |

**Verified:** `863794 × 192 = 165,848,448 = file size` (exact).

### 2.2 Record layout

- **Records 0–255:** Metadata/header records (256 records)
- **Records 256–863,793:** Game records (863,538 games)
- All records are 192 bytes, little-endian fields.

### 2.3 Game record layout (192 bytes)

| Offset | Type | Meaning | Notes |
|--------|------|---------|-------|
| 0x00 | uint64 LE | Marker = `0x0000000001010001` | Constant for all games |
| 0x08 | uint64 LE | **cbgOffset** | Byte offset into `.2cbg` file |
| 0x10 | uint64 LE | **cbaOffset** | Byte offset into `.2cba` file |
| 0x18 | uint64 LE | **whitePlayerId** | Index into `.2lid` namebase |
| 0x20 | uint64 LE | **blackPlayerId** | Index into `.2lid` namebase |
| 0x28 | uint64 LE | **eventId** | Index into `.2lcd` namebase |
| 0x30 | uint64 LE | 2 (constant) | Unknown — possibly database type |
| 0x38 | uint64 LE | 0 | Reserved |
| 0x40 | 16 bytes | `0xFF...FF` | Sentinel |
| 0x50 | uint64 LE | 0 | Reserved |
| 0x58 | uint64 LE | Flags | Varies per game |
| 0x60 | uint64 LE | ? (ECO code?) | Varies |
| 0x68 | uint64 LE | 0 | Reserved |
| 0x70 | uint64 LE | ? | Varies |
| 0x78 | uint64 LE | 0 | Reserved |
| 0x80 | uint64 LE | ? | Varies |
| 0x88 | uint64 LE | Date/round packed | Varies |
| 0x90 | uint64 LE | ? | Varies |
| 0x98 | uint64 LE | ? | Varies |
| 0xA0–0xAF | — | 0 | Padding |
| 0xB0–0xB7 | — | 0 | Padding |
| 0xB8 | uint32 LE | 0 | |
| 0xBC | uint32 LE | ? | Varies |

**Note:** The result code (1-0, 0-1, draw) was NOT found in the .2CBH index
after exhaustive byte/word/dword scans against PGN-verified results for 20
games. The result is likely stored in the encoded `.2cbg` game data, not
the index — unlike classic CBH where it's in the flags word at offset 12.

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

`.2CBH` record N (for N ≥ 1) → `.2CBG` record N-1 (byte offset stored in cbgOffset field).

- `.2CBH` has 863,794 records (0 = header, 1–255 = metadata, 256+ = games)
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

### 3.6 Encoding scheme (DECODED 2026-08-23)

The game data is **NOT encrypted**. XOR analysis proved that games with the
same opening moves produce identical ciphertext, confirming plaintext
encoding. The encoding has been **verified end-to-end for 21 plies** of game 0
against scidb's own classic CBG encoder.

**Model (genuinely encrypted — keyed by nonce):**

The encoding uses the standard LUT (`MoveNumberLookup` at VA `0x141a783c0`)
with an evolving count:

```
raw_p = (InvLUT[lc_p] + count_p) mod 256
count_p = f(count_{p-1}, lc_{p-1}, lc_p, ply, KEY)
```

where KEY is a per-game value derived from the 8-byte nonce. The count
evolution function `f` depends on FIVE inputs: the previous count, the
previous move's lc, the current move's lc, the ply number, and the
per-game key. The key makes the function non-deterministic from the move
sequence alone — the same (count_prev, lc_prev, lc, ply) can produce
different count_p in different games with different nonces.

**Evidence:**
- The LUT-swap hypothesis (like Chess960) was tested and RULED OUT: no
  LUT + constant offset combination decodes all 5 plies of game 0.
- The 4-input model `(count_prev, lc_prev, lc, ply)` has 431 cross-game
  conflicts (same key, different output), proving the function needs a
  5th input (the per-game key/nonce).
- 999/1000 games pass per-game consistency (the key is constant within
  a game), but cross-game conflicts confirm the per-game variation.
- The specific conflict: `(161, 0xad, 0xc0, ply=2)` gives count_p=42 in
  game 4 but 46 in another game, despite identical count_prev and move pair.
  The only difference is the nonce.

**Disproven models:**
- `count_p = count_{p-1} + F(lc_{p-1}, lc_p)` (additive, 2-input): WRONG
- `count_p = 2*count_{p-1} + G(lc_{p-1}, lc_p)` (doubling, 2-input): WRONG
- `count_p = f(count_{p-1}, lc_{p-1}, lc_p)` (3-input, no ply): WRONG
- `count_p = f(count_{p-1}, lc_{p-1}, lc_p, ply)` (4-input): WRONG (431 conflicts)
- LUT swap with count=move_index (like Chess960): RULED OUT

**What IS verified:**
- The LUT is the standard `MoveNumberLookup` (same as classic CBH).
- `raw = InvLUT[lc] + count` mod 256 — this part IS correct.
- Move bytes are contiguous at the start of the move data.
- Games decode correctly when their counts are provided manually.
- The count evolution is keyed by the per-game nonce (genuine encryption).

**What is needed:**
Binary RE of CBase26.exe to recover the key derivation function from
the 8-byte nonce. The nonce-to-key derivation determines how the count
evolves, and without it, the game data cannot be decoded.

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

## 4. .2CBA Annotation Format

Same magic-based record structure as `.2cbg`:
- `magic(8) + dataSize(4) + extraSize(4) + data + extra + trailer(18)`
- Records referenced by `cbaOffset` in `.2cbh` game records.

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

## 6. .2LCD / .2LGD — Tournament Namebase and Index

- `.2lcd`: Tournament/event namebase (3.4 MB)
- `.2lgd`: B-tree index for namebase lookups (106 MB)
- Neither has the `0x1122334455667788` magic
- `.2lgd` contains B-tree nodes with offsets and `0xFFFFFFFF` sentinels

## 7. What scidb CAN do now (index-only support)

Even without decoding game data, scidb could:

1. **Open 2CBH databases** and list games in the game list (player names,
   event names, dates, ECO from the index).
2. **Search by player, event, date** using the namebase indexes.
3. **Show game counts and statistics** from index data alone.

This would be a read-only "browse" mode — clicking a game would show
"game data encoding not yet supported" rather than playing through moves.

## 8. What's blocked

| Capability | Blocker |
|------------|---------|
| Decode game moves | Per-game keyed encryption (nonce-derived key modifies count evolution); needs binary RE of CBase26.exe to recover key derivation |
| Read annotations | Likely same encoding as `.2cbg` (same magic-based records) |
| Write 2CBH | Cannot write without understanding the encoding |
| Read result code | Stored in game data stream, not in index |

## 9. Path forward

1. **Short term:** Implement index-only 2CBH browsing (player/event/date
   listing without move data). This gives users visibility into Corr
   Database and other 2CBH databases they own.

2. **Medium term:** Trace ChessBase 26 binary (CBase26.exe, already extracted
   to `/tmp/cb26_files/CBase26_EXE`, 31 MB PE32+) to find the 2CBG decode
   routine. 36 LUT permutations found at VA `0x141a782c0` (0x100 intervals).
   CBase26 runs under Wine 10.0 and can open the fixture database.
   Dynamic tracing via winedbg is the path to recovering the decode algorithm.
   Key source files: `Cbg1File_cbg.cpp` (VA 0x1401a9220),
   `GPUMove16CB17.cpp` (VA 0x14021a200), `Check2CBH.cpp` (VA 0x140213cf0).

3. **Alternative:** Export 2CBH databases to PGN using ChessBase itself
   (under Wine), then import the PGN into scidb. This is the pragmatic
   workaround for users who need the game data today.

## 10. Comparison with classic CBH

| Feature | Classic CBH | 2CBH |
|---------|-------------|------|
| Index record size | 46 bytes | 192 bytes |
| Field encoding | Big-endian | Little-endian |
| Field size | 4-byte | 8-byte (64-bit) |
| Game data | Plain LUT-encoded | Variable-length encoded (~7-13 B/ply) |
| Magic per record | None | `0x1122334455667788` |
| Name length limits | Fixed (31 chars) | Unlimited |
| Result in index | Yes (flags bits 0-1) | No (in encoded game data) |
| Record count in header | Yes (offset 6) | Yes (offset 0x10) |
