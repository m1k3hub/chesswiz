// ======================================================================
// cdb2pgn -- export a Scidb/ChessBase database to PGN (with comments/NAGs).
//
//   cdb2pgn <database> <out.pgn> [encoding] [max-games]
//
// Reads any database Scidb can open (.cbh, .sci, .si4, ...) game by game and
// writes PGN through PgnWriter, so human/engine comments and NAGs survive.
// Intended for the corpus pipeline: it feeds scripts/annotation_extract.py.
// ======================================================================

#include "db_database.h"
#include "db_board.h"
#include "db_board_base.h"
#include "db_eco_table.h"
#include "db_home_pawns.h"
#include "db_signature.h"
#include "db_pgn_writer.h"
#include "db_exception.h"
#include "db_common.h"

#include "sci/sci_encoder.h"
#include "si3/si3_encoder.h"

#include "sys_utf8_codec.h"

#include "util/u_progress.h"

#include "m_ofstream.h"
#include "m_ifstream.h"
#include "m_string.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <tcl.h>

using namespace db;

// Required by sys_thread.o (as in cdb2sci).
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

// The ECO table must be loaded, or GameInfo::addOpening() recurses forever.
void
loadEcoFile()
{
	mstl::string path(SHAREDIR "/data/eco.bin");
	mstl::ifstream stream(path, mstl::ios_base::in | mstl::ios_base::binary);

	if (!stream)
	{
		fprintf(stderr, "cannot open ECO file '%s'\n", path.c_str());
		exit(1);
	}

	EcoTable::specimen(variant::Normal).load(stream, variant::Normal);
}

} // namespace


int
main(int argc, char** argv)
{
	if (argc < 3)
	{
		fprintf(stderr, "usage: cdb2pgn <database> <out.pgn> [encoding] [max-games]\n");
		return 2;
	}

	mstl::string	path(argv[1]);
	mstl::string	outPath(argv[2]);
	mstl::string	encoding = (argc > 3) ? argv[3] : sys::utf8::Codec::automatic();
	unsigned			maxGames = (argc > 4) ? unsigned(::strtoul(argv[4], nullptr, 10)) : 0;

	try
	{
		TclInterpreter tcl;
		initializeStatics();
		loadEcoFile();

		util::Progress& progress = util::Progress::null();
		Database			 src(path, encoding, permission::ReadOnly, progress);

		mstl::ofstream out(outPath);

		if (!out)
		{
			fprintf(stderr, "cannot create '%s'\n", outPath.c_str());
			return 1;
		}

		PgnWriter writer(	src.format(),
								out,
								sys::utf8::Codec::utf8(),
								PgnWriter::Unix,
								PgnWriter::Default_Flags);

		unsigned n = src.countGames();

		if (maxGames && maxGames < n)
			n = maxGames;

		unsigned written = 0;

		for (unsigned i = 0; i < n; ++i)
		{
			try
			{
				src.exportGame(i, writer);
				++written;
			}
			catch (...)
			{
				// skip games that fail to export
			}
		}

		out.close();
		printf("%u\n", written);
	}
	catch (mstl::exception const& exc)
	{
		fprintf(stderr, "%s\n", exc.what());
		return 1;
	}

	return 0;
}

// vi:set ts=3 sw=3:
