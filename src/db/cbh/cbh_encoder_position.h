// ======================================================================
// Author : $Author$
// Version: $Revision$
// Date   : $Date$
// Url    : $URL$
// ======================================================================

// ======================================================================
//    _/|            __
//   // o\         /    )           ,        /    /
//   || ._)    ----\---------__----------__-/----/__-
//   //__\          \      /   '  /    /   /    /   )
//   )___(     _(____/____(___ __/____(___/____(___/_
// ======================================================================

// ======================================================================
// Copyright: (C) 2009-2013 Gregor Cramer
// Copyright: (C) 2026 Michael Thomas (Chesswiz)
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#ifndef _cbh_encoder_position_included
#define _cbh_encoder_position_included

#include "db_board.h"
#include "db_move.h"

#include "m_stack.h"

namespace util { class BitStream; }

namespace db {
namespace cbh {
namespace encoder {

class Position
{
public:

	Position();

	unsigned variationLevel() const;

	void setup();
	void setup(Board const& board);

	void push();
	void pop();

	Board const& board() const;

	// Encode a move and update internal state.
	// Returns the logical code (0x00-0xEA), or 0xEB for multi-byte moves.
	// For multi-byte moves (under-promotions), the 16-bit word is written to *multiByteWord.
	Byte encodeMove(Move const& move, uint16_t* multiByteWord = 0);

	// Apply a move to update internal position state (without encoding).
	void doMove(Move const& move);

	// Set Chess960 mode (uses 0xeb castling/promotion descriptors).
	void setChess960(bool on) { m_isChess960 = on; }

private:

	typedef Byte Count[64];
	typedef Byte Pieces[10][15];

	struct Lookup
	{
		Board		board;
		Count		pieceCount;
		Pieces	pieces;
	};

	typedef mstl::stack<Lookup> Stack;

	void reset();
	void handleCapture(Pieces& pieces, Count& pieceCount, Byte to, Byte piece);
	void applyMove(Move const& move, bool updateLookup = true);

	Byte encodePawnMove(Move const& move);
	Byte encodeKingMove(Move const& move);
	Byte encodeCastling(Move const& move);
	Byte encodeQueenMove(Move const& move);
	Byte encodeRookMove(Move const& move);
	Byte encodeBishopMove(Move const& move);
	Byte encodeKnightMove(Move const& move);

	// Find the CBH piece number for a given piece type at a given square.
	Byte findPieceNumber(piece::Type pieceType, Square square) const;

	Stack m_stack;
	bool m_isChess960;
};

} // namespace encoder
} // namespace cbh
} // namespace db

namespace mstl {

template <typename> struct is_pod;

template <>
struct is_pod<db::cbh::encoder::Position::Lookup> { enum { value = is_pod<db::Board>::value }; };

} // namespace mstl

#include "cbh_encoder_position.ipp"

#endif // _cbh_encoder_position_included

// vi:set ts=3 sw=3:
