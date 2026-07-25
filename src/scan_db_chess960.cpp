// ======================================================================
// Scan a database for custom-start and likely Chess960 games.
// Works with any format Database can open, including CBV.
// ======================================================================

#include "db/db_board.h"
#include "db/db_board_base.h"
#include "db/db_database.h"
#include "db/db_eco_table.h"
#include "db/db_exception.h"
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
}


bool
looksLikeChess960Fen(mstl::string const& fen)
{
	mstl::string::size_type first = fen.find(' ');
	if (first == mstl::string::npos)
		return false;

	mstl::string::size_type second = fen.find(' ', first + 1);
	if (second == mstl::string::npos)
		return false;

	mstl::string::size_type third = fen.find(' ', second + 1);
	if (third == mstl::string::npos)
		return false;

	mstl::string castling = fen.substr(second + 1, third - second - 1);

	if (castling.empty() || castling == "-")
		return false;

	for (unsigned i = 0; i < castling.size(); ++i)
	{
		char c = castling[i];
		if ((c >= 'A' && c <= 'H') || (c >= 'a' && c <= 'h'))
			return true;
	}

	return false;
}


void
usage(char const* argv0)
{
	::fprintf(stderr, "usage: %s <database-path>\n", argv0);
}

} // namespace


int
main(int argc, char** argv)
{
	if (argc != 2)
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

		Database db(argv[1], sys::utf8::Codec::utf8(), permission::ReadOnly, progress);

		unsigned total = db.countGames();
		unsigned setups = 0;
		unsigned fens = 0;
		unsigned likely960 = 0;
		unsigned shown = 0;

		::printf("database=%s\n", argv[1]);
		::printf("games=%u\n", total);

		for (unsigned i = 0; i < total; ++i)
		{
			TagSet tags;
			db.setupTags(i, tags);

			bool hasSetup = tags.contains(tag::SetUp) && tags.value(tag::SetUp) == "1";
			bool hasFen = tags.contains(tag::Fen) && !tags.value(tag::Fen).empty();
			bool is960 = hasFen && looksLikeChess960Fen(tags.value(tag::Fen));

			if (hasSetup) ++setups;
			if (hasFen) ++fens;
			if (is960) ++likely960;

			if (is960 && shown < 5)
			{
				::printf("sample game=%u white='%s' black='%s'\n",
							i,
							tags.value(tag::White).c_str(),
							tags.value(tag::Black).c_str());
				::printf("  fen=%s\n", tags.value(tag::Fen).c_str());
				++shown;
			}
		}

		::printf("summary setups=%u fens=%u likely_chess960=%u\n", setups, fens, likely960);
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

	return 1;
}
