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

The §3.6 empirical model ("standard LUT + evolving keyed count") is a
**partial shadow** of the real codec, analogous to the H0-count shadow
in the Chess960 effort. The real 2CBH path is:

1. `move` → 16-bit code via `FUN_14021a020` (the `s_nIndex` table).
2. The 16-bit code (2 bytes) is written to the `.2cbg` data field.
3. A byte-stream cipher (reusing the LUT-atlas + count machinery in
   `0x14020xxxx`) scrambles the bytes, with the **count evolution keyed
   by the 8-byte nonce**.

Step 3's key-derivation + count-update function has **not yet** been
located statically. The 2CBG record writer `FUN_1401c42d0` and the
validators only touch the plain header; the cipher must be applied by a
function reached from the game-data reader that consumes the nonce. The
classic `FUN_14020c080` dispatch and `FUN_140210e10` per-move decode use
`count = move_index` (plain increment), so the 2CBH keyed-count path is a
**different** callee selected by the 2CBH game-type word.

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

### 3.7.7 Next step (decisive)

The remaining unknown is the **nonce → key → count-evolution** function.
Two routes:

1. **Static:** find the function that reads the 8-byte nonce at game-data
   offset 0 (the first `FUN_140f42780`/read of size 8 after the record
   header) and trace where the value feeds a per-move count update that
   also references the LUT atlas. Likely a callee of the 2CBH game-data
   reader distinct from `FUN_14020c080` (selected by the 2CBH game-type
   word in the sub-header). Search: xrefs to the LUT atlas that are NOT
   `FUN_14020c080`/`14020f170`/`14020fd00`, plus functions reading an
   8-byte value then seeding an LCG/PRNG.
2. **Dynamic (recommended, per §9):** winedbg trace of live CBase26
   opening a 2CBH fixture, breakpoint the Move16 encode `FUN_14021a020`
   and the byte-stream cipher, capture (nonce, count_prev, lc_prev, lc,
   ply → count_p) for one known game to recover the keyed count function
   empirically — the same approach that solved Chess960.

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

### 6.1 Refined findings (2026-08-26)

- `.2lgd` header (little-endian): `0x00` = page size `0x100` (256),
  `0x04` = entry count `0x328d6` (207,062 players).
- `.2lgd` is a **B-tree of player IDs in sorted order**. A leaf node holds
  consecutive player IDs as 8-byte entries with the ID in the **high 32
  bits** and `0` in the low 32 bits (e.g. `… 388, 389, 390, 391, 392 …` at
  `0xb118`+). The low-32-bit field (the `.2lid` offset) is **not yet
  located** — it is not in the leaf entries examined so far.
- **Open question:** where the `.2lid` byte offset for a given player ID is
  stored. The offset `0xb8` (Balashov) appears in `.2lgd` at `0x5d4c`,
  `0x5f4c`, `0x614c`… (spaced `0x200` apart), suggesting a separate
  parallel offset array or a second B-tree level. This is the remaining
  blocker for resolving player/event names in index-only browsing.

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
| Decode game moves | Per-game keyed byte-stream cipher: 16-bit Move16 codes (`s_nIndex` @ `0x141b57110`, encoder `FUN_14021a020`) are written to `.2cbg` then scrambled by a nonce-keyed count evolution reusing the LUT atlas. The nonce→key→count function is **not yet located statically** (see §3.7.7). |
| Read annotations | Likely same encoding as `.2cbg` (same magic-based records) |
| Write 2CBH | Cannot write without the nonce-keyed cipher (and producing a valid nonce) |
| Read result code | Stored in game data stream, not in index |

## 9. Path forward

1. **Short term:** Implement index-only 2CBH browsing (player/event/date
   listing without move data). This gives users visibility into Corr
   Database and other 2CBH databases they own. The index/namebase layout
   (§2, §5, §6) is fully decoded.

2. **Medium term — static RE (in progress, §3.7):** the move layer is
   solved (`FUN_14021a020` encode, `s_nIndex` table). Remaining: locate the
   nonce-keyed count-evolution function — a byte-stream cipher callee that
   reads the 8-byte nonce at game-data offset 0 and feeds an LCG/PRNG that
   advances the count per move. Search: xrefs to the LUT atlas
   `0x141a783c0` that are NOT `FUN_14020c080`/`14020f170`/`14020fd00`,
   plus functions reading 8 bytes then seeding a state. Decompile scripts
   in `docs/ghidra_2cbh/` (PyGhidra).

3. **Medium term — dynamic RE (decisive):** winedbg trace of live CBase26
   opening a 2CBH fixture. Breakpoint `FUN_14021a020` (encode) and the
   byte-stream cipher; capture `(nonce, count_prev, lc_prev, lc, ply →
   count_p)` for one known game to recover the keyed count function
   empirically — the same approach that solved Chess960 (see
   `CHESS960_STATUS.md` "DYNAMIC TRACE"). CBase26 runs under Wine 10.0;
   fixture `LumbrasGigaBase_OTB_ELO2400` opens fine; binary extracted to
   `/tmp/cb26_files/CBase26_EXE` (31 MB PE32+), Ghidra project
   `/home/michael-g-thomas/ghidra_projects/CBase26`.

4. **Alternative:** Export 2CBH databases to PGN using ChessBase itself
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
