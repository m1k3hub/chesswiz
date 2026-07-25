# CBV Archive Format Specification

## Overview
CBV is ChessBase's archive format. It contains compressed sub-files that make up a ChessBase database (.cbh, .cbg, .cba, .cbp, .cbt, .cbc, .cbs, .cbe, .cbj, .cbm, .cbb, .ini, .html).

## File Structure

### Archive Header (8 bytes)
| Offset | Size | Type   | Description                                     |
|--------|------|--------|-------------------------------------------------|
| 0      | 2    | uint16 | Header size (always 8)                          |
| 2      | 2    | uint16 | Number of directory entries (e.g., 14)          |
| 4      | 2    | uint16 | Size of each directory entry (e.g., 173)       |
| 6      | 2    | uint16 | Archive version (always 3)                      |

### Directory Entries (173 bytes each, starting at offset 8)
| Offset | Size | Type   | Description                                     |
|--------|------|--------|-------------------------------------------------|
| 0      | 125  | char[] | Null-terminated filename + preview data         |
| 132    | 4    | int32  | Compressed size                                 |
| 136    | 4    | int32  | Decompressed size                               |
| 140    | 33   | footer | Entry footer (see below)                       |

### Entry Footer (33 bytes, at offset 140 within each entry)
| Offset | Size | Type   | Description                                     |
|--------|------|--------|-------------------------------------------------|
| 0      | 4    | bytes  | Flags/magic (typically `01 37 26 35`)           |
| 4      | 3    | bytes  | Type ID (identifies file type)                   |
| 7      | 8    | uint64 | Data offset in archive (LE)                    |
| 15     | 8    | uint64 | Stored size in archive (LE)                     |
| 23     | 8    | uint64 | Expanded (decompressed) size (LE)               |
| 31     | 2    | bytes  | Unknown (typically `00 00`)                     |

## Compression

### Block Format
Sub-file data is divided into blocks. Each block has:
- **4-byte header**: `uint16 block_size` + `uint16 unknown` (always 0x0800)
- **Block data** (block_size bytes): First byte is the compression flag

### Compression Types (first byte of block data)
| Value | Description                     |
|-------|--------------------------------|
| 0x00  | Raw/uncompressed data           |
| 0x01  | LZ77 compressed                |
| 0x02  | Huffman compressed             |
| 0x03  | Huffman + LZ77 compressed     |

### Huffman Encoding

**Code table format** (1024 bytes = 256 × 4 bytes):
- 4 bytes per symbol: `[4-bit code_length][code_length bits of code]` (big-endian)
- Code lengths range from 1 to 24 bits
- The Huffman tree is built from 256 symbol entries

**Compressed block format** (after compression flag 0x02 or 0x03):
1. Huffman code table (1024 bytes)
2. Big-endian `uint16` decompressed size
3. Huffman-encoded bit stream

### LZ77 Decompression

**16-bit code masks**: The LZ77 data uses 16-bit codes read from the bit stream.

For each code:
- Read 16 bits of LZ77 data
- Bit 0 = literal flag
  - If bit 0 = 0: Literal byte (remaining 15 bits = byte value)
  - If bit 0 = 1: Coded reference
    - Read high nibble of the 16-bit code (4 bits)
    - If high_nibble == 0: **RLE** (repeat last byte)
      - Length = low byte + 2
      - Repeat last output byte
    - If high_nibble == 1: **Long RLE**
      - Read additional 8 bits
      - byte2 = low byte, byte3 = additional bits
      - Length = (((byte2 & 0x0F) << 8) | byte3) + 3
      - value = output[output_pos - ((byte2 >> 4) + 1)]
    - Otherwise: **Back-reference**
      - Distance = ((high_nibble - 2) << 8) + low byte + 1
      - Length = read additional bits (variable, based on distance table)
      - Copy from output[output_pos - distance]

## CBH Game Format Notes

### Start Position (FEN) Setup
When bit 30 (`0x40000000`) of the game data word is set, the game starts from a custom position. The 28-byte position format follows the 4-byte word header:

| Offset | Size | Description                                     |
|--------|------|-------------------------------------------------|
| 0      | 1    | Always 0x01 (format marker)                     |
| 1      | 1    | Bits 0-3: EP file (0=none); Bit 4: 0=white/1=black to move |
| 2      | 1    | Bit 0: W-O-O-O; Bit 1: W-O-O; Bit 2: B-O-O-O; Bit 3: B-O-O |
| 3      | 1    | Next move number                                |
| 4      | 24   | Piece setup as bit stream                       |

**Piece bit stream**: 64 squares, scanned column-major (a1-a8, b1-b8, ..., h1-h8).
Each square: 1-bit presence flag + 4-bit piece code if present.

**Piece codes** (4 bits):
| Code | Piece          | Code | Piece          |
|------|----------------|------|----------------|
| 1    | White King     | 9    | Black King     |
| 2    | White Queen    | 10   | Black Queen    |
| 3    | White Knight   | 11   | Black Knight   |
| 4    | White Bishop   | 12   | Black Bishop   |
| 5    | White Rook     | 13   | Black Rook     |
| 6    | White Pawn     | 14   | Black Pawn     |

**Piece numbering**: First piece of each type found in the scan is numbered 0 (first), second is numbered 1 (second), etc.

### Game Data Word Bits
| Bit    | Meaning                                         |
|--------|-------------------------------------------------|
| 31     | Encrypted (cannot decode)                       |
| 30     | Has start position (FEN)                        |
| 29     | Unknown                                         |
| 28     | Unknown (possibly correspondence)               |
| 27     | Unknown (set with bit 30 in v5 Chess960)        |
| 26     | Unknown                                         |
| 25     | Unknown (possibly chess960 indicator in v1)      |
| 24     | Unknown                                         |
| 0-23   | Game data size (bytes, including word)          |

### Known Limitation: Chess960 Games
ChessBase v5 (ChessBase 17) introduces Chess960 game support. The move encoding for Chess960 games differs from standard chess in ways that have not been fully reverse-engineered. This is acknowledged as an unsolved problem by scidb's original author (gcramer, 2017):

> "CBH version 10 supports chess 960 games. The decoding doesn't work for chess 960 games. ChessBase has changed either the game data decoding (move decoding) or the encryption."

**Symptoms**: 606 games with custom start positions fail with `DecodingFailed` errors. The position setup (FEN) decodes correctly, but subsequent move data cannot be interpreted using the standard CBH move encoding.

**Current status**: Position setup works correctly for v5 FEN positions. Standard games (without FEN) decode perfectly. Chess960/annotated games with bit 30 set still fail move decoding.

## Decrypted Archives
Some CBV archives may be encrypted using DES-based encryption (the first directory entry's filename starts with `·I·` instead of a real filename, and the stored data is the encrypted archive key). This is not currently supported.

## Implementation Notes
- The decompression algorithm is fully implemented (Huffman + LZ77) and verified to produce byte-identical output to the original sub-files
- CBV archive support is implemented as `cbv::Codec` in scidb, which:
  - Decompresses the entire archive into a temporary directory
  - Delegates game parsing to `cbh::Codec`
  - Cleans up temporary files on close
- The `format::ChessBaseArchive` type (1 << 7) is used for CBV format detection
