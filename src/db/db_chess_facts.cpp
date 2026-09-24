// ======================================================================
//    _/|            __
//   // o\         /    )           ,        /    /
//   || ._)    ----\---------__----------__-/----/__-
//   //__\          \      /   '  /    /   /    /   )
//   )___(     _(____/____(___ __/____(___/____(___/_
// ======================================================================
//
// Chess anatomy fact extractor -- see db_chess_facts.h for the rationale.
//
// ======================================================================

#include "db_chess_facts.h"
#include "db_board.h"
#include "db_board_base.h"
#include "db_move.h"
#include "db_move_list.h"

#include "m_string.h"

#include <stdio.h>
#include <string.h>

namespace db {

namespace {

// ----------------------------------------------------------------------
// JSON helpers
// ----------------------------------------------------------------------

void
appNum(mstl::string& s, long v)
{
	char buf[32];
	::snprintf(buf, sizeof(buf), "%ld", v);
	s += buf;
}

void
appStr(mstl::string& s, char const* v)
{
	s += '"';

	for ( ; *v; ++v)
	{
		if (*v == '"' || *v == '\\')
			s += '\\';
		s += *v;
	}

	s += '"';
}

void
appBool(mstl::string& s, bool v)
{
	s += v ? "true" : "false";
}

void
appListText(mstl::string& s, uint64_t mask)
{
	s += '[';

	bool first = true;

	while (mask)
	{
		if (!first)
			s += ',';
		first = false;
		s += sq::printAlgebraic(Square(board::lsbClear(mask)));
	}

	s += ']';
}

struct Json
{
	Json(mstl::string& out) : s(out), depth(0) { first[0] = true; s.clear(); }

	void sep() { if (!first[depth]) s += ','; first[depth] = false; }

	void key(char const* k) { sep(); appStr(s, k); s += ':'; }

	void beginObject() { s += '{'; ++depth; first[depth] = true; }
	void endObject()   { --depth; s += '}'; }
	void beginArray()  { s += '['; ++depth; first[depth] = true; }
	void endArray()    { --depth; s += ']'; }

	void valueNum(long v)          { sep(); appNum(s, v); }
	void valueBoolean(bool v)      { sep(); appBool(s, v); }
	void valueStr(char const* v)   { sep(); appStr(s, v); }

	void num(long v)                 { valueNum(v); }
	void boolean(bool v)             { valueBoolean(v); }
	void str(char const* v)          { valueStr(v); }

	void num(char const* k, long v)          { key(k); appNum(s, v); }
	void boolean(char const* k, bool v)      { key(k); appBool(s, v); }
	void str(char const* k, char const* v)   { key(k); appStr(s, v); }
	void nullValue(char const* k)            { key(k); s += "null"; }

	void keyedObject(char const* k) { key(k); beginObject(); }
	void keyedArray(char const* k)  { key(k); beginArray(); }

	void numList(unsigned const* v, unsigned n)
	{
		beginArray();
		for (unsigned i = 0; i < n; ++i)
			num(v[i]);
		endArray();
	}

	void squareList(uint64_t mask)
	{
		beginArray();
		while (mask)
			str(sq::printAlgebraic(Square(board::lsbClear(mask))));
		endArray();
	}

	void fileList(unsigned fileMask) // bit f set => file a+f
	{
		beginArray();
		for (unsigned f = 0; f < 8; ++f)
		{
			if (fileMask & (1u << f))
			{
				char b[2] = { char('a' + f), 0 };
				str(b);
			}
		}
		endArray();
	}

	mstl::string&	s;
	bool				first[40];
	unsigned			depth;
};


// ----------------------------------------------------------------------
// geometry / attack helpers
// ----------------------------------------------------------------------

uint64_t
rayAttacks(Board const& board, Square from, int df, int dr)
{
	uint64_t result = 0;

	int f = sq::fyle(from);
	int r = sq::rank(from);

	for ( ; ; )
	{
		f += df;
		r += dr;

		if (f < 0 || f > 7 || r < 0 || r > 7)
			break;

		Square to = sq::make(Square(f), Square(r));
		result |= uint64_t(1) << to;

		if (board.piece(to) != piece::None)
			break;
	}

	return result;
}

/// All squares the piece standing on <from> attacks (pseudo-legal, with
/// blockers included as final squares).
uint64_t
attacksOf(Board const& board, Square from)
{
	piece::Type	pt = board.piece(from);
	color::ID	c = board.color(from);

	switch (pt)
	{
		case piece::Pawn:	return board::PawnAttacks[c][from];
		case piece::Knight:	return board::KnightAttacks[from];
		case piece::King:	return board::KingAttacks[from];

		case piece::Bishop:
			return rayAttacks(board, from, 1, 1) | rayAttacks(board, from, -1, 1)
				 | rayAttacks(board, from, 1, -1) | rayAttacks(board, from, -1, -1);

		case piece::Rook:
			return rayAttacks(board, from, 1, 0) | rayAttacks(board, from, -1, 0)
				 | rayAttacks(board, from, 0, 1) | rayAttacks(board, from, 0, -1);

		case piece::Queen:
			return rayAttacks(board, from, 1, 0) | rayAttacks(board, from, -1, 0)
				 | rayAttacks(board, from, 0, 1) | rayAttacks(board, from, 0, -1)
				 | rayAttacks(board, from, 1, 1) | rayAttacks(board, from, -1, 1)
				 | rayAttacks(board, from, 1, -1) | rayAttacks(board, from, -1, -1);

		default: return 0;
	}
}

/// Squares of <color>'s pieces that are pinned against their own king.
uint64_t
pinnedPieces(Board const& board, color::ID color)
{
	static int const Dir[8][2] =
	{
		{ 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
		{ 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
	};

	uint64_t result = 0;

	Square	ksq = board.kingSquare(color);
	int		kf = sq::fyle(ksq);
	int		kr = sq::rank(ksq);

	for (unsigned d = 0; d < 8; ++d)
	{
		int		f = kf;
		int		r = kr;
		Square	candidate = sq::Null;

		for ( ; ; )
		{
			f += Dir[d][0];
			r += Dir[d][1];

			if (f < 0 || f > 7 || r < 0 || r > 7)
				break;

			Square		s = sq::make(Square(f), Square(r));
			piece::Type	pt = board.piece(s);

			if (pt == piece::None)
				continue;

			color::ID pc = board.color(s);

			if (candidate == sq::Null)
			{
				if (pc == color)
				{
					candidate = s;
					continue;
				}
				break; // enemy piece directly in front: a check, not a pin
			}

			if (pc != color)
			{
				bool diagonal = (Dir[d][0] != 0 && Dir[d][1] != 0);

				if (   (diagonal && (pt == piece::Bishop || pt == piece::Queen))
				    || (!diagonal && (pt == piece::Rook   || pt == piece::Queen)))
				{
					result |= uint64_t(1) << candidate;
				}
			}
			break;
		}
	}

	return result;
}

inline bool
squareIsLight(Square s)
{
	return ((sq::fyle(s) + sq::rank(s)) & 1) != 0;
}

char const*
pieceLetter(piece::Type t)
{
	static char const* const Letters[7] = { "", "K", "Q", "R", "B", "N", "P" };
	return (t >= piece::None && t <= piece::Pawn) ? Letters[t] : "";
}

/// Pieces of <side> that are attacked and not defended.
uint64_t
undefendedPieces(Board const& board, color::ID side)
{
	color::ID const	opp = color::opposite(side);
	uint64_t			result = 0;

	for (uint64_t m = board.pieces(side); m; )
	{
		Square s = Square(board::lsbClear(m));

		if (board.piece(s) != piece::King
		 && board.attacks(opp, s) && !board.attacks(side, s))
			result |= uint64_t(1) << s;
	}

	return result;
}

int
pieceValue(piece::Type t)
{
	static int const Value[7] = { 0, 20000, 900, 500, 330, 320, 100 };
	return (t >= piece::None && t <= piece::Pawn) ? Value[t] : 0;
}

/// Pieces of <side> that can be profitably captured: attacked by a piece
/// cheaper than themselves.
uint64_t
enPrisePieces(Board const& board, color::ID side)
{
	color::ID const	opp = color::opposite(side);
	uint64_t			result = 0;

	for (uint64_t m = board.pieces(side); m; )
	{
		Square s = Square(board::lsbClear(m));

		if (board.piece(s) == piece::King)
			continue;

		uint64_t attackers = board.attacks(opp, s);

		if (!attackers)
			continue;

		int minAttacker = 100000;

		for (uint64_t a = attackers; a; )
		{
			int const v = pieceValue(board.piece(Square(board::lsbClear(a))));
			if (v < minAttacker)
				minAttacker = v;
		}

		if (minAttacker < pieceValue(board.piece(s)))
			result |= uint64_t(1) << s;
	}

	return result;
}

/// The moved capture removed the only defender of an attacked enemy piece.
uint64_t
removesDefender(Board const& before, Board const& after, Move const& move, color::ID mover)
{
	if (!move.isCapture())
		return 0;

	color::ID const	opp			= color::opposite(mover);
	uint64_t const	capturedBit	= uint64_t(1) << move.to();
	uint64_t			result		= 0;

	for (uint64_t m = before.pieces(opp); m; )
	{
		Square const t = Square(board::lsbClear(m));

		if (before.piece(t) == piece::King)
			continue;
		if (!(before.attacks(opp, t) & capturedBit)) // the captured piece did not defend t
			continue;
		if (after.attacks(opp, t))                   // t is still defended
			continue;
		if (!after.attacks(mover, t))                // and t is not attacked anyway
			continue;

		result |= uint64_t(1) << t;
	}

	return result;
}

/// One piece attacking two or more enemy non-pawn units (the king counts).
void
appendForks(Json& j, Board const& board, color::ID attacker)
{
	color::ID const	opp = color::opposite(attacker);
	uint64_t const	nonPawnEnemy = board.pieces(opp) & ~board.pawns(opp);

	j.beginArray();

	for (uint64_t m = board.pieces(attacker); m; )
	{
		Square s = Square(board::lsbClear(m));

		if (board.piece(s) == piece::King)
			continue;

		uint64_t targets = attacksOf(board, s) & nonPawnEnemy;

		if (board::count(targets) >= 2)
		{
			j.beginObject();
			j.str("from", sq::printAlgebraic(s));
			j.key("targets"); j.squareList(targets);
			j.endObject();
		}
	}

	j.endArray();
}

/// A slider attacking a more valuable enemy piece with a lesser one behind.
void
appendSkewers(Json& j, Board const& board, color::ID attacker)
{
	static int const Ortho[4][2] = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } };
	static int const Diag[4][2]  = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } };

	j.beginArray();

	for (uint64_t m = board.pieces(attacker); m; )
	{
		Square const		s = Square(board::lsbClear(m));
		piece::Type const	pt = board.piece(s);

		if (pt != piece::Bishop && pt != piece::Rook && pt != piece::Queen)
			continue;

		for (unsigned d = 0; d < 8; ++d)
		{
			bool const diagonal = d >= 4;

			if (diagonal && pt == piece::Rook)    continue;
			if (!diagonal && pt == piece::Bishop) continue;

			int df = diagonal ? Diag[d - 4][0] : Ortho[d][0];
			int dr = diagonal ? Diag[d - 4][1] : Ortho[d][1];
			int f = sq::fyle(s);
			int r = sq::rank(s);

			Square first = sq::Null;
			Square second = sq::Null;

			for ( ; ; )
			{
				f += df;
				r += dr;

				if (f < 0 || f > 7 || r < 0 || r > 7)
					break;

				Square const t = sq::make(Square(f), Square(r));

				if (board.piece(t) == piece::None)
					continue;
				if (board.color(t) == attacker)
					break;

				if (first == sq::Null)
					first = t;
				else
				{
					second = t;
					break;
				}
			}

			if (   first != sq::Null && second != sq::Null
			    && pieceValue(board.piece(first)) > pieceValue(board.piece(second)))
			{
				j.beginObject();
				j.str("by", sq::printAlgebraic(s));
				j.str("through", sq::printAlgebraic(first));
				j.str("wins", sq::printAlgebraic(second));
				j.endObject();
			}
		}
	}

	j.endArray();
}

/// King on its home rank behind an intact pawn shield, with an enemy heavy
/// piece able to reach that rank.
bool
backRankWeak(Board const& board, color::ID side)
{
	Square const	king = board.kingSquare(side);
	sq::Rank const	home = (side == color::White) ? sq::Rank1 : sq::Rank8;

	if (sq::rank(king) != home)
		return false;

	sq::Rank const	pawnRank = (side == color::White) ? sq::Rank2 : sq::Rank7;
	uint64_t const	ownPawns = board.pawns(side);
	int const		kf = sq::fyle(king);

	for (int f = kf - 1; f <= kf + 1; ++f)
	{
		if (f < 0 || f > 7)
			continue;
		if (!(ownPawns & board::FyleMask[f] & board::RankMask[pawnRank]))
			return false; // a pawn has moved: luft exists
	}

	color::ID const	opp = color::opposite(side);
	uint64_t const	homeRankMask = board::RankMask[home];

	for (uint64_t m = board.rooks(opp) | board.queens(opp); m; )
	{
		if (attacksOf(board, Square(board::lsbClear(m))) & homeRankMask)
			return true;
	}

	return false;
}

/// A friendly slider that gains a target because the moved piece vacated
/// a line to it (a discovered attack).
void
appendDiscovered(Json& j, Board const& before, Board const& after, Move const& move, color::ID mover)
{
	color::ID const	opp = color::opposite(mover);
	uint64_t const	enemyTargets = after.pieces(opp);
	uint64_t const	movedBit = uint64_t(1) << move.from();

	j.beginArray();

	for (uint64_t m = before.pieces(mover); m; )
	{
		Square s = Square(board::lsbClear(m));
		piece::Type const pt = before.piece(s);

		if (pt != piece::Bishop && pt != piece::Rook && pt != piece::Queen)
			continue;
		if (s == move.from())
			continue;
		if (after.piece(s) != pt || after.color(s) != mover) // slider itself did not move
			continue;

		uint64_t const gained = attacksOf(after, s) & ~attacksOf(before, s) & enemyTargets;

		if (!gained)
			continue;

		uint64_t targets = 0;

		for (uint64_t t = gained; t; )
		{
			Square const tsq = Square(board::lsbClear(t));
			if (board::allSquaresBetween(s, tsq) & movedBit)
				targets |= uint64_t(1) << tsq;
		}

		if (targets)
		{
			j.beginObject();
			j.str("by", sq::printAlgebraic(s));
			j.key("targets"); j.squareList(targets);
			j.boolean("check", (targets & (uint64_t(1) << after.kingSquare(opp))) != 0);
			j.endObject();
		}
	}

	j.endArray();
}

/// Legal-move counts for the side to move.
void
appendMoveStats(Json& j, Board const& board, variant::Type variant)
{
	MoveList list;
	board.generateMoves(variant, list);
	board.filterLegalMoves(list, variant); // generateMoves() is pseudo-legal

	unsigned legal = 0, captures = 0, checks = 0, mates = 0;

	for (unsigned i = 0; i < list.size(); ++i)
	{
		Move const& m = list[i];

		legal++;
		if (m.isCapture())
			captures++;

		unsigned const st = board.checkState(m, variant);

		if (st & Board::Check)
			checks++;
		if (st & Board::Checkmate)
			mates++;
	}

	j.keyedObject("moveStats");
	j.num("legalMoves", legal);
	j.num("captures", captures);
	j.num("checks", checks);
	j.num("mates", mates);
	j.endObject();
}


// ----------------------------------------------------------------------
// pawn structure
// ----------------------------------------------------------------------

struct PawnStats
{
	PawnStats() { ::memset(this, 0, sizeof(*this)); }

	unsigned	count;
	unsigned	file[8];
	unsigned	islands;
	unsigned	doubled;
	unsigned	isolated;
	unsigned	backward;
	unsigned	passed;
	unsigned	protectedPawns;
	unsigned	connected;
	unsigned	queenside;
	unsigned	kingside;
	unsigned	advanced;
	bool		iqp;
	bool		hanging;
};

PawnStats
computePawns(Board const& board, color::ID color)
{
	color::ID const	opp = color::opposite(color);
	uint64_t const		own = board.pawns(color);
	uint64_t const		enemy = board.pawns(opp);

	PawnStats ps;
	ps.count = board::count(own);

	for (uint64_t m = own; m; )
	{
		Square	s = Square(board::lsbClear(m));
		unsigned	f = sq::fyle(s);
		unsigned	r = sq::rank(s);

		ps.file[f]++;

		bool isolated = (own & board::MaskIsolatedPawn[s]) == 0;
		bool passed = (enemy & board::MaskPassedPawn[color][s]) == 0;

		if (isolated)
			ps.isolated++;
		if (passed)
			ps.passed++;
		if (own & board::MaskDuoPawn[s])
			ps.connected++;
		if (own & board::PawnAttacks[opp][s]) // own pawn defends this square
			ps.protectedPawns++;

		if (f <= 3)
			ps.queenside++;
		else
			ps.kingside++;

		if ((color == color::White && r >= 4) || (color == color::Black && r <= 3))
			ps.advanced++;

		// backward: not isolated, not passed, no neighbouring pawn able to
		// advance to its support, and the stop square covered by an enemy pawn
		if (!isolated && !passed && r >= 1 && r <= 6)
		{
			Square stop = Square(color == color::White ? s + 8 : s - 8);

			if (enemy & board::PawnAttacks[color][stop])
			{
				uint64_t behind = 0;

				if (color == color::White)
				{
					for (unsigned rr = 0; rr <= r; ++rr) behind |= board::RankMask[rr];
				}
				else
				{
					for (unsigned rr = r; rr < 8; ++rr) behind |= board::RankMask[rr];
				}

				bool supported = false;

				if (f > 0 && (own & board::FyleMask[f - 1] & behind)) supported = true;
				if (f < 7 && (own & board::FyleMask[f + 1] & behind)) supported = true;

				if (!supported)
					ps.backward++;
			}
		}
	}

	for (unsigned f = 0; f < 8; ++f)
	{
		if (ps.file[f] > 1)
			ps.doubled += ps.file[f] - 1;
	}

	bool inIsland = false;

	for (unsigned f = 0; f < 8; ++f)
	{
		if (ps.file[f])
		{
			if (!inIsland)
			{
				ps.islands++;
				inIsland = true;
			}
		}
		else
		{
			inIsland = false;
		}
	}

	// isolated queen's pawn
	ps.iqp = ps.file[3] > 0 && ps.file[2] == 0 && ps.file[4] == 0;

	// hanging pawns: c+d on one rank with neither b nor e pawn present
	{
		sq::Rank duoRank = (color == color::White) ? sq::Rank4 : sq::Rank5;

		bool cOn = (own & board::FyleMask[2] & board::RankMask[duoRank]) != 0;
		bool dOn = (own & board::FyleMask[3] & board::RankMask[duoRank]) != 0;
		bool bOn = (own & board::FyleMask[1]) != 0;
		bool eOn = (own & board::FyleMask[4]) != 0;

		ps.hanging = cOn && dOn && !bOn && !eOn;
	}

	return ps;
}


// ----------------------------------------------------------------------
// piece play
// ----------------------------------------------------------------------

struct PieceStats
{
	PieceStats() { ::memset(this, 0, sizeof(*this)); }

	unsigned	bishops;
	unsigned	badBishops;
	unsigned	knightsOutposted;
	unsigned	rooksOnOpenFile;
	unsigned	rooksOnSemiOpenFile;
	unsigned	rooksOnSeventh;
	unsigned	developedMinors;
	unsigned	mobility;
};

PieceStats
computePieces(Board const& board, color::ID color)
{
	color::ID const	opp = color::opposite(color);
	uint64_t const		ownOcc = board.pieces(color);
	uint64_t const		enemyOcc = board.pieces(opp);
	uint64_t const		allPawns = board.pawns();
	uint64_t const		ownPawns = board.pawns(color);
	uint64_t const		enemyPawns = board.pawns(opp);

	PieceStats st;

	sq::Rank homeRank		= (color == color::White) ? sq::Rank1 : sq::Rank8;
	sq::Rank seventhRank	= (color == color::White) ? sq::Rank7 : sq::Rank2;
	sq::Rank pawnHomeRank	= (color == color::White) ? sq::Rank2 : sq::Rank7;

	// bishops
	for (uint64_t m = board.bishops(color); m; )
	{
		Square s = Square(board::lsbClear(m));
		st.bishops++;

		unsigned sameColourPawns = 0;

		for (uint64_t p = ownPawns; p; )
		{
			Square sq = Square(board::lsbClear(p));

			// only committed pawns make a bishop bad; pawns still on their
			// original rank are not yet a structural liability
			if (sq::rank(sq) != pawnHomeRank && squareIsLight(sq) == squareIsLight(s))
				sameColourPawns++;
		}

		if (sameColourPawns >= 3)
			st.badBishops++;
	}

	// knights / outposts
	for (uint64_t m = board.knights(color); m; )
	{
		Square	s = Square(board::lsbClear(m));
		unsigned	r = sq::rank(s);
		unsigned	rel = (color == color::White) ? r : 7 - r;

		if (rel >= 3 && rel <= 5 && (enemyPawns & board::MaskNoAttacks[opp][s]) == 0)
			st.knightsOutposted++;
	}

	// rooks
	for (uint64_t m = board.rooks(color); m; )
	{
		Square	s = Square(board::lsbClear(m));
		unsigned	f = sq::fyle(s);

		bool anyPawn = (allPawns & board::FyleMask[f]) != 0;
		bool ownPawn = (ownPawns & board::FyleMask[f]) != 0;

		if (!anyPawn)
			st.rooksOnOpenFile++;
		else if (!ownPawn)
			st.rooksOnSemiOpenFile++;

		if (sq::rank(s) == seventhRank)
			st.rooksOnSeventh++;
	}

	// development
	for (uint64_t m = board.knights(color) | board.bishops(color); m; )
	{
		Square s = Square(board::lsbClear(m));
		if (sq::rank(s) != homeRank)
			st.developedMinors++;
	}

	// mobility: non-pawn pieces (pawn captures come via attacksOf, advances below)
	for (uint64_t m = ownOcc; m; )
	{
		Square s = Square(board::lsbClear(m));

		if (board.piece(s) == piece::King || board.piece(s) == piece::Pawn)
			continue;

		st.mobility += board::count(attacksOf(board, s) & ~ownOcc);
	}

	for (uint64_t m = ownPawns; m; )
	{
		Square	s = Square(board::lsbClear(m));
		unsigned	r = sq::rank(s);

		st.mobility += board::count(board::PawnAttacks[color][s] & enemyOcc);

		if (color == color::White)
		{
			if (r < 7 && board.piece(Square(s + 8)) == piece::None)
			{
				st.mobility++;
				if (r == 1 && board.piece(Square(s + 16)) == piece::None)
					st.mobility++;
			}
		}
		else
		{
			if (r > 0 && board.piece(Square(s - 8)) == piece::None)
			{
				st.mobility++;
				if (r == 6 && board.piece(Square(s - 16)) == piece::None)
					st.mobility++;
			}
		}
	}

	return st;
}


// ----------------------------------------------------------------------
// king safety
// ----------------------------------------------------------------------

struct KingSafety
{
	KingSafety() { ::memset(this, 0, sizeof(*this)); }

	unsigned	shieldPawns;
	unsigned	openFilesNearKing;
	unsigned	semiOpenFilesNearKing;
	unsigned	attackers;
	unsigned	defenders;
	bool		castled;
	char		kingSquare[3];
};

KingSafety
computeKingSafety(Board const& board, color::ID color)
{
	color::ID const	opp = color::opposite(color);
	Square const		ksq = board.kingSquare(color);

	KingSafety ks;

	::snprintf(ks.kingSquare, sizeof(ks.kingSquare), "%s", sq::printAlgebraic(ksq));

	uint64_t const	allPawns = board.pawns();
	uint64_t const	ownPawns = board.pawns(color);

	uint64_t zone = board::KingAttacks[ksq] | (uint64_t(1) << ksq);

	int kf = sq::fyle(ksq);
	int kr = sq::rank(ksq);

	for (int f = kf - 1; f <= kf + 1; ++f)
	{
		if (f < 0 || f > 7)
			continue;

		if (allPawns & board::FyleMask[f])
		{
			if (!(ownPawns & board::FyleMask[f]))
				ks.semiOpenFilesNearKing++;
		}
		else
		{
			ks.openFilesNearKing++;
		}

		for (int i = 1; i <= 2; ++i)
		{
			int rr = (color == color::White) ? kr + i : kr - i;

			if (rr >= 0 && rr <= 7 && (ownPawns & board::FyleMask[f] & board::RankMask[rr]))
				ks.shieldPawns++;
		}
	}

	for (uint64_t m = board.pieces(opp); m; )
	{
		if (attacksOf(board, Square(board::lsbClear(m))) & zone)
			ks.attackers++;
	}

	for (uint64_t m = board.pieces(color); m; )
	{
		Square s = Square(board::lsbClear(m));
		if (board.piece(s) != piece::King && (attacksOf(board, s) & zone))
			ks.defenders++;
	}

	sq::Rank home = (color == color::White) ? sq::Rank1 : sq::Rank8;
	ks.castled = (kr == home) && (kf == 2 || kf == 6);

	return ks;
}


// ----------------------------------------------------------------------
// material
// ----------------------------------------------------------------------

struct MaterialStats
{
	MaterialStats() { ::memset(this, 0, sizeof(*this)); }

	unsigned	pawn, knight, bishop, rook, queen;
	unsigned	nonPawns;
	int		valueCp;
	bool		hasLightBishop;
	bool		hasDarkBishop;
};

MaterialStats
computeMaterial(Board const& board, color::ID color)
{
	MaterialStats st;

	// read from bitboards, not the cached m_material: the cache is not
	// refreshed on a throw-away Board after doMove()
	st.pawn	= board::count(board.pawns(color));
	st.knight	= board::count(board.knights(color));
	st.bishop	= board::count(board.bishops(color));
	st.rook	= board::count(board.rooks(color));
	st.queen	= board::count(board.queens(color));
	st.nonPawns	= st.knight + st.bishop + st.rook + st.queen;

	st.valueCp = 100 * int(st.pawn) + 320 * int(st.knight) + 330 * int(st.bishop)
				  + 500 * int(st.rook) + 900 * int(st.queen);

	for (uint64_t mm = board.bishops(color); mm; )
	{
		Square s = Square(board::lsbClear(mm));
		if (squareIsLight(s)) st.hasLightBishop = true; else st.hasDarkBishop = true;
	}

	return st;
}

// ----------------------------------------------------------------------
// named claims (for the language-layer claim checker)
// ----------------------------------------------------------------------

bool predIsolated(Board const& b, color::ID c) { return computePawns(b, c).isolated > 0; }
bool predDoubled(Board const& b, color::ID c)  { return computePawns(b, c).doubled > 0; }
bool predBackward(Board const& b, color::ID c) { return computePawns(b, c).backward > 0; }
bool predPassed(Board const& b, color::ID c)   { return computePawns(b, c).passed > 0; }
bool predIqp(Board const& b, color::ID c)      { return computePawns(b, c).iqp; }
bool predHanging(Board const& b, color::ID c)  { return computePawns(b, c).hanging; }

bool predBishopPair(Board const& b, color::ID c) { return computeMaterial(b, c).bishop >= 2; }
bool predOutpost(Board const& b, color::ID c)    { return computePieces(b, c).knightsOutposted > 0; }
bool predCastled(Board const& b, color::ID c)    { return computeKingSafety(b, c).castled; }
bool predBackRank(Board const& b, color::ID c)   { return backRankWeak(b, c); }
bool predPin(Board const& b, color::ID c)        { return pinnedPieces(b, c) != 0; }
bool predEnPrise(Board const& b, color::ID c)    { return enPrisePieces(b, c) != 0; }

bool predOpenFile(Board const& b, color::ID)
{
	uint64_t const pawns = b.pawns();
	for (unsigned f = 0; f < 8; ++f)
		if (!(pawns & board::FyleMask[f]))
			return true;
	return false;
}

bool predSemiOpenFile(Board const& b, color::ID c)
{
	uint64_t const pawns = b.pawns(c);
	for (unsigned f = 0; f < 8; ++f)
		if (!(pawns & board::FyleMask[f]))
			return true;
	return false;
}

bool predOppositeBishops(Board const& b, color::ID)
{
	MaterialStats const w = computeMaterial(b, color::White);
	MaterialStats const k = computeMaterial(b, color::Black);
	return    (w.hasLightBishop && !w.hasDarkBishop && k.hasDarkBishop && !k.hasLightBishop)
	       || (w.hasDarkBishop && !w.hasLightBishop && k.hasLightBishop && !k.hasDarkBishop);
}

bool predFork(Board const& b, color::ID attacker)
{
	color::ID const	opp = color::opposite(attacker);
	uint64_t const	nonPawnEnemy = b.pieces(opp) & ~b.pawns(opp);

	for (uint64_t m = b.pieces(attacker); m; )
	{
		Square s = Square(board::lsbClear(m));
		if (b.piece(s) == piece::King)
			continue;
		if (board::count(attacksOf(b, s) & nonPawnEnemy) >= 2)
			return true;
	}

	return false;
}

bool isSkeweringSlider(Board const& board, Square s)
{
	static int const Ortho[4][2] = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } };
	static int const Diag[4][2]  = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } };

	piece::Type const pt = board.piece(s);
	color::ID const   c  = board.color(s);

	if (pt != piece::Bishop && pt != piece::Rook && pt != piece::Queen)
		return false;

	for (unsigned d = 0; d < 8; ++d)
	{
		bool const diagonal = d >= 4;

		if (diagonal && pt == piece::Rook)    continue;
		if (!diagonal && pt == piece::Bishop) continue;

		int df = diagonal ? Diag[d - 4][0] : Ortho[d][0];
		int dr = diagonal ? Diag[d - 4][1] : Ortho[d][1];
		int f = sq::fyle(s);
		int r = sq::rank(s);

		Square first = sq::Null;
		Square second = sq::Null;

		for ( ; ; )
		{
			f += df;
			r += dr;

			if (f < 0 || f > 7 || r < 0 || r > 7)
				break;

			Square const t = sq::make(Square(f), Square(r));

			if (board.piece(t) == piece::None)
				continue;
			if (board.color(t) == c)
				break;

			if (first == sq::Null) first = t;
			else { second = t; break; }
		}

		if (   first != sq::Null && second != sq::Null
		    && pieceValue(board.piece(first)) > pieceValue(board.piece(second)))
			return true;
	}

	return false;
}

bool predSkewer(Board const& b, color::ID c)
{
	for (uint64_t m = b.pieces(c); m; )
		if (isSkeweringSlider(b, Square(board::lsbClear(m))))
			return true;
	return false;
}

} // anonymous namespace


// ----------------------------------------------------------------------
// public API
// ----------------------------------------------------------------------

void
ChessFacts::toJson(Board const& board, variant::Type variant, mstl::string& result)
{
	PawnStats const	wPawns = computePawns(board, color::White);
	PawnStats const	bPawns = computePawns(board, color::Black);
	PieceStats const	wPieces = computePieces(board, color::White);
	PieceStats const	bPieces = computePieces(board, color::Black);
	KingSafety const	wKing = computeKingSafety(board, color::White);
	KingSafety const	bKing = computeKingSafety(board, color::Black);
	MaterialStats const	wMat = computeMaterial(board, color::White);
	MaterialStats const	bMat = computeMaterial(board, color::Black);

	unsigned nonPawnValue = unsigned(wMat.valueCp - 100 * int(wMat.pawn))
								 + unsigned(bMat.valueCp - 100 * int(bMat.pawn));
	unsigned nonPawnCount = wMat.nonPawns + bMat.nonPawns;

	color::ID const	stm = board.sideToMove();
	bool const		inCheck = board.checkers() != 0;

	char const* phase =
		(nonPawnValue <= 1300 || nonPawnCount <= 6) ? "endgame"
		: (board.plyNumber() <= 24 && wMat.nonPawns + bMat.nonPawns >= 10 ? "opening"
		: "middlegame");

	Json j(result);

	j.beginObject();

	j.str("fen", board.toFen(variant).c_str());
	j.str("sideToMove", board.sideToMove() == color::White ? "white" : "black");
	j.str("phase", phase);
	j.num("ply", board.plyNumber());
	j.num("moveNumber", board.moveNumber());
	j.num("halfmoveClock", board.halfMoveClock());
	j.boolean("inCheck", inCheck);

	// material -----------------------------------------------------------
	j.keyedObject("material");
	{
		j.keyedObject("white");
		j.num("pawns", wMat.pawn);
		j.num("knights", wMat.knight);
		j.num("bishops", wMat.bishop);
		j.num("rooks", wMat.rook);
		j.num("queens", wMat.queen);
		j.num("nonPawns", wMat.nonPawns);
		j.num("valueCp", wMat.valueCp);
		j.boolean("bishopPair", wMat.bishop >= 2);
		j.endObject();

		j.keyedObject("black");
		j.num("pawns", bMat.pawn);
		j.num("knights", bMat.knight);
		j.num("bishops", bMat.bishop);
		j.num("rooks", bMat.rook);
		j.num("queens", bMat.queen);
		j.num("nonPawns", bMat.nonPawns);
		j.num("valueCp", bMat.valueCp);
		j.boolean("bishopPair", bMat.bishop >= 2);
		j.endObject();

		j.num("balanceCp", wMat.valueCp - bMat.valueCp);
		j.boolean("oppositeColouredBishops",
					 (wMat.hasLightBishop && !wMat.hasDarkBishop && bMat.hasDarkBishop && !bMat.hasLightBishop)
				  || (wMat.hasDarkBishop && !wMat.hasLightBishop && bMat.hasLightBishop && !bMat.hasDarkBishop));
	}
	j.endObject();

	// pawns --------------------------------------------------------------
	j.keyedObject("pawns");
	{
		j.keyedObject("white");
		j.num("count", wPawns.count);
		j.num("islands", wPawns.islands);
		j.num("doubled", wPawns.doubled);
		j.num("isolated", wPawns.isolated);
		j.num("backward", wPawns.backward);
		j.num("passed", wPawns.passed);
		j.num("protected", wPawns.protectedPawns);
		j.num("connected", wPawns.connected);
		j.num("advanced", wPawns.advanced);
		j.num("queenside", wPawns.queenside);
		j.num("kingside", wPawns.kingside);
		j.key("files");
		j.numList(wPawns.file, 8);
		j.boolean("isolatedQueenPawn", wPawns.iqp);
		j.boolean("hangingPawns", wPawns.hanging);
		j.endObject();

		j.keyedObject("black");
		j.num("count", bPawns.count);
		j.num("islands", bPawns.islands);
		j.num("doubled", bPawns.doubled);
		j.num("isolated", bPawns.isolated);
		j.num("backward", bPawns.backward);
		j.num("passed", bPawns.passed);
		j.num("protected", bPawns.protectedPawns);
		j.num("connected", bPawns.connected);
		j.num("advanced", bPawns.advanced);
		j.num("queenside", bPawns.queenside);
		j.num("kingside", bPawns.kingside);
		j.key("files");
		j.numList(bPawns.file, 8);
		j.boolean("isolatedQueenPawn", bPawns.iqp);
		j.boolean("hangingPawns", bPawns.hanging);
		j.endObject();
	}
	j.endObject();

	// files --------------------------------------------------------------
	{
		uint64_t const allPawns	= board.pawns();
		uint64_t const whitePawns	= board.pawns(color::White);
		uint64_t const blackPawns	= board.pawns(color::Black);

		unsigned open = 0, semiOpenWhite = 0, semiOpenBlack = 0;

		for (unsigned f = 0; f < 8; ++f)
		{
			if (!(allPawns & board::FyleMask[f]))		open |= (1u << f);
			if (!(whitePawns & board::FyleMask[f]))	semiOpenWhite |= (1u << f);
			if (!(blackPawns & board::FyleMask[f]))	semiOpenBlack |= (1u << f);
		}

		j.keyedObject("files");
		j.key("open");				j.fileList(open);
		j.key("semiOpenForWhite");	j.fileList(semiOpenWhite);
		j.key("semiOpenForBlack");	j.fileList(semiOpenBlack);
		j.endObject();
	}

	// piece play ---------------------------------------------------------
	j.keyedObject("pieces");
	{
		j.keyedObject("white");
		j.num("badBishops", wPieces.badBishops);
		j.num("knightsOutposted", wPieces.knightsOutposted);
		j.num("rooksOnOpenFile", wPieces.rooksOnOpenFile);
		j.num("rooksOnSemiOpenFile", wPieces.rooksOnSemiOpenFile);
		j.num("rooksOnSeventh", wPieces.rooksOnSeventh);
		j.num("developedMinors", wPieces.developedMinors);
		j.num("mobility", wPieces.mobility);
		j.endObject();

		j.keyedObject("black");
		j.num("badBishops", bPieces.badBishops);
		j.num("knightsOutposted", bPieces.knightsOutposted);
		j.num("rooksOnOpenFile", bPieces.rooksOnOpenFile);
		j.num("rooksOnSemiOpenFile", bPieces.rooksOnSemiOpenFile);
		j.num("rooksOnSeventh", bPieces.rooksOnSeventh);
		j.num("developedMinors", bPieces.developedMinors);
		j.num("mobility", bPieces.mobility);
		j.endObject();
	}
	j.endObject();

	// king safety --------------------------------------------------------
	j.keyedObject("kingSafety");
	{
		j.keyedObject("white");
		j.num("shieldPawns", wKing.shieldPawns);
		j.num("openFilesNearKing", wKing.openFilesNearKing);
		j.num("semiOpenFilesNearKing", wKing.semiOpenFilesNearKing);
		j.num("attackers", wKing.attackers);
		j.num("defenders", wKing.defenders);
		j.boolean("castled", wKing.castled);
		j.str("kingSquare", wKing.kingSquare);
		j.endObject();

		j.keyedObject("black");
		j.num("shieldPawns", bKing.shieldPawns);
		j.num("openFilesNearKing", bKing.openFilesNearKing);
		j.num("semiOpenFilesNearKing", bKing.semiOpenFilesNearKing);
		j.num("attackers", bKing.attackers);
		j.num("defenders", bKing.defenders);
		j.boolean("castled", bKing.castled);
		j.str("kingSquare", bKing.kingSquare);
		j.endObject();
	}
	j.endObject();

	// tactics ------------------------------------------------------------
	{
		uint64_t const wHanging = undefendedPieces(board, color::White);
		uint64_t const bHanging = undefendedPieces(board, color::Black);

		j.keyedObject("tactics");
		j.key("whitePinned");		j.squareList(pinnedPieces(board, color::White));
		j.key("blackPinned");		j.squareList(pinnedPieces(board, color::Black));
		j.key("whiteUndefended");	j.squareList(wHanging);
		j.key("blackUndefended");	j.squareList(bHanging);
		j.key("checkers");			j.squareList(inCheck ? board.attacks(color::opposite(stm), board.kingSquare(stm)) : 0);
		j.endObject();
	}

	// motifs ------------------------------------------------------------
	j.keyedObject("motifs");
	{
		j.key("forks");
		j.beginObject();
		j.key("white"); appendForks(j, board, color::White);
		j.key("black"); appendForks(j, board, color::Black);
		j.endObject();

		j.key("enPrise");
		j.beginObject();
		j.key("white"); j.squareList(enPrisePieces(board, color::White));
		j.key("black"); j.squareList(enPrisePieces(board, color::Black));
		j.endObject();

		j.key("skewers");
		j.beginObject();
		j.key("white"); appendSkewers(j, board, color::White);
		j.key("black"); appendSkewers(j, board, color::Black);
		j.endObject();

		j.key("backRankWeak");
		j.beginObject();
		j.boolean("white", backRankWeak(board, color::White));
		j.boolean("black", backRankWeak(board, color::Black));
		j.endObject();
	}
	j.endObject();

	appendMoveStats(j, board, variant);

	j.endObject();
}


void
ChessFacts::toMoveJson( Board const& before,
                        Move const& move,
                        variant::Type variant,
                        mstl::string& result)
{
	Move prepared = move;
	before.prepareForPrint(prepared, variant, Board::ExternalRepresentation);

	mstl::string san;
	prepared.printSAN(san, protocol::Standard, encoding::Latin1);

	mstl::string uci;
	Square toSquare = move.to();

	// standard chess UCI names the king's destination square; Chess960 UCI
	// (and scidb's internal Move) names the rook square
	if (move.isCastling() && variant::isNormalChess(variant))
	{
		Square const from = move.from();
		bool const kingside = sq::fyle(move.to()) > sq::fyle(from);
		toSquare = sq::make(kingside ? sq::FyleG : sq::FyleC, sq::rank(from));
	}

	uci += sq::printAlgebraic(move.from());
	uci += sq::printAlgebraic(toSquare);

	if (move.isPromotion())
	{
		char c = piece::print(move.promoted());
		if (c >= 'A' && c <= 'Z')
			c = char(c - 'A' + 'a');
		uci += c;
	}

	Board after(before);
	after.doMove(move, variant);

	color::ID const	mover = before.sideToMove();
	unsigned const	status = after.checkState(variant);

	Json j(result);
	j.beginObject();

	j.str("san", san.c_str());
	j.str("uci", uci.c_str());
	j.str("from", sq::printAlgebraic(move.from()));
	j.str("to", sq::printAlgebraic(move.to()));
	j.str("piece", pieceLetter(move.moved()));
	j.str("color", mover == color::White ? "white" : "black");

	j.boolean("capture", move.isCapture());
	if (move.isCapture()) j.str("captured", pieceLetter(move.captured()));
	else                 j.nullValue("captured");

	if (move.isPromotion()) j.str("promotion", pieceLetter(move.promoted()));
	else                    j.nullValue("promotion");

	j.boolean("castling", move.isCastling());
	j.boolean("enPassant", move.isEnPassant());
	j.boolean("check", (status & Board::Check) != 0);
	j.boolean("mate", (status & Board::Checkmate) != 0);
	j.boolean("stalemate", (status & Board::Stalemate) != 0);

	// material swing caused by the move: what the opponent lost minus what
	// the mover lost (both sides measured from bitboards after doMove())
	{
		MaterialStats const wBefore = computeMaterial(before, color::White);
		MaterialStats const wAfter  = computeMaterial(after, color::White);
		MaterialStats const bBefore = computeMaterial(before, color::Black);
		MaterialStats const bAfter  = computeMaterial(after, color::Black);

		int const whiteDelta = wAfter.valueCp - wBefore.valueCp;
		int const blackDelta = bAfter.valueCp - bBefore.valueCp;

		j.num("materialChangeCp", mover == color::White ? whiteDelta - blackDelta
		                                                   : blackDelta - whiteDelta);
		j.num("materialBalanceWhiteCp", wAfter.valueCp - bAfter.valueCp);
	}

	// development: a minor piece left its home rank
	{
		sq::Rank const	home = (mover == color::White) ? sq::Rank1 : sq::Rank8;
		piece::Type const	pt = move.moved();

		j.boolean("developed",
					  (pt == piece::Knight || pt == piece::Bishop) && sq::rank(move.from()) == home);
	}

	// pawn-structure delta (after minus before)
	j.keyedObject("structureDelta");
	for (unsigned ci = 0; ci < 2; ++ci)
	{
		color::ID const	c = color::ID(ci);
		PawnStats const	pb = computePawns(before, c);
		PawnStats const	pa = computePawns(after, c);

		j.keyedObject(c == color::White ? "white" : "black");
		j.num("passed",   int(pa.passed)   - int(pb.passed));
		j.num("isolated", int(pa.isolated) - int(pb.isolated));
		j.num("doubled",  int(pa.doubled)  - int(pb.doubled));
		j.num("backward", int(pa.backward) - int(pb.backward));
		j.num("islands",  int(pa.islands)  - int(pb.islands));
		j.boolean("createsIqp", !pb.iqp && pa.iqp);
		j.endObject();
	}
	j.endObject();

	// pieces that become undefended or pinned because of the move
	{
		uint64_t const wNewHang = undefendedPieces(after, color::White) & ~undefendedPieces(before, color::White);
		uint64_t const bNewHang = undefendedPieces(after, color::Black) & ~undefendedPieces(before, color::Black);
		uint64_t const wNewPin  = pinnedPieces(after, color::White) & ~pinnedPieces(before, color::White);
		uint64_t const bNewPin  = pinnedPieces(after, color::Black) & ~pinnedPieces(before, color::Black);

		j.key("newUndefended");
		j.beginObject();
		j.key("white"); j.squareList(wNewHang);
		j.key("black"); j.squareList(bNewHang);
		j.endObject();

		j.key("newPins");
		j.beginObject();
		j.key("white"); j.squareList(wNewPin);
		j.key("black"); j.squareList(bNewPin);
		j.endObject();
	}

	j.key("discoveredAttacks");
	appendDiscovered(j, before, after, move, mover);

	{
		uint64_t const wNewEnPrise = enPrisePieces(after, color::White) & ~enPrisePieces(before, color::White);
		uint64_t const bNewEnPrise = enPrisePieces(after, color::Black) & ~enPrisePieces(before, color::Black);

		j.key("newEnPrise");
		j.beginObject();
		j.key("white"); j.squareList(wNewEnPrise);
		j.key("black"); j.squareList(bNewEnPrise);
		j.endObject();
	}

	j.key("removesDefender");
	j.squareList(removesDefender(before, after, move, mover));

	if (move.isCapture())
	{
		// the king must carry a large value, or the exchange treats it as a
		// free recapture and deflates every defended-capture evaluation
		static int const Values[7] = { 0, 32767, 900, 500, 330, 320, 100 };
		int const see = before.staticExchangeEvaluator(move, Values);
		bool const isMate = (status & Board::Checkmate) != 0;

		j.num("seeCp", see);
		j.boolean("losesMaterial", see < 0 && !isMate);
	}
	else
	{
		j.nullValue("seeCp");
		j.boolean("losesMaterial", false);
	}

	j.str("fenAfter", after.toFen(variant).c_str());
	j.endObject();
}


void
ChessFacts::toText(Board const& board, variant::Type variant, mstl::string& result)
{
	PawnStats const	wPawns = computePawns(board, color::White);
	PawnStats const	bPawns = computePawns(board, color::Black);
	PieceStats const	wPieces = computePieces(board, color::White);
	PieceStats const	bPieces = computePieces(board, color::Black);
	KingSafety const	wKing = computeKingSafety(board, color::White);
	KingSafety const	bKing = computeKingSafety(board, color::Black);
	MaterialStats const	wMat = computeMaterial(board, color::White);
	MaterialStats const	bMat = computeMaterial(board, color::Black);

	result.clear();
	result.format("%s  (%s to move)\n", board.toFen(variant).c_str(),
					  board.sideToMove() == color::White ? "white" : "black");

	result.format("material   white Q%u R%u B%u N%u P%u   black Q%u R%u B%u N%u P%u   balance %+dcp\n",
					  wMat.queen, wMat.rook, wMat.bishop, wMat.knight, wMat.pawn,
					  bMat.queen, bMat.rook, bMat.bishop, bMat.knight, bMat.pawn,
					  wMat.valueCp - bMat.valueCp);

	result.format("pawns      white: islands=%u doubled=%u isolated=%u backward=%u passed=%u iqp=%s hanging=%s\n",
					  wPawns.islands, wPawns.doubled, wPawns.isolated, wPawns.backward,
					  wPawns.passed, wPawns.iqp ? "yes" : "no", wPawns.hanging ? "yes" : "no");
	result.format("           black: islands=%u doubled=%u isolated=%u backward=%u passed=%u iqp=%s hanging=%s\n",
					  bPawns.islands, bPawns.doubled, bPawns.isolated, bPawns.backward,
					  bPawns.passed, bPawns.iqp ? "yes" : "no", bPawns.hanging ? "yes" : "no");

	result.format("pieces     white: badBishops=%u outposts=%u rooksOpen=%u rooks7th=%u developed=%u mobility=%u\n",
					  wPieces.badBishops, wPieces.knightsOutposted, wPieces.rooksOnOpenFile,
					  wPieces.rooksOnSeventh, wPieces.developedMinors, wPieces.mobility);
	result.format("           black: badBishops=%u outposts=%u rooksOpen=%u rooks7th=%u developed=%u mobility=%u\n",
					  bPieces.badBishops, bPieces.knightsOutposted, bPieces.rooksOnOpenFile,
					  bPieces.rooksOnSeventh, bPieces.developedMinors, bPieces.mobility);

	result.format("king       white: shield=%u openNear=%u semiOpen=%u attackers=%u defenders=%u castled=%s\n",
					  wKing.shieldPawns, wKing.openFilesNearKing, wKing.semiOpenFilesNearKing,
					  wKing.attackers, wKing.defenders, wKing.castled ? "yes" : "no");
	result.format("           black: shield=%u openNear=%u semiOpen=%u attackers=%u defenders=%u castled=%s\n",
					  bKing.shieldPawns, bKing.openFilesNearKing, bKing.semiOpenFilesNearKing,
					  bKing.attackers, bKing.defenders, bKing.castled ? "yes" : "no");

	result += "tactics    whitePinned=";
	appListText(result, pinnedPieces(board, color::White));
	result += " blackPinned=";
	appListText(result, pinnedPieces(board, color::Black));
	result += "\n";
}


bool
ChessFacts::claim(Board const& board, char const* term, int side, bool& known)
{
	known = true;

	auto both = [&](bool (*pred)(Board const&, color::ID)) -> bool
	{
		if (side == 0)
			return pred(board, color::White) || pred(board, color::Black);
		return pred(board, color::ID(side - 1));
	};

	if (::strcmp(term, "isolatedPawn") == 0) return both(predIsolated);
	if (::strcmp(term, "doubledPawns") == 0) return both(predDoubled);
	if (::strcmp(term, "backwardPawn") == 0) return both(predBackward);
	if (::strcmp(term, "passedPawn") == 0)   return both(predPassed);
	if (::strcmp(term, "iqp") == 0)          return both(predIqp);
	if (::strcmp(term, "hangingPawns") == 0) return both(predHanging);
	if (::strcmp(term, "bishopPair") == 0)   return both(predBishopPair);
	if (::strcmp(term, "outpost") == 0)      return both(predOutpost);
	if (::strcmp(term, "castled") == 0)      return both(predCastled);
	if (::strcmp(term, "backRank") == 0)     return both(predBackRank);
	if (::strcmp(term, "pin") == 0)          return both(predPin);
	if (::strcmp(term, "enPrise") == 0)      return both(predEnPrise);
	if (::strcmp(term, "openFile") == 0)     return predOpenFile(board, color::White);
	if (::strcmp(term, "semiOpenFile") == 0) return both(predSemiOpenFile);
	if (::strcmp(term, "oppositeBishops") == 0) return predOppositeBishops(board, color::White);
	if (::strcmp(term, "fork") == 0)         return both(predFork);
	if (::strcmp(term, "skewer") == 0)       return both(predSkewer);

	known = false;
	return false;
}

} // namespace db

// vi:set ts=3 sw=3:
