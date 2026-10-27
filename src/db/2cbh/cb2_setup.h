// ======================================================================
// cb2_setup.h -- the start-position block of a 2CBH game record.
//
// A .2cbg record of type 1 or 2 whose game does not start from the standard
// position begins with
//
//    u16 0xfffb
//    u16 position          only for type 2: 0..959 = Scharnagl, 1000 = arbitrary
//    setup block           only for 1000, or for type 1
//    u16 0xfffc            game-start marker, then the Move16 move stream
//
// The setup block is (2026-10-27, run 9, decoded from probe databases that
// ChessBase 26 wrote itself for tests/tmp-app/2cbh-re/run9):
//
//    u16 leading   = 1 in every block CBase26 writes
//    u8  side      = 0 White to move, 1 Black to move
//    u8  castling  = bit 0 White towards its a-side rook,   bit 1 White h-side
//                    bit 2 Black a-side,                    bit 3 Black h-side
//    u16 trailing  = 0
//
// followed by one Move16 code per occupied square, enumerated in Move16
// square order (file*8 + rank, 0..63), until the 0xfffc marker.  Each code is
// the descriptor `piece` from `from` to `to` with from == to, so its `to`
// square (file-major) receives the piece.
//
// Evidence (probe database, each game imported through CBase26's own PGN
// path and stored by CBase26):
//
//   FEN "4k3/8/8/8/8/8/8/1R2K1R1 w BG -"      -> [0001 side=0 cast=03 tail=0000]
//   FEN "4k3/8/8/8/8/8/8/R3K3 w Q -"           -> [0001 side=0 cast=01 tail=0000]
//   FEN "4k3/8/8/8/8/8/8/4K2R w K -"           -> [0001 side=0 cast=02 tail=0000]
//   FEN "r3k3/8/8/8/8/8/8/4K3 b q -"           -> [0001 side=1 cast=04 tail=0000]
//   FEN "4k2r/8/8/8/8/8/8/4K3 b k -"           -> [0001 side=1 cast=08 tail=0000]
//   FEN "r3k2r/8/8/8/8/8/8/R3K2R w KQkq -"     -> [0001 side=0 cast=0f tail=0000]
//   FEN "1r2k1r1/8/8/8/8/8/8/1R2K1R1 w BGbg -"-> [0001 side=0 cast=0f tail=0000]
//
// The last line is the Chess960 case: CBase26 titles that game "Chess 960"
// but stores exactly the same block shape, so there is **no Variant flag** --
// whether a position is Chess960 is derived from the placement (king not on
// the e-file and/or castling rooks off the a/h files), which is also how
// Scidb's Board treats it.
//
// The trailing zero word is optional when reading: no placement code can be
// 0x0000 (piece 0 is not a piece), so a zero word directly after the castling
// byte is always the trailing word and never a piece.  Reading accepts both
// widths, writing always emits the six bytes CBase26 emits.
// ======================================================================

#ifndef _cb2_setup_included
#define _cb2_setup_included

#include <stdint.h>

namespace db {

namespace cb2 {

/// Move16 marker words of a game record.
static const uint16_t SetupMarker = 0xfffb;	///< start-position marker
static const uint16_t GameStartMarker = 0xfffc;	///< game-start marker
static const uint16_t TerminatorMarker = 0xffff;	///< end of mainline

/// Castling bits of the setup block's castling byte.  "a-side" is the
/// queenside (O-O-O) side, "h-side" the kingside (O-O).
enum SetupCastling
{
	SetupCastleWhiteLong	= 1 << 0,	///< White may castle towards its a-side rook
	SetupCastleWhiteShort= 1 << 1,	///< White may castle towards its h-side rook
	SetupCastleBlackLong	= 1 << 2,	///< Black may castle towards its a-side rook
	SetupCastleBlackShort= 1 << 3,	///< Black may castle towards its h-side rook
	SetupCastleAll			= 0x0f
};

/// The value of the block's leading word in every block CBase26 writes.
static const uint16_t SetupLeadingWord = 1;

/// Bytes of a setup block, trailing zero word included.
static const unsigned SetupBlockBytes = 6;

struct SetupHeader
{
	unsigned side;		///< 0 = White to move, 1 = Black
	unsigned castling;///< bit mask of SetupCastling
	unsigned words;	///< u16 words consumed: 2 (no trailing word) or 3
};

/// Decode the setup block at @a words (byte offset 0 = just after the marker
/// and, for type 2, the position word).  Returns false if the block is not
/// one CBase26 writes (wrong leading word, side or castling byte out of range,
/// or truncated).
inline bool
readSetupHeader(uint16_t const* words, uint32_t count, SetupHeader& result)
{
	if (words == 0 || count < 2)
		return false;
	if (words[0] != SetupLeadingWord)
		return false;

	unsigned const side = words[1] & 0xff;
	unsigned const castling = (words[1] >> 8) & 0xff;

	if (side > 1 || (castling & ~unsigned(SetupCastleAll)) != 0)
		return false;

	result.side = side;
	result.castling = castling;
	result.words = 2;

	// The trailing zero word is not a placement code (piece 0), so its
	// presence is unambiguous.
	if (count >= 3 && words[2] == 0)
		result.words = 3;
	else if (count >= 3)
		result.words = 2;	// four-byte block written by older readers

	return true;
}

/// Write the six-byte block CBase26 writes into @a out.
inline void
writeSetupHeader(unsigned char* out, unsigned side, unsigned castling)
{
	uint16_t const leading = SetupLeadingWord;
	uint16_t const flags = uint16_t((side & 1) | ((castling & SetupCastleAll) << 8));
	uint16_t const trailing = 0;

	out[0] = uint8_t(leading);  out[1] = uint8_t(leading >> 8);
	out[2] = uint8_t(flags);    out[3] = uint8_t(flags >> 8);
	out[4] = uint8_t(trailing); out[5] = uint8_t(trailing >> 8);
}

} // namespace cb2
} // namespace db

#endif // _cb2_setup_included
