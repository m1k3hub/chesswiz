// ======================================================================
// Headless verifier for database maintenance helpers.
// ======================================================================

#include "db/db_board.h"
#include "db/db_board_base.h"
#include "db/db_database.h"
#include "db/db_common.h"
#include "db/db_home_pawns.h"
#include "db/db_maintenance.h"
#include "db/db_pgn_reader.h"
#include "db/db_signature.h"
#include "db/db_exception.h"

#include "db/sci/sci_encoder.h"
#include "db/si3/si3_encoder.h"

#include "sys/sys_utf8_codec.h"

#include "util/u_progress.h"
#include "util/u_misc.h"

#include "mstl/m_sstream.h"
#include "mstl/m_string.h"

#include <tcl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

using namespace db;

namespace tcl { namespace bits { Tcl_Interp* interp = nullptr; } }

namespace {

char const* SamplePgn =
	"[Event \"Duplicate 1\"]\n"
	"[Site \"Test\"]\n"
	"[Date \"2024.01.01\"]\n"
	"[Round \"1\"]\n"
	"[White \"Alpha\"]\n"
	"[Black \"Beta\"]\n"
	"[Result \"1-0\"]\n"
	"[ECO \"C20\"]\n"
	"\n"
	"1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. c3 Nf6 5. d3 d6 1-0\n"
	"\n"
	"[Event \"Duplicate 1\"]\n"
	"[Site \"Test\"]\n"
	"[Date \"2024.01.01\"]\n"
	"[Round \"1\"]\n"
	"[White \"Alpha\"]\n"
	"[Black \"Beta\"]\n"
	"[Result \"1-0\"]\n"
	"[ECO \"C20\"]\n"
	"\n"
	"1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. c3 Nf6 5. d3 d6 1-0\n"
	"\n"
	"[Event \"Unique C20\"]\n"
	"[Site \"Test\"]\n"
	"[Date \"2024.01.03\"]\n"
	"[Round \"1\"]\n"
	"[White \"Gamma\"]\n"
	"[Black \"Delta\"]\n"
	"[Result \"1/2-1/2\"]\n"
	"[ECO \"C20\"]\n"
	"\n"
	"1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. d3 Nf6 5. c3 d6 1/2-1/2\n"
	"\n"
	"[Event \"Unique D00\"]\n"
	"[Site \"Test\"]\n"
	"[Date \"2024.01.04\"]\n"
	"[Round \"1\"]\n"
	"[White \"Epsilon\"]\n"
	"[Black \"Zeta\"]\n"
	"[Result \"0-1\"]\n"
	"[ECO \"D00\"]\n"
	"\n"
	"1. d4 d5 2. Nc3 Nf6 3. Bf4 e6 4. e3 Bd6 5. Bxd6 Qxd6 0-1\n";


struct SilentPgnReader : public PgnReader
{
	SilentPgnReader(mstl::istream& stream)
		:PgnReader(stream,
					 variant::Normal,
					 sys::utf8::Codec::utf8(),
					 PgnReader::File,
					 PgnReader::Normalize,
					 PgnReader::UseResultTag)
		,errors(0)
	{
	}

	void warning(Warning,
					 unsigned,
					 unsigned,
					 unsigned,
					 variant::Type,
					 mstl::string const&,
					 mstl::string const&) override
	{
	}

	void error(Error,
				  unsigned,
				  unsigned,
				  unsigned,
				  variant::Type,
				  mstl::string const&,
				  mstl::string const&,
				  mstl::string const&) override
	{
		++errors;
	}

	void error(save::State, unsigned, unsigned, variant::Type) override
	{
		++errors;
	}

	unsigned estimateNumberOfGames() override
	{
		return 4;
	}

	unsigned errors;
};


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


mstl::string
rootFromArg(int argc, char** argv)
{
	if (argc > 1)
		return argv[1];

	char buf[128];
	::snprintf(buf, sizeof(buf), "/tmp/scidb-maintenance-%ld.sci", long(::getpid()));
	return buf;
}


void
cleanup(mstl::string const& filename)
{
	mstl::string root = ::util::misc::file::rootname(filename);

	::remove((root + ".sci").c_str());
	::remove((root + ".scg").c_str());
	::remove((root + ".scn").c_str());
}


bool
checkEcoStat(maintenance::EcoStatsList const& stats,
				 char const* eco,
				 unsigned total,
				 unsigned white,
				 unsigned draws,
				 unsigned black)
{
	for (unsigned i = 0; i < stats.size(); ++i)
	{
		if (stats[i].eco == eco)
		{
			return stats[i].total == total
				&& stats[i].white == white
				&& stats[i].draws == draws
				&& stats[i].black == black;
		}
	}

	return false;
}


bool
verifyInitialState(Database& db)
{
	maintenance::DuplicateGroups groups = maintenance::findDuplicates(db);
	if (groups.size() != 1 || groups[0].size() != 2 || groups[0][0] != 0 || groups[0][1] != 1)
		return false;

	maintenance::EcoStatsList stats = maintenance::computeEcoStats(db, variant::Normal);
	return checkEcoStat(stats, "C20", 3, 2, 1, 0)
		&& checkEcoStat(stats, "D00", 1, 0, 0, 1);
}


bool
verifyAfterDeletion(Database& db)
{
	maintenance::DuplicateGroups groups = maintenance::findDuplicates(db);
	if (!groups.empty())
		return false;

	if (!db.gameInfo(1).isDeleted())
		return false;

	maintenance::EcoStatsList stats = maintenance::computeEcoStats(db, variant::Normal);
	return checkEcoStat(stats, "C20", 2, 1, 1, 0)
		&& checkEcoStat(stats, "D00", 1, 0, 0, 1);
}

} // namespace


int
main(int argc, char** argv)
{
	mstl::string filename = rootFromArg(argc, argv);
	util::Progress& progress = util::Progress::null();

	try
	{
		TclInterpreter tcl;
		initializeStatics();

		cleanup(filename);

		mstl::string samplePgn(SamplePgn);
		mstl::istringstream stream(samplePgn);
		SilentPgnReader reader(stream);
		Database created(filename, sys::utf8::Codec::utf8(), storage::OnDisk, variant::Normal);

		unsigned imported = created.importGames(reader, progress);
		if (reader.errors != 0 || imported != 4)
		{
			::fprintf(stderr, "PGN import failed: imported=%u errors=%u\n", imported, reader.errors);
			cleanup(filename);
			return 1;
		}

		if (!verifyInitialState(created))
		{
			::fprintf(stderr, "Initial maintenance verification failed\n");
			cleanup(filename);
			return 1;
		}

		created.deleteGame(1, true);
		if (!verifyAfterDeletion(created))
		{
			::fprintf(stderr, "Post-delete maintenance verification failed\n");
			cleanup(filename);
			return 1;
		}

		created.close();

		Database reopened(filename, sys::utf8::Codec::utf8(), permission::ReadWrite, progress);
		if (!verifyAfterDeletion(reopened))
		{
			::fprintf(stderr, "Reopen verification failed\n");
			cleanup(filename);
			return 1;
		}

		reopened.close();
		cleanup(filename);
		::puts("maintenance verification passed");
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

	cleanup(filename);
	return 1;
}
