// ======================================================================
// Dump per-game: index, white, black, fen, mainline SAN moves (TSV).
// Usage: probe_dump_moves <database-path> [game-index-start] [game-index-end]
// Works on any Database-opened format (sci, si3, si4, cbv...).
// Used to compare fallback vs no-fallback decodes against PGN ground truth.
// ======================================================================

#include "db/db_board.h"
#include "db/db_board_base.h"
#include "db/db_database.h"
#include "db/db_eco_table.h"
#include "db/db_exception.h"
#include "db/db_game.h"
#include "db/db_home_pawns.h"
#include "db/db_pgn_reader.h"
#include "db/db_signature.h"
#include "db/db_tag_set.h"

#include "db/sci/sci_encoder.h"
#include "db/si3/si3_encoder.h"

#include "sys/sys_utf8_codec.h"

#include "util/u_progress.h"

#include "mstl/m_ifstream.h"
#include "mstl/m_string.h"

#include <tcl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

}

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
loadEcoFile()
{
	mstl::string path(SHAREDIR "/data/eco.bin");
	mstl::ifstream stream(path, mstl::ios_base::in | mstl::ios_base::binary);

	if (!stream)
	{
		::fprintf(stderr, "cannot open ECO file '%s'\n", path.c_str());
		::exit(1);
	}

	EcoTable::specimen(variant::Normal).load(stream, variant::Normal);
	::fprintf(stderr, "dbg: eco loaded\n");
}


void
usage(char const* argv0)
{
	::fprintf(stderr, "usage: %s <database-path> [start] [end]\n", argv0);
}


int
main(int argc, char** argv)
{
	if (argc < 2 || argc > 4)
	{
		usage(argv[0]);
		return 1;
	}

	util::Progress& progress = util::Progress::null();

	try
	{
		TclInterpreter tcl;
		initializeStatics();
		loadEcoFile();

		::fprintf(stderr, "dbg: opening db\n");
		Database db(argv[1], sys::utf8::Codec::utf8(), permission::ReadOnly, progress);
		::fprintf(stderr, "dbg: db opened, total=%u\n", db.countGames());

		unsigned total = db.countGames();
		unsigned start = 0, end = total;

		if (argc >= 3)
			start = ::strtoul(argv[2], 0, 10);
		if (argc >= 4)
			end = ::strtoul(argv[3], 0, 10);

		if (end > total)
			end = total;

		for (unsigned i = start; i < end; ++i)
		{
			try
			{
				Game game;
				load::State st = db.loadGame(i, game);
				if (st != load::Ok)
					continue;

				TagSet tags;
				db.setupTags(i, tags);

				mstl::string white = tags.value(tag::White);
				mstl::string black = tags.value(tag::Black);
				mstl::string fen   = tags.value(tag::Fen);
				::fprintf(stderr, "game %u: countLength=%u vars=%u subvars=%u\n",
						 i, game.countLength(), game.variationCount(), game.subVariationCount());
				mstl::string result = tags.value(tag::Result);

				// Walk the mainline, collecting SAN.
				mstl::string sanList;
				game.moveToStart();
				unsigned guard = 0;
				while (game.forward() && ++guard < 2000000)
				{
					mstl::string san;
					game.printMove(san, Game::ExportFormat, move::SAN);
					if (!san.empty())
					{
						if (!sanList.empty())
							sanList += " ";
						sanList += san;
					}
				}
				::fprintf(stderr, "game %u: countLength=%u guard=%u variations=%u\n",
						 i, game.countLength(), guard, game.variationCount());

				mstl::string round = tags.value(tag::Round);
				::printf("%u\t%s\t%s\t%s\t%s\t%s\t%s\n",
						 i,
						 white.c_str(), black.c_str(),
						 result.c_str(), fen.c_str(),
						 round.c_str(), sanList.c_str());
				::fflush(stdout);
			}
			catch (mstl::exception const&)
			{
				// Skip games that fail to replay cleanly.
				::fprintf(stderr, "skip game %u (replay failure)\n", i);
				continue;
			}
			catch (std::exception const&)
			{
				::fprintf(stderr, "skip game %u (replay failure)\n", i);
				continue;
			}
		}

		db.close();
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
	catch (std::exception const& exc)
	{
		::fprintf(stderr, "exception: %s\n", exc.what());
	}

	return 1;
}
