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

#ifndef _cbh_encoder_included
#define _cbh_encoder_included

#include "cbh_encoder_position.h"
#include "db_move.h"

namespace util { class ByteStream; }

namespace db {

class Board;
class TagSet;

namespace cbh {

class Encoder
{
public:

	Encoder(util::ByteStream& gStrm);

	/// Write game header and set up position for encoding.
	/// If the board is not standard, the position data is written to the stream.
	void startEncoding(Board const& board, bool isStandardPosition);

	/// Encode a single move and write to stream.
	void encodeMove(Move const& move, unsigned& count);

	/// Encode a variation-start (push) token.
	void encodePush(unsigned count);

	/// Encode a variation-end (pop) token.
	void encodePop(unsigned count);

	/// Access the encoder position.
	encoder::Position& position();

private:

	Encoder(Encoder const&);
	Encoder& operator=(Encoder const&);

	void putByte(Byte logicalCode, unsigned count);
	void encodePosition(Board const& board);

	util::ByteStream&		m_gStrm;
	encoder::Position		m_position;

	static Byte InverseMoveNumberLookup[256];
	static bool s_initialized;

	static void initialize();
};

} // namespace cbh
} // namespace db

#include "cbh_encoder.ipp"

#endif // _cbh_encoder_included

// vi:set ts=3 sw=3:
