// ======================================================================
// cb2_elo.h -- Elo decode for the 2CBH (ChessBase 17+) .2cbh index record.
//
// Both ratings are a plain little-endian u16 inside the 192-byte index
// record -- White at 0x60, Black at 0x70 -- unencoded (no key, no offset,
// no scaling), i.e. the same storage convention as classic .cbh.  Found by
// reading the raw disassembly of CBase26.exe's PGN-import tag setters: the
// WhiteElo leaf is `CMP word [RCX+2], 0x101 / JNZ skip / MOV word [RCX+0x60],
// DX` and the BlackElo leaf is identical but stores to [RCX+0x70].  See
// docs/formats/2CBH_FORMAT_DESIGN.md ("Elo: RESOLVED", 4th Ghidra pass).
//
// Empirically validated against the fixture's own source PGN by
// tests/2cbh_elo_validation.cpp: 1,653,474 of 1,653,474 compared values
// exact (100%) over 826,737 identity-matched twin games, and a full-file
// census of all 863,538 index records found every one of the 1,727,076
// values inside [2400, 2894] -- the fixture's 2400 floor is its own rating
// filter, so the low end is expected, not a decode artifact.
//
// Single source of truth: cb2::Codec's index read, the standalone 2cbh2pgn
// converter and the validation test all decode through readIndexElo(), so
// the offsets and the endianness cannot drift apart between them.
// ======================================================================

#ifndef _cb2_elo_included
#define _cb2_elo_included

#include "db_common.h"	// color::ID

#include <stdint.h>

namespace db {

namespace cb2 {

/// Byte offset of @a color's Elo field inside a .2cbh index record.
constexpr uint16_t eloIndexOffset(color::ID color)
{
	return color == color::White ? 0x60 : 0x70;
}

/// The Elo stored for @a color in a .2cbh index record, i.e. the raw
/// little-endian u16 at eloIndexOffset(@a color).  @a rec points at the
/// start of one index record (at least 0x72 bytes long).
///
/// This returns the stored value unchanged; gate it with
/// db::rating::isValid(), which is what rejects the "no rating" values.
inline unsigned readIndexElo(unsigned char const* rec, color::ID color)
{
	unsigned char const* p = rec + eloIndexOffset(color);
	return unsigned(p[0]) | (unsigned(p[1]) << 8);
}

} // namespace cb2
} // namespace db

#endif // _cb2_elo_included
