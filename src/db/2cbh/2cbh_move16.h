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