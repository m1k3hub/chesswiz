// ======================================================================
// Move16 decode table access for the 2CBH (ChessBase 17+) format.
//
// A 2CBG game record stores its mainline as a sequence of 16-bit
// "Move16" codes (0xfffc = game start, 0xffff = end of mainline,
// 0xfffb/0xfffd = rare markers, codes < 0xfffb = moves).  Each move
// code indexes a global decode table built by ChessBase at startup and
// dumped from a live process (see docs/formats/2CBH_FORMAT_DESIGN.md section 3.8).
//
// Descriptor words (little endian):
//
//   word0: [from:6][to:6][piece:4][captured:4][unused:8]
//          square = file*8 + rank, pieces 1..6 white K,Q,N,B,R,P,
//          9..14 black, captured = piece standing on the to-square.
//   word1 (only for promotions, castling and en-passant):
//          a second square transition with the same layout:
//          - promotion:  [to][to][promoted piece][pawn]
//          - castling:   [rook from][rook to][rook][0]
//          - en passant: [captured sq][captured sq][0][captured pawn]
//
// Copyright (C) 2026 the scidb contributors.
// ==========================================================================

#ifndef _db_cb2_2cbh_move16_included
#define _db_cb2_2cbh_move16_included

#include <stdint.h>

namespace db
{

class Board;
class Move;

namespace cb2
{

struct Move16Descriptor
{
   uint8_t   from;        ///< from-square (file*8 + rank)
   uint8_t   to;          ///< to-square
   uint8_t   piece;       ///< moving piece (1..6 white, 9..14 black)
   uint8_t   captured;    ///< captured piece (0 = none)
   uint32_t  word1From;   ///< second transition: from-square
   uint32_t  word1To;     ///< second transition: to-square
   uint32_t  word1Piece;  ///< second transition: piece
   uint32_t  word1Cap;    ///< second transition: piece losing the to-square
   bool      hasWord1;
};

/// Decode a 16-bit Move16 code into its move descriptor.
/// Returns false if the code is out of range.
bool decodeMove16(uint16_t code, Move16Descriptor& desc);

/// Table accessors (defined in the generated 2cbh_move16_table.cpp).
unsigned const* packedTable();
unsigned const* sideTable();
unsigned packedTableSize();
unsigned sideTableSize();

/// Move16 squares are file-major (sq = file*8 + rank), scidb is rank-major.
inline unsigned toScidbSquare(unsigned m16sq)
{
   return ((m16sq & 7) << 3) | (m16sq >> 3);
}

/// Inverse of toScidbSquare().
inline unsigned toMove16Square(unsigned scidbSq)
{
   return ((scidbSq & 7) << 3) | (scidbSq >> 3);
}

/// 1..6 = white K,Q,N,B,R,P; 9..14 = black. 0 for an empty square.
unsigned toMove16Piece(unsigned scidbPiece);

/// Resolve one Move16 code into a legal move of `board`.
/// ChessBase encodes castling as two transitions (king move + rook move);
/// scidb's internal representation sends the king to the rook square. Both
/// transitions are matched so that the other rook's square cannot be mistaken
/// for the king's destination in Chess960 positions.
bool resolveMove16(Board const& board, Move16Descriptor const& desc, Move& move);

/// The inverse of decodeMove16(): find the code whose descriptor resolves to
/// `move` on `board`.  The packed table is searched through a keyed index built
/// on first use, and every candidate is verified against the board's legal
/// move list, so an encode/decode round trip is guaranteed for any move.
bool encodeMove16(Board const& board, Move const& move, uint16_t& code);

/// Find the "placement" code used by the arbitrary-setup (position 1000) form:
/// a descriptor that puts `m16piece` on `m16square` (from == to).
bool findPlacementCode(unsigned m16piece, unsigned m16square, uint16_t& code);

/// Special Move16 stream tokens.
enum
{
   Move16_None        = 0xfffb,  ///< rare sub-structure marker
   Move16_GameStart   = 0xfffc,  ///< precedes the first move of a game
   Move16_Marker      = 0xfffd,  ///< rare mid-game marker (semantics TBD)
   Move16_Terminator  = 0xffff,  ///< ends the mainline
};

} // namespace cb2

} // namespace db

#endif // _db_cb2_2cbh_move16_included