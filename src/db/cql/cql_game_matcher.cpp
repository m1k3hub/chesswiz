// ======================================================================
// Runs one game of a database through a parsed CQL query -- see the header.
// ======================================================================

#include "cql_game_matcher.h"
#include "cql_match.h"

#include "db_board.h"
#include "db_consumer.h"
#include "db_database.h"
#include "db_game_info.h"
#include "db_move.h"

using namespace db;

namespace {

// Walks the decoded game until the first mainline position that satisfies
// the query.
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

	bool sendMove(Move const& move) override						{ return visit(move); }
	bool sendMove(	Move const& move,
						Annotation const&,
						MarkSet const&,
						Comment const&,
						Comment const&) override							{ return visit(move); }

	void beginMoveSection() override									{}
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

	cql::Match&			m_match;
	GameInfo const&	m_info;
	variant::Type		m_variant;
	unsigned				m_ply;
	int					m_hit;
	bool					m_moves;
	bool					m_moveOk;
	bool					m_variations;
	bool					m_excludes;
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

	GameConsumer consumer(match, info, variant);
	db.exportGame(index, consumer);
	return match.excluded() ? -1 : consumer.m_hit;
}

// vi:set ts=3 sw=3:
