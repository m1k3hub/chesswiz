// ======================================================================
// Runs one game of a database through a parsed CQL query -- see the header.
// ======================================================================

#include "cql_game_matcher.h"
#include "cql_match.h"
#include "cql_designator.h"

#include "db_board.h"
#include "db_common.h"
#include "db_consumer.h"
#include "db_database.h"
#include "db_game_info.h"
#include "db_move.h"

using namespace db;

namespace {

// Walks the decoded game until the first mainline position that satisfies
// the query. When the query uses :forany tags it also tracks, for every
// square, the mark (identity) of the piece standing there.
struct GameConsumer : public db::Consumer
{
	GameConsumer(cql::Match& match, GameInfo const& info, variant::Type variant)
		:db::Consumer(format::Pgn, "utf-8", TagBits(), false)
		,m_match(match)
		,m_info(info)
		,m_variant(variant)
		,m_ply(0)
		,m_hit(-1)
		,m_moves(match.sections() & cql::Match::Section_Moves)
		,m_moveOk(!m_moves)
		,m_variations(match.includesVariations())
		,m_excludes(match.hasExclude())
		,m_tags(match.forAnyCount() != 0)
		,m_markCount(0)
	{
		setVariant(variant);

		for (unsigned i = 0; i < 64; ++i)
			m_mark[i] = 0;
	}

	format::Type format() const override							{ return format::Scidb; }
	void start() override												{}
	void finish() override												{}
	bool beginGame(TagSet const&) override							{ return true; }
	save::State endGame(TagSet const&) override					{ return save::Ok; }

	void sendPrecedingComment(Comment const&, Annotation const&, MarkSet const&) override {}
	void sendTrailingComment(Comment const&, bool) override	{}
	void sendComment(Comment const&) override						{}
	void sendMoveInfo(MoveInfoSet const&) override				{}

	bool sendMove(Move const& move) override						{ return visit(move); }
	bool sendMove(	Move const& move,
						Annotation const&,
						MarkSet const&,
						Comment const&,
						Comment const&) override							{ return visit(move); }

	void beginMoveSection() override
	{
		if (m_tags)
			initMarks();
	}

	void endMoveSection(result::ID) override						{ position(cql::flags::IsFinalPosition); }
	void beginVariation() override									{}
	void endVariation(bool isEmpty) override
	{
		if (m_variations && !isEmpty)
			position(cql::flags::IsInsideVariation);
	}

	// board() is the position before <move>: test it, then decide whether
	// <move> satisfies the move filters for the position it leads to.
	// False stops decoding.
	bool visit(Move const& move)
	{
		if (!m_variations && variationLevel() > 0)
			return true;
		position(variationLevel() > 0 ? cql::flags::IsInsideVariation : 0u);
		// keep going after a hit while an :exclude may still fire
		if (m_hit >= 0 && !m_excludes)
			return false;
		if (m_moves)
			m_moveOk = m_match.match(board(), move, m_variant);
		if (m_tags)
			updateMarks(move);
		++m_ply;
		return true;
	}

	// A position is a candidate only when the move that led to it passed
	// the move filters (so with move filters the start position is not).
	// Variations are visited only for a :variations/:variationsonly query;
	// Position::match applies the include/exclude gate itself.
	void position(unsigned flags)
	{
		if (m_hit < 0 && m_moveOk && m_match.match(m_info, board(), m_variant, flags))
			m_hit = int(m_ply);
	}

	// Each piece of the start position gets a unique mark; the mark travels
	// with the piece (promotion keeps it, a capture destroys it).
	void initMarks()
	{
		cql::clearMarkSquares();

		m_markCount = 0;

		for (unsigned s = 0; s < 64; ++s)
		{
			piece::ID p = board().pieceAt(sq::ID(s));

			if (p != piece::Empty)
			{
				m_mark[s] = Byte(++m_markCount);
				cql::setMarkSquare(int(m_markCount), int(s));
			}
		}
	}

	void updateMarks(Move const& move)
	{
		int from = int(move.from());
		int to = int(move.to());

		if (move.isCastling())
		{
			int rookFrom = to > from ? from + 3 : from - 4;
			int rookTo = to > from ? to - 1 : to + 1;
			int rookMark = m_mark[rookFrom];

			if (rookMark)
			{
				m_mark[rookTo] = Byte(rookMark);
				m_mark[rookFrom] = 0;
				cql::setMarkSquare(rookMark, rookTo);
			}
		}
		else if (move.isEnPassant())
		{
			int captured = board().sideToMove() == color::White ? to - 8 : to + 8;
			int capturedMark = m_mark[captured];

			if (capturedMark)
			{
				m_mark[captured] = 0;
				cql::setMarkSquare(capturedMark, -1);
			}
		}
		else if (move.capturedOrDropped() != piece::None)
		{
			int capturedMark = m_mark[to];

			if (capturedMark)
			{
				m_mark[to] = 0;
				cql::setMarkSquare(capturedMark, -1);
			}
		}

		int pieceMark = m_mark[from];
		m_mark[from] = 0;
		m_mark[to] = Byte(pieceMark);

		if (pieceMark)
			cql::setMarkSquare(pieceMark, to);
	}

	cql::Match&			m_match;
	GameInfo const&	m_info;
	variant::Type		m_variant;
	unsigned				m_ply;
	int					m_hit;
	bool					m_moves;
	bool					m_moveOk;
	bool					m_variations;
	bool					m_excludes;
	bool					m_tags;
	Byte					m_mark[64];
	unsigned				m_markCount;
};


// Reads the piece IDs of the start position, to pick the candidate marks a
// :forany tag may be bound to.
struct MarkScanner : public db::Consumer
{
	MarkScanner(variant::Type variant)
		:db::Consumer(format::Pgn, "utf-8", TagBits(), false)
		,m_count(0)
		,m_ready(false)
	{
		setVariant(variant);
	}

	format::Type format() const override							{ return format::Scidb; }
	void start() override												{}
	void finish() override												{}
	bool beginGame(TagSet const&) override							{ return true; }
	save::State endGame(TagSet const&) override					{ return save::Ok; }

	void sendPrecedingComment(Comment const&, Annotation const&, MarkSet const&) override {}
	void sendTrailingComment(Comment const&, bool) override	{}
	void sendComment(Comment const&) override						{}
	void sendMoveInfo(MoveInfoSet const&) override				{}

	bool sendMove(Move const&) override
	{
		scan();
		return false;
	}

	bool sendMove(	Move const&,
						Annotation const&,
						MarkSet const&,
						Comment const&,
						Comment const&) override
	{
		scan();
		return false;
	}

	void beginMoveSection() override									{}
	void endMoveSection(result::ID) override						{ scan(); }
	void beginVariation() override									{}
	void endVariation(bool) override									{}

	void scan()
	{
		if (m_ready)
			return;
		m_ready = true;
		m_count = 0;

		for (unsigned s = 0; s < 64; ++s)
		{
			piece::ID p = board().pieceAt(sq::ID(s));

			if (p != piece::Empty)
				m_ids[++m_count] = unsigned(p);
		}
	}

	unsigned	m_ids[33];
	unsigned	m_count;
	bool		m_ready;
};

} // namespace


int
cql::matchGame(Database const& db, variant::Type variant, unsigned index, Match& match)
{
	GameInfo const& info = db.gameInfo(index);
	unsigned sections = match.sections();

	match.newGame();

	if ((sections & Match::Section_GameInfo) && !match.match(info, variant, index))
		return -1;

	if (!(sections & (Match::Section_Positions | Match::Section_Moves)))
		return 0;

	if (match.forAnyCount() == 0)
	{
		GameConsumer consumer(match, info, variant);
		db.exportGame(index, consumer);
		return match.excluded() ? -1 : consumer.m_hit;
	}

	// Tagging: the query has to be run once per binding of the tags to marks,
	// and the tags may only take marks whose piece matches (or, after a
	// promotion, eventually matches) the :forany designator. Candidate marks
	// are taken from the start position's pieces.
	unsigned ids[33];
	unsigned count = 0;

	{
		MarkScanner scanner(variant);
		db.exportGame(index, scanner);
		count = scanner.m_count;
		for (unsigned i = 1; i <= count; ++i)
			ids[i] = scanner.m_ids[i];
	}

	unsigned n = match.forAnyCount();
	unsigned mask0 = match.forAny(0).idMask;
	unsigned mask1 = n > 1 ? match.forAny(1).idMask : 0;

	for (unsigned a = 1; a <= count; ++a)
	{
		if (!(mask0 & (1u << ids[a])))
			continue;

		if (n == 1)
		{
			match.newGame();
			cql::clearTagBindings();
			cql::bindTag(match.forAny(0).name, int(a));

			GameConsumer consumer(match, info, variant);
			db.exportGame(index, consumer);

			if (!match.excluded() && consumer.m_hit >= 0)
				return consumer.m_hit;
			continue;
		}

		for (unsigned b = 1; b <= count; ++b)
		{
			if (b == a || !(mask1 & (1u << ids[b])))
				continue;

			match.newGame();
			cql::clearTagBindings();
			cql::bindTag(match.forAny(0).name, int(a));
			cql::bindTag(match.forAny(1).name, int(b));

			GameConsumer consumer(match, info, variant);
			db.exportGame(index, consumer);

			if (!match.excluded() && consumer.m_hit >= 0)
				return consumer.m_hit;
		}
	}

	return -1;
}

// vi:set ts=3 sw=3:
