// ======================================================================
// Author : $Author$
// Version: $Revision: 1010 $
// Date   : $Date: 2014-10-18 11:12:33 -0400 (Sat, 18 Oct 2014) $
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

#include "m_bit_functions.h"

// NOTE: the shift count is masked to the width of the operand (as done by the
// x86 shift instructions) to make negative arguments (e.g. -1, used as a
// sentinel by some call sites) well defined instead of undefined behaviour.
// The result for the valid range (0..63) is unchanged; for negative counts
// this reproduces the previous x86-64 runtime result exactly.
inline constexpr uint64_t db::board::set1Bit(int s)	{ return uint64_t(1) << (s & 63); }
inline constexpr uint64_t db::board::set2Bit(int s)	{ return uint64_t(3) << (s & 63); }

inline uint64_t db::board::shiftDown(uint64_t m)		{ return m >> 8; }
inline uint64_t db::board::shift2Down(uint64_t m)		{ return m >> 16; }
inline uint64_t db::board::shiftUp(uint64_t m)			{ return m << 8; }
inline uint64_t db::board::shift2Up(uint64_t m)			{ return m << 16; }
inline uint64_t db::board::shiftUpLeft(uint64_t m)		{ return (m << 7) & ~FyleMaskH; }
inline uint64_t db::board::shiftUpRight(uint64_t m)	{ return (m << 9) & ~FyleMaskA; }
inline uint64_t db::board::shiftDownLeft(uint64_t m)	{ return (m >> 9) & ~FyleMaskH; }
inline uint64_t db::board::shiftDownRight(uint64_t m)	{ return (m >> 7) & ~FyleMaskA; }
inline uint64_t db::board::shiftLeft(uint64_t m)		{ return (m >> 1) & ~FyleMaskH; }
inline uint64_t db::board::shiftRight(uint64_t m)		{ return (m << 1) & ~FyleMaskA; }
inline uint64_t db::board::shift2Left(uint64_t m)		{ return (m >> 2) & ~(FyleMaskG | FyleMaskH); }
inline uint64_t db::board::shift2Right(uint64_t m)		{ return (m << 2) & ~(FyleMaskA | FyleMaskB); }

inline int db::board::lsb(uint8_t n)	{ return mstl::bf::lsb_index(n); }
inline int db::board::lsb(uint64_t n)	{ return mstl::bf::lsb_index(n); }

inline int db::board::msb(uint8_t n)	{ return mstl::bf::msb_index(n); }
inline int db::board::msb(uint64_t n)	{ return mstl::bf::msb_index(n); }

template <typename T> inline int db::board::count(T n) { return mstl::bf::count_bits(n); }


inline
int
db::board::lsbClear(uint8_t& n)
{
	int r = lsb(n);
	n &= ~(1 << r);
	return r;
}


inline
int
db::board::lsbClear(uint64_t& n)
{
	int r = lsb(n);
	n &= ~(uint64_t(1) << r);
	return r;
}


inline
int
db::board::msbClear(uint8_t& n)
{
	int r = msb(n);
	n &= ~(1 << r);
	return r;
}


inline
int
db::board::msbClear(uint64_t& n)
{
	int r = msb(n);
	n &= ~(uint64_t(1) << r);
	return r;
}


inline
uint64_t
db::board::allSquaresBetween(Square from, Square to)
{
	M_REQUIRE(from <= sq::h8);
	M_REQUIRE(to <= sq::h8);

	return Obstructed[from][to];
}

// vi:set ts=3 sw=3:
