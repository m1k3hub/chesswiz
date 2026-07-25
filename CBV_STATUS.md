# CBV Archive Format Support — Status Assessment

## Current Capability

**Scidb can open and read .cbv archives.** The implementation is fully
integrated into the database codec framework:

- `cbv::Codec` (in `src/db/cbv/cbv_codec.cpp`) handles archive extraction,
  decompression, and delegation to the CBH codec for game parsing.
- `format::ChessBaseArchive` (bit 7, value `1 << 7`) is registered in
  `db_common.h` / `db_common.cpp` for `.cbv` extension detection.
- `db_database_codec.cpp` creates a `cbv::Codec` instance when the format
  is `ChessBaseArchive`.
- `cdb2sci` (the headless converter) accepts `.cbv` files and converts
  them to `.sci` format.
- `app_application.cpp` handles `ChessBaseArchive` in its reopen/recode
  logic, so the GUI can open CBV files.

The codec works by:
1. Reading the 8-byte archive header (header size, entry count, entry
   record size, version).
2. Reading directory entries (173 bytes each) to find sub-file names
   and data offsets/sizes via the 33-byte entry footer.
3. Decompressing each sub-file block-by-block using Huffman and/or LZ77
   decompression into a temporary directory (`/tmp/scidb-cbv-XXXXXX/`).
4. Finding the `.cbh` file among the extracted sub-files and delegating
   to `cbh::Codec` for game data parsing.
5. Cleaning up the temporary directory on close.

**Cannot write .cbv archives** — `isWritable()` returns false.

## Files / Functions Involved

| File | Role |
|------|------|
| `src/db/cbv/cbv_codec.h` | `cbv::Codec` class declaration (96 lines) |
| `src/db/cbv/cbv_codec.cpp` | Full implementation: header parsing, directory entry parsing, Huffman + LZ77 decompression, block extraction, archive extraction, CBH delegation, temp dir cleanup (824 lines) |
| `src/db/db_common.h` | `format::ChessBaseArchive = 1 << 7` |
| `src/db/db_common.cpp` | Extension → format mapping for `.cbv` |
| `src/db/db_database_codec.cpp` | Codec factory: creates `cbv::Codec` for `ChessBaseArchive` format |
| `src/db/cbh/cbh_codec.h` | Forward declares `cbv::Codec` as friend |
| `src/cdb2sci.cpp` | Headless converter accepts `.cbv` input |
| `src/app/app_application.cpp` | GUI reopen/recode for `ChessBaseArchive` |
| `src/scan_db_chess960.cpp` | Chess960 scanner (works with any format including CBV) |

### Key internal functions in `cbv_codec.cpp`:

| Function | Purpose |
|----------|---------|
| `extractCBV()` | Main extraction: reads header, iterates directory entries, decompresses blocks, writes to temp dir |
| `extractBlock()` | Decompresses a single block: reads compression flag, dispatches to Huffman/LZ77/raw |
| `decodeHuffman()` | Builds Huffman tree from bit-stream code table, decodes encoded data |
| `decompressLZ77()` | ChessBase LZ77 scheme: 16-bit code masks, RLE, long RLE, back-references |
| `buildHuffmanTree()` | Constructs Huffman tree from 256 (bit_length, code) entries |
| `Codec::doOpen()` | Creates temp dir, calls `extractCBV()`, opens inner `cbh::Codec` |
| `Codec::isCBV()` | Quick magic-number check (header validation) |
| `Codec::getAttributes()` | Extracts archive to temp dir, delegates to `cbh::Codec::getAttributes` |

## Comparison Against CBV_FORMAT_SPECIFICATION.md

### Implemented and matching spec:

- ✅ **Archive header parsing** (8 bytes: header size, entry count, entry record size, version)
- ✅ **Directory entry iteration** (173-byte entries starting at offset 8)
- ✅ **Entry footer magic check** (`01 37 26 35` at footer offset 0)
- ✅ **Block format** (4-byte header: block_size + unknown, then block data)
- ✅ **Compression flag dispatch** (0x00 raw, 0x01 LZ77, 0x02 Huffman, 0x03 Huffman+LZ77)
- ✅ **Huffman tree construction** (256 entries, 4-bit code lengths, variable-length codes)
- ✅ **LZ77 RLE / long RLE / back-reference** decoding
- ✅ **CBH delegation** (finds `.cbh` among extracted files, opens with `cbh::Codec`)
- ✅ **Temp directory management** (mkdtemp, cleanup on close)

### Discrepancies between code and spec:

These may be spec errors, code errors, or format-version differences.
Without binary test fixtures, it is impossible to determine which is
correct. The code claims to be based on "reverse engineering and antoyo's
uncbv Rust tool," suggesting the code may be more accurate than the spec.

1. **Entry footer field offsets** — Spec says data offset at footer+7
   (4 bytes magic + 3 bytes type ID); code reads at footer+9 (4 bytes
   magic + 5 bytes skipped). Either the type ID is 5 bytes (not 3), or
   the code has a 2-byte offset error. The expanded size at footer+23
   (spec) / footer+25 (code) is not read by the code at all.

2. **Huffman block field order** — Spec says: code table (1024 bytes)
   → decompressed size (u16) → bit stream. Code reads: decompressed
   size (u16) → code table (bit-by-bit) → bit stream. The order is
   reversed.

3. **Huffman code table encoding** — Spec says 1024 bytes = 256 × 4
   bytes, each 4-byte entry is `[4-bit code_length][code_length bits of
   code]` (big-endian). Code reads it as a bit stream: 4 bits for
   length, then `length` bits for code, for each of 256 entries. These
   may be equivalent if the bit-packing matches, but the spec's "1024
   bytes" suggests fixed-size entries while the code uses variable-size.

4. **LZ77 code mask bit order** — Spec says "bit 0 = literal flag"
   (LSB). Code uses MSB (`0x8000`) as the coded flag. This is a
   fundamental endianness difference in the code mask interpretation.

5. **LZ77 RLE length** — Spec says `low byte + 2`. Code uses `low + 3`.

6. **LZ77 long RLE length** — Spec says
   `(((byte2 & 0x0F) << 8) | byte3) + 3`. Code uses
   `low + (data[pos] << 4) + 0x13` (= `low + data[pos]*16 + 19`).

7. **LZ77 back-reference distance** — Spec says
   `((high_nibble - 2) << 8) + low byte + 1`. Code uses
   `(data[pos] << 4) + low + 3`.

### Not implemented:

- ❌ **Encrypted CBV archives** — DES-based encryption is not supported.
  The spec mentions that some archives use encryption (first directory
  entry's filename starts with `·I·`). The code has no encryption
  handling at all.
- ❌ **CBV writing** — `isWritable()` returns false; no encode path.
- ❌ **Expanded size validation** — The footer's expanded/decompressed
  size field is not read or validated against actual output.
- ❌ **Type ID parsing** — The 3-byte (or 5-byte) type ID in the entry
  footer is not parsed or used for file type identification.
- ❌ **Chess960 game decoding** — CBV delegates to CBH, which has known
  Chess960 move decoding failures (see `CHESS960_CBG_REVERSE_ENGINEERING.md`).
  This is a CBH-level issue, not a CBV container issue.

## Missing Implementation Steps (Priority Order)

1. **Obtain binary test fixtures** — No `.cbv` files exist in the
   repository. Without them, the decompression code cannot be verified.
   A single small `.cbv` file would allow end-to-end testing.

2. **Verify and resolve spec/code discrepancies** — The 7 discrepancies
   listed above need to be resolved. The most reliable approach is to
   test against real `.cbv` files and compare output with ChessBase or
   antoyo's uncbv tool. If the code works correctly with real files,
   update the spec. If not, fix the code.

3. **Add expanded size validation** — Read the expanded size from the
   entry footer and verify that decompressed output matches. This
   provides a safety check against corrupted or partially-decoded
   archives.

4. **Add encrypted archive detection** — At minimum, detect encrypted
   archives and raise a clear error message instead of silently
   producing garbage. Full DES decryption is a larger effort.

5. **Add unit tests** — Create a test harness that can verify
   decompression against known-good outputs. Even without a real `.cbv`
   file, synthetic test blocks with known Huffman/LZ77 data could
   validate the decompression functions.

6. **Chess960 CBH game decoding** — This is the most significant
   functional gap for end users. CBV files containing Chess960 games
   will extract correctly but fail at the CBH move decoding level.
  See `CHESS960_CBG_REVERSE_ENGINEERING.md` for details.

## Recommended Next Action

~~Obtain a small `.cbv` test fixture and run `cdb2sci` on it.~~

**DONE 2026-07-25 — the CBV code works.** Tested against two real
fixtures (`opening-report/tests/fixtures/`, gitignored):

- `twic1654.cbv` (TWIC issue 1654, downloaded from theweekinchess.com,
  `zips/twic1654c6.zip`): `--count-games` reports **8721**, exactly
  matching the PGN edition (`twic1654g.zip`) of the same issue.
  Conversion: **8441 written, 0 rejected, 280 corrupted, 0 warnings,
  0 errors** in ~2s. The PGN edition contains exactly **280 games
  tagged `[Variant "Chess960"]`** — a perfect 1:1 match, so every
  failure is the known Chess960 CBG move-decoding gap (see
  `CHESS960_STATUS.md`), not a CBV container bug. Standard-chess
  decode rate: 8441/8441 = 100%.
- `twic1639_grenke_freestyle_open.cbv`: 7965 written, 606 corrupted
  (Chess960-heavy freestyle issue, same failure class).

Conclusion: CBV extraction/decompression and standard-chess CBH decode
are verified end-to-end against real ChessBase-produced archives. The
spec/code discrepancies listed above should be resolved in favor of the
code where they conflict; remaining conversion failures are tracked as
Chess960 decoder work, not CBV work.

Command used:
```bash
./src/cdb2sci --count-games fixtures/twic1654.cbv
./src/cdb2sci --force fixtures/twic1654.cbv /tmp/twic1654.sci
```

## Binary Fixtures Availability

**No `.cbv` files are available** in the repository or test directory.
The `tests/` directory contains only `.sci` files (small temporary
databases from GUI test runs). No CBV-specific test files, test
scripts, or test cases exist.

## Build Status

The code compiles successfully:
- `cbv/cbv_codec.o` builds clean (no warnings)
- Full `make -j4` succeeds, producing `tkscidb-beta`, `tclscidb-beta`,
  `cbh2si4`, `cdb2sci`, and `verify_maintenance` binaries
- The CBV codec is linked into the main application and converter tools