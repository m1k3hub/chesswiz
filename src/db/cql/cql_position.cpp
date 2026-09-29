// ======================================================================
// Author : $Author$
// Version: $Revision: 976 $
// Date   : $Date: 2013-10-18 18:15:24 -0400 (Fri, 18 Oct 2013) $
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
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#include "cql_position.h"
#include "cql_relation.h"
#include "cql_designator.h"
#include "cql_piece_type_designator.h"
#include "cql_match.h"
#include "cql_match_board.h"
#include "cql_match_move.h"
#include "cql_match_info.h"

#include "db_board.h"
#include "db_board_base.h"

#include "m_auto_ptr.h"
#include "m_string.h"
#include "m_algorithm.h"
#include "m_type_traits.h"

#include <ctype.h>
#include <stdlib.h>
#include <map>

using namespace cql;
using namespace cql::error;
using namespace cql::transformation;
using namespace db;
using namespace db::color;


template <class Iterator>
inline
static void
deleteAll(Iterator first, Iterator last)
{
	for ( ; first != last; ++first)
		delete *first;
}


namespace {

typedef char const* (Position::*PosMeth)(Match& match, char const* s, error::Type& error);

struct PosPair
{
	PosPair(char const* s, PosMeth f) :keyword(s), func(f) {}

	bool operator<(mstl::string const& s) const { return keyword < s; }

	mstl::string	keyword;
	PosMeth			func;
};


struct Adaptor : public cql::board::Match
{
	Adaptor(cql::info::Match* match) :m_match(match) {}
	~Adaptor() { delete m_match; }

	bool match(GameInfo const& info, Board const& board, Variant variant, unsigned flags)
	{
		return m_match->match(info, variant, 0); // game number not required
	}

	cql::info::Match* m_match;
};

} // namespace


namespace mstl {

static inline
bool
operator<(mstl::string const& lhs, PosPair const& rhs)
{
	return lhs < rhs.keyword;
}

} // namespace mstl


namespace { // file-local: cql_match.cpp and cql_position.cpp both define logical::And/Or
namespace logical {

struct Match : virtual public cql::move::Match, virtual public cql::board::Match
{
	typedef mstl::vector<Position*> PositionList;
	typedef db::Board Board;
	typedef variant::Type Variant;

	~Match() { ::deleteAll(m_list.begin(), m_list.end()); }

	Position& pushBack()
	{
		m_list.push_back(new Position);
		return *m_list.back();
	}

	PositionList m_list;
};


struct And : public Match
{
	bool match(	GameInfo const& info,
					Board const& board,
					Variant variant,
					unsigned flags) override
	{
		PositionList::iterator i = m_list.begin();
		PositionList::iterator e = m_list.end();

		for ( ; i != e; ++i)
		{
			if (!(*i)->match(info, board, variant, flags))
				return false;
		}

		return true;
	}

	bool match(Board const& board, Move const& move, Variant variant) override
	{
		PositionList::iterator i = m_list.begin();
		PositionList::iterator e = m_list.end();

		for ( ; i != e; ++i)
		{
			if (!(*i)->match(board, move, variant))
				return false;
		}

		return true;
	}
};


struct Or : public Match
{
	bool match(	GameInfo const& info,
					Board const& board,
					Variant variant,
					unsigned flags) override
	{
		PositionList::iterator i = m_list.begin();
		PositionList::iterator e = m_list.end();

		for ( ; i != e; ++i)
		{
			if ((*i)->match(info, board, variant, flags))
				return true;
		}

		return false;
	}

	bool match(Board const& board, Move const& move, Variant variant) override
	{
		PositionList::iterator i = m_list.begin();
		PositionList::iterator e = m_list.end();

		for ( ; i != e; ++i)
		{
			if ((*i)->match(board, move, variant))
				return true;
		}

		return false;
	}
};

} // namespace logical
} // namespace


static bool
isDelim(char c)
{
	return isspace(c) || c == '\0' || c == '(' || c == ')' || c == ';';
}


static char const*
skipToDelim(char const* s)
{
	while (!isDelim(*s))
		++s;

	return s;
}


static char const*
skipSpaces(char const* s)
{
	while (isspace(*s))
		++s;

	if (*s == ';')
	{
		// skip comment
		while (*s != '\n' && *s != '\0')
			++s;

		while (isspace(*s))
			++s;
	}

	return s;
}


// "(position" -> the pointer after the keyword, where Position::parse
// takes over; Position::parse returns the pointer after its own ')'.
static char const*
openPosition(char const* s, error::Type& error)
{
	if (*s != '(')
	{
		error = error::Keyword_Position_Expected;
		return s;
	}

	char const* t = ::skipSpaces(s + 1);

	if (::strncmp(t, "position", 8) != 0 || ::isalnum(t[8]))
	{
		error = error::Keyword_Position_Expected;
		return s;
	}

	return t + 8;
}


// "((position ...) (position ...))": every position is appended to <list>;
// returns the pointer after the closing ')'.
template <class List>
static char const*
parsePositionList(List& list, Match& match, char const* s, error::Type& error)
{
	if (*s != '(')
	{
		error = error::Left_Parenthesis_Expected;
		return s;
	}

	s = ::skipSpaces(s + 1);

	do
	{
		s = ::openPosition(s, error);

		if (error != error::No_Error)
			return s;

		s = list.pushBack().parse(match, s, error);

		if (error != error::No_Error)
			return s;

		s = ::skipSpaces(s);
	}
	while (*s == '(');

	if (*s != ')')
	{
		error = error::Right_Parenthesis_Expected;
		return s;
	}

	return ::skipSpaces(s + 1);
}


static unsigned
lengthOfKeyword(char const* s)
{
	char const* t = s;

	while (isalpha(*t))
		++t;

	return t - s;
}


static char const*
parseSequence(cql::board::GappedSequence& seq, Match& match, char const* s, error::Type& error)
{
	return ::parsePositionList(seq, match, s, error);
}


static char const*
parseRange(char const* s, error::Type& error, float& lower, float& upper)
{
	char *e;

	lower = strtof(s, &e);

	if (s == e || !isDelim(*s))
	{
		error = Invalid_Range_Argument;
	}
	else
	{
		upper = strtof(s = skipSpaces(e), &e);

		if (s == e || !isDelim(*s))
			error = Invalid_Range_Argument;
	}

	return s;
}


Position::Position()
	:m_relation(0)
	,m_cutExpression(0)
	,m_designators(new cql::board::Designators)
	,m_state(0)
	,m_finalState(0)
	,m_includeMainline(true)
	,m_includeVariations(false)
	,m_not(false)
	,m_preceding(false)
	,m_matchCount(0)
	,m_minMatchCount(1)
	,m_maxMatchCount(1)
	,m_minMoveNumber(0)
	,m_maxMoveNumber(unsigned(-1))
	,m_transformations(0)
	,m_accumulate(false)
{
}


Position::~Position()
{
	delete m_designators;
	delete m_relation;
	::deleteAll(m_boardMatchList.begin(), m_boardMatchList.end());
	::deleteAll(m_moveMatchList.begin(), m_moveMatchList.end());
}


bool
Position::doMatch(GameInfo const& info, Board const& board, Variant variant, unsigned flags)
{
	if (m_cutExpression && m_cutExpression->match(info, board, variant, flags))
	{
		m_cutFunc();

		if (m_cutExpression->m_preceding)
			return false;
	}

	if (m_finalState)
	{
		if (!m_finalState->match(info, board, variant, flags))
			return m_not;
	}

	if (!m_designators->match(info, board, variant, flags))
		return m_not;

	{
		BoardMatchList::iterator i = m_boardMatchList.begin();
		BoardMatchList::iterator e = m_boardMatchList.end();

		for ( ; i != e; ++i)
		{
			if (!(*i)->match(info, board, variant, flags))
			{
				static_assert(
					(mstl::is_convertible<cql::board::GappedSequence, cql::board::Sequence>::value),
					"we have to check both, Sequence and GappedSequence");

				if (m_not && dynamic_cast<cql::board::GappedSequence const*>(*i))
					return false;

				return m_not;
			}
		}
	}

	{
		PositionList::iterator i = m_positionList.begin();
		PositionList::iterator e = m_positionList.end();

		for ( ; i != e; ++i)
		{
			if (!(*i)->match(info, board, variant, flags))
				return m_not;
		}
	}

	return !m_not;
}


bool
Position::doMatch(Board const& board, Move const& move, Variant variant)
{
	MoveMatchList::iterator i = m_moveMatchList.begin();
	MoveMatchList::iterator e = m_moveMatchList.end();

	for ( ; i != e; ++i)
	{
		if (!(*i)->match(board, move, variant))
			return m_not;
	}

	{
		PositionList::iterator i = m_positionList.begin();
		PositionList::iterator e = m_positionList.end();

		for ( ; i != e; ++i)
		{
			if (!(*i)->match(board, move, variant))
				return m_not;
		}
	}

	return !m_not;
}


// The position with the colours exchanged: ranks mirrored, white and black
// swapped, the other side to move. Built through FEN, which carries the
// castling rights and the en-passant square.
static void
swapCase(mstl::string& s)
{
	for (unsigned i = 0; i < s.size(); ++i)
	{
		if (::isupper(s[i]))
			s[i] = char(::tolower(s[i]));
		else if (::islower(s[i]))
			s[i] = char(::toupper(s[i]));
	}
}


static bool
flipColor(db::Board const& board, db::variant::Type variant, db::Board& result)
{
	mstl::string fen(board.toFen(variant));

	// the fields: placement, side to move, castling, en passant, the rest
	mstl::string field[5];
	unsigned n = 0;
	mstl::string::size_type start = 0;

	for (mstl::string::size_type i = 0; i <= fen.size() && n < 5; ++i)
	{
		if (i == fen.size() || (fen[i] == ' ' && n < 4))
		{
			field[n++].assign(fen, start, i - start);
			start = i + 1;
		}
	}

	if (n < 4)
		return false;

	// the ranks in reverse order (a holding makes more than eight: no flip)
	mstl::string ranks[8];
	unsigned k = 0;
	start = 0;

	for (mstl::string::size_type i = 0; i <= field[0].size(); ++i)
	{
		if (i == field[0].size() || field[0][i] == '/')
		{
			if (k == 8)
				return false;
			ranks[k++].assign(field[0], start, i - start);
			start = i + 1;
		}
	}

	if (k != 8)
		return false;

	mstl::string flipped;

	for (unsigned i = 0; i < 8; ++i)
	{
		if (i > 0)
			flipped += '/';
		flipped += ranks[7 - i];
	}

	::swapCase(flipped);
	::swapCase(field[2]);		// castling rights change hands

	if (field[3].size() == 2)	// the en-passant square moves to the other side
		field[3][1] = field[3][1] == '3' ? '6' : '3';

	flipped += ' ';
	flipped += field[1] == "w" ? "b" : "w";
	flipped += ' ';
	flipped += field[2];
	flipped += ' ';
	flipped += field[3];

	if (n == 5)
	{
		flipped += ' ';
		flipped += field[4];
	}

	return result.setup(flipped.c_str(), variant) != 0;
}


// <move> played on the colour-flipped board.
static bool
flipMove(db::Board const& flipped, db::Move const& move, db::Move& result)
{
	if (move.isPieceDrop() || move.isNull())
		return false;

	result = flipped.makeMove(
		sq::flipRank(sq::ID(move.from())),
		sq::flipRank(sq::ID(move.to())),
		move.isPromotion() ? move.promoted() : db::piece::Queen);
	return true;
}


// A permutation of the 64 squares. The piece on square s is moved to p.m[s].
// Spatial transformation keywords build a set of these; every spatial flip is
// a bijection, so it can be applied to the board instead of the pattern (a
// pattern D transformed by F matches board B iff D matches F(B)).
struct Perm
{
	Byte m[64];

	Perm()
	{
		for (unsigned i = 0; i < 64; ++i)
			m[i] = Byte(i);
	}

	bool isIdentity() const
	{
		for (unsigned i = 0; i < 64; ++i)
		{
			if (m[i] != Byte(i))
				return false;
		}
		return true;
	}

	// apply *this first, then <other>
	Perm compose(Perm const& other) const
	{
		Perm r;
		for (unsigned i = 0; i < 64; ++i)
			r.m[i] = other.m[m[i]];
		return r;
	}
};


static unsigned
permRankMirror(unsigned sq)
{
	return sq::make(sq::fyle(sq), sq::flipRank(sq::rank(sq)));
}


static unsigned
permFileMirror(unsigned sq)
{
	return sq::make(sq::flipFyle(sq::fyle(sq)), sq::rank(sq));
}


static unsigned
permMainDiagonal(unsigned sq)
{
	return sq::make(sq::rank(sq), sq::fyle(sq));
}


static unsigned
permAntiDiagonal(unsigned sq)
{
	return sq::make(sq::flipRank(sq::rank(sq)), sq::flipFyle(sq::fyle(sq)));
}


typedef unsigned (*SquareFunc)(unsigned);


static Perm
makePerm(SquareFunc func)
{
	Perm p;
	for (unsigned i = 0; i < 64; ++i)
		p.m[i] = Byte(func(i));
	return p;
}


static bool
samePerm(Perm const& a, Perm const& b)
{
	for (unsigned i = 0; i < 64; ++i)
	{
		if (a.m[i] != b.m[i])
			return false;
	}
	return true;
}


// The transformation set of the spatial flip keywords: identity is always
// included, and the reflections named by the bits generate the rest by
// composition (the four reflections generate the eight-element dihedral
// group, so :flip/:flipdihedral yields all eight).
static void
collectFlips(uint64_t transformations, mstl::vector<Perm>& perms)
{
	perms.clear();
	perms.push_back(Perm());

	mstl::vector<Perm> generators;

	if (transformations & Flip_Main_Diagonal)	generators.push_back(makePerm(::permMainDiagonal));
	if (transformations & Flip_Off_Diagonal)	generators.push_back(makePerm(::permAntiDiagonal));
	if (transformations & Flip_Vertical)		generators.push_back(makePerm(::permFileMirror));
	if (transformations & Flip_Horizontal)		generators.push_back(makePerm(::permRankMirror));

	for (unsigned i = 0; i < perms.size(); ++i)
	{
		for (unsigned j = 0; j < generators.size(); ++j)
		{
			Perm c = perms[i].compose(generators[j]);
			bool found = false;

			for (unsigned k = 0; k < perms.size(); ++k)
			{
				if (::samePerm(c, perms[k]))
				{
					found = true;
					break;
				}
			}

			if (!found)
				perms.push_back(c);
		}
	}
}


// Applies <p> (and optional colour/side swaps) to <board> through the FEN,
// which carries the castling rights and the en-passant square. Castling and
// en passant are dropped for a non-trivial permutation: after a reflection
// they no longer denote meaningful positions of king and rook.
static bool
transformBoard(	db::Board const& board,
					db::variant::Type variant,
					Perm const& p,
					bool swapColor,
					bool swapSide,
					db::Board& result)
{
	mstl::string fen(board.toFen(variant));

	mstl::string field[5];
	unsigned n = 0;
	mstl::string::size_type start = 0;

	for (mstl::string::size_type i = 0; i <= fen.size() && n < 5; ++i)
	{
		if (i == fen.size() || (fen[i] == ' ' && n < 4))
		{
			field[n++].assign(fen, start, i - start);
			start = i + 1;
		}
	}

	if (n < 4)
		return false;

	char grid[64];
	for (unsigned i = 0; i < 64; ++i)
		grid[i] = 0;

	int rank = 7;
	int fyle = 0;

	for (mstl::string::size_type i = 0; i < field[0].size(); ++i)
	{
		char c = field[0][i];

		if (c == '/')
		{
			--rank;
			fyle = 0;
		}
		else if ('1' <= c && c <= '9')
		{
			fyle += c - '0';
		}
		else
		{
			if (rank < 0 || rank > 7 || fyle < 0 || fyle > 7)
				return false;
			grid[rank*8 + fyle] = c;
			++fyle;
		}
	}

	char transformed[64];
	for (unsigned i = 0; i < 64; ++i)
		transformed[i] = 0;

	for (unsigned i = 0; i < 64; ++i)
	{
		if (grid[i])
		{
			char c = grid[i];

			if (swapColor)
				c = ::isupper(c) ? char(::tolower(c)) : char(::toupper(c));

			transformed[p.m[i]] = c;
		}
	}

	mstl::string out;

	for (int r = 7; r >= 0; --r)
	{
		int empty = 0;

		for (int f = 0; f < 8; ++f)
		{
			char c = transformed[r*8 + f];

			if (c)
			{
				if (empty)
				{
					out += char('0' + empty);
					empty = 0;
				}
				out += c;
			}
			else
			{
				++empty;
			}
		}

		if (empty)
			out += char('0' + empty);
		if (r > 0)
			out += '/';
	}

	out += ' ';
	out += swapSide ? (field[1] == "w" ? "b" : "w") : (field[1] == "w" ? "w" : "b");
	out += ' ';
	out += (p.isIdentity() || swapColor) ? field[2] : "-";
	out += ' ';
	out += (p.isIdentity() || swapColor) ? field[3] : "-";

	if (n == 5)
	{
		out += ' ';
		out += field[4];
	}

	return result.setup(out.c_str(), variant) != 0;
}


// <move> played on the board transformed by <p>.
static bool
permMove(db::Board const& transformed, db::Move const& move, Perm const& p, db::Move& result)
{
	if (move.isPieceDrop() || move.isNull())
		return false;

	result = transformed.makeMove(
		sq::ID(p.m[move.from()]),
		sq::ID(p.m[move.to()]),
		move.isPromotion() ? move.promoted() : db::piece::Queen);
	return true;
}


// A translation. Unlike the flips this is not a bijection (edges smear), so
// it cannot be applied to the board; the active shift is applied to the
// designators of the position list instead (see Designator::view).
struct ShiftOffset
{
	int fyle;
	int rank;

	ShiftOffset(int f = 0, int r = 0) :fyle(f), rank(r) {}
};


static void
collectShifts(uint64_t transformations, mstl::vector<ShiftOffset>& shifts)
{
	shifts.clear();
	shifts.push_back(ShiftOffset());

	uint64_t t = transformations & Shift;

	if (t == 0)
		return;

	// the horizontal and the vertical families together generate every
	// translation, and :shift names all four families
	if ((t & Shift_Both) == Shift_Both || t == Shift)
	{
		for (int f = -7; f <= 7; ++f)
		{
			for (int r = -7; r <= 7; ++r)
			{
				if (f || r)
					shifts.push_back(ShiftOffset(f, r));
			}
		}
		return;
	}

	if (t & Shift_Horizontal)
	{
		for (int f = -7; f <= 7; ++f)
			if (f) shifts.push_back(ShiftOffset(f, 0));
	}
	if (t & Shift_Vertical)
	{
		for (int r = -7; r <= 7; ++r)
			if (r) shifts.push_back(ShiftOffset(0, r));
	}
	if (t & Shift_Main_Diagonal)
	{
		for (int d = -7; d <= 7; ++d)
			if (d) shifts.push_back(ShiftOffset(d, d));
	}
	if (t & Shift_Off_Diagonal)
	{
		for (int d = -7; d <= 7; ++d)
			if (d) shifts.push_back(ShiftOffset(-d, d));
	}
}


// The accumulator extension (CQL-S). The map belongs to the board position
// currently being matched: it is cleared when a new position is reached and is
// shared by the nested position lists of that position.
namespace {

std::map<std::string, unsigned> g_accumulators;
unsigned g_accumulatorDepth = 0;

} // namespace


bool
Position::match(GameInfo const& info, Board const& board, Variant variant, unsigned flags)
{
	// :variations includes the main line and the variations, :variationsonly
	// only the variations; a position list without either skips variations.
	if ((flags & flags::IsInsideVariation) ? !m_includeVariations : !m_includeMainline)
		return m_not;

	bool spatial = m_transformations
		& (Flip | Flip_Horizontal | Flip_Vertical | Flip_Diagonal | Flip_Off_Diagonal);
	bool shift = (m_transformations & Shift) != 0;
	bool colorFlip = m_transformations & Flip_Color;

	mstl::vector<Perm> perms;
	if (spatial)
		::collectFlips(m_transformations, perms);
	else
		perms.push_back(Perm());

	mstl::vector<ShiftOffset> shifts;
	if (shift)
		::collectShifts(m_transformations, shifts);
	else
		shifts.push_back(ShiftOffset());

	// a surrounding position list may have its own shift transformation: the
	// transforms compose, so add this list's shift to the active one
	int outerFyle = cql::activeShiftFyle();
	int outerRank = cql::activeShiftRank();

	// the accumulator map is cleared when a new position is reached; nested
	// position lists share the map of their surrounding list
	if (g_accumulatorDepth == 0)
		g_accumulators.clear();
	++g_accumulatorDepth;

	if (!m_resetName.empty())
		g_accumulators[m_resetName] = 0;

	bool			needCount = m_accumulate || !m_sumRanges.empty();
	unsigned		matches = 0;

	for (unsigned i = 0; i < perms.size(); ++i)
	{
		db::Board transformed;
		db::Board const* src = &board;

		if (!perms[i].isIdentity())
		{
			if (!::transformBoard(board, variant, perms[i], false, false, transformed))
				continue;
			src = &transformed;
		}

		for (unsigned j = 0; j < shifts.size(); ++j)
		{
			cql::setActiveShift(outerFyle + shifts[j].fyle, outerRank + shifts[j].rank);

			bool m = doMatch(info, *src, variant, flags);

			if (!m && colorFlip)
			{
				db::Board flipped;

				if (::flipColor(*src, variant, flipped))
					m = doMatch(info, flipped, variant, flags);
			}

			cql::clearActiveShift();

			if (m && ++matches == 1 && !needCount)
				break;
		}

		if (matches && !needCount)
			break;
	}

	if (m_accumulate)
		g_accumulators[m_accumulateName] += matches;

	bool sumsOk = true;

	for (unsigned k = 0; k < m_sumRanges.size(); ++k)
	{
		unsigned value = g_accumulators[m_sumRanges[k].name];

		if (value < m_sumRanges[k].min || value > m_sumRanges[k].max)
		{
			sumsOk = false;
			break;
		}
	}

	bool match = matches > 0 && sumsOk;

	--g_accumulatorDepth;
	cql::setActiveShift(outerFyle, outerRank);

	if (match)
		++m_matchCount;

	if (m_relation && !m_relation->match(board, false)) // XXX set parameter insideVariation
		return m_not;

	if (flags & flags::IsFinalPosition)
		return m_minMatchCount <= m_matchCount && m_matchCount <= m_maxMatchCount;

	return m_matchCount >= m_maxMatchCount;
}


bool
Position::match(Board const& board, Move const& move, Variant variant)
{
	unsigned moveNumber = board.moveNumber();

	if (m_minMoveNumber > moveNumber || moveNumber > m_maxMoveNumber)
		return m_not;

	bool spatial = m_transformations
		& (Flip | Flip_Horizontal | Flip_Vertical | Flip_Diagonal | Flip_Off_Diagonal);
	bool shift = (m_transformations & Shift) != 0;
	bool colorFlip = m_transformations & Flip_Color;

	if (!spatial && !shift && !colorFlip)
		return doMatch(board, move, variant);

	mstl::vector<Perm> perms;
	if (spatial)
		::collectFlips(m_transformations, perms);
	else
		perms.push_back(Perm());

	mstl::vector<ShiftOffset> shifts;
	if (shift)
		::collectShifts(m_transformations, shifts);
	else
		shifts.push_back(ShiftOffset());

	int outerFyle = cql::activeShiftFyle();
	int outerRank = cql::activeShiftRank();

	for (unsigned i = 0; i < perms.size(); ++i)
	{
		db::Board transformed;
		db::Move transformedMove;
		db::Board const* src = &board;
		db::Move const* mv = &move;

		if (!perms[i].isIdentity())
		{
			if (!::transformBoard(board, variant, perms[i], false, false, transformed))
				continue;
			if (!::permMove(transformed, move, perms[i], transformedMove))
				continue;
			src = &transformed;
			mv = &transformedMove;
		}

		for (unsigned j = 0; j < shifts.size(); ++j)
		{
			int fyle = outerFyle + shifts[j].fyle;
			int rank = outerRank + shifts[j].rank;

			cql::setActiveShift(fyle, rank);
			bool match = doMatch(*src, *mv, variant);
			cql::clearActiveShift();

			if (match)
				return true;

			if (colorFlip)
			{
				db::Board flipped;
				db::Move flippedMove;

				if (::flipColor(*src, variant, flipped) && ::flipMove(flipped, *mv, flippedMove))
				{
					cql::setActiveShift(fyle, rank);
					match = doMatch(flipped, flippedMove, variant);
					cql::clearActiveShift();

					if (match)
						return true;
				}
			}
		}
	}

	cql::setActiveShift(outerFyle, outerRank);

	return false;
}


char const*
Position::adopt(Match& match, char const* s, Error& error)
{
	if (error == No_Error)
	{
		M_ASSERT(!match.m_matchGameInfoList.empty());
		m_boardMatchList.push_back(new Adaptor(match.m_matchGameInfoList.back()));
		match.m_matchGameInfoList.erase(match.m_matchGameInfoList.end() - 1);
	}

	return s;
}


void
Position::toggleNot()
{
	m_not = !m_not;
}


char const*
Position::parseAccumulate(Match& match, char const* s, Error& error)
{
	s = ::skipSpaces(s);

	char const* t = ::skipToDelim(s);

	if (t == s)
	{
		error = Missing_Parameter;
		return s;
	}

	m_accumulateName.assign(s, t - s);
	m_accumulate = true;
	match.m_sections |= Match::Section_Positions;
	return t;
}


char const*
Position::parseAnd(Match& match, char const* s, Error& error)
{
	mstl::auto_ptr<logical::And> list(new logical::And);
	s = ::parsePositionList(*list, match, s, error);

	if (error == No_Error)
		m_boardMatchList.push_back(list.release());

	return s;
}


char const*
Position::parseAttackCount(Match& match, char const* s, Error& error)
{
	Designator fst;
	Designator snd;

	s = fst.parse(s, error);

	if (error != No_Error)
		return s;

	s = snd.parse(s, error);

	if (error != No_Error)
		return s;

	if (!::isdigit(*s))
	{
		error = Positive_Integer_Expected;
		return s;
	}

	char* e;
	unsigned min = ::strtoul(s, &e, 10);
	s = ::skipSpaces(e);

	unsigned max = min;

	if (::isdigit(*s))
	{
		max = ::strtoul(s, &e, 10);
		s = e;
	}

	m_boardMatchList.push_back(new cql::board::AttackCount(fst, snd, min, max));
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseBlackCannotWin(Match& match, char const* s, Error& error)
{
	m_boardMatchList.push_back(new cql::board::CannotWin(color::Black));
	match.m_isStandard = false;
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseBlackElo(Match& match, char const* s, Error& error)
{
	return adopt(match, match.parseBlackElo(s, error), error);
}


char const*
Position::parseBlackRating(Match& match, char const* s, Error& error)
{
	return adopt(match, match.parseBlackRating(s, error), error);
}


char const*
Position::parseBlackToMove(Match& match, char const* s, Error& error)
{
	m_boardMatchList.push_back(new cql::board::ToMove(Black));
	return s;
}


char const*
Position::parseCastling(Match& match, char const* s, Error& error)
{
	PieceTypeDesignator designator;
	char const* t = designator.parse(s, error);

	if (error == No_Error)
	{
		PieceTypeDesignator::Pieces pieces = designator.pieces();

		pieces.reset(cql::piece::WK);
		pieces.reset(cql::piece::BK);
		pieces.reset(cql::piece::WQ);
		pieces.reset(cql::piece::BQ);

		if (pieces.count() > 0)
		{
			error = Invalid_Designator;
		}
		else
		{
			m_boardMatchList.push_back(new cql::board::Castling(designator));
			s = t;
		}
	}

	match.m_isStandard = false;
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseCut(Match& match, char const* s, Error& error)
{
	char const* t = ::skipSpaces(s);

	if (*t == '(')
	{
		mstl::auto_ptr<Position> pos(new Position);

		s = pos->parse(match, t, error);
		pos->m_cutFunc = CutFunc(&Match::cut, &match);

		if (error == No_Error)
			m_positionList.push_back(pos.release());

	}
	else
	{
		m_cutFunc = CutFunc(&Match::cut, &match);
	}

	match.m_isStandard = false;
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseIsCastling(Match& match, char const* s, Error& error)
{
	m_moveMatchList.push_back(new cql::move::IsCastling);
	match.m_isStandard = false;
	match.m_sections |= Match::Section_Moves;
	return s;
}


char const*
Position::parseCheck(Match& match, char const* s, Error& error)
{
	m_boardMatchList.push_back(new cql::board::Check);
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseCheckCount(Match& match, char const* s, Error& error)
{
	s = ::skipSpaces(s);

	if (isdigit(*s))
	{
		char* e;
		unsigned count = ::strtoul(s, &e, 10);

		if (count > 3)
			error = Integer_Out_Of_Range;
		else
			m_boardMatchList.push_back(new cql::board::CheckCount(count));
	}
	else if (*s == '+')
	{
		char* e;
		unsigned wcount = ::strtoul(s, &e, 10);

		if (wcount > 3)
		{
			error = Integer_Out_Of_Range;
		}
		else
		{
			s = e;

			if (*s == '+')
			{
				unsigned bcount = ::strtoul(s, &e, 10);

				if (bcount > 3)
				{
					error = Integer_Out_Of_Range;
				}
				else
				{
					s = e;
					m_boardMatchList.push_back(new cql::board::CheckCount(wcount, bcount));
				}
			}
			else
			{
				error = Positive_Integer_Expected;
			}
		}
	}
	else
	{
		error = Positive_Integer_Expected;
	}

	match.m_isStandard = false;
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseContactCheck(Match& match, char const* s, Error& error)
{
	m_boardMatchList.push_back(new cql::board::ContactCheck);
	match.m_isStandard = false;
	return s;
}


char const*
Position::parseDoubleCheck(Match& match, char const* s, Error& error)
{
	if (m_state == 0)
	{
		m_state = new cql::board::State;
		m_boardMatchList.push_back(m_state);
	}

	m_state->add(Board::DoubleCheck);
	match.m_isStandard = false;
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseElo(Match& match, char const* s, Error& error)
{
	return adopt(match, match.parseElo(s, error), error);
}


char const*
Position::parseEndGame(Match& match, char const* s, Error& error)
{
	m_boardMatchList.push_back(new cql::board::EndGame);
	match.m_isStandard = false;
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseEndmost(Match& match, char const* s, Error& error)
{
	error = Not_Implemented; // TODO
	return s;
}


char const*
Position::parseEnPassant(Match& match, char const* s, Error& error)
{
	m_moveMatchList.push_back(new cql::move::EnPassant);
	match.m_sections |= Match::Section_Moves;
	return s;
}


char const*
Position::parseEvaluation(Match& match, char const* s, Error& error)
{
	char const *t = ::skipToDelim(s);
	mstl::string mode(s, t);

	if (mode != "depth" && mode != "movetime")
	{
		error = Invalid_Evaluation_Mode;
		return s;
	}

	s = ::skipSpaces(t);

	if (!::isdigit(*s))
	{
		error = Positive_Integer_Expected;
		return s;
	}

	char* e;
	unsigned n = ::strtoul(s, &e, 10);

	if (n == 0)
	{
		error = Integer_Out_Of_Range;
		return s;
	}

	cql::board::Evaluation::Mode emode = mode == "depth" ? cql::Engine::Depth : cql::Engine::MoveTime;

	s = ::skipSpaces(s);

	if (::isdigit(*s) || *s == '.')
	{
		float lower, upper;
		s = ::parseRange(s, error, lower, upper);

		if (error != No_Error)
			return s;

		s = ::skipSpaces(s);
		t = ::skipToDelim(s);
		mstl::string stm(s, t);

		if (stm != "sidetomove" && stm != "absolute")
		{
			error = Invalid_Evaluation_View;
			return s;
		}

		s = t;

		cql::board::Evaluation::View view;

		if (stm == "sidetomove")
			view = cql::board::Evaluation::SideToMove;
		else
			view = cql::board::Evaluation::Absolute;

		m_boardMatchList.push_back(
			new cql::board::Evaluation(Engine::Score, emode, n, lower, upper, view));
	}
	else if (::strncmp(s, "mate", 4) == 0 && ::isDelim(s[4]))
	{
		m_boardMatchList.push_back(new cql::board::Evaluation(Engine::Mate, emode, n));
	}

	match.m_isStandard = false;
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseExclude(Match& match, char const* s, Error& error)
{
	error = Not_Implemented; // TODO
	match.m_isStandard = false;
	return s;
}


char const*
Position::parseExchangeEvaluation(Match& match, char const* s, Error& error)
{
	int min, max;
	s = parseSignedRange(s, error, min, max);
	if (error == No_Error)
		m_moveMatchList.push_back(new cql::move::ExchangeEvaluation(min, max));
	match.m_isStandard = false;
	match.m_sections |= Match::Section_Moves;
	return s;
}


char const*
Position::parseFen(Match& match, char const* s, Error& error)
{
	char const* t = ::skipToDelim(s);
	Variant variant = variant::Normal;

	mstl::string fen(s, t);
	Board board;

	if (	board.setup(s, variant::ThreeCheck)
		&& (board.checksGiven(White) > 0 || board.checksGiven(Black) > 0))
	{
		variant = variant::ThreeCheck;
	}
	else if (	board.setup(s, variant::Crazyhouse)
				&& (board.holding(White).total() + board.holding(Black).total() > 0))
	{
		variant = variant::Crazyhouse;
	}
	else if (!Board::isValidFen(s, variant::Normal) && Board::isValidFen(s, variant::Suicide))
	{
		variant = variant::Suicide;
	}

	if (Board::isValidFen(s, variant))
	{
		char const* p = board.setup(fen, variant);

		if (p == fen.end())
		{
			m_boardMatchList.push_back(new cql::board::Fen(board));
			s = t;
		}
		else
		{
			error = Invalid_Fen;
		}
	}
	else
	{
		error = Invalid_Fen;
	}

	match.m_isStandard = false;
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseFiftyMoveRule(Match& match, char const* s, Error& error)
{
	m_boardMatchList.push_back(new cql::board::FiftyMoveRule);
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseFlipColor(Match& match, char const* s, Error& error)
{
	m_transformations |= Flip_Color;
	return s;
}


char const*
Position::parseFlipDiagonal(Match& match, char const* s, Error& error)
{
	m_transformations |= Flip_Diagonal;
	return s;
}


char const*
Position::parseFlipDihedral(Match& match, char const* s, Error& error)
{
	m_transformations |= Flip;
	return s;
}


char const*
Position::parseFlipHorizontal(Match& match, char const* s, Error& error)
{
	m_transformations |= Flip_Horizontal;
	return s;
}


char const*
Position::parseFlipOffDiagonal(Match& match, char const* s, Error& error)
{
	m_transformations |= Flip_Off_Diagonal;
	return s;
}


char const*
Position::parseFlipVertical(Match& match, char const* s, Error& error)
{
	m_transformations |= Flip_Vertical;
	return s;
}


char const*
Position::parseFollowing(Match& match, char const* s, Error& error)
{
	error = Not_Implemented; // TODO
	return s;
}


char const*
Position::parseGameIsOver(Match& match, char const* s, Error& error)
{
	if (m_state == 0)
	{
		m_state = new cql::board::State;
		m_boardMatchList.push_back(m_state);
	}

	m_state->add(Board::Checkmate | Board::ThreeChecks | Board::Stalemate | Board::Losing);
	m_boardMatchList.push_back(new cql::board::MatingMaterial(true));
	match.m_isStandard = false;
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseGappedSequence(Match& match, char const* s, Error& error)
{
	mstl::auto_ptr<cql::board::GappedSequence> seq(new cql::board::GappedSequence);
	s = ::parseSequence(*seq, match, s, error);
	if (error == No_Error)
		m_boardMatchList.push_back(seq.release());
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseHalfmoveClockLimit(Match& match, char const* s, Error& error)
{
	s = ::skipSpaces(s);

	if (::isdigit(*s))
	{
		char* e;
		unsigned limit = ::strtoul(s, &e, 10);

		if (limit == 0)
		{
			error = Integer_Out_Of_Range;
		}
		else
		{
			s = e;
			m_boardMatchList.push_back(new cql::board::HalfmoveClockLimit(limit));
		}
	}
	else
	{
		error = Positive_Integer_Expected;
	}

	match.m_isStandard = false;
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseInitial(Match& match, char const* s, Error& error)
{
	match.setInitial();
	return s;
}


char const*
Position::parseInside(Match& match, char const* s, Error& error)
{
	error = Not_Implemented; // TODO
	match.m_isStandard = false;
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseLosing(Match& match, char const* s, Error& error)
{
	if (m_finalState == 0)
		m_finalState = new cql::board::State;

	m_finalState->add(Board::Losing);
	match.m_isStandard = false;
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseMarkAll(Match& match, char const* s, Error& error)
{
	return s; // ignore
}


char const*
Position::parseMatchCount(Match& match, char const* s, Error& error)
{
	return parseUnsignedRange(s, error, m_minMatchCount, m_maxMatchCount);
}


char const*
Position::parseMate(Match& match, char const* s, Error& error)
{
	if (m_finalState == 0)
		m_finalState = new cql::board::State;

	m_finalState->add(Board::Checkmate);
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseMatingMaterial(Match& match, char const* s, Error& error)
{
	m_boardMatchList.push_back(new cql::board::MatingMaterial(false));
	match.m_isStandard = false;
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseMaxSwapEvaluation(Match& match, char const* s, Error& error)
{
	Designator from;
	s = from.parse(s, error);

	if (error == No_Error)
	{
		Designator to;
		s = to.parse(s, error);

		if (error == No_Error)
		{
			int min, max;
			s = parseSignedRange(s, error, min, max);

			if (error == No_Error)
				m_boardMatchList.push_back(new cql::board::MaxSwapEvaluation(from, to, min, max));
		}
	}

	match.m_isStandard = false;
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseMoveEvaluation(Match& match, char const* s, Error& error)
{
	Designator from, to;

	s = from.parse(s, error);

	if (error != No_Error)
		return s;

	s = to.parse(::skipSpaces(s), error);

	if (error != No_Error)
		return s;

	char const *t = ::skipToDelim(::skipSpaces(s));
	mstl::string mode(s, t);

	if (mode != "depth" && mode != "movetime")
	{
		error = Invalid_Evaluation_Mode;
		return s;
	}

	s = ::skipSpaces(t);

	if (!::isdigit(*s))
	{
		error = Positive_Integer_Expected;
		return s;
	}

	char* e;
	unsigned n = ::strtoul(s, &e, 10);

	if (n == 0)
	{
		error = Integer_Out_Of_Range;
		return s;
	}

	float lower, upper;
	s = ::parseRange(s, error, lower, upper);

	if (error != No_Error)
		return s;

	s = ::skipSpaces(s);
	t = ::skipToDelim(s);
	mstl::string stm(s, t);

	if (stm != "sidetomove" && stm != "absolute")
	{
		error = Invalid_Evaluation_View;
		return s;
	}

	s = t;

	cql::move::MoveEvaluation::Mode emode;
	cql::move::MoveEvaluation::View view;

	if (mode == "depth")
		emode = cql::Engine::Depth;
	else
		emode = cql::Engine::MoveTime;

	if (stm == "sidetomove")
		view = cql::move::MoveEvaluation::SideToMove;
	else
		view = cql::move::MoveEvaluation::Absolute;

	m_moveMatchList.push_back(new cql::move::MoveEvaluation(emode, n, from, to, lower, upper, view));

	match.m_isStandard = false;
	match.m_sections |= Match::Section_Moves;
	return s;
}


char const*
Position::parseMoveFrom(Match& match, char const* s, Error& error)
{
	Designator designator;
	s = designator.parse(s, error);
	if (error == No_Error)
		m_moveMatchList.push_back(new cql::move::MoveFrom(designator));
	match.m_sections |= Match::Section_Moves;
	return s;
}


char const*
Position::parseMoveNumber(Match& match, char const* s, Error& error)
{
	return parseUnsignedRange(s, error, m_minMoveNumber, m_maxMoveNumber);
}


char const*
Position::parseMoveTo(Match& match, char const* s, Error& error)
{
	Designator designator;
	s = designator.parse(s, error);
	if (error == No_Error)
		m_moveMatchList.push_back(new cql::move::MoveTo(designator));
	match.m_sections |= Match::Section_Moves;
	return s;
}


char const*
Position::parseNoAnnotate(Match& match, char const* s, Error& error)
{
	return s; // nothing to do
}


char const*
Position::parseNoCastling(Match& match, char const* s, Error& error)
{
	m_moveMatchList.push_back(new cql::move::NoCastling);
	match.m_isStandard = false;
	match.m_sections |= Match::Section_Moves;
	return s;
}


char const*
Position::parseNoCheck(Match& match, char const* s, Error& error)
{
	m_boardMatchList.push_back(new cql::board::NoCheck);
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseNoContactCheck(Match& match, char const* s, Error& error)
{
	m_boardMatchList.push_back(new cql::board::NoContactCheck);
	match.m_isStandard = false;
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseNoDoubleCheck(Match& match, char const* s, Error& error)
{
	if (m_state == 0)
	{
		m_state = new cql::board::State;
		m_boardMatchList.push_back(m_state);
	}

	m_state->sub(Board::DoubleCheck);
	match.m_isStandard = false;
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseNoEndGame(Match& match, char const* s, Error& error)
{
	m_boardMatchList.push_back(new cql::board::NoEndGame);
	match.m_isStandard = false;
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseNoEnpassant(Match& match, char const* s, Error& error)
{
	m_moveMatchList.push_back(new cql::move::NoEnPassant);
	match.m_isStandard = false;
	match.m_sections |= Match::Section_Moves;
	return s;
}


char const*
Position::parseNoMate(Match& match, char const* s, Error& error)
{
	if (m_finalState == 0)
		m_finalState = new cql::board::State;

	m_finalState->sub(Board::Checkmate);
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseNoMatingMaterial(Match& match, char const* s, Error& error)
{
	m_boardMatchList.push_back(new cql::board::MatingMaterial(true));
	match.m_isStandard = false;
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseNoStalemate(Match& match, char const* s, Error& error)
{
	if (m_finalState == 0)
		m_finalState = new cql::board::State;

	m_finalState->sub(Board::Stalemate);
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseNot(Match& match, char const* s, Error& error)
{
	char const* t = ::skipSpaces(s);

	if (*t == '(')
	{
		mstl::auto_ptr<Position> pos(new Position);

		s = pos->parse(match, t, error);
		pos->toggleNot();

		if (error == No_Error)
			m_positionList.push_back(pos.release());

		match.m_isStandard = false;
	}
	else
	{
		m_not = !m_not;
	}

	return s;
}


char const*
Position::parseOr(Match& match, char const* s, Error& error)
{
	mstl::auto_ptr<logical::Or> list(new logical::Or);
	s = ::parsePositionList(*list, match, s, error);

	if (error == No_Error)
		m_boardMatchList.push_back(list.release());

	return s;
}


char const*
Position::parsePieceCount(Match& match, char const* s, Error& error)
{
	Designator designator;

	s = designator.parse(s, error);

	if (error == No_Error)
	{
		unsigned min(0), max(0); // prevent compiler warnings
		s = parseUnsignedRange(s, error, min, max);
		m_boardMatchList.push_back(new cql::board::PieceCount(designator, min, max));
	}

	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parsePieceDrop(Match& match, char const* s, Error& error)
{
	Designator designator;
	s = designator.parse(s, error);
	if (error == No_Error)
		m_moveMatchList.push_back(new cql::move::PieceDrop(designator));
	match.m_isStandard = false;
	match.m_sections |= Match::Section_Moves;
	return s;
}


char const*
Position::parsePower(Match& match, char const* s, Error& error)
{
	Designator designator;

	s = designator.parse(s, error);

	if (error == No_Error)
	{
		unsigned min(0), max(0); // prevent compiler warnings
		s = parseUnsignedRange(s, error, min, max);
		m_boardMatchList.push_back(new cql::board::Power(designator, min, max));
	}

	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parsePowerDifference(Match& match, char const* s, Error& error)
{
	Designator designator;

	s = designator.parse(s, error);

	if (error == No_Error)
	{
		int min(0), max(0); // prevent compiler warnings
		s = parseSignedRange(s, error, min, max);
		m_boardMatchList.push_back(new cql::board::PowerDifference(designator, min, max));
	}

	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parsePreceding(Match& match, char const* s, Error& error)
{
	error = Not_Implemented; // TODO
	return s;
}


char const*
Position::parsePreTransformMatchCount(Match& match, char const* s, Error& error)
{
	error = Not_Implemented; // TODO
	return s;
}


char const*
Position::parsePromote(Match& match, char const* s, Error& error)
{
	Designator designator;
	char const* t = designator.parse(s, error);

	if (error == No_Error)
	{
		uint64_t pieces = (designator.pieces(White) | designator.pieces(Black))
							 & ~(db::board::RankMask1 | db::board::RankMask8);

		if (pieces)
		{
			error = Invalid_Promotion_Ranks;
		}
		else
		{
			m_moveMatchList.push_back(new cql::move::Promote(designator));
			s = t;
		}
	}

	match.m_sections |= Match::Section_Moves;
	return s;
}


char const*
Position::parseRay(Match& match, char const* s, Error& error, cql::board::MatchRay* ray)
{
	mstl::auto_ptr<cql::board::MatchRay> rayp(ray);

	if (*s != '(')
	{
		error = Left_Parenthesis_Expected;
		return s;
	}

	s = ::skipSpaces(s);

	while (*s != ')')
	{
		Designator designator;
		s = designator.parse(s, error);

		if (error == No_Error)
			return s;

		rayp->add(designator);
		s = ::skipSpaces(s);
	}

	s = ::skipSpaces(s + 1);

	if (::isdigit(*s))
	{
		char* e;
		rayp->m_min = ::strtoul(s, &e, 10);
		s = ::skipSpaces(e);

		if (::isdigit(*s))
		{
			rayp->m_max = ::strtoul(s, &e, 10);

			if (rayp->m_min > rayp->m_max)
				mstl::swap(rayp->m_min, rayp->m_max);

			s = e;
		}
	}

	m_boardMatchList.push_back(rayp.release());
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseRay(Match& match, char const* s, Error& error)
{
	return parseRay(match, s, error, new cql::board::Ray);
}


char const*
Position::parseRayAttack(Match& match, char const* s, Error& error)
{
	return parseRay(match, s, error, new cql::board::RayAttack);
}


char const*
Position::parseRayDiagonal(Match& match, char const* s, Error& error)
{
	return parseRay(match, s, error, new cql::board::RayDiagonal);
}


char const*
Position::parseRayHorizontal(Match& match, char const* s, Error& error)
{
	return parseRay(match, s, error, new cql::board::RayHorizontal);
}


char const*
Position::parseRayOrthogonal(Match& match, char const* s, Error& error)
{
	return parseRay(match, s, error, new cql::board::RayOrthogonal);
}


char const*
Position::parseRayVertical(Match& match, char const* s, Error& error)
{
	return parseRay(match, s, error, new cql::board::RayVertical);
}


char const*
Position::parseRelation(Match& match, char const* s, Error& error)
{
	if (m_relation == 0)
		m_relation = new Relation;

	return m_relation->parse(s, error);
}


char const*
Position::parseRepetition(Match& match, char const* s, Error& error)
{
	m_boardMatchList.push_back(new cql::board::Repetition);
	match.m_isStandard = false;
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseReset(Match& match, char const* s, Error& error)
{
	s = ::skipSpaces(s);

	char const* t = ::skipToDelim(s);

	if (t == s)
	{
		error = Missing_Parameter;
		return s;
	}

	m_resetName.assign(s, t - s);
	match.m_isStandard = false;
	match.m_sections |= Match::Section_Positions;
	return t;
}


char const*
Position::parseResult(Match& match, char const* s, Error& error)
{
	return adopt(match, match.parseResult(s, error), error);
}


char const*
Position::parseSequence(Match& match, char const* s, Error& error)
{
	mstl::auto_ptr<cql::board::Sequence> seq(new cql::board::Sequence);
	s = ::parseSequence(*seq, match, s, error);
	if (error == No_Error)
		m_boardMatchList.push_back(seq.release());
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseShift(Match& match, char const* s, Error& error)
{
	m_transformations |= Shift;
	return s;
}


char const*
Position::parseShiftDiagonal(Match& match, char const* s, Error& error)
{
	m_transformations |= Shift_Diagonal;
	return s;
}


char const*
Position::parseShiftHorizontal(Match& match, char const* s, Error& error)
{
	m_transformations |= Shift_Horizontal;
	return s;
}


char const*
Position::parseShiftMainDiagonal(Match& match, char const* s, Error& error)
{
	m_transformations |= Shift_Main_Diagonal;
	return s;
}


char const*
Position::parseShiftOffDiagonal(Match& match, char const* s, Error& error)
{
	m_transformations |= Shift_Off_Diagonal;
	return s;
}


char const*
Position::parseShiftVertical(Match& match, char const* s, Error& error)
{
	m_transformations |= Shift_Vertical;
	return s;
}


char const*
Position::parseStalemate(Match& match, char const* s, Error& error)
{
	if (m_finalState == 0)
		m_finalState = new cql::board::State;

	m_finalState->add(Board::Stalemate);
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseSumRange(Match& match, char const* s, Error& error)
{
	s = ::skipSpaces(s);

	char const* t = ::skipToDelim(s);

	if (t == s)
	{
		error = Missing_Parameter;
		return s;
	}

	SumRange range;
	range.name.assign(s, t - s);

	unsigned min(0), max(0);
	s = parseUnsignedRange(::skipSpaces(t), error, min, max);

	if (error == No_Error)
	{
		range.min = min;
		range.max = max;
		m_sumRanges.push_back(range);
	}

	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseTagMatch(Match& match, char const* s, Error& error)
{
	error = Not_Implemented; // TODO
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseTerminal(Match& match, char const* s, Error& error)
{
	match.setFinal();
	match.m_isStandard = false;
	return s;
}


char const*
Position::parseVariant(Match& match, char const* s, Error& error)
{
	return adopt(match, match.parseVariant(s, error), error);
}


char const*
Position::parseVariations(Match& match, char const* s, Error& error)
{
	m_includeVariations = true;
	match.m_includesVariations = true;
	return s;
}


char const*
Position::parseVariationsOnly(Match& match, char const* s, Error& error)
{
	m_includeMainline = false;
	m_includeVariations = true;
	match.m_includesVariations = true;
	return s;
}


char const*
Position::parseWhiteCannotWin(Match& match, char const* s, Error& error)
{
	m_boardMatchList.push_back(new cql::board::CannotWin(color::White));
	match.m_isStandard = false;
	match.m_sections |= Match::Section_Positions;
	return s;
}


char const*
Position::parseWhiteElo(Match& match, char const* s, Error& error)
{
	return adopt(match, match.parseWhiteElo(s, error), error);
}


char const*
Position::parseWhiteRating(Match& match, char const* s, Error& error)
{
	return adopt(match, match.parseWhiteRating(s, error), error);
}


char const*
Position::parseWhiteToMove(Match& match, char const* s, Error& error)
{
	m_boardMatchList.push_back(new cql::board::ToMove(White));
	return s;
}


Position*
Position::makeLogicalAnd(Match& match, char const*& s, Error& error)
{
	mstl::auto_ptr<Position> pos(new Position);
	s = pos->parseAnd(match, s, error);
	return pos.release();
}


Position*
Position::makeLogicalOr(Match& match, char const*& s, Error& error)
{
	mstl::auto_ptr<Position> pos(new Position);
	s = pos->parseOr(match, s, error);
	return pos.release();
}


char const*
Position::parse(Match& match, char const* s, Error& error)
{
	typedef PosPair Pair;

	static Pair const Trampolin[] =
	{
		Pair("accumulate",					&Position::parseAccumulate),
		Pair("and",								&Position::parseAnd),
		Pair("attackcount",					&Position::parseAttackCount),
		Pair("blackcannotwin",				&Position::parseBlackCannotWin),
 		Pair("blackelo",						&Position::parseBlackElo),
 		Pair("blackrating",					&Position::parseBlackRating),
		Pair("btm",								&Position::parseBlackToMove),
		Pair("castling",						&Position::parseCastling),
		Pair("check",							&Position::parseCheck),
		Pair("checkcount",					&Position::parseCheckCount),
		Pair("contactcheck",					&Position::parseContactCheck),
		Pair("cut",								&Position::parseCut),
		Pair("doublecheck",					&Position::parseDoubleCheck),
	 	Pair("elo",								&Position::parseElo),
		Pair("endgame",						&Position::parseEndGame),
		Pair("endmost",						&Position::parseEndmost),
		Pair("enpassant",						&Position::parseEnPassant),
		Pair("evaluation",					&Position::parseEvaluation),
		Pair("exchangeevaluation",			&Position::parseExchangeEvaluation),
		Pair("exclude",						&Position::parseExclude),
		Pair("fen",								&Position::parseFen),
		Pair("fiftymoverule",				&Position::parseFiftyMoveRule),
		Pair("flip",							&Position::parseFlipDihedral),
		Pair("flipcolor",						&Position::parseFlipColor),
		Pair("flipdiagonal",					&Position::parseFlipDiagonal),
		Pair("flipdihedral",					&Position::parseFlipDihedral),
		Pair("fliphorizontal",				&Position::parseFlipHorizontal),
		Pair("flipoffdiagonal",				&Position::parseFlipOffDiagonal),
		Pair("flipvertical",					&Position::parseFlipVertical),
		Pair("following",						&Position::parseFollowing),
		Pair("gameisover",					&Position::parseGameIsOver),
		Pair("gappedsequence",				&Position::parseGappedSequence),
		Pair("halfmoveclocklimit",			&Position::parseHalfmoveClockLimit),
		Pair("initial",						&Position::parseInitial),
		Pair("inside",							&Position::parseInside),
		Pair("iscastling",					&Position::parseIsCastling),
		Pair("losing",							&Position::parseLosing),
		Pair("markall",						&Position::parseMarkAll),
		Pair("matchcount",					&Position::parseMatchCount),
		Pair("mate",							&Position::parseMate),
		Pair("matingmaterial",				&Position::parseMatingMaterial),
		Pair("maxswapevaluation",			&Position::parseMaxSwapEvaluation),
		Pair("movefrom",						&Position::parseMoveFrom),
		Pair("movenumber",					&Position::parseMoveNumber),
		Pair("moveto",							&Position::parseMoveTo),
		Pair("noannotate",					&Position::parseNoAnnotate),
		Pair("nocastling",					&Position::parseNoCastling),
		Pair("nocheck",						&Position::parseNoCheck),
		Pair("nocontactcheck",				&Position::parseNoContactCheck),
		Pair("nodoublecheck",				&Position::parseNoDoubleCheck),
		Pair("noendgame",						&Position::parseNoEndGame),
		Pair("noenpassant",					&Position::parseNoEnpassant),
		Pair("nomate",							&Position::parseNoMate),
		Pair("nomatingmaterial",			&Position::parseNoMatingMaterial),
		Pair("nostalemate",					&Position::parseNoStalemate),
		Pair("not",								&Position::parseNot),
		Pair("or",								&Position::parseOr),
		Pair("piececount",					&Position::parsePieceCount),
		Pair("piecedrop",						&Position::parsePieceDrop),
		Pair("power",							&Position::parsePower),
		Pair("powerdifference",				&Position::parsePowerDifference),
		Pair("preceding",						&Position::parsePreceding),
		Pair("pretransformmatchcount",	&Position::parsePreTransformMatchCount),
		Pair("promote",						&Position::parsePromote),
		Pair("ray",								&Position::parseRay),
		Pair("rayattack",						&Position::parseRayAttack),
		Pair("raydiagonal",					&Position::parseRayDiagonal),
		Pair("rayhorizontal",				&Position::parseRayHorizontal),
		Pair("rayorthogonal",				&Position::parseRayOrthogonal),
		Pair("rayvertical",					&Position::parseRayVertical),
		Pair("relation",						&Position::parseRelation),
		Pair("repetition",					&Position::parseRepetition),
		Pair("reset",							&Position::parseReset),
 		Pair("result",							&Position::parseResult),
		Pair("sequence",						&Position::parseSequence),
		Pair("shift",							&Position::parseShift),
		Pair("shiftdiagonal",				&Position::parseShiftDiagonal),
		Pair("shifthorizontal",				&Position::parseShiftHorizontal),
		Pair("shiftmaindiagonal",			&Position::parseShiftMainDiagonal),
		Pair("shiftoffdiagonal",			&Position::parseShiftOffDiagonal),
		Pair("shiftvertical",				&Position::parseShiftVertical),
		Pair("stalemate",						&Position::parseStalemate),
		Pair("sumrange",						&Position::parseSumRange),
		Pair("tagmatch",						&Position::parseTagMatch),
		Pair("terminal",						&Position::parseTerminal),
		Pair("variant",						&Position::parseVariant),
		Pair("variations",					&Position::parseVariations),
		Pair("variationsonly",				&Position::parseVariationsOnly),
		Pair("whitecannotwin",				&Position::parseWhiteCannotWin),
 		Pair("whiteelo",						&Position::parseWhiteElo),
 		Pair("whiterating",					&Position::parseWhiteRating),
		Pair("wtm",								&Position::parseWhiteToMove),
	};

	mstl::string key;

	error = No_Error;

	bool closed = false;

	do
	{
		match.m_isStandard = true;
		s = ::skipSpaces(s);

		if (*s == ')')
		{
			// the end of this position (an empty one matches all)
			s = ::skipSpaces(s + 1);
			closed = true;
			break;
		}
		else if (*s == ':')
		{
			mstl::string key(s + 1, ::lengthOfKeyword(s + 1));
			Pair const* p = mstl::binary_search(Trampolin, Trampolin + U_NUMBER_OF(Trampolin), key);

			if (p == Trampolin + U_NUMBER_OF(Trampolin))
			{
				error = Invalid_Keyword;
				return s;
			}

			char const* t = (this->*p->func)(match, ::skipSpaces(s + key.size() + 1), error);

			if (error != No_Error)
				return t;

			if (!match.m_isStandard)
				match.m_ranges.push_back(mstl::make_pair(s, t));

			s = ::skipSpaces(t);
		}
		else if (*s)
		{
			Designator designator;
			s = designator.parse(s, error);
			if (error == No_Error)
			{
				m_designators->add(designator);
				match.m_sections |= Match::Section_Positions;
			}
		}
	}
	while (*s && error == No_Error);

	if (error == No_Error && !closed)
		error = Right_Parenthesis_Expected;

	if (error == No_Error
		&& (m_transformations
			& (Flip_Color | Flip | Flip_Horizontal | Flip_Vertical | Flip_Diagonal | Flip_Off_Diagonal | Shift)))
	{
		// these keep state between positions, which a second (flipped)
		// evaluation of the same position would corrupt
		bool stateful = m_relation || m_cutExpression || !m_positionList.empty();

		for (BoardMatchList::const_iterator i = m_boardMatchList.begin(); i != m_boardMatchList.end(); ++i)
		{
			if (	dynamic_cast<cql::board::GappedSequence const*>(*i)
				|| dynamic_cast<logical::Match const*>(*i))
			{
				stateful = true;
			}
		}

		if (stateful)
			error = Not_Implemented;
	}

	if (!match.m_ranges.empty())
		match.m_isStandard = false;

	return s;
}


void
Position::reset()
{
	if (m_relation)
		m_relation->reset();

	m_matchCount = 0;

	PositionList::iterator i = m_positionList.begin();
	PositionList::iterator e = m_positionList.end();

	for ( ; i != e; ++i)
		(*i)->reset();
}


void
Position::finish(Match& match)
{
	// :flipcolor is applied at match time (Position::match tests the
	// colour-flipped board as well); the other transformations are refused
	// by their parsers.
}


char const*
Position::parseUnsignedRange(char const* s, Error& error, unsigned& min, unsigned& max)
{
	if (!::isdigit(*s))
	{
		error = Positive_Integer_Expected;
	}
	else
	{
		char* e;

		min = ::strtoul(s, &e, 10);

		char const* t = ::skipSpaces(e);

		if (!::isdigit(*t))
		{
			// a single number is an exact count
			max = min;
			s = e;
		}
		else
		{
			max = ::strtoul(t, &e, 10);

			if (min > max)
				mstl::swap(min, max);

			s = e;
		}
	}

	return s;
}


char const*
Position::parseSignedRange(char const* s, Error& error, int& min, int& max)
{
	if (!::isdigit(s[0]) && ((s[0] != '-' && s[1] != '+') || !::isdigit(s[1])))
	{
		error = Integer_Expected;
	}
	else
	{
		char* e;
		int sign;

		if (*s == '-')
		{
			sign = -1;
			++s;
		}
		else if (*s == '+')
		{
			sign = 1;
			++s;
		}
		else
		{
			sign = 1;
		}

		min = sign*::strtoul(s, &e, 10);
		s = ::skipSpaces(e);

		if (!::isdigit(s[0]) && ((s[0] != '-' && s[1] != '+') || !::isdigit(s[1])))
		{
			error = Integer_Expected;
		}
		else
		{
			if (*s == '-')
			{
				sign = -1;
				++s;
			}
			else if (*s == '+')
			{
				sign = 1;
				++s;
			}
			else
			{
				sign = 1;
			}

			max = sign*::strtoul(s, &e, 10);

			if (min > max)
				mstl::swap(min, max);

			s = e;
		}
	}

	return s;
}

// vi:set ts=3 sw=3:
