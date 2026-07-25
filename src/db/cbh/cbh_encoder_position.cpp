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
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#include "cbh_encoder_position.h"

#include "db_exception.h"

#include "m_utility.h"

#include <string.h>

using namespace db;
using namespace db::cbh::encoder;
using namespace db::cbh;
using namespace db::sq;


inline
static Byte
mapSquare(Byte sq)
{
	return sq::make(sq >> 3, sq & 7);
}


Position::Position()
{
	m_stack.reserve(5);
	m_stack.push();
}


void
Position::reset()
{
	M_ASSERT(!m_stack.empty());

	while (m_stack.size() > 1)
		m_stack.pop();
}


void
Position::handleCapture(Pieces& pieces, Count& pieceCount, Byte to, Byte piece)
{
	if (piece == piece::Empty)
		return;

	Byte pieceNum = pieceCount[to];

	pieces[pieceNum][piece] = Null;

	if (piece::type(piece::ID(piece)) == piece::Pawn)
		return;

	for (unsigned i = 0; i < 10; ++i)
	{
		Byte square = pieces[i][piece];

		if (square != Null)
		{
			Byte number = pieceCount[square];

			if (number > pieceNum)
			{
				pieces[number - 1][piece] = pieces[number][piece];
				pieces[number][piece] = Null;
				--pieceCount[square];
			}
		}
		else if (i != pieceNum)
		{
			return;
		}
	}
}


void
Position::applyMove(Move const& move, bool updateLookup)
{
	Lookup&		lookup		= m_stack.top();
	Board&		board			= lookup.board;
	Pieces&		pieces		= lookup.pieces;
	Count&		pieceCount	= lookup.pieceCount;
	color::ID	sideToMove	= board.sideToMove();

	if (!move.isNull() && updateLookup)
	{
		Square from = move.from();
		Square to   = move.to();

		if (move.isCastling())
		{
			// Move king
			bool isShort = move.isShortCastling();
			Byte rank    = sq::rank(from);
			Square kingTo  = sq::make(isShort ? sq::FyleG : sq::FyleC, rank);
			Byte kingPiece = piece::piece(piece::King, sideToMove);

			pieces[0][kingPiece] = kingTo;
			pieceCount[kingTo] = 0;

			// Move rook
			Square rookFrom = isShort
				? board.shortCastlingRook(sideToMove)
				: board.longCastlingRook(sideToMove);
			if (rookFrom == sq::Null)
				rookFrom = sq::make(isShort ? sq::FyleH : sq::FyleA, rank);
			Square rookTo   = sq::make(isShort ? sq::FyleF : sq::FyleD, rank);
			Byte rookPiece  = piece::piece(piece::Rook, sideToMove);
			Byte rookNum    = pieceCount[rookFrom];

			pieces[rookNum][rookPiece] = rookTo;
			pieceCount[rookTo] = rookNum;
		}
		else if (move.isPromotion())
		{
			// Find first empty slot for promoted piece type (before handleCapture, matching decoder)
			piece::Type promType    = move.promoted();
			Byte        promoted_id = piece::piece(promType, sideToMove);
			unsigned    number      = 0;

			while (pieces[number][promoted_id] != Null)
			{
				if (++number == 10)
				{
					// All 10 slots occupied; the decoder rejects this game too
					// (Move::empty() at the same point).
					IO_RAISE(Game, Encoding_Failed,
								"too many promoted pieces (piece type %u)", unsigned(promType));
				}
			}

			Byte capturedPiece = board.pieceAt(to);
			handleCapture(pieces, pieceCount, to, capturedPiece);

			pieces[number][promoted_id] = to;
			pieceCount[to] = number;
		}
		else
		{
			// Normal move (including en passant)
			piece::Type pieceType = move.moved();
			Byte piece_id = piece::piece(pieceType, sideToMove);
			Byte number   = pieceCount[from];

			if (move.capturedType())
			{
				if (move.isEnPassant())
				{
					Square epSquare = move.enPassantSquare();
					handleCapture(pieces, pieceCount, epSquare, board.pieceAt(epSquare));
				}
				else
				{
					handleCapture(pieces, pieceCount, to, board.pieceAt(to));
				}
			}

			pieces[number][piece_id] = to;
			pieceCount[to] = number;
		}
	}

	// Update board state
	Move m(move);

	if (board.isValidMove(m, variant::Normal, move::AllowIllegalMove))
		m.setLegalMove();
	else
		board.checkMove(m, variant::Normal, move::AllowIllegalMove);

	m.setColor(sideToMove);
	board.prepareUndo(m);
	board.doMove(m, variant::Normal);
}


void
Position::doMove(Move const& move)
{
	applyMove(move);
}


Byte
Position::encodeKingMove(Move const& move)
{
	int fyle_delta = int(sq::fyle(move.to())) - int(sq::fyle(move.from()));
	int rank_delta = int(sq::rank(move.to())) - int(sq::rank(move.from()));

	M_ASSERT(fyle_delta >= -1 && fyle_delta <= 1);
	M_ASSERT(rank_delta >= -1 && rank_delta <= 1);
	M_ASSERT(fyle_delta != 0 || rank_delta != 0);

	// Map direction (fyle_delta, rank_delta) to logical code.
	// Decoder directions:
	//   OFFSET(0,1)=+rank    → 0x01    OFFSET(1,1)=NE → 0x02
	//   OFFSET(1,0)=+fyle    → 0x03    OFFSET(1,7)=SE → 0x04
	//   OFFSET(0,7)=-rank    → 0x05    OFFSET(7,7)=SW → 0x06
	//   OFFSET(7,0)=-fyle    → 0x07    OFFSET(7,1)=NW → 0x08
	static Byte const KingCodeTable[3][3] =
	{
		// fyle_delta = -1:   rank: -1    0    +1
		{                      0x06, 0x07, 0x08 },
		// fyle_delta = 0:
		{                      0x05, 0x00, 0x01 },
		// fyle_delta = +1:
		{                      0x04, 0x03, 0x02 },
	};

	return KingCodeTable[fyle_delta + 1][rank_delta + 1];
}


Byte
Position::encodeCastling(Move const& move)
{
	// CBH keeps castling as logical short/long tokens, even when the
	// rook starts on a Chess960 file. The board state tracks the rook square.
	return move.isShortCastling() ? 0x09 : 0x0a;
}


Byte
Position::encodeQueenMove(Move const& move)
{
	Byte number = m_stack.top().pieceCount[move.from()];

	// Queen 0: 0x0b, Queen 1: 0x8f, Queen 2: 0xab
	// Each queen has 28 codes: 7 rank + 7 fyle + 7 diagonal + 7 anti-diagonal
	static Byte const queenBase[3] = { 0x0b, 0x8f, 0xab };

	M_ASSERT(number <= 2);

	Byte base = queenBase[number];

	int fyle_delta = int(sq::fyle(move.to())) - int(sq::fyle(move.from()));
	int rank_delta = int(sq::rank(move.to())) - int(sq::rank(move.from()));

	if (fyle_delta == 0)
	{
		// Rank move: base + 0..6
		return base + ((rank_delta & 7) - 1);
	}
	else if (rank_delta == 0)
	{
		// Fyle move: base + 7..13
		return base + 7 + ((fyle_delta & 7) - 1);
	}
	else if (fyle_delta == rank_delta)
	{
		// Diagonal (NE/SW): base + 14..20
		return base + 14 + ((fyle_delta & 7) - 1);
	}
	else
	{
		// Anti-diagonal (NW/SE): base + 21..27
		M_ASSERT(fyle_delta == -rank_delta);
		return base + 21 + ((fyle_delta & 7) - 1);
	}
}


Byte
Position::encodeRookMove(Move const& move)
{
	Byte number = m_stack.top().pieceCount[move.from()];

	// Each rook has 14 codes: 7 rank + 7 fyle
	static Byte const rookBaseRank[3] = { 0x27, 0x35, 0xc7 };
	static Byte const rookBaseFyle[3] = { 0x2e, 0x3c, 0xce };

	M_ASSERT(number <= 2);

	int fyle_delta = int(sq::fyle(move.to())) - int(sq::fyle(move.from()));
	int rank_delta = int(sq::rank(move.to())) - int(sq::rank(move.from()));

	if (fyle_delta == 0)
	{
		// Rank move
		return rookBaseRank[number] + ((rank_delta & 7) - 1);
	}
	else
	{
		// Fyle move
		M_ASSERT(rank_delta == 0);
		return rookBaseFyle[number] + ((fyle_delta & 7) - 1);
	}
}


Byte
Position::encodeBishopMove(Move const& move)
{
	Byte number = m_stack.top().pieceCount[move.from()];

	// Each bishop has 14 codes: 7 diagonal + 7 anti-diagonal
	static Byte const bishopBaseDiag[3] = { 0x43, 0x51, 0xd5 };
	static Byte const bishopBaseAnti[3] = { 0x4a, 0x58, 0xdc };

	M_ASSERT(number <= 2);

	int fyle_delta = int(sq::fyle(move.to())) - int(sq::fyle(move.from()));
	int rank_delta = int(sq::rank(move.to())) - int(sq::rank(move.from()));

	if (fyle_delta == rank_delta)
	{
		// Diagonal (NE/SW)
		return bishopBaseDiag[number] + ((fyle_delta & 7) - 1);
	}
	else
	{
		// Anti-diagonal (NW/SE)
		M_ASSERT(fyle_delta == -rank_delta);
		return bishopBaseAnti[number] + ((fyle_delta & 7) - 1);
	}
}


Byte
Position::encodeKnightMove(Move const& move)
{
	Byte number = m_stack.top().pieceCount[move.from()];

	// Each knight has 8 codes for L-shaped moves
	static Byte const knightBase[3] = { 0x5f, 0x67, 0xe3 };

	M_ASSERT(number <= 2);

	// Decoder uses: to = (from + offs) & 63, where offs = OFFSET(x,y) = x + y*8
	// Encoder computes: (to - from) & 63 = offs & 63
	Byte offs = (move.to() - move.from()) & 63;

	switch (offs)
	{
		case 10: return knightBase[number] + 0;	// OFFSET(+2, +1) = 10
		case 17: return knightBase[number] + 1;	// OFFSET(+1, +2) = 17
		case 15: return knightBase[number] + 2;	// OFFSET(-1, +2) = 15
		case  6: return knightBase[number] + 3;	// OFFSET(-2, +1) = 6
		case 54: return knightBase[number] + 4;	// OFFSET(-2, -1) = -10 & 63 = 54
		case 47: return knightBase[number] + 5;	// OFFSET(-1, -2) = -17 & 63 = 47
		case 49: return knightBase[number] + 6;	// OFFSET(+1, -2) = -15 & 63 = 49
		case 58: return knightBase[number] + 7;	// OFFSET(+2, -1) = -6 & 63 = 58
	}

	M_ASSERT(!"invalid knight offset");
	return 0;
}


Byte
Position::encodePawnMove(Move const& move)
{
	Byte number = m_stack.top().pieceCount[move.from()];

	M_ASSERT(number <= 7);

	// Each pawn has 4 codes: one-forward, two-forward, capture-right, capture-left
	Byte base = 0x6f + number * 4;

	int fyle_delta = int(sq::fyle(move.to())) - int(sq::fyle(move.from()));

	if (fyle_delta != 0)
	{
		// Capture (including en passant)
		// "Right" = fyle increases for white, fyle decreases for black
		bool isWhite = m_stack.top().board.whiteToMove();

		if ((isWhite && fyle_delta > 0) || (!isWhite && fyle_delta < 0))
			return base + 2;	// CaptureRight
		else
			return base + 3;	// CaptureLeft
	}
	else if (move.isDoubleAdvance())
	{
		return base + 1;		// TwoForward
	}
	else
	{
		return base + 0;		// OneForward
	}
}


Byte
Position::findPieceNumber(piece::Type pieceType, Square square) const
{
	Lookup const&	lookup	= m_stack.top();
	Byte				number	= lookup.pieceCount[square];
	Byte				piece_id	= piece::piece(pieceType, lookup.board.sideToMove());

	M_ASSERT(lookup.pieces[number][piece_id] == square);

	return number;
}


Byte
Position::encodeMove(Move const& move, uint16_t* multiByteWord)
{
	Byte code;

	if (move.isNull())
	{
		code = 0x00;
	}
	else if (move.isCastling())
	{
		code = encodeCastling(move);
	}
	else if (move.isPromotion())
	{
		// All promotions use multi-byte encoding (0xEB + 2 bytes)
		Byte mapped_from = ::mapSquare(move.from());
		Byte mapped_to   = ::mapSquare(move.to());
		Byte promo       = move.promoted() - piece::Queen;
		uint16_t word    = (mapped_from & 63) | ((mapped_to & 63) << 6) | ((promo & 3) << 12);

		if (multiByteWord)
			*multiByteWord = word;

		code = 0xeb;
	}
	else
	{
		piece::Type moved = move.moved();

		if (	(moved == piece::Queen || moved == piece::Rook
				|| moved == piece::Bishop || moved == piece::Knight)
			&& m_stack.top().pieceCount[move.from()] > 2)
		{
			// No single-byte code exists for the 4th piece onwards; use the
			// 0xEB escape. The decoder's non-promotion 0xEB path updates only
			// the board (no piece-table bookkeeping), so mirror that here.
			uint16_t word = (::mapSquare(move.from()) & 63)
								| (uint16_t(::mapSquare(move.to()) & 63) << 6);

			if (multiByteWord)
				*multiByteWord = word;

			applyMove(move, false);

			return 0xeb;
		}

		switch (moved)
		{
			case piece::King:		code = encodeKingMove(move); break;
			case piece::Queen:	code = encodeQueenMove(move); break;
			case piece::Rook:		code = encodeRookMove(move); break;
			case piece::Bishop:	code = encodeBishopMove(move); break;
			case piece::Knight:	code = encodeKnightMove(move); break;
			case piece::Pawn:		code = encodePawnMove(move); break;
			default:					code = 0x00; break;
		}
	}

	applyMove(move);

	return code;
}


void
Position::setup()
{
#define __ Null
	static Pieces const StandardPosition =
	{
	//   e   wk  wq  wr  wb  wn  wp  -   -   bk  bq  br  bb  bn  bp
		{ __, e1, d1, a1, c1, b1, a2, __, __, e8, d8, a8, c8, b8, a7 },
		{ __, __, __, h1, f1, g1, b2, __, __, __, __, h8, f8, g8, b7 },
		{ __, __, __, __, __, __, c2, __, __, __, __, __, __, __, c7 },
		{ __, __, __, __, __, __, d2, __, __, __, __, __, __, __, d7 },
		{ __, __, __, __, __, __, e2, __, __, __, __, __, __, __, e7 },
		{ __, __, __, __, __, __, f2, __, __, __, __, __, __, __, f7 },
		{ __, __, __, __, __, __, g2, __, __, __, __, __, __, __, g7 },
		{ __, __, __, __, __, __, h2, __, __, __, __, __, __, __, h7 },
		{ __, __, __, __, __, __, __, __, __, __, __, __, __, __, __ },
		{ __, __, __, __, __, __, __, __, __, __, __, __, __, __, __ },
	};
#undef __
#define _ 0
	static Count const PieceCountSetup =
	{
		0, 0, 0, 0, 0, 1, 1, 1,	// a1 .. h1
	   0, 1, 2, 3, 4, 5, 6, 7,	// a2 .. h2
		_, _, _, _, _, _, _, _,	// a3 .. h3
		_, _, _, _, _, _, _, _,	// a4 .. h4
		_, _, _, _, _, _, _, _,	// a5 .. h5
		_, _, _, _, _, _, _, _,	// a6 .. h6
	   0, 1, 2, 3, 4, 5, 6, 7,	// a7 .. h7
		0, 0, 0, 0, 0, 1, 1, 1,	// a8 .. h8
	};
#undef _

	reset();

	Lookup& lookup = m_stack.top();

	lookup.board.setStandardPosition();
	::memcpy(lookup.pieces, StandardPosition, sizeof(StandardPosition));
	::memcpy(lookup.pieceCount, PieceCountSetup, sizeof(PieceCountSetup));
}


void
Position::setup(Board const& board)
{
	reset();

	Lookup&	lookup		= m_stack.top();
	Pieces&	pieces		= lookup.pieces;
	Count&	pieceCount	= lookup.pieceCount;

	lookup.board = board;

	::memset(pieces, Null, sizeof(Pieces));
	::memset(pieceCount, 0, sizeof(Count));

	// Scan squares in fyle-major order (matching decoder's setup(BitStream&) scanning order).
	// This ensures piece numbering is identical to what the decoder produces.
	Byte countPieces[15] = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };

	for (unsigned fyle = 0; fyle <= sq::FyleH; ++fyle)
	{
		for (unsigned rank = 0; rank <= sq::Rank8; ++rank)
		{
			Square sq = sq::make(sq::Fyle(fyle), sq::Rank(rank));
			Byte p = board.pieceAt(sq);

			if (p != piece::Empty)
			{
				Byte& count = countPieces[p];

				if (count < 10)
				{
					pieces[count][p] = sq;
					pieceCount[sq] = count++;
				}
			}
		}
	}
}

// vi:set ts=3 sw=3:
