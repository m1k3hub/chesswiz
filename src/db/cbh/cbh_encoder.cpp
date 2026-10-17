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

#include "cbh_encoder.h"

#include "db_board.h"
#include "db_exception.h"

#include "u_byte_stream.h"

#include "m_utility.h"

#include <string.h>

using namespace util;
using namespace db;
using namespace db::cbh;


// The same permutation table used in the decoder (cbh_decoder.cpp).
static Byte MoveNumberLookup[256] =
{
	0xa2, 0x95, 0x43, 0xf5, 0xc1, 0x3d, 0x4a, 0x6c,	//   0 -   7
	0x53, 0x83, 0xcc, 0x7c, 0xff, 0xae, 0x68, 0xad,	//   8 -  15
	0xd1, 0x92, 0x8b, 0x8d, 0x35, 0x81, 0x5e, 0x74,	//  16 -  23
	0x26, 0x8e, 0xab, 0xca, 0xfd, 0x9a, 0xf3, 0xa0,	//  24 -  31
	0xa5, 0x15, 0xfc, 0xb1, 0x1e, 0xed, 0x30, 0xea,	//  32 -  39
	0x22, 0xeb, 0xa7, 0xcd, 0x4e, 0x6f, 0x2e, 0x24,	//  40 -  47
	0x32, 0x94, 0x41, 0x8c, 0x6e, 0x58, 0x82, 0x50,	//  48 -  55
	0xbb, 0x02, 0x8a, 0xd8, 0xfa, 0x60, 0xde, 0x52,	//  56 -  63
	0xba, 0x46, 0xac, 0x29, 0x9d, 0xd7, 0xdf, 0x08,	//  64 -  71
	0x21, 0x01, 0x66, 0xa3, 0xf1, 0x19, 0x27, 0xb5,	//  72 -  79
	0x91, 0xd5, 0x42, 0x0e, 0xb4, 0x4c, 0xd9, 0x18,	//  80 -  87
	0x5f, 0xbc, 0x25, 0xa6, 0x96, 0x04, 0x56, 0x6a,	//  88 -  95
	0xaa, 0x33, 0x1c, 0x2b, 0x73, 0xf0, 0xdd, 0xa4,	//  96 - 103
	0x37, 0xd3, 0xc5, 0x10, 0xbf, 0x5a, 0x23, 0x34,	// 104 - 111
	0x75, 0x5b, 0xb8, 0x55, 0xd2, 0x6b, 0x09, 0x3a,	// 112 - 119
	0x57, 0x12, 0xb3, 0x77, 0x48, 0x85, 0x9b, 0x0f,	// 120 - 127
	0x9e, 0xc7, 0xc8, 0xa1, 0x7f, 0x7a, 0xc0, 0xbd,	// 128 - 135
	0x31, 0x6d, 0xf6, 0x3e, 0xc3, 0x11, 0x71, 0xce,	// 136 - 143
	0x7d, 0xda, 0xa8, 0x54, 0x90, 0x97, 0x1f, 0x44,	// 144 - 151
	0x40, 0x16, 0xc9, 0xe3, 0x2c, 0xcb, 0x84, 0xec,	// 152 - 159
	0x9f, 0x3f, 0x5c, 0xe6, 0x76, 0x0b, 0x3c, 0x20,	// 160 - 167
	0xb7, 0x36, 0x00, 0xdc, 0xe7, 0xf9, 0x4f, 0xf7,	// 168 - 175
	0xaf, 0x06, 0x07, 0xe0, 0x1a, 0x0a, 0xa9, 0x4b,	// 176 - 183
	0x0c, 0xd6, 0x63, 0x87, 0x89, 0x1d, 0x13, 0x1b,	// 184 - 191
	0xe4, 0x70, 0x05, 0x47, 0x67, 0x7b, 0x2f, 0xee,	// 192 - 199
	0xe2, 0xe8, 0x98, 0x0d, 0xef, 0xcf, 0xc4, 0xf4,	// 200 - 207
	0xfb, 0xb0, 0x17, 0x99, 0x64, 0xf2, 0xd4, 0x2a,	// 208 - 215
	0x03, 0x4d, 0x78, 0xc6, 0xfe, 0x65, 0x86, 0x88,	// 216 - 223
	0x79, 0x45, 0x3b, 0xe5, 0x49, 0x8f, 0x2d, 0xb9,	// 224 - 231
	0xbe, 0x62, 0x93, 0x14, 0xe9, 0xd0, 0x38, 0x9c,	// 232 - 239
	0xb2, 0xc2, 0x59, 0x5d, 0xb6, 0x72, 0x51, 0xf8,	// 240 - 247
	0x28, 0x7e, 0x61, 0x39, 0xe1, 0xdb, 0x69, 0x80,	// 248 - 255
};


// Chess960 move-token lookup table (CBase26.exe VA 0x141a799c0).  Decode
// formula: lc = Chess960MoveNumberLookup[raw] - count (mod 256).
static Byte Chess960MoveNumberLookup[256] =
{
	0x38, 0x50, 0x64, 0xcc, 0x9f, 0x56, 0x6f, 0x73,	//   0 -   7
	0x4d, 0x41, 0x66, 0xa2, 0xc6, 0xb9, 0x96, 0x47,	//   8 -  15
	0xee, 0xcf, 0xb1, 0x6d, 0x48, 0x4f, 0x44, 0x20,	//  16 -  23
	0x15, 0xbe, 0x82, 0x09, 0x34, 0x99, 0xeb, 0x1a,	//  24 -  31
	0x33, 0x7c, 0xab, 0x59, 0x00, 0x22, 0x24, 0xb0,	//  32 -  39
	0xb4, 0xfa, 0x85, 0xdd, 0x57, 0xf3, 0xd9, 0xd2,	//  40 -  47
	0x8a, 0x8d, 0x70, 0xb5, 0x6e, 0x43, 0xa7, 0x0b,	//  48 -  55
	0x27, 0x08, 0xea, 0xb3, 0x94, 0x1c, 0x63, 0x1b,	//  56 -  63
	0x2b, 0xc5, 0x0c, 0xd4, 0x3f, 0x37, 0xe8, 0xde,	//  64 -  71
	0xa6, 0x23, 0xef, 0x06, 0xfd, 0x3e, 0xc1, 0x40,	//  72 -  79
	0x32, 0xdf, 0x2d, 0xc8, 0xd0, 0x0f, 0xf1, 0xe2,	//  80 -  87
	0x7a, 0x95, 0xec, 0x3c, 0xca, 0x49, 0x11, 0xe0,	//  88 -  95
	0x25, 0xd8, 0x30, 0xfe, 0x2e, 0xba, 0xdc, 0xaa,	//  96 - 103
	0x53, 0x4c, 0xd1, 0x5e, 0x67, 0x8b, 0x0d, 0x9e,	// 104 - 111
	0xa9, 0xbf, 0x05, 0x78, 0x35, 0xc4, 0xb6, 0xa4,	// 112 - 119
	0x4b, 0xd6, 0x04, 0x52, 0xa8, 0x76, 0x2c, 0xbd,	// 120 - 127
	0xae, 0x39, 0xb2, 0xe3, 0x03, 0x81, 0x17, 0x9a,	// 128 - 135
	0x3d, 0x68, 0xc0, 0x65, 0x92, 0xc9, 0xf7, 0x77,	// 136 - 143
	0x16, 0xff, 0xf5, 0xe1, 0x1e, 0x36, 0xbb, 0x86,	// 144 - 151
	0x8e, 0xf9, 0x9d, 0xd5, 0x6b, 0xf4, 0x74, 0x80,	// 152 - 159
	0x2f, 0x7b, 0x14, 0x97, 0x29, 0xe5, 0x4a, 0x02,	// 160 - 167
	0x93, 0x5c, 0xcb, 0xa1, 0x58, 0x79, 0xf8, 0x5f,	// 168 - 175
	0x26, 0x28, 0x8f, 0x7e, 0xa5, 0xed, 0xd3, 0x89,	// 176 - 183
	0xc7, 0x88, 0x9b, 0x54, 0x87, 0x60, 0xda, 0xf0,	// 184 - 191
	0x45, 0x3a, 0xc2, 0x84, 0x90, 0x21, 0xf6, 0xf2,	// 192 - 199
	0x5a, 0x2a, 0x55, 0x18, 0x61, 0x01, 0xfb, 0xe6,	// 200 - 207
	0x8c, 0x6a, 0x12, 0xb8, 0x62, 0x83, 0x98, 0x10,	// 208 - 215
	0x71, 0x5b, 0xe4, 0xad, 0xdb, 0x42, 0x0a, 0xcd,	// 216 - 223
	0x46, 0xd7, 0x72, 0x07, 0xce, 0x19, 0xb7, 0x3b,	// 224 - 231
	0x31, 0x9c, 0x51, 0xc3, 0x69, 0xa3, 0x91, 0xe9,	// 232 - 239
	0x0e, 0x1f, 0xfc, 0x75, 0x6c, 0x1d, 0x7d, 0xe7,	// 240 - 247
	0xaf, 0x5d, 0xa0, 0xbc, 0x13, 0x7f, 0xac, 0x4e,	// 248 - 255
};


Byte Encoder::InverseMoveNumberLookup[256];
Byte Encoder::Chess960InverseMoveNumberLookup[256];
bool Encoder::s_initialized = false;


void
Encoder::initialize()
{
	if (s_initialized)
		return;

	// Build the inverse: InverseMoveNumberLookup[MoveNumberLookup[i]] = i
	for (unsigned i = 0; i < 256; ++i)
	{
		InverseMoveNumberLookup[::MoveNumberLookup[i]] = i;
		Chess960InverseMoveNumberLookup[::Chess960MoveNumberLookup[i]] = i;
	}

	s_initialized = true;
}


Encoder::Encoder(ByteStream& gStrm)
	:m_gStrm(gStrm)
	,m_isChess960(false)
{
	initialize();
}


void
Encoder::putByte(Byte logicalCode, unsigned count)
{
	if (m_isChess960)
	{
		// Chess960 decode: lc = Chess960MoveNumberLookup[raw] - count
		// Inverse: raw = Chess960InverseMoveNumberLookup[lc + count]
		m_gStrm.put(Byte(Chess960InverseMoveNumberLookup[Byte(logicalCode + count)]));
	}
	else
	{
		// Inverse of decoder: MoveNumberLookup[(raw_byte - count) & 0xFF] == logicalCode
		// So: raw_byte = InverseMoveNumberLookup[logicalCode] + count
		m_gStrm.put(Byte(InverseMoveNumberLookup[logicalCode] + count));
	}
}


void
Encoder::startEncoding(Board const& board, bool isStandardPosition)
{
	m_isChess960 = !isStandardPosition && board.isChess960Position(variant::Normal);
	m_position.setChess960(m_isChess960);

	if (isStandardPosition)
	{
		// Write a 4-byte header with just the size placeholder.
		// The size will be patched later by the caller.
		// For standard position: bit 30 is NOT set.
		m_gStrm << uint32_t(0);	// placeholder, caller patches with final size
		m_position.setup();
	}
	else
	{
		// Write header with non-standard position flag (bit 30)
		m_gStrm << uint32_t(0);	// placeholder, caller patches with size | 0x40000000
		encodePosition(board);
		m_position.setup(board);
	}
}


void
Encoder::encodeMove(Move const& move, unsigned& count)
{
	uint16_t multiByteWord = 0;
	Byte logicalCode = m_position.encodeMove(move, &multiByteWord);

	if (logicalCode == 0xeb)
	{
		// Multi-byte move: 3 bytes total, all using the same count
		putByte(0xeb, count);
		putByte(Byte(multiByteWord >> 8), count);	// high byte first
		putByte(Byte(multiByteWord & 0xff), count);	// then low byte
	}
	else
	{
		putByte(logicalCode, count);
	}

	++count;
}


void
Encoder::encodePush(unsigned count)
{
	// Variation start token (0xFE). Count is NOT incremented by caller.
	putByte(0xfe, count);
}


void
Encoder::encodePop(unsigned count)
{
	// Variation end token (0xFF). Count is NOT incremented by caller.
	putByte(0xff, count);
}


// ======================================================================
// Bit-packed position encoding (reverse of decoder::Position::setup(BitStream&))
// ======================================================================

namespace {

class BitWriter
{
public:

	BitWriter(Byte* buf, unsigned size)
		:m_buf(buf)
		,m_size(size)
		,m_pos(0)
	{
		::memset(buf, 0, size);
	}

	void write(unsigned value, unsigned nbits)
	{
		for (int i = int(nbits) - 1; i >= 0; --i)
		{
			M_ASSERT(m_pos / 8 < m_size);

			unsigned bytePos = m_pos / 8;
			unsigned bitPos  = 7 - (m_pos % 8);

			if (value & (1u << i))
				m_buf[bytePos] |= Byte(1u << bitPos);

			++m_pos;
		}
	}

	void skip(unsigned nbits) { m_pos += nbits; }

	unsigned bitsWritten() const { return m_pos; }

private:

	Byte*		m_buf;
	unsigned	m_size;
	unsigned	m_pos;
};


inline
Byte
mapSquare(Byte sq)
{
	return db::sq::make(sq >> 3, sq & 7);
}

} // namespace


void
Encoder::encodePosition(Board const& board)
{
	// Inverse of PieceMap in decoder: piece::ID → 4-bit code
	static Byte const InversePieceMap[15] =
	{
		0,		// piece::Empty (0) — unused, empty squares are handled by presence bit
		1,		// piece::WhiteKing   (1)
		2,		// piece::WhiteQueen  (2)
		5,		// piece::WhiteRook   (3)
		4,		// piece::WhiteBishop (4)
		3,		// piece::WhiteKnight (5)
		6,		// piece::WhitePawn   (6)
		0,		// unused (7)
		0,		// unused (8)
		9,		// piece::BlackKing   (9)
		10,	// piece::BlackQueen  (10)
		13,	// piece::BlackRook   (11)
		12,	// piece::BlackBishop (12)
		11,	// piece::BlackKnight (13)
		14,	// piece::BlackPawn   (14)
	};

	// Position data is exactly 28 bytes (224 bits) for non-960 games
	Byte buf[28];
	BitWriter bw(buf, sizeof(buf));

	// 11 bits: padding
	bw.skip(11);

	// 1 bit: side to move (0=white, 1=black)
	bw.write(board.sideToMove() == color::Black ? 1 : 0, 1);

	// 4 bits: en passant fyle (0=none, 1=a, ..., 8=h)
	Square epSquare = board.enPassantSquare();
	if (epSquare != sq::Null)
		bw.write(sq::fyle(epSquare) - sq::FyleA + 1, 4);
	else
		bw.write(0, 4);

	// 4 bits: padding
	bw.skip(4);

	// 4 bits: castling rights (bshort, blong, wshort, wlong)
	bw.write(board.canCastleShort(color::Black) ? 1 : 0, 1);
	bw.write(board.canCastleLong (color::Black) ? 1 : 0, 1);
	bw.write(board.canCastleShort(color::White) ? 1 : 0, 1);
	bw.write(board.canCastleLong (color::White) ? 1 : 0, 1);

	// 8 bits: move number (1-based)
	// Decoder: plyNumber = 2 * (max(1, moveNum) - 1) + toMove
	// Encoder: moveNum = plyNumber / 2 + 1
	unsigned moveNum = board.plyNumber() / 2 + 1;
	if (moveNum > 255) moveNum = 255;
	bw.write(moveNum, 8);

	// 64 squares: presence bit + 4-bit piece code if occupied
	// Scanning order: same as decoder (i=0..63, sq = mapSquare(i))
	for (unsigned i = 0; i < 64; ++i)
	{
		sq::ID sq = sq::ID(::mapSquare(i));
		Byte piece = board.pieceAt(sq);

		if (piece != piece::Empty)
		{
			bw.write(1, 1);
			bw.write(InversePieceMap[piece], 4);
		}
		else
		{
			bw.write(0, 1);
		}
	}

	m_gStrm.put(buf, sizeof(buf));

	if (m_isChess960)
	{
		// 8-byte castling extension (ChessBase 36-byte position block).
		// Squares are CBH-encoded (file*8 + rank, rank 0-indexed); the
		// transpose ((s&7)<<3)|(s>>3) is self-inverse.
		Byte ext[8] = { 0, 0, 0, 0, 0, 0, 0, 0 };
		auto scidbToCbh = [](Square s) -> Byte {
			return Byte(((s & 7) << 3) | (s >> 3));
		};

		ext[0] = scidbToCbh(board.kingSquare(color::White));
		ext[1] = scidbToCbh(board.kingSquare(color::Black));
		ext[2] = scidbToCbh(board.shortCastlingRook(color::White));
		ext[3] = scidbToCbh(board.longCastlingRook(color::White));
		ext[4] = scidbToCbh(board.shortCastlingRook(color::Black));
		ext[5] = scidbToCbh(board.longCastlingRook(color::Black));

		m_gStrm.put(ext, sizeof(ext));
	}
}

// vi:set ts=3 sw=3:
