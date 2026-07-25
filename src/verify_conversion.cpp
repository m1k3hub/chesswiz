// ======================================================================
// Headless verifier for conversion and range-copy workflows.
// ======================================================================

#include "db/db_board.h"
#include "db/db_board_base.h"
#include "db/db_database.h"
#include "db/db_eco_table.h"
#include "db/db_exception.h"
#include "db/db_home_pawns.h"
#include "db/db_log.h"
#include "db/db_pgn_reader.h"
#include "db/db_signature.h"

#include "db/sci/sci_encoder.h"
#include "db/sci/sci_consumer.h"
#include "db/sci/sci_codec.h"
#include "db/si3/si3_encoder.h"
#include "db/si3/si3_consumer.h"
#include "db/si3/si3_codec.h"

#include "sys/sys_utf8_codec.h"

#include "util/u_misc.h"
#include "util/u_progress.h"

#include "mstl/m_sstream.h"
#include "mstl/m_string.h"
#include "mstl/m_ifstream.h"

#include <tcl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

using namespace db;

namespace tcl { namespace bits { Tcl_Interp* interp = nullptr; } }

namespace {

char const* SamplePgn =
	"[Event \"Conversion 1\"]\n"
	"[Site \"Test\"]\n"
	"[Date \"2024.01.01\"]\n"
	"[Round \"1\"]\n"
	"[White \"Alpha\"]\n"
	"[Black \"Beta\"]\n"
	"[WhiteElo \"2500\"]\n"
	"[BlackElo \"2400\"]\n"
	"[Result \"1-0\"]\n"
	"[ECO \"C20\"]\n"
	"\n"
	"1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. c3 Nf6 5. d3 d6 1-0\n"
	"\n"
	"[Event \"Conversion 2\"]\n"
	"[Site \"Test\"]\n"
	"[Date \"2024.01.02\"]\n"
	"[Round \"2\"]\n"
	"[White \"Gamma\"]\n"
	"[Black \"Delta\"]\n"
	"[WhiteElo \"2300\"]\n"
	"[BlackElo \"2300\"]\n"
	"[Result \"1/2-1/2\"]\n"
	"[ECO \"C44\"]\n"
	"\n"
	"1. e4 e5 2. Nf3 Nc6 3. c3 Nf6 4. d4 Nxe4 5. d5 Ne7 1/2-1/2\n"
	"\n"
	"[Event \"Conversion 3\"]\n"
	"[Site \"Test\"]\n"
	"[Date \"2024.01.03\"]\n"
	"[Round \"3\"]\n"
	"[White \"Epsilon\"]\n"
	"[Black \"Zeta\"]\n"
	"[WhiteElo \"2200\"]\n"
	"[BlackElo \"2250\"]\n"
	"[Result \"0-1\"]\n"
	"[ECO \"D30\"]\n"
	"\n"
	"1. d4 d5 2. c4 e6 3. Nc3 c6 4. Nf3 Nf6 5. Bg5 dxc4 0-1\n"
	"\n"
	"[Event \"Conversion 4\"]\n"
	"[Site \"Test\"]\n"
	"[Date \"2024.01.04\"]\n"
	"[Round \"4\"]\n"
	"[White \"Eta\"]\n"
	"[Black \"Theta\"]\n"
	"[WhiteElo \"2100\"]\n"
	"[BlackElo \"2150\"]\n"
	"[Result \"1-0\"]\n"
	"[ECO \"B01\"]\n"
	"\n"
	"1. e4 d5 2. exd5 Qxd5 3. Nc3 Qa5 4. d4 c6 5. Nf3 Bf5 1-0\n";


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


struct CountingLog : public db::Log
{
	CountingLog() :errors(0), warnings(0) {}

	bool error(save::State, unsigned) override
	{
		++errors;
		return true;
	}

	void warning(Warning, unsigned) override
	{
		++warnings;
	}

	unsigned errors;
	unsigned warnings;
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


mstl::string
rootFromArg(int argc, char** argv)
{
	if (argc > 1)
		return argv[1];

	char buf[160];
	::snprintf(buf, sizeof(buf), "/tmp/scidb-conversion-%ld", long(::getpid()));
	return buf;
}


void
cleanup(mstl::string const& name)
{
	mstl::string root(::util::misc::file::rootname(name));
	::remove(name.c_str());
	::remove((root + ".sci").c_str());
	::remove((root + ".scg").c_str());
	::remove((root + ".scn").c_str());
	::remove((root + ".si4").c_str());
	::remove((root + ".si3").c_str());
}


bool
sameChecksums(Database const& lhs, Database const& rhs, unsigned lhsOffset = 0)
{
	if (rhs.countGames() + lhsOffset > lhs.countGames())
		return false;

	for (unsigned i = 0; i < rhs.countGames(); ++i)
	{
		if (lhs.computeChecksum(i + lhsOffset) != rhs.computeChecksum(i))
			return false;
	}

	return true;
}


bool
samePlayerResultTags(Database const& lhs, unsigned lhsIndex, Database const& rhs, unsigned rhsIndex)
{
	TagSet lhsTags;
	TagSet rhsTags;
	lhs.setupTags(lhsIndex, lhsTags);
	rhs.setupTags(rhsIndex, rhsTags);

	tag::ID fields[] = {
		tag::White,
		tag::Black,
		tag::Result
	};

	for (unsigned i = 0; i < sizeof(fields)/sizeof(fields[0]); ++i)
	{
		if (lhsTags.value(fields[i]) != rhsTags.value(fields[i]))
			return false;
	}

	return true;
}


bool
verifyCopy(mstl::string const& sourceName,
			  mstl::string const& copyName,
			  unsigned firstIndex,
			  unsigned lastIndex,
			  bool expectFull,
			  util::Progress& progress)
{
	Database source(sourceName, sys::utf8::Codec::utf8(), permission::ReadOnly, progress);
	Database destination(copyName, sys::utf8::Codec::utf8(), storage::OnDisk, source.variant());
	unsigned copied = 0;

	for (unsigned i = firstIndex; i <= lastIndex; ++i)
	{
		if (!save::isOk(source.exportGame(i, destination)))
			copied = unsigned(-1);
		if (copied == unsigned(-1))
			break;
		++copied;
	}

	destination.save(progress);
	destination.close();

	Database reopened(copyName, sys::utf8::Codec::utf8(), permission::ReadOnly, progress);
	bool ok = copied != unsigned(-1)
		&& copied == reopened.countGames()
		&& sameChecksums(source, reopened, firstIndex);

	if (expectFull)
		ok = ok && copied == source.countGames();

	reopened.close();
	source.close();
	return ok;
}


bool
verifySi4Copy(mstl::string const& sourceName, mstl::string const& copyName, util::Progress& progress)
{
	Database source(sourceName, sys::utf8::Codec::utf8(), permission::ReadOnly, progress);
	Database destination(copyName, sys::utf8::Codec::utf8(), storage::OnDisk, variant::Normal);
	Database::TagBits allowedTags(true);
	si3::Consumer consumer(source.format(),
								  dynamic_cast<si3::Codec&>(destination.codec()),
								  sys::utf8::Codec::utf8(),
								  allowedTags,
								  true);
	unsigned copied = 0;

	for (unsigned i = 0; i < source.countGames(); ++i)
	{
		if (!save::isOk(source.exportGame(i, consumer)))
			copied = unsigned(-1);
		if (copied == unsigned(-1))
			break;
		++copied;
	}

	destination.save(progress);
	destination.close();

	Database reopened(copyName, sys::utf8::Codec::utf8(), permission::ReadOnly, progress);
	bool ok = copied != unsigned(-1)
		&& copied == source.countGames()
		&& reopened.countGames() == source.countGames()
		&& reopened.variant() == source.variant();
	for (unsigned i = 0; ok && i < reopened.countGames(); ++i)
		ok = samePlayerResultTags(source, i, reopened, i);
	reopened.close();
	source.close();
	return ok;
}

} // namespace


int
main(int argc, char** argv)
{
	mstl::string root(rootFromArg(argc, argv));
	mstl::string sourceName(root + ".sci");
	mstl::string fullCopy(root + "-full.sci");
	mstl::string rangeCopy(root + "-range.sci");
	mstl::string si4Copy(root + ".si4");
	util::Progress& progress = util::Progress::null();

	try
	{
		TclInterpreter tcl;
		initializeStatics();
		loadEcoFile();
		cleanup(sourceName);
		cleanup(fullCopy);
		cleanup(rangeCopy);
		cleanup(si4Copy);

		mstl::string samplePgn(SamplePgn);
		mstl::istringstream stream(samplePgn);
		SilentPgnReader reader(stream);
		Database source(sourceName, sys::utf8::Codec::utf8(), storage::OnDisk, variant::Normal);
		unsigned imported = source.importGames(reader, progress);
		source.close();

		if (reader.errors != 0 || imported != 4)
		{
			::fprintf(stderr, "sample PGN import failed: imported=%u errors=%u\n", imported, reader.errors);
			cleanup(sourceName);
			return 1;
		}

		if (!verifyCopy(sourceName, fullCopy, 0, 3, true, progress))
		{
			::fprintf(stderr, "full copy verification failed\n");
			cleanup(sourceName);
			cleanup(fullCopy);
			return 1;
		}

		if (!verifyCopy(sourceName, rangeCopy, 1, 2, false, progress))
		{
			::fprintf(stderr, "range copy verification failed\n");
			cleanup(sourceName);
			cleanup(fullCopy);
			cleanup(rangeCopy);
			return 1;
		}

		if (!verifySi4Copy(sourceName, si4Copy, progress))
		{
			::fprintf(stderr, "si4 copy verification failed\n");
			cleanup(sourceName);
			cleanup(fullCopy);
			cleanup(rangeCopy);
			cleanup(si4Copy);
			return 1;
		}

		cleanup(sourceName);
		cleanup(fullCopy);
		cleanup(rangeCopy);
		cleanup(si4Copy);
		::puts("conversion verification passed");
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

	cleanup(sourceName);
	cleanup(fullCopy);
	cleanup(rangeCopy);
	cleanup(si4Copy);
	return 1;
}
