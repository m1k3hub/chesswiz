// ======================================================================
// List game headers (White/Black/Event/Date/SetUp/FEN) for every game in
// a database, WITHOUT decoding moves. Designed to pair CBV Chess960 games
// (which fail to decode and so are absent from any converted .sci) with
// PGN games by player names.
//
// Usage: list_cbv_headers <database-path> [chess960-only]
//   chess960-only: print only games whose SetUp/Fen tag looks Chess960.
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
	::fprintf(stderr, "usage: %s <database-path> [chess960-only]\n", argv0);
}

} // namespace


int
main(int argc, char** argv)
{
	if (argc != 2 && argc != 3)
	{
		usage(argv[0]);
		return 1;
	}

	bool chess960Only = (argc == 3 && ::strcmp(argv[2], "chess960-only") == 0);

	util::Progress& progress = util::Progress::null();

	try
	{
		TclInterpreter tcl;
		initializeStatics();
		loadEcoFile();

		Database db(argv[1], sys::utf8::Codec::utf8(), permission::ReadOnly, progress);

		unsigned total = db.countGames();
		unsigned printed = 0;

		::printf("database=%s games=%u%s\n", argv[1], total, chess960Only ? " (chess960-only)" : "");

		for (unsigned i = 0; i < total; ++i)
		{
			TagSet tags;
			db.setupTags(i, tags);

			bool hasSetup = tags.contains(tag::SetUp) && tags.value(tag::SetUp) == "1";
			bool hasFen   = tags.contains(tag::Fen) && !tags.value(tag::Fen).empty();
			bool is960    = hasFen && looksLikeChess960Fen(tags.value(tag::Fen));

			if (chess960Only && !(is960 || hasSetup))
				continue;

			mstl::string white = tags.value(tag::White);
			mstl::string black = tags.value(tag::Black);
			mstl::string event = tags.value(tag::Event);
			mstl::string date  = tags.value(tag::Date);
			mstl::string site  = tags.value(tag::Site);
			mstl::string round = tags.value(tag::Round);
			mstl::string welo  = tags.value(tag::WhiteElo);
			mstl::string belo  = tags.value(tag::BlackElo);
			mstl::string fen   = hasFen ? tags.value(tag::Fen) : mstl::string();

			// TSV: index<TAB>white<TAB>black<TAB>event<TAB>date<TAB>site<TAB>round<TAB>welo<TAB>belo<TAB>fen
			::printf("%u\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
					 i,
					 white.c_str(), black.c_str(),
					 event.c_str(), date.c_str(), site.c_str(), round.c_str(),
					 welo.c_str(), belo.c_str(),
					 fen.c_str());
			++printed;
		}

		::printf("printed=%u\n", printed);
		db.close();
		return 0;
	}
	catch (IOException const& exc)
	{
		::fprintf(stderr, "Error: %s\n", exc.what());
		return 1;
	}
	catch (std::exception const& exc)
	{
		::fprintf(stderr, "Error: %s\n", exc.what());
		return 1;
	}
}