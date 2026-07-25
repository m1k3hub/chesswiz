// ======================================================================
// Headless benchmark for database open/search/prep workflows.
// ======================================================================

#include "db/db_board.h"
#include "db/db_board_base.h"
#include "db/db_database.h"
#include "db/db_exception.h"
#include "db/db_home_pawns.h"
#include "db/db_line.h"
#include "db/db_maintenance.h"
#include "db/db_player_stats.h"
#include "db/db_search.h"
#include "db/db_signature.h"
#include "db/db_tree.h"

#include "db/sci/sci_encoder.h"
#include "db/si3/si3_encoder.h"

#include "sys/sys_file.h"
#include "sys/sys_time.h"
#include "sys/sys_utf8_codec.h"

#include "mstl/m_string.h"

#include "util/u_progress.h"

#include <tcl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

using namespace db;

namespace tcl { namespace bits { Tcl_Interp* interp = nullptr; } }

namespace {

struct TclInterpreter
{
	TclInterpreter()
	{
		tcl::bits::interp = Tcl_CreateInterp();
		Tcl_Init(tcl::bits::interp);
	}

	~TclInterpreter()
	{
		Tcl_DeleteInterp(tcl::bits::interp);
		tcl::bits::interp = nullptr;
	}
};


struct Config
{
	mstl::string source;
	mstl::string encoding;
	unsigned runs;
	bool includeDuplicates;
};


struct Result
{
	uint64_t openUsec;
	uint64_t searchUsec;
	uint64_t prepUsec;
	uint64_t treeBuildUsec;
	uint64_t treeLookupUsec;
	unsigned wildcardMatches;
	unsigned ratingMatches;
	unsigned ecoRows;
	unsigned duplicateGroups;
	unsigned prepGames;
	unsigned treeMoves;
};


void
initializeStatics()
{
	db::tag::initialize();
	db::castling::initialize();
	db::board::base::initialize();
	db::Board::initialize();
	db::HomePawns::initialize();
	db::Signature::initialize();
	db::sci::Encoder::initialize();
	db::si3::Encoder::initialize();
}


void
printUsageAndExit(char const* argv0, int rc)
{
	::fprintf(stderr, "Usage: %s <source-db> [--runs N] [--encoding ENC] [--duplicates]\n", argv0);
	::exit(rc);
}


unsigned
parseUnsignedOption(char const* value, char const* argv0)
{
	char* end = nullptr;
	unsigned long parsed = ::strtoul(value, &end, 10);

	if (!value || !*value || !end || *end != '\0' || parsed == 0 || parsed > UINT_MAX)
		printUsageAndExit(argv0, 1);

	return unsigned(parsed);
}


Config
parseArgs(int argc, char** argv)
{
	Config cfg;
	cfg.runs = 1;
	cfg.encoding = sys::utf8::Codec::automatic();
	cfg.includeDuplicates = false;

	for (int i = 1; i < argc; ++i)
	{
		if (::strcmp(argv[i], "--help") == 0)
		{
			printUsageAndExit(argv[0], 0);
		}
			else if (::strcmp(argv[i], "--runs") == 0)
			{
				if (++i == argc)
					printUsageAndExit(argv[0], 1);

				cfg.runs = parseUnsignedOption(argv[i], argv[0]);
			}
		else if (::strcmp(argv[i], "--encoding") == 0)
		{
			if (++i == argc)
				printUsageAndExit(argv[0], 1);
			cfg.encoding = argv[i];
		}
		else if (::strcmp(argv[i], "--duplicates") == 0)
		{
			cfg.includeDuplicates = true;
		}
		else if (argv[i][0] == '-')
		{
			printUsageAndExit(argv[0], 1);
		}
		else
		{
			if (!cfg.source.empty())
				printUsageAndExit(argv[0], 1);
			cfg.source = argv[i];
		}
	}

	if (cfg.source.empty())
		printUsageAndExit(argv[0], 1);

	return cfg;
}


unsigned
countMatches(Database const& db, Search const& search)
{
	unsigned matches = 0;

	for (unsigned i = 0, n = db.countGames(); i < n; ++i)
	{
		if (!db.gameInfo(i).isDeleted() && search.match(db.gameInfo(i)))
			++matches;
	}

	return matches;
}


NamebasePlayer const*
findBusyPlayer(Database const& db)
{
	unsigned bestCount = 0;
	NamebasePlayer const* bestPlayer = 0;

	for (unsigned i = 0, n = db.countGames(); i < n; ++i)
	{
		GameInfo const& info = db.gameInfo(i);

		if (info.isDeleted())
			continue;

		for (unsigned side = 0; side < 2; ++side)
		{
			NamebasePlayer const* player = info.playerEntry(color::ID(side));
			if (!player)
				continue;

			unsigned count = player->frequency();
			if (count > bestCount)
			{
				bestCount = count;
				bestPlayer = player;
			}
		}
	}

	return bestPlayer;
}


Result
runOnce(Config const& cfg)
{
	Result result;
	result.openUsec = 0;
	result.searchUsec = 0;
	result.prepUsec = 0;
	result.treeBuildUsec = 0;
	result.treeLookupUsec = 0;
	result.wildcardMatches = 0;
	result.ratingMatches = 0;
	result.ecoRows = 0;
	result.duplicateGroups = 0;
	result.prepGames = 0;
	result.treeMoves = 0;

	uint64_t start = sys::time::timestamp();
	Database db(cfg.source, cfg.encoding, permission::ReadOnly, util::Progress::null());
	result.openUsec = sys::time::timestamp() - start;

	start = sys::time::timestamp();
	SearchPlayerName wildcard(SearchPlayerName::Any, "*a*");
	SearchRating rating(rating::Elo, SearchRating::Average, 2000, 2600);
	result.wildcardMatches = countMatches(db, wildcard);
	result.ratingMatches = countMatches(db, rating);
	result.ecoRows = maintenance::computeEcoStats(db, db.variant()).size();
	if (cfg.includeDuplicates)
		result.duplicateGroups = maintenance::findDuplicates(db).size();
	result.searchUsec = sys::time::timestamp() - start;

	start = sys::time::timestamp();
	NamebasePlayer const* player = findBusyPlayer(db);
	if (player)
	{
		PlayerStats stats;
		db.playerStatistic(*player, stats);
		result.prepGames = stats.countGames();
	}
	result.prepUsec = sys::time::timestamp() - start;

	if (db.variant() == variant::Normal && !format::isChessBaseFormat(db.format()))
	{
		Board startBoard;
		startBoard.setStandardPosition(db.variant());
		Board currentBoard(startBoard);
		uint16_t lineBuf[opening::Max_Line_Length] = {0};
		Line line(lineBuf, 0);
		Tree::TreeP tree;

		db.treeCache().clear();
		db.openAsyncTreeSearchReader();
		start = sys::time::timestamp();
		tree.reset(Tree::makeTree(tree,
										 variant::Standard,
										 startBoard,
										 currentBoard,
										 line,
										 0,
										 db,
										 tree::Fast,
										 tree::MainlineOnly,
										 rating::Elo,
										 util::Progress::null()));
		result.treeBuildUsec = sys::time::timestamp() - start;
		db.closeAsyncTreeSearchReader();

		if (tree)
		{
			tree->compressFilter();
			result.treeMoves = tree->size();
			Tree::addToCache(tree.get());

			start = sys::time::timestamp();
			Tree* cached = Tree::lookup(db, currentBoard, tree::Fast, tree::MainlineOnly, rating::Elo);
			result.treeLookupUsec = sys::time::timestamp() - start;
			if (!cached)
				result.treeLookupUsec = 0;
		}
	}

	return result;
}


void
printResult(unsigned run, Result const& result)
{
	::printf("run=%u open_usec=%llu search_usec=%llu prep_usec=%llu tree_build_usec=%llu tree_lookup_usec=%llu wildcard_matches=%u rating_matches=%u eco_rows=%u duplicate_groups=%u prep_games=%u tree_moves=%u\n",
				run,
				static_cast<unsigned long long>(result.openUsec),
				static_cast<unsigned long long>(result.searchUsec),
				static_cast<unsigned long long>(result.prepUsec),
				static_cast<unsigned long long>(result.treeBuildUsec),
				static_cast<unsigned long long>(result.treeLookupUsec),
				result.wildcardMatches,
				result.ratingMatches,
				result.ecoRows,
				result.duplicateGroups,
				result.prepGames,
				result.treeMoves);
}

} // namespace


int
main(int argc, char** argv)
{
	try
	{
		TclInterpreter tcl;
		initializeStatics();
		Config cfg = parseArgs(argc, argv);

		for (unsigned run = 1; run <= cfg.runs; ++run)
			printResult(run, runOnce(cfg));

		return 0;
	}
	catch (IOException const& exc)
	{
		::fprintf(stderr, "I/O exception: %s\n", exc.what());
	}
	catch (mstl::exception const& exc)
	{
		::fprintf(stderr, "exception: %s\n", exc.what());
	}

	return 1;
}
