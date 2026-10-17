// ======================================================================
// Author : $Author$
// Version: $Revision: 719 $
// Date   : $Date: 2013-04-19 12:40:59 -0400 (Fri, 19 Apr 2013) $
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
// Copyright: (C) 2013 Gregor Cramer
// Modified for Chesswiz, 2026; see docs/UPSTREAM.md
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

namespace cql {

inline uint64_t Designator::kings(db::color::ID color) const	{ return view().board.pieces[color].kings; }
inline uint64_t Designator::queens(db::color::ID color) const	{ return view().board.pieces[color].queens; }
inline uint64_t Designator::rooks(db::color::ID color) const	{ return view().board.pieces[color].rooks; }
inline uint64_t Designator::bishops(db::color::ID color) const	{ return view().board.pieces[color].bishops; }
inline uint64_t Designator::knights(db::color::ID color) const	{ return view().board.pieces[color].knights; }
inline uint64_t Designator::pawns(db::color::ID color) const	{ return view().board.pieces[color].pawns; }
inline uint64_t Designator::pieces(db::color::ID color) const	{ return view().board.pieces[color].any; }
inline uint64_t Designator::empty() const								{ return view().board.empty; }

inline bool Designator::match(db::Board const& board) const
{
	View v = view();
	return v.match(v.board, board);
}


inline unsigned Designator::count(db::Board const& board) const
{
	View v = view();
	return v.count(v.board, board);
}


inline uint64_t Designator::find(db::Board const& board) const
{
	View v = view();
	return v.find(v.board, board);
}


inline
unsigned
Designator::different(db::Board const& p1, db::Board const& p2) const
{
	View v = view();
	return v.diff(v.board, p1, p2);
}


inline
unsigned
Designator::same(db::Board const& p1, db::Board const& p2) const
{
	View v = view();
	return v.same(v.board, p1, p2);
}

} // namespace cql

// vi:set ts=3 sw=3:
