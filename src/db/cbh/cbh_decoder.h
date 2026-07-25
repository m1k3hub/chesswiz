// ======================================================================
// Author : $Author$
// Version: $Revision: 1339 $
// Date   : $Date: 2017-07-31 15:09:29 -0400 (Mon, 31 Jul 2017) $
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

#ifndef _cbh_decoder_included
#define _cbh_decoder_included

#include "cbh_decoder_position.h"
#include "db_move.h"


namespace util { class ByteStream; }

namespace db {

class TagSet;
class MoveNode;

namespace cbh {

class Decoder
{
public:

	Decoder(util::ByteStream& gStrm, bool isChess960);

	Move findExactPosition(Board const& position, bool skipVariations);

	unsigned doDecoding(uint16_t* moves, unsigned length, Board& startBoard, bool useStartBoard);

protected:

	enum { Token_Move, Token_Push, Token_Pop, Token_Skip };

	unsigned decodeMove(db::Move& move, unsigned& count, bool skipVariations = false);
	void startDecoding(TagSet* tags = 0);


	/// Setup a custom start position from the game stream.
	/// Reads 28 bytes of position data and sets up the board.
	/// If @p tags is non-null, sets the SetUp and FEN tags.
	/// Throws DecodingFailedException if the stream has insufficient data.
	void setupStartPosition(TagSet* tags);

	util::ByteStream&	m_gStrm;
	decoder::Position	m_position;
	bool					m_isChess960;

private:

	Decoder(Decoder const&);
	Decoder& operator=(Decoder const&);

	unsigned decodeMoves(uint16_t* line, unsigned length, Board* startBoard);

	/// Dispatch a decoded logicalCode through the move switch.
	/// @p decodeCount is the count used for multi-byte (0xeb) reads.
	unsigned dispatchMove(unsigned lc, unsigned decodeCount,
	                       db::Move& move, bool skipVariations);

	/// Resolve the cipher count for a candidate logicalCode.
	/// Returns 0xffff if the candidate is not in the table.
	unsigned resolveCipherCount(unsigned candidateLc) const;

	unsigned				m_cipherCount;	///< Current cipher count (Chess960)
	unsigned				m_lcPrev;		///< Previous move's logicalCode (Chess960)
	bool					m_cipherActive;	///< True after the first cipher-decoded move
	bool					m_useCipher;		///< True for real ChessBase Chess960 (36-byte pos)
};

} // namespace cbh
} // namespace db

#endif // _cbh_decoder_included

// vi:set ts=3 sw=3:
