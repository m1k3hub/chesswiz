// ======================================================================
// Author : $Author$
// Version: $Revision: 688 $
// Date   : $Date: 2013-03-29 12:55:41 -0400 (Fri, 29 Mar 2013) $
// Url    : $URL$
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

#ifndef _SCI_LEGACY_DECODER

static Byte const Invalid = 0xff;


__attribute__((noreturn))
inline static void
throwCorruptData()
{
	IO_RAISE(Game, Corrupted, "error while decoding game data");
}


__attribute__((noreturn))
inline static void
throwInvalidFen()
{
	IO_RAISE(Game, Corrupted, "error while decoding game data (invalid FEN)");
}


inline static Square
convSquare(unsigned s)
{
	using namespace sq;
	return make(fyle(s), Rank8 - rank(s));
}


Position::Position()
{
	m_stack.reserve(10);
	m_stack.push();
}


void
Position::doMove(Move& move, unsigned pieceNum)
{
	M_ASSERT(pieceNum < 64);

	Squares& squares = m_stack.top().squares;

	if (move.isCastling())
	{
		using namespace sq;

		Byte rank = sq::rank(move.to());

		if (move.isShortCastling())
		{
			squares[pieceNum] = make(FyleG, rank);

			unsigned rookNum = m_rookNumbers[castling::kingSideIndex(move.color())];

			if (rookNum != Invalid)	// we allow castlings w/o rook
				squares[rookNum] = make(FyleF, rank);
		}
		else
		{
			squares[pieceNum] = make(FyleC, rank);

			unsigned rookNum = m_rookNumbers[castling::queenSideIndex(move.color())];

			if (rookNum != Invalid)	// we allow castlings w/o rook
				squares[rookNum] = make(FyleD, rank);
		}
	}
	else if (move.isPieceDrop())
	{
		squares[pieceNum] = move.to();
	}
	else if (__builtin_expect(!move.isNull(), 1))
	{
		squares[pieceNum] = move.to();
	}
}


void
Position::setup(char const* fen, variant::Type variant)
{
	Board board;
	if (!board.setup(fen, variant))
		throwInvalidFen();

	setupBoard(board, variant);
}


void
Position::setup(uint16_t idn, variant::Type variant)
{
	Board board;
	board.setup(idn, variant);

	setupBoard(board, variant);
}


void
Position::setupBoard(Board const& board, variant::Type variant)
{
	using namespace sq;

	Lookup& lookup = m_stack.top();
	lookup.board = board;

	for (unsigned i = 0; i < 64; ++i)
		lookup.squares[i] = sq::Null;

	for (unsigned i = 0; i < 4; ++i)
		m_rookNumbers[i] = Invalid;

	// Mirror the encoder (sci::encoder::Position::setupZero): piece numbers are
	// assigned per color (white 0..15, black 16..31), the king always gets
	// number 0, and all remaining pieces are numbered from 1 in flipped-square
	// order. The decoder reads white piece numbers directly and black ones as
	// 0x10|n, so black must live at offset 16 (not 32).
	enum { BlackOffset = 16 };

	Square whiteKingSq = sq::Null;
	Square blackKingSq = sq::Null;

	unsigned whitePieceNum = 1;	// number 0 is reserved for the king
	unsigned blackPieceNum = 1;

	for (unsigned i = 0; i < 64; ++i)
	{
		Square s = convSquare(i);

		switch (board.pieceAt(s))
		{
			case piece::Empty:
				break;

			case piece::WhiteKing:
				if (whiteKingSq == sq::Null)
				{
					whiteKingSq = s;
					lookup.squares[0] = s;
				}
				else
				{
					lookup.squares[whitePieceNum++] = s;
				}
				break;

			case piece::WhiteRook:
				if (s == board.castlingRookSquare(castling::WhiteKS))
					m_rookNumbers[castling::WhiteKS] = whitePieceNum;
				else if (s == board.castlingRookSquare(castling::WhiteQS))
					m_rookNumbers[castling::WhiteQS] = whitePieceNum;
				// fallthru

			case piece::WhiteQueen:
			case piece::WhiteBishop:
			case piece::WhiteKnight:
			case piece::WhitePawn:
				if (whitePieceNum == 16)
					throwCorruptData();
				lookup.squares[whitePieceNum++] = s;
				break;

			case piece::BlackKing:
				if (blackKingSq == sq::Null)
				{
					blackKingSq = s;
					lookup.squares[BlackOffset] = s;
				}
				else
				{
					lookup.squares[BlackOffset + blackPieceNum++] = s;
				}
				break;

			case piece::BlackRook:
				if (s == board.castlingRookSquare(castling::BlackKS))
					m_rookNumbers[castling::BlackKS] = BlackOffset + blackPieceNum;
				else if (s == board.castlingRookSquare(castling::BlackQS))
					m_rookNumbers[castling::BlackQS] = BlackOffset + blackPieceNum;
				// fallthru

			case piece::BlackQueen:
			case piece::BlackBishop:
			case piece::BlackKnight:
			case piece::BlackPawn:
				if (blackPieceNum == 16)
					throwCorruptData();
				lookup.squares[BlackOffset + blackPieceNum++] = s;
				break;
		}
	}
}


void
Position::reset()
{
	for (unsigned i = 0; i < 64; ++i)
		m_stack.top().squares[i] = sq::Null;

	for (unsigned i = 0; i < 4; ++i)
		m_rookNumbers[i] = Invalid;
}

#else // _SCI_LEGACY_DECODER

static Byte const NoRook = 0xff;


__attribute__((noreturn))
inline static void
throwInvalidFen()
{
	IO_RAISE(Game, Corrupted, "error while decoding game data (invalid FEN)");
}


inline static unsigned
convSquare(unsigned s)
{
	return sq::make(sq::fyle(s), sq::Rank8 - sq::rank(s));
}


Position::Position()
{
	m_stack.reserve(10);
	m_stack.push();
}


void
Position::doMove(Move& move, unsigned pieceNum)
{
	Lookup& lookup = m_stack.top();

	if (move.isCastling())
	{
		Byte rank = sq::rank(move.to());

		if (move.isShortCastling())
		{
			lookup.squares[pieceNum] = sq::make(sq::FyleG, rank);

			unsigned rookNum = m_rookNumbers[castling::kingSideIndex(move.color())];

			if (rookNum != NoRook)	// we allow castlings without rook
				lookup.squares[rookNum] = sq::make(sq::FyleF, rank);
		}
		else
		{
			lookup.squares[pieceNum] = sq::make(sq::FyleC, rank);

			unsigned rookNum = m_rookNumbers[castling::queenSideIndex(move.color())];

			if (rookNum != NoRook)	// we allow castlings without rook
				lookup.squares[rookNum] = sq::make(sq::FyleD, rank);
		}
	}
	else if (__builtin_expect(!move.isNull(), 1))
	{
		lookup.squares[pieceNum] = move.to();
	}
}


void
Position::setup(char const* fen)
{
	if (!board().setup(fen, variant::Normal))
		throwInvalidFen();

	setup(board());
}


void
Position::setup(Board const& board)
{
	M_ASSERT(board.isShuffleChessPosition(variant::Normal));

	static Square const Rank2[8] = { sq::a2, sq::b2, sq::c2, sq::d2, sq::e2, sq::f2, sq::g2, sq::h2 };
	static Square const Rank7[8] = { sq::a7, sq::b7, sq::c7, sq::d7, sq::e7, sq::f7, sq::g7, sq::h7 };

	Byte whitePieceNum = 8;
	Byte blackPieceNum = 16;

	Lookup&	lookup	= m_stack.top();
	Squares&	squares	= lookup.squares;

	::memset(squares, 0, sizeof(Squares));
	::memcpy(squares, Rank2, sizeof(Rank2));
	::memcpy(squares + 24, Rank7, sizeof(Rank7));
	::memset(m_rookNumbers, NoRook, sizeof(m_rookNumbers));

	for (unsigned square = sq::a1; square <= sq::h1; ++square)
	{
		switch (unsigned(board.piece(sq::ID(square))))
		{
			case piece::King:
				squares[whitePieceNum++] = squares[0];
				squares[0] = square;
				break;

			case piece::Rook:
				if (m_rookNumbers[castling::WhiteQS] == NoRook)
					m_rookNumbers[castling::WhiteQS] = whitePieceNum;
				else
					m_rookNumbers[castling::WhiteKS] = whitePieceNum;
				// fallthru

			case piece::Queen:
			case piece::Bishop:
			case piece::Knight:
				if (unsigned(board.piece(sq::ID(square))) != piece::Rook)
					squares[whitePieceNum++] = square;
				break;
		}

		switch (unsigned(board.piece(sq::ID(square + 56))))
		{
			case piece::King:
				squares[blackPieceNum++] = squares[16];
				squares[16] = square + 56;
				break;

			case piece::Rook:
				if (m_rookNumbers[castling::BlackQS] == NoRook)
					m_rookNumbers[castling::BlackQS] = blackPieceNum;
				else
					m_rookNumbers[castling::BlackKS] = blackPieceNum;
				// fallthru

			case piece::Queen:
			case piece::Bishop:
			case piece::Knight:
				if (unsigned(board.piece(sq::ID(square + 56))) != piece::Rook)
					squares[blackPieceNum++] = square + 56;
				break;
		}
	}
}


void
Position::setup(uint16_t idn)
{
	while (m_stack.size() > 1)
		m_stack.pop();

	if (idn == variant::Standard)
	{
		static Squares const StandardSquares =
		{
			sq::e1, sq::b2, sq::c2, sq::d2, sq::e2, sq::f2, sq::g2, sq::h2,
			sq::a1, sq::b1, sq::c1, sq::d1, sq::a2, sq::f1, sq::g1, sq::h1,
			sq::e8, sq::b8, sq::c8, sq::d8, sq::a8, sq::f8, sq::g8, sq::h8,
			sq::a7, sq::b7, sq::c7, sq::d7, sq::e7, sq::f7, sq::g7, sq::h7,
		};

		::memcpy(m_stack.top().squares, StandardSquares, sizeof(StandardSquares));

		m_rookNumbers[castling::WhiteQS] =  8;
		m_rookNumbers[castling::WhiteKS] = 15;
		m_rookNumbers[castling::BlackQS] = 20;
		m_rookNumbers[castling::BlackKS] = 23;

		board().setStandardPosition();
	}
	else
	{
		board().setup(idn, variant::Normal);
		setup(board());
	}
}

#endif // _SCI_LEGACY_DECODER
