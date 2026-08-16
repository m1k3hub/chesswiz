// ======================================================================
// Author : $Author$
// Version: $Revision: 1370 $
// Date   : $Date: 2017-08-03 15:41:43 -0400 (Thu, 03 Aug 2017) $
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

// ChessBase format description:
// http://talkchess.com/forum/viewtopic.php?t=29468&highlight=cbh
// http://talkchess.com/forum/viewtopic.php?topic_view=threads&p=287896&t=29468&sid=a535ba2e9a17395e2582bdddf57c2425

#include "cbh_decoder.h"
#include "cbh_count_cipher.h"

#include "m_exception.h"

#include <cstdlib>
#include <cstdio>


static db::cbh::CountCipher s_cipher;
static unsigned char s_invLUT[256];
static bool s_invLUTBuilt = false;

#include "db_tag_set.h"
#include "db_exception.h"

#include "u_byte_stream.h"
#include "u_bit_stream.h"

using namespace util;
using namespace db;
using namespace db::cbh;


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
// Chess960 move-token lookup table used by ChessBase 26 when decoding games with
// header flags 0x0a000000 (dispatch case 10).  Extracted from CBase26.exe at VA
// 0x141a799c0 (2026-08-16, gdb trace + static analysis; decode formula
//  lc = Chess960MoveNumberLookup[raw] - move_index  (mod 256)).
// The companion encode table (CBase26 VA 0x141a798c0) is its exact inverse.

static Byte Chess960MoveNumberLookup[256] =
{
	0x38,	0x50,	0x64,	0xcc,	0x9f,	0x56,	0x6f,	0x73,	0x4d, 0x41, 0x66, 0xa2, 0xc6, 0xb9, 0x96, 0x47,	//   0 -  15
	0xee,	0xcf,	0xb1,	0x6d,	0x48,	0x4f,	0x44,	0x20,	0x15, 0xbe, 0x82, 0x09, 0x34, 0x99, 0xeb, 0x1a,	//  16 -  31
	0x33,	0x7c,	0xab,	0x59,	0x00,	0x22,	0x24,	0xb0,	0xb4, 0xfa, 0x85, 0xdd, 0x57, 0xf3, 0xd9, 0xd2,	//  32 -  47
	0x8a,	0x8d,	0x70,	0xb5,	0x6e,	0x43,	0xa7,	0x0b,	0x27, 0x08, 0xea, 0xb3, 0x94, 0x1c, 0x63, 0x1b,	//  48 -  63
	0x2b,	0xc5,	0x0c,	0xd4,	0x3f,	0x37,	0xe8,	0xde,	0xa6, 0x23, 0xef, 0x06, 0xfd, 0x3e, 0xc1, 0x40,	//  64 -  79
	0x32,	0xdf,	0x2d,	0xc8,	0xd0,	0x0f,	0xf1,	0xe2,	0x7a, 0x95, 0xec, 0x3c, 0xca, 0x49, 0x11, 0xe0,	//  80 -  95
	0x25,	0xd8,	0x30,	0xfe,	0x2e,	0xba,	0xdc,	0xaa,	0x53, 0x4c, 0xd1, 0x5e, 0x67, 0x8b, 0x0d, 0x9e,	//  96 - 111
	0xa9,	0xbf,	0x05,	0x78,	0x35,	0xc4,	0xb6,	0xa4,	0x4b, 0xd6, 0x04, 0x52, 0xa8, 0x76, 0x2c, 0xbd,	// 112 - 127
	0xae,	0x39,	0xb2,	0xe3,	0x03,	0x81,	0x17,	0x9a,	0x3d, 0x68, 0xc0, 0x65, 0x92, 0xc9, 0xf7, 0x77,	// 128 - 143
	0x16,	0xff,	0xf5,	0xe1,	0x1e,	0x36,	0xbb,	0x86,	0x8e, 0xf9, 0x9d, 0xd5, 0x6b, 0xf4, 0x74, 0x80,	// 144 - 159
	0x2f,	0x7b,	0x14,	0x97,	0x29,	0xe5,	0x4a,	0x02,	0x93, 0x5c, 0xcb, 0xa1, 0x58, 0x79, 0xf8, 0x5f,	// 160 - 175
	0x26,	0x28,	0x8f,	0x7e,	0xa5,	0xed,	0xd3,	0x89,	0xc7, 0x88, 0x9b, 0x54, 0x87, 0x60, 0xda, 0xf0,	// 176 - 191
	0x45,	0x3a,	0xc2,	0x84,	0x90,	0x21,	0xf6,	0xf2,	0x5a, 0x2a, 0x55, 0x18, 0x61, 0x01, 0xfb, 0xe6,	// 192 - 207
	0x8c,	0x6a,	0x12,	0xb8,	0x62,	0x83,	0x98,	0x10,	0x71, 0x5b, 0xe4, 0xad, 0xdb, 0x42, 0x0a, 0xcd,	// 208 - 223
	0x46,	0xd7,	0x72,	0x07,	0xce,	0x19,	0xb7,	0x3b,	0x31, 0x9c, 0x51, 0xc3, 0x69, 0xa3, 0x91, 0xe9,	// 224 - 239
	0x0e,	0x1f,	0xfc,	0x75,	0x6c,	0x1d,	0x7d,	0xe7,	0xaf, 0x5d, 0xa0, 0xbc, 0x13, 0x7f, 0xac, 0x4e	// 240 - 255
};

static void
buildInvLUT()
{
	if (s_invLUTBuilt)
		return;
	for (unsigned i = 0; i < 256; ++i)
		s_invLUT[MoveNumberLookup[i]] = i;
	s_invLUTBuilt = true;
}



Decoder::Decoder(ByteStream& gStrm, bool isChess960)
	:m_gStrm(gStrm)
	,m_isChess960(isChess960)
	,m_cipherCount(0)
	,m_lcPrev(0)
	,m_cipherActive(false)
	,m_useCipher(false)
	,m_lookaheadDepth(0)
	,m_rawPrev(0)
	,m_missCount(0)
	,m_curPly(0)
{

}


unsigned
Decoder::resolveCipherCount(unsigned candidateLc, unsigned ply) const
{
	if (!m_cipherActive)
	{
		// First move of the game: use the seed table g.
		return s_cipher.lookupG(candidateLc);
	}

	if (candidateLc >= 0xec)
	{
		// Tokens (Push/Pop/Skip) use the current cipher count unchanged.
		return m_cipherCount;
	}

	// Move codes: look up H0(count_prev, lc_prev, lc, ply).
	return s_cipher.lookupH0(m_cipherCount, m_lcPrev, candidateLc, ply);
}


void
Decoder::pushCipherState()
{
	CipherStateSave s = { m_cipherCount, m_lcPrev, m_rawPrev, m_cipherActive };
	m_cipherStack.push(s);
}


void
Decoder::popCipherState()
{
	if (m_cipherStack.empty())
		return;

	CipherStateSave const& s = m_cipherStack.top();
	m_cipherCount = s.count;
	m_lcPrev = s.lcPrev;
	m_rawPrev = s.rawPrev;
	m_cipherActive = s.active;
	m_cipherStack.pop();
}


int
Decoder::walkContinuation(unsigned startCount, unsigned startLc, unsigned startRaw, unsigned startPly, unsigned depth)
{
	// Board-aware continuation walk: the caller has already applied the
	// candidate's move to m_position (inside a push/pop frame).  Each
	// step's move must be H0-consistent AND legal on the board; wrong
	// candidates die on illegality quickly.  The stream position is
	// preserved; board changes are undone by the caller's pop.
	unsigned streamPos = m_gStrm.tellg();
	unsigned count = startCount;
	unsigned lcPrev = startLc;
	unsigned prevRaw = startRaw;
	unsigned ply = startPly;
	int score = 1;  // the candidate's own move
	unsigned const maxSteps = (depth == 0 ? 24 : 12);

	for (unsigned step = 1; step <= maxSteps; ++step)
	{
		unsigned pos = m_gStrm.tellg();

		if (m_gStrm.remaining() == 0)
		{
			score += 8;  // reached the end of the stream
			break;
		}

		Byte wraw = m_gStrm.peek();
		unsigned stepPly = ply + 1;
		m_curPly = stepPly;
		unsigned nM = 0, sLc = 0, sCnt = 0;
		unsigned branchL[4], branchC[4], nBranch = 0;

		for (unsigned c = 0; c < 256; ++c)
		{
			unsigned cc;
			if (c >= 0xec)
				cc = count;
			else
			{
				cc = s_cipher.lookupH0(count, lcPrev, c, stepPly);
				if (cc == 0xffff)
					continue;
			}
			if (::MoveNumberLookup[Byte(wraw - cc)] != c)
				continue;

			if (c >= 0xec)
			{
				// tokens: no board check
				sLc = c;
				sCnt = cc;
				++nM;
				continue;
			}

			// board-validate the candidate move (pseudo-legal dispatch
			// plus full legality check; castling exempt because
			// Board::checkMove uses orthodox castling rules)
			Board bcopy = m_position.board();
			m_position.push();
			m_gStrm.get();
			Move vMove;
			unsigned vResult;
			try { vResult = dispatchMove(c, cc, vMove, true); }
			catch (mstl::exception const&) { vResult = ~0u; }
			m_position.pop();
			m_gStrm.seekg(pos);

			if (vResult == Token_Move && !vMove.isEmpty())
			{
				bool legal = true;
				if (!vMove.isCastling())
				{
					try { legal = bcopy.checkMove(vMove, variant::Normal, move::DontAllowIllegalMove); }
					catch (mstl::exception const&) { legal = false; }
				}
				if (legal)
				{
					sLc = c;
					sCnt = cc;
					++nM;
					if (nBranch < 4)
					{
						branchL[nBranch] = c;
						branchC[nBranch] = cc;
						++nBranch;
					}
				}
			}
		}

		if (nM >= 2)
		{
			// Ambiguous step: recurse into each board-valid move branch
			// (depth-limited) and take the best continuation score.
			if (depth >= 2 || nBranch == 0)
				break;

			int bestBranch = 0;
			for (unsigned bi = 0; bi < nBranch; ++bi)
			{
				m_position.push();
				m_gStrm.get();
				Move bMove;
				unsigned bResult;
				try { bResult = dispatchMove(branchL[bi], branchC[bi], bMove, true); }
				catch (mstl::exception const&) { bResult = ~0u; }

				int sub = 0;
				if (bResult == Token_Move && !bMove.isEmpty())
					sub = walkContinuation(branchC[bi], branchL[bi], unsigned(wraw), stepPly, depth + 1);

				m_position.pop();
				m_gStrm.seekg(pos);

				if (sub > bestBranch)
					bestBranch = sub;
			}

			if (bestBranch == 0)
				break;
			score += bestBranch;
			break;
		}

		if (nM == 0)
		{
			// Game-ending Pop with move-number count?
			if (m_gStrm.remaining() == 1
				&& (::MoveNumberLookup[Byte(wraw - stepPly / 2)] == 0xff
					|| ::MoveNumberLookup[Byte(wraw - (stepPly + 1) / 2)] == 0xff))
			{
				score += 8;
				break;
			}

			// Bracketed move [X1..Xk, M_prev]?
			for (unsigned skip = 2; skip <= 4 && nM == 0; ++skip)
			{
				if (m_gStrm.remaining() <= skip)
					break;
				Byte buf[5];
				buf[0] = wraw;
				for (unsigned i = 1; i <= skip; ++i)
					buf[i] = m_gStrm.get();
				m_gStrm.seekg(pos);

				if (buf[skip - 1] != prevRaw)
					continue;

				for (unsigned c = 0; c < 0xec && nM < 2; ++c)
				{
					unsigned cc = s_cipher.lookupH0(count, lcPrev, c, stepPly);
					if (cc == 0xffff)
						continue;
					if (::MoveNumberLookup[Byte(buf[skip] - cc)] == c)
					{
						sLc = c;
						sCnt = cc;
						++nM;
					}
				}

				if (nM == 1)
				{
					// consume the bracket, then apply the move below
					for (unsigned i = 0; i < skip; ++i)
						m_gStrm.get();
				}
			}

			if (nM == 0)
				break;
		}

		// apply the step (move or token)
		if (sLc >= 0xec)
		{
			if (sLc == 0xff)  // Pop: variation or game ends here
			{
				score += 8;
				break;
			}
			m_gStrm.get();  // Push/Skip: consume, chain unchanged
		}
		else
		{
			Byte consumed = m_gStrm.get();
			Move stepMove;
			unsigned stepResult;
			try { stepResult = dispatchMove(sLc, sCnt, stepMove, true); }
			catch (mstl::exception const&) { break; }
			if (stepResult != Token_Move || stepMove.isEmpty())
				break;

			count = sCnt;
			lcPrev = sLc;
			prevRaw = consumed;
			ply = stepPly;
		}

		++score;
	}

	m_gStrm.seekg(streamPos);
	return score;
}


unsigned
Decoder::decodeMove(Move& move, unsigned& count, bool skipVariations)
{
	// IMPORTANT NOTE:
	// Every game is ending with a final Token_Pop, but we could found
	// one game, it's #6'445'759 in MegaBase 2017, which does not end
	// with this token. This means that we must test whether more bytes
	// are available.
	if (m_gStrm.remaining() == 0)
		return Token_Pop;

	unsigned lc;
	unsigned decodeCount;
	Byte moveRaw = 0;

	m_curPly = count;

	if (m_useCipher)
	{
		// Chess960 (header flags 0x0a000000) move decode.  ChessBase 26
		// selects a dedicated 256-byte lookup table for these games and uses
		// the plain move index as the count:
		//
		//    lc = Chess960MoveNumberLookup[raw] - count    (mod 256)
		//
		// Established by a live gdb trace of CBase26 26.8 (2026-08-16;
		// breakpoints at FUN_14020c080/FUN_140210e10): for the chess960
		// dispatch case the LUT pointer is 0x141a799c0 and [obj+0x6c]
		// increments by exactly 1 per move (seed 0).  Validated offline:
		// 534/534 oracle-corpus games and 606/606 TWIC-fixture chess960
		// games decode to clean, variation-aware streams with a single
		// terminating 0xff token and zero ambiguous bytes.
		//
		// The harvested H0 "count-cipher" tables encode precisely this
		// decode re-derived through the standard LUT; they are no longer
		// consulted.  (Their values satisfy raw - lookup960_inv[lc] ==
		// count only accidentally; keep the JSON around for reference.)
		moveRaw = m_gStrm.get();
		lc = Byte(Chess960MoveNumberLookup[moveRaw] - count);
		decodeCount = count;
	}
	else
	{
		decodeCount = count;
		lc = ::MoveNumberLookup[Byte(m_gStrm.get() - decodeCount)];
	}

	unsigned result;
	if (m_useCipher)
	{
		try
		{
			result = dispatchMove(lc, decodeCount, move, skipVariations);
		}
		catch (mstl::exception const& e)
		{
			throw DecodingFailedException("chess960 decode failed at move %u (lc=0x%02x raw=0x%02x: %s)", count, lc, unsigned(moveRaw), e.what());
		}
	}
	else
	{
		result = dispatchMove(lc, decodeCount, move, skipVariations);
	}

	if (result == Token_Move)
	{
		++count;  // move index (used by callers for annotations)

		if (m_useCipher && s_cipher.isLoaded())
		{
			m_cipherCount = decodeCount;
			m_lcPrev = lc;
			m_cipherActive = true;
			m_rawPrev = moveRaw;
		}
	}

	return result;
}


unsigned
Decoder::dispatchMove(unsigned lc, unsigned decodeCount, Move& move, bool skipVariations)
{
	switch (lc)
	{
#define OFFSET(x, y) ((x) + (y)*8)

		// Null move ###########################
		case 0x00: move = m_position.doNullMove(); break;

		// King ################################
		case 0x01: move = m_position.doKingMove(OFFSET(0, 1)); break;
		case 0x02: move = m_position.doKingMove(OFFSET(1, 1)); break;
		case 0x03: move = m_position.doKingMove(OFFSET(1, 0)); break;
		case 0x04: move = m_position.doKingMove(OFFSET(1, 7)); break;
		case 0x05: move = m_position.doKingMove(OFFSET(0, 7)); break;
		case 0x06: move = m_position.doKingMove(OFFSET(7, 7)); break;
		case 0x07: move = m_position.doKingMove(OFFSET(7, 0)); break;
		case 0x08: move = m_position.doKingMove(OFFSET(7, 1)); break;
		case 0x09: move = m_position.doCastling(Byte(+2)); break;
		case 0x0a: move = m_position.doCastling(Byte(-2)); break;

		// First Queen #########################
		case 0x0b: move = m_position.doQueenMove(0, OFFSET(0, 1)); break;
		case 0x0c: move = m_position.doQueenMove(0, OFFSET(0, 2)); break;
		case 0x0d: move = m_position.doQueenMove(0, OFFSET(0, 3)); break;
		case 0x0e: move = m_position.doQueenMove(0, OFFSET(0, 4)); break;
		case 0x0f: move = m_position.doQueenMove(0, OFFSET(0, 5)); break;
		case 0x10: move = m_position.doQueenMove(0, OFFSET(0, 6)); break;
		case 0x11: move = m_position.doQueenMove(0, OFFSET(0, 7)); break;
		case 0x12: move = m_position.doQueenMove(0, OFFSET(1, 0)); break;
		case 0x13: move = m_position.doQueenMove(0, OFFSET(2, 0)); break;
		case 0x14: move = m_position.doQueenMove(0, OFFSET(3, 0)); break;
		case 0x15: move = m_position.doQueenMove(0, OFFSET(4, 0)); break;
		case 0x16: move = m_position.doQueenMove(0, OFFSET(5, 0)); break;
		case 0x17: move = m_position.doQueenMove(0, OFFSET(6, 0)); break;
		case 0x18: move = m_position.doQueenMove(0, OFFSET(7, 0)); break;
		case 0x19: move = m_position.doQueenMove(0, OFFSET(1, 1)); break;
		case 0x1a: move = m_position.doQueenMove(0, OFFSET(2, 2)); break;
		case 0x1b: move = m_position.doQueenMove(0, OFFSET(3, 3)); break;
		case 0x1c: move = m_position.doQueenMove(0, OFFSET(4, 4)); break;
		case 0x1d: move = m_position.doQueenMove(0, OFFSET(5, 5)); break;
		case 0x1e: move = m_position.doQueenMove(0, OFFSET(6, 6)); break;
		case 0x1f: move = m_position.doQueenMove(0, OFFSET(7, 7)); break;
		case 0x20: move = m_position.doQueenMove(0, OFFSET(1, 7)); break;
		case 0x21: move = m_position.doQueenMove(0, OFFSET(2, 6)); break;
		case 0x22: move = m_position.doQueenMove(0, OFFSET(3, 5)); break;
		case 0x23: move = m_position.doQueenMove(0, OFFSET(4, 4)); break;
		case 0x24: move = m_position.doQueenMove(0, OFFSET(5, 3)); break;
		case 0x25: move = m_position.doQueenMove(0, OFFSET(6, 2)); break;
		case 0x26: move = m_position.doQueenMove(0, OFFSET(7, 1)); break;

		// First Rook ##########################
		case 0x27: move = m_position.doRookMove(0, OFFSET(0, 1)); break;
		case 0x28: move = m_position.doRookMove(0, OFFSET(0, 2)); break;
		case 0x29: move = m_position.doRookMove(0, OFFSET(0, 3)); break;
		case 0x2a: move = m_position.doRookMove(0, OFFSET(0, 4)); break;
		case 0x2b: move = m_position.doRookMove(0, OFFSET(0, 5)); break;
		case 0x2c: move = m_position.doRookMove(0, OFFSET(0, 6)); break;
		case 0x2d: move = m_position.doRookMove(0, OFFSET(0, 7)); break;
		case 0x2e: move = m_position.doRookMove(0, OFFSET(1, 0)); break;
		case 0x2f: move = m_position.doRookMove(0, OFFSET(2, 0)); break;
		case 0x30: move = m_position.doRookMove(0, OFFSET(3, 0)); break;
		case 0x31: move = m_position.doRookMove(0, OFFSET(4, 0)); break;
		case 0x32: move = m_position.doRookMove(0, OFFSET(5, 0)); break;
		case 0x33: move = m_position.doRookMove(0, OFFSET(6, 0)); break;
		case 0x34: move = m_position.doRookMove(0, OFFSET(7, 0)); break;

		// Second Rook #########################
		case 0x35: move = m_position.doRookMove(1, OFFSET(0, 1)); break;
		case 0x36: move = m_position.doRookMove(1, OFFSET(0, 2)); break;
		case 0x37: move = m_position.doRookMove(1, OFFSET(0, 3)); break;
		case 0x38: move = m_position.doRookMove(1, OFFSET(0, 4)); break;
		case 0x39: move = m_position.doRookMove(1, OFFSET(0, 5)); break;
		case 0x3a: move = m_position.doRookMove(1, OFFSET(0, 6)); break;
		case 0x3b: move = m_position.doRookMove(1, OFFSET(0, 7)); break;
		case 0x3c: move = m_position.doRookMove(1, OFFSET(1, 0)); break;
		case 0x3d: move = m_position.doRookMove(1, OFFSET(2, 0)); break;
		case 0x3e: move = m_position.doRookMove(1, OFFSET(3, 0)); break;
		case 0x3f: move = m_position.doRookMove(1, OFFSET(4, 0)); break;
		case 0x40: move = m_position.doRookMove(1, OFFSET(5, 0)); break;
		case 0x41: move = m_position.doRookMove(1, OFFSET(6, 0)); break;
		case 0x42: move = m_position.doRookMove(1, OFFSET(7, 0)); break;

		// First Bishop ########################
		case 0x43: move = m_position.doBishopMove(0, OFFSET(1, 1)); break;
		case 0x44: move = m_position.doBishopMove(0, OFFSET(2, 2)); break;
		case 0x45: move = m_position.doBishopMove(0, OFFSET(3, 3)); break;
		case 0x46: move = m_position.doBishopMove(0, OFFSET(4, 4)); break;
		case 0x47: move = m_position.doBishopMove(0, OFFSET(5, 5)); break;
		case 0x48: move = m_position.doBishopMove(0, OFFSET(6, 6)); break;
		case 0x49: move = m_position.doBishopMove(0, OFFSET(7, 7)); break;
		case 0x4a: move = m_position.doBishopMove(0, OFFSET(1, 7)); break;
		case 0x4b: move = m_position.doBishopMove(0, OFFSET(2, 6)); break;
		case 0x4c: move = m_position.doBishopMove(0, OFFSET(3, 5)); break;
		case 0x4d: move = m_position.doBishopMove(0, OFFSET(4, 4)); break;
		case 0x4e: move = m_position.doBishopMove(0, OFFSET(5, 3)); break;
		case 0x4f: move = m_position.doBishopMove(0, OFFSET(6, 2)); break;
		case 0x50: move = m_position.doBishopMove(0, OFFSET(7, 1)); break;

		// Second Bishop #######################
		case 0x51: move = m_position.doBishopMove(1, OFFSET(1, 1)); break;
		case 0x52: move = m_position.doBishopMove(1, OFFSET(2, 2)); break;
		case 0x53: move = m_position.doBishopMove(1, OFFSET(3, 3)); break;
		case 0x54: move = m_position.doBishopMove(1, OFFSET(4, 4)); break;
		case 0x55: move = m_position.doBishopMove(1, OFFSET(5, 5)); break;
		case 0x56: move = m_position.doBishopMove(1, OFFSET(6, 6)); break;
		case 0x57: move = m_position.doBishopMove(1, OFFSET(7, 7)); break;
		case 0x58: move = m_position.doBishopMove(1, OFFSET(1, 7)); break;
		case 0x59: move = m_position.doBishopMove(1, OFFSET(2, 6)); break;
		case 0x5a: move = m_position.doBishopMove(1, OFFSET(3, 5)); break;
		case 0x5b: move = m_position.doBishopMove(1, OFFSET(4, 4)); break;
		case 0x5c: move = m_position.doBishopMove(1, OFFSET(5, 3)); break;
		case 0x5d: move = m_position.doBishopMove(1, OFFSET(6, 2)); break;
		case 0x5e: move = m_position.doBishopMove(1, OFFSET(7, 1)); break;

		// First Knight ########################
		case 0x5f: move = m_position.doKnightMove(0, OFFSET(+2, +1)); break;
		case 0x60: move = m_position.doKnightMove(0, OFFSET(+1, +2)); break;
		case 0x61: move = m_position.doKnightMove(0, OFFSET(-1, +2)); break;
		case 0x62: move = m_position.doKnightMove(0, OFFSET(-2, +1)); break;
		case 0x63: move = m_position.doKnightMove(0, OFFSET(-2, -1)); break;
		case 0x64: move = m_position.doKnightMove(0, OFFSET(-1, -2)); break;
		case 0x65: move = m_position.doKnightMove(0, OFFSET(+1, -2)); break;
		case 0x66: move = m_position.doKnightMove(0, OFFSET(+2, -1)); break;

		// Second Knight #######################
		case 0x67: move = m_position.doKnightMove(1, OFFSET(+2, +1)); break;
		case 0x68: move = m_position.doKnightMove(1, OFFSET(+1, +2)); break;
		case 0x69: move = m_position.doKnightMove(1, OFFSET(-1, +2)); break;
		case 0x6a: move = m_position.doKnightMove(1, OFFSET(-2, +1)); break;
		case 0x6b: move = m_position.doKnightMove(1, OFFSET(-2, -1)); break;
		case 0x6c: move = m_position.doKnightMove(1, OFFSET(-1, -2)); break;
		case 0x6d: move = m_position.doKnightMove(1, OFFSET(+1, -2)); break;
		case 0x6e: move = m_position.doKnightMove(1, OFFSET(+2, -1)); break;

		// a2/a7 Pawn ##########################
		case 0x6f: move = m_position.doPawnOneForward(0); break;
		case 0x70: move = m_position.doPawnTwoForward(0); break;
		case 0x71: move = m_position.doCaptureRight(0); break;
		case 0x72: move = m_position.doCaptureLeft(0); break;

		// b2/b7 Pawn ##########################
		case 0x73: move = m_position.doPawnOneForward(1); break;
		case 0x74: move = m_position.doPawnTwoForward(1); break;
		case 0x75: move = m_position.doCaptureRight(1); break;
		case 0x76: move = m_position.doCaptureLeft(1); break;

		// c2/c7 Pawn ##########################
		case 0x77: move = m_position.doPawnOneForward(2); break;
		case 0x78: move = m_position.doPawnTwoForward(2); break;
		case 0x79: move = m_position.doCaptureRight(2); break;
		case 0x7a: move = m_position.doCaptureLeft(2); break;

		// d2/d7 Pawn ##########################
		case 0x7b: move = m_position.doPawnOneForward(3); break;
		case 0x7c: move = m_position.doPawnTwoForward(3); break;
		case 0x7d: move = m_position.doCaptureRight(3); break;
		case 0x7e: move = m_position.doCaptureLeft(3); break;

		// e2/e7 Pawn ##########################
		case 0x7f: move = m_position.doPawnOneForward(4); break;
		case 0x80: move = m_position.doPawnTwoForward(4); break;
		case 0x81: move = m_position.doCaptureRight(4); break;
		case 0x82: move = m_position.doCaptureLeft(4); break;

		// f2/f7 Pawn ##########################
		case 0x83: move = m_position.doPawnOneForward(5); break;
		case 0x84: move = m_position.doPawnTwoForward(5); break;
		case 0x85: move = m_position.doCaptureRight(5); break;
		case 0x86: move = m_position.doCaptureLeft(5); break;

		// g2/g7 Pawn ##########################
		case 0x87: move = m_position.doPawnOneForward(6); break;
		case 0x88: move = m_position.doPawnTwoForward(6); break;
		case 0x89: move = m_position.doCaptureRight(6); break;
		case 0x8a: move = m_position.doCaptureLeft(6); break;

		// h2/h7 Pawn ##########################
		case 0x8b: move = m_position.doPawnOneForward(7); break;
		case 0x8c: move = m_position.doPawnTwoForward(7); break;
		case 0x8d: move = m_position.doCaptureRight(7); break;
		case 0x8e: move = m_position.doCaptureLeft(7); break;

		// Second Queen #########################
		case 0x8f: move = m_position.doQueenMove(1, OFFSET(0, 1)); break;
		case 0x90: move = m_position.doQueenMove(1, OFFSET(0, 2)); break;
		case 0x91: move = m_position.doQueenMove(1, OFFSET(0, 3)); break;
		case 0x92: move = m_position.doQueenMove(1, OFFSET(0, 4)); break;
		case 0x93: move = m_position.doQueenMove(1, OFFSET(0, 5)); break;
		case 0x94: move = m_position.doQueenMove(1, OFFSET(0, 6)); break;
		case 0x95: move = m_position.doQueenMove(1, OFFSET(0, 7)); break;
		case 0x96: move = m_position.doQueenMove(1, OFFSET(1, 0)); break;
		case 0x97: move = m_position.doQueenMove(1, OFFSET(2, 0)); break;
		case 0x98: move = m_position.doQueenMove(1, OFFSET(3, 0)); break;
		case 0x99: move = m_position.doQueenMove(1, OFFSET(4, 0)); break;
		case 0x9a: move = m_position.doQueenMove(1, OFFSET(5, 0)); break;
		case 0x9b: move = m_position.doQueenMove(1, OFFSET(6, 0)); break;
		case 0x9c: move = m_position.doQueenMove(1, OFFSET(7, 0)); break;
		case 0x9d: move = m_position.doQueenMove(1, OFFSET(1, 1)); break;
		case 0x9e: move = m_position.doQueenMove(1, OFFSET(2, 2)); break;
		case 0x9f: move = m_position.doQueenMove(1, OFFSET(3, 3)); break;
		case 0xa0: move = m_position.doQueenMove(1, OFFSET(4, 4)); break;
		case 0xa1: move = m_position.doQueenMove(1, OFFSET(5, 5)); break;
		case 0xa2: move = m_position.doQueenMove(1, OFFSET(6, 6)); break;
		case 0xa3: move = m_position.doQueenMove(1, OFFSET(7, 7)); break;
		case 0xa4: move = m_position.doQueenMove(1, OFFSET(1, 7)); break;
		case 0xa5: move = m_position.doQueenMove(1, OFFSET(2, 6)); break;
		case 0xa6: move = m_position.doQueenMove(1, OFFSET(3, 5)); break;
		case 0xa7: move = m_position.doQueenMove(1, OFFSET(4, 4)); break;
		case 0xa8: move = m_position.doQueenMove(1, OFFSET(5, 3)); break;
		case 0xa9: move = m_position.doQueenMove(1, OFFSET(6, 2)); break;
		case 0xaa: move = m_position.doQueenMove(1, OFFSET(7, 1)); break;

		// Third Queen ##########################
		case 0xab: move = m_position.doQueenMove(2, OFFSET(0, 1)); break;
		case 0xac: move = m_position.doQueenMove(2, OFFSET(0, 2)); break;
		case 0xad: move = m_position.doQueenMove(2, OFFSET(0, 3)); break;
		case 0xae: move = m_position.doQueenMove(2, OFFSET(0, 4)); break;
		case 0xaf: move = m_position.doQueenMove(2, OFFSET(0, 5)); break;
		case 0xb0: move = m_position.doQueenMove(2, OFFSET(0, 6)); break;
		case 0xb1: move = m_position.doQueenMove(2, OFFSET(0, 7)); break;
		case 0xb2: move = m_position.doQueenMove(2, OFFSET(1, 0)); break;
		case 0xb3: move = m_position.doQueenMove(2, OFFSET(2, 0)); break;
		case 0xb4: move = m_position.doQueenMove(2, OFFSET(3, 0)); break;
		case 0xb5: move = m_position.doQueenMove(2, OFFSET(4, 0)); break;
		case 0xb6: move = m_position.doQueenMove(2, OFFSET(5, 0)); break;
		case 0xb7: move = m_position.doQueenMove(2, OFFSET(6, 0)); break;
		case 0xb8: move = m_position.doQueenMove(2, OFFSET(7, 0)); break;
		case 0xb9: move = m_position.doQueenMove(2, OFFSET(1, 1)); break;
		case 0xba: move = m_position.doQueenMove(2, OFFSET(2, 2)); break;
		case 0xbb: move = m_position.doQueenMove(2, OFFSET(3, 3)); break;
		case 0xbc: move = m_position.doQueenMove(2, OFFSET(4, 4)); break;
		case 0xbd: move = m_position.doQueenMove(2, OFFSET(5, 5)); break;
		case 0xbe: move = m_position.doQueenMove(2, OFFSET(6, 6)); break;
		case 0xbf: move = m_position.doQueenMove(2, OFFSET(7, 7)); break;
		case 0xc0: move = m_position.doQueenMove(2, OFFSET(1, 7)); break;
		case 0xc1: move = m_position.doQueenMove(2, OFFSET(2, 6)); break;
		case 0xc2: move = m_position.doQueenMove(2, OFFSET(3, 5)); break;
		case 0xc3: move = m_position.doQueenMove(2, OFFSET(4, 4)); break;
		case 0xc4: move = m_position.doQueenMove(2, OFFSET(5, 3)); break;
		case 0xc5: move = m_position.doQueenMove(2, OFFSET(6, 2)); break;
		case 0xc6: move = m_position.doQueenMove(2, OFFSET(7, 1)); break;

		// Third Rook ##########################
		case 0xc7: move = m_position.doRookMove(2, OFFSET(0, 1)); break;
		case 0xc8: move = m_position.doRookMove(2, OFFSET(0, 2)); break;
		case 0xc9: move = m_position.doRookMove(2, OFFSET(0, 3)); break;
		case 0xca: move = m_position.doRookMove(2, OFFSET(0, 4)); break;
		case 0xcb: move = m_position.doRookMove(2, OFFSET(0, 5)); break;
		case 0xcc: move = m_position.doRookMove(2, OFFSET(0, 6)); break;
		case 0xcd: move = m_position.doRookMove(2, OFFSET(0, 7)); break;
		case 0xce: move = m_position.doRookMove(2, OFFSET(1, 0)); break;
		case 0xcf: move = m_position.doRookMove(2, OFFSET(2, 0)); break;
		case 0xd0: move = m_position.doRookMove(2, OFFSET(3, 0)); break;
		case 0xd1: move = m_position.doRookMove(2, OFFSET(4, 0)); break;
		case 0xd2: move = m_position.doRookMove(2, OFFSET(5, 0)); break;
		case 0xd3: move = m_position.doRookMove(2, OFFSET(6, 0)); break;
		case 0xd4: move = m_position.doRookMove(2, OFFSET(7, 0)); break;

		// Third Bishop ########################
		case 0xd5: move = m_position.doBishopMove(2, OFFSET(1, 1)); break;
		case 0xd6: move = m_position.doBishopMove(2, OFFSET(2, 2)); break;
		case 0xd7: move = m_position.doBishopMove(2, OFFSET(3, 3)); break;
		case 0xd8: move = m_position.doBishopMove(2, OFFSET(4, 4)); break;
		case 0xd9: move = m_position.doBishopMove(2, OFFSET(5, 5)); break;
		case 0xda: move = m_position.doBishopMove(2, OFFSET(6, 6)); break;
		case 0xdb: move = m_position.doBishopMove(2, OFFSET(7, 7)); break;
		case 0xdc: move = m_position.doBishopMove(2, OFFSET(1, 7)); break;
		case 0xdd: move = m_position.doBishopMove(2, OFFSET(2, 6)); break;
		case 0xde: move = m_position.doBishopMove(2, OFFSET(3, 5)); break;
		case 0xdf: move = m_position.doBishopMove(2, OFFSET(4, 4)); break;
		case 0xe0: move = m_position.doBishopMove(2, OFFSET(5, 3)); break;
		case 0xe1: move = m_position.doBishopMove(2, OFFSET(6, 2)); break;
		case 0xe2: move = m_position.doBishopMove(2, OFFSET(7, 1)); break;

		// Third Knight ########################
		case 0xe3: move = m_position.doKnightMove(2, OFFSET(+2, +1)); break;
		case 0xe4: move = m_position.doKnightMove(2, OFFSET(+1, +2)); break;
		case 0xe5: move = m_position.doKnightMove(2, OFFSET(-1, +2)); break;
		case 0xe6: move = m_position.doKnightMove(2, OFFSET(-2, +1)); break;
		case 0xe7: move = m_position.doKnightMove(2, OFFSET(-2, -1)); break;
		case 0xe8: move = m_position.doKnightMove(2, OFFSET(-1, -2)); break;
		case 0xe9: move = m_position.doKnightMove(2, OFFSET(+1, -2)); break;
		case 0xea: move = m_position.doKnightMove(2, OFFSET(+2, -1)); break;

		// Multiple byte move ##################
		case 0xeb:
			{
				if (m_useCipher)
				{
					// Chess960 0xeb special move (CBase26 FUN_140212eb0 +
					// empirical fit over all 896 corpus occurrences,
					// 2026-08-16).  Params decode with the chess960 LUT and
					// the SAME count as the marker byte:
					//
					//   X1 = Chess960MoveNumberLookup[b1] - count
					//   X2 = Chess960MoveNumberLookup[b2] - count
					//
					// Chess960 uses 0xeb ONLY for castling and promotions:
					//
					//   castling:  (X1,X2) in { (4,16) O-O-O white,
					//			  (12,48) O-O white, (5,215) O-O-O black,
					//			  (13,247) O-O black }
					//   promotion: X1 = (piece<<4) | (toFile<<1) | color
					//              X2 = (fromFile<<3) | (color ? 0xC6 : 0x01)
					//              piece nibble: 0=Q, 1=R, 2=B, 3=N;
					//              color: 1=white, 0=black
					Byte b1 = m_gStrm.get();
					Byte b2 = m_gStrm.get();

					unsigned x1 = Byte(Chess960MoveNumberLookup[b1] - decodeCount);
					unsigned x2 = Byte(Chess960MoveNumberLookup[b2] - decodeCount);

					if ((x1 == 4 && x2 == 16) || (x1 == 12 && x2 == 48) ||
					    (x1 == 5 && x2 == 215) || (x1 == 13 && x2 == 247))
					{
						// Castling: destinations are fixed (Convention B);
						// the rook source comes from the position.
						bool kside = (x1 == 12 || x1 == 13);
						move = m_position.doCastling(Byte(kside ? +2 : -2));
					}
					else
					{
						// Promotion of a home-stretch pawn.  Squares are in
						// CBH numbering (file*8 + rank-1), matching the
						// standard 0xeb path and doMove()'s mapSquare().
						unsigned color = x1 & 1;      // 1 = white, 0 = black
						unsigned toFile = (x1 >> 1) & 7;
						unsigned fromFile = (x2 >> 3) & 7;
						Byte promo = Byte((x1 >> 4) + piece::Queen); // 0=Q,1=R,2=B,3=N

						move = m_position.doMove(
							Byte(fromFile * 8 + (color ? 6 : 1)),
							Byte(toFile * 8 + (color ? 7 : 0)),
							promo);
					}
				}
				else
				{
					unsigned word = ::MoveNumberLookup[Byte(m_gStrm.get() - decodeCount)] << 8;
					word |= ::MoveNumberLookup[Byte(m_gStrm.get() - decodeCount)];
					move = m_position.doMove(word & 63, (word >> 6) & 63, ((word >> 12) & 3) + piece::Queen);
				}
			}
			break;

		// Padding #############################
		case 0xec: return Token_Skip;

		// Unused ##############################
		case 0xed: // fallthru
		case 0xee: // fallthru
		case 0xef: // fallthru
		case 0xf0: // fallthru
		case 0xf1: // fallthru
		case 0xf2: // fallthru
		case 0xf3: // fallthru
		case 0xf4: // fallthru
		case 0xf5: // fallthru
		case 0xf6: // fallthru
		case 0xf7: // fallthru
		case 0xf8: // fallthru
		case 0xf9: // fallthru
		case 0xfa: // fallthru
		case 0xfb: // fallthru
		case 0xfc: // fallthru
		case 0xfd: return Token_Skip;

		// Push position #######################
		case 0xfe:
			if (!skipVariations)
				m_position.push();
			return Token_Push;

		// Pop position ########################
		case 0xff:
			// Symmetric with Push: only pop when variations are being
			// decoded.  In look-ahead (skipVariations) the position stack
			// must stay balanced with the look-ahead's own save/restore.
			if (!skipVariations && m_position.variationLevel())
				m_position.pop();
			return Token_Pop;

#undef OFFSET
	}

	return Token_Move;
}


unsigned
Decoder::decodeMoves(uint16_t* line, unsigned length, Board* startBoard)
{
	unsigned	count	= 0;
	Move		move;

	for (unsigned index = 0; index < length; )
	{
		switch (decodeMove(move, count, true))
		{
			case Token_Move:
				if (!startBoard)
				{
					line[index++] = move.index();
				}
				else if (startBoard->isEqualZHPosition(m_position.board()))
				{
					startBoard->setPlyNumber(m_position.board().plyNumber());
					startBoard = nullptr;
				}
				break;

			case Token_Pop:
				return index;
		}
	}

	return length;
}


void
Decoder::setupStartPosition(TagSet* tags)
{
	// Standard CBH start position: 28 bytes.
	// Chess960 CBH start position: 36 bytes (28 + 8-byte extension).
	// The 8-byte extension encodes castling-relevant squares:
	//   byte 0: white king square (CBH encoding, informational)
	//   byte 1: black king square
	//   byte 2: white short-castling rook square
	//   byte 3: white long-castling rook square
	//   byte 4: black short-castling rook square
	//   byte 5: black long-castling rook square
	//   byte 6-7: trailing bytes (likely checksum, not needed)
	// CBH squares: file*8 + (rank-1); convert to scidb via mapSquare().
	// Chess960 real ChessBase files have a 36-byte position block (28 + 8-byte extension).
	// scidb-produced Chess960 files have only a 28-byte block.
	// Use 36 bytes only if enough data is available.
	unsigned const posSize = (m_isChess960 && m_gStrm.remaining() >= 36) ? 36 : 28;
	m_useCipher = (posSize == 36);

	if (m_gStrm.remaining() < posSize)
		throw DecodingFailedException("corrupted data (insufficient bytes for start position: have %u, need %u)",
		                             m_gStrm.remaining(), posSize);

	BitStream bstrm(m_gStrm.data(), 28);  // Position::setup reads 224 bits = 28 bytes
	m_position.setup(bstrm, m_isChess960);

	if (m_isChess960 && posSize == 36)
	{
		// Set castling rook squares from the 8-byte extension.
		// Position::setup already set castling rights via the 1-arg form
		// (which scans for the rook). The 2-arg form here overrides with
		// the exact rook square from the ChessBase extension.
		unsigned char const* ext = m_gStrm.data() + 28;
		Board& board = m_position.board();

		auto cbhToScidb = [](unsigned char s) { return ((s & 7) << 3) | (s >> 3); };

		if (m_position.m_wshrt)
			board.setCastleShort(color::White, cbhToScidb(ext[2]));
		if (m_position.m_wlong)
			board.setCastleLong(color::White, cbhToScidb(ext[3]));
		if (m_position.m_bshrt)
			board.setCastleShort(color::Black, cbhToScidb(ext[4]));
		if (m_position.m_blong)
			board.setCastleLong(color::Black, cbhToScidb(ext[5]));
	}

	m_gStrm.skip(posSize);

	if (tags)
	{
		tags->set(tag::SetUp, "1");	// bad PGN design
		tags->set(tag::Fen, m_position.board().toFen(variant::Normal, Board::Shredder));
	}
}


void
Decoder::startDecoding(TagSet* tags)
{
	unsigned word = m_gStrm.uint32();

	if (word & 0x40000000)
	{
		setupStartPosition(tags);
	}
	else
	{
		m_position.setup();
	}
}


unsigned
Decoder::doDecoding(uint16_t* moves, unsigned length, Board& startBoard, bool useStartBoard)
{
	startDecoding();

	if (!useStartBoard)
		startBoard = m_position.board();
	else if (startBoard.isEqualZHPosition(m_position.board()))
		useStartBoard = false;

	if (!useStartBoard)
		return decodeMoves(moves, length, nullptr);
	
	Board board(startBoard);
	return decodeMoves(moves, length, &board);
}


db::Move
Decoder::findExactPosition(Board const& position, bool skipVariations)
{
	startDecoding();

	unsigned	count = 0;
	bool		found	= false;
	Move		move;

	if (m_position.board().isEqualPosition(position))
		found = true;

	while (true)
	{
		unsigned tag = decodeMove(move, count);

		if (found)
			return move;

		switch (tag)
		{
			case Token_Move:
				if (!move || !m_position.board().signature().isReachablePawns(position.signature()))
					return Move::invalid();
				if (m_position.board().isEqualPosition(position))
					found = true;
				break;

			case Token_Pop:
				if (skipVariations)
					return Move::invalid();
				break;
		}
	}

	return move;	// not reached
}

// vi:set ts=3 sw=3:
