// ======================================================================
// Headless benchmark for database conversion into .sci.
// ======================================================================

#include "db/db_board.h"
#include "db/db_board_base.h"
#include "db/db_database.h"
#include "db/db_database_codec.h"
#include "db/db_exception.h"
#include "db/db_filter.h"
#include "db/db_home_pawns.h"
#include "db/db_log.h"
#include "db/db_pgn_reader.h"
#include "db/db_selector.h"
#include "db/db_signature.h"

#include "db/sci/sci_encoder.h"
#include "db/si3/si3_encoder.h"

#include "sys/sys_file.h"
#include "sys/sys_time.h"
#include "sys/sys_utf8_codec.h"

#include "util/u_misc.h"
#include "util/u_progress.h"
#include "util/u_zstream.h"

#include "mstl/m_ifstream.h"
#include "mstl/m_string.h"
#include "mstl/m_vector.h"

#include <tcl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <unistd.h>

using namespace db;

namespace tcl { namespace bits { Tcl_Interp* interp = nullptr; } }

namespace {

bool
isPgnLikeSource(mstl::string const& source);

bool
isCompressedPgnLikeSource(mstl::string const& source)
{
	mstl::string innerSuffix(::util::misc::file::suffix(::util::misc::file::rootname(source)));
	innerSuffix.tolower();
	return innerSuffix == "pgn" || innerSuffix == "bpgn";
}

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


struct SilentPgnReader : public PgnReader
{
	SilentPgnReader(mstl::istream& stream, mstl::string const& encoding)
		:PgnReader(stream,
					 variant::Undetermined,
					 encoding,
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

	unsigned errors;
};


struct Config
{
	mstl::string source;
	mstl::string output;
	mstl::string encoding;
	unsigned runs;
	unsigned verifySample;
	bool keep;
};


struct Result
{
	uint64_t elapsedUsec;
	unsigned games;
	unsigned illegalRejected;
	unsigned errors;
	unsigned warnings;
	long sourceBytes;
	long targetBytes;
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
	::fprintf(stderr,
				 "Usage: %s <source-db-or-pgn> [--runs N] [--output target.sci] [--encoding ENC] [--verify-sample N] [--keep]\n",
				 argv0);
	::exit(rc);
}


unsigned
parseUnsignedOption(char const* value, char const* argv0, bool allowZero = false)
{
	char* end = nullptr;
	unsigned long parsed = ::strtoul(value, &end, 10);

	if (!value || !*value || !end || *end != '\0' || (!allowZero && parsed == 0))
		printUsageAndExit(argv0, 1);

	if (parsed > UINT_MAX)
		printUsageAndExit(argv0, 1);

	return unsigned(parsed);
}


mstl::string
resolvedSourceEncoding(mstl::string const& source, mstl::string const& encoding)
{
	mstl::string useEncoding(encoding);

	if (isPgnLikeSource(source))
	{
		if (useEncoding == sys::utf8::Codec::automatic())
		{
			if (util::ZStream::testByteOrderMark(sys::file::internalName(source)))
				useEncoding = sys::utf8::Codec::utf8();
			else
				useEncoding = sys::utf8::Codec::latin1();
		}
	}
	else if (useEncoding == sys::utf8::Codec::automatic())
	{
		useEncoding = sys::utf8::Codec::utf8();
	}

	return useEncoding;
}


Config
	parseArgs(int argc, char** argv)
	{
		Config cfg;
		cfg.runs = 1;
		cfg.verifySample = 5;
		cfg.keep = false;
		cfg.encoding = sys::utf8::Codec::automatic();

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
			else if (::strcmp(argv[i], "--output") == 0)
			{
				if (++i == argc)
					printUsageAndExit(argv[0], 1);
				cfg.output = argv[i];
			}
			else if (::strcmp(argv[i], "--verify-sample") == 0)
			{
				if (++i == argc)
					printUsageAndExit(argv[0], 1);
				cfg.verifySample = parseUnsignedOption(argv[i], argv[0], true);
			}
			else if (::strcmp(argv[i], "--encoding") == 0)
			{
				if (++i == argc)
					printUsageAndExit(argv[0], 1);
				cfg.encoding = argv[i];
			}
			else if (::strcmp(argv[i], "--keep") == 0)
			{
				cfg.keep = true;
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

		if (cfg.output.empty())
		{
			char buf[160];
			::snprintf(buf, sizeof(buf), "/tmp/scidb-conversion-benchmark-%ld.sci", long(::getpid()));
			cfg.output = buf;
		}

		if (::util::misc::file::suffix(cfg.output) != "sci")
			cfg.output.append(".sci");

		return cfg;
	}


void
cleanupDatabaseFiles(mstl::string const& filename)
{
	mstl::string root(::util::misc::file::rootname(filename));

	::remove((root + ".sci").c_str());
	::remove((root + ".scg").c_str());
	::remove((root + ".scn").c_str());
}


long
databaseSize(mstl::string const& filename)
{
	mstl::string root(::util::misc::file::rootname(filename));
	return mstl::max(0L, sys::file::size(root + ".sci"))
		+ mstl::max(0L, sys::file::size(root + ".scg"))
		+ mstl::max(0L, sys::file::size(root + ".scn"));
}


mstl::string
makeOutputName(mstl::string const& base, unsigned run, unsigned runs)
{
	if (runs == 1)
		return base;

	mstl::string root(::util::misc::file::rootname(base));
	mstl::string name;
	name.format("%s.run%u.sci", root.c_str(), run + 1);
	return name;
}


bool
isPgnLikeSource(mstl::string const& source)
{
	mstl::string suffix(::util::misc::file::suffix(source));
	suffix.tolower();
	return suffix == "pgn" || suffix == "bpgn" || suffix == "zip"
		|| (suffix == "gz" && isCompressedPgnLikeSource(source));
}


mstl::vector<unsigned>
sampleIndexes(unsigned total, unsigned sampleCount)
{
	mstl::vector<unsigned> indexes;

	if (total == 0 || sampleCount == 0)
		return indexes;

	unsigned desired = mstl::min(total, sampleCount);
	indexes.reserve(desired);

	for (unsigned i = 0; i < desired; ++i)
	{
		unsigned index = desired == 1 ? 0 : ((uint64_t(i) * (total - 1)) / (desired - 1));
		if (indexes.empty() || indexes.back() != index)
			indexes.push_back(index);
	}

	return indexes;
}


unsigned
verifyOutput(mstl::string const& source,
				 mstl::string const& output,
				 mstl::string const& encoding,
				 unsigned verifySample,
				 util::Progress& progress)
{
	Database reopened(output, sys::utf8::Codec::utf8(), permission::ReadOnly, progress);
	unsigned games = reopened.countGames();
	mstl::string useEncoding(resolvedSourceEncoding(source, encoding));

	if (verifySample > 0 && games > 0)
	{
		mstl::string sourceCopy;
		bool generatedSourceCopy = false;

		if (isPgnLikeSource(source))
		{
			char buf[192];
			::snprintf(buf,
							 sizeof(buf),
							 "/tmp/scidb-conversion-verify-%ld-%u.sci",
							 long(::getpid()),
							 unsigned(sys::time::timestamp()));
			sourceCopy = buf;
			generatedSourceCopy = true;
			cleanupDatabaseFiles(sourceCopy);

			util::ZStream stream(sys::file::internalName(source), mstl::ios_base::in);
			if (!stream)
			{
				reopened.close();
				IO_RAISE(PgnFile, Open_Failed, "cannot open file '%s'", source.c_str());
			}

			SilentPgnReader reader(stream, useEncoding);
			Database imported(sourceCopy, sys::utf8::Codec::utf8(), storage::OnDisk, variant::Normal);
			imported.importGames(reader, progress);
			imported.close();
		}
		else
		{
			sourceCopy = source;
		}

		Database sourceDb(sourceCopy, useEncoding, permission::ReadOnly, progress);

		if (sourceDb.variant() != reopened.variant())
		{
			::fprintf(stderr,
						 "verification mismatch for %s: source variant=%s reopened variant=%s\n",
						 output.c_str(),
						 variant::identifier(sourceDb.variant()).c_str(),
						 variant::identifier(reopened.variant()).c_str());
			sourceDb.close();
			reopened.close();
			if (generatedSourceCopy)
				cleanupDatabaseFiles(sourceCopy);
			return unsigned(-1);
		}

		mstl::vector<unsigned> indexes(sampleIndexes(games, verifySample));
		for (unsigned i = 0; i < indexes.size(); ++i)
		{
			unsigned index = indexes[i];
			util::crc::checksum_t sourceChecksum = sourceDb.computeChecksum(index);
			util::crc::checksum_t reopenedChecksum = reopened.computeChecksum(index);

			if (sourceChecksum != reopenedChecksum)
			{
				::fprintf(stderr,
							 "verification mismatch for %s at game %u: source checksum=%08x reopened checksum=%08x\n",
							 output.c_str(),
							 index + 1,
							 unsigned(sourceChecksum),
					unsigned(reopenedChecksum));
					sourceDb.close();
					reopened.close();
					if (generatedSourceCopy)
						cleanupDatabaseFiles(sourceCopy);
					return unsigned(-1);
				}
			}

			sourceDb.close();
			if (generatedSourceCopy)
				cleanupDatabaseFiles(sourceCopy);
		}

	reopened.close();
	return games;
}


Result
benchmarkPgn(mstl::string const& source,
				 mstl::string const& output,
				 mstl::string const& encoding,
				 util::Progress& progress)
{
	Result result;
	result.elapsedUsec = 0;
	result.games = 0;
	result.illegalRejected = 0;
	result.errors = 0;
	result.warnings = 0;
	result.sourceBytes = mstl::max(0L, sys::file::size(source));
	result.targetBytes = 0;

	util::ZStream stream(sys::file::internalName(source), mstl::ios_base::in);

	if (!stream)
		IO_RAISE(PgnFile, Open_Failed, "cannot open file '%s'", source.c_str());

	mstl::string useEncoding(encoding);
	useEncoding = resolvedSourceEncoding(source, useEncoding);

	SilentPgnReader reader(stream, useEncoding);
	Database destination(output, sys::utf8::Codec::utf8(), storage::OnDisk, variant::Normal);

	uint64_t started = sys::time::timestamp();
	unsigned imported = destination.importGames(reader, progress);
	destination.close();
	uint64_t ended = sys::time::timestamp();

	result.elapsedUsec = ended - started;
	result.games = imported;
	result.errors = reader.errors;
	result.targetBytes = databaseSize(output);
	return result;
}


Result
benchmarkDatabase(mstl::string const& source,
						mstl::string const& output,
						mstl::string const& encoding,
						util::Progress& progress)
{
	Result result;
	result.elapsedUsec = 0;
	result.games = 0;
	result.illegalRejected = 0;
	result.errors = 0;
	result.warnings = 0;
	result.sourceBytes = mstl::max(0L, sys::file::size(source));
	result.targetBytes = 0;

	mstl::string useEncoding(encoding);
	useEncoding = resolvedSourceEncoding(source, useEncoding);

	Database sourceDb(source, useEncoding, permission::ReadOnly, progress);
	Database destination(output, sys::utf8::Codec::utf8(), storage::OnDisk, sourceDb.variant());
	CountingLog log;

	uint64_t started = sys::time::timestamp();
	unsigned imported = destination.importGames(sourceDb, &result.illegalRejected, log, progress);
	destination.close();
	uint64_t ended = sys::time::timestamp();

	result.elapsedUsec = ended - started;
	result.games = imported;
	result.errors = log.errors;
	result.warnings = log.warnings;
	result.targetBytes = databaseSize(output);

	sourceDb.close();
	return result;
}


Result
runBenchmark(mstl::string const& source,
					mstl::string const& output,
					mstl::string const& encoding,
				 util::Progress& progress)
{
	mstl::string suffix(::util::misc::file::suffix(source));
	suffix.tolower();

	cleanupDatabaseFiles(output);

	if (suffix == "pgn" || suffix == "bpgn" || suffix == "zip"
		|| (suffix == "gz" && isCompressedPgnLikeSource(source)))
		return benchmarkPgn(source, output, encoding, progress);

	return benchmarkDatabase(source, output, encoding, progress);
}


double
seconds(uint64_t elapsedUsec)
{
	return double(elapsedUsec)/1000000.0;
}


double
mbPerSecond(long bytes, uint64_t elapsedUsec)
{
	if (elapsedUsec == 0)
		return 0.0;

	return (double(bytes)/(1024.0*1024.0))/seconds(elapsedUsec);
}


void
printRun(unsigned run, Result const& result)
{
	::printf("run %u: %.3fs, games=%u, target=%.2f MiB, rate=%.1f games/s, %.2f MiB/s\n",
				run + 1,
				seconds(result.elapsedUsec),
				result.games,
				double(result.targetBytes)/(1024.0*1024.0),
				result.elapsedUsec ? double(result.games)/seconds(result.elapsedUsec) : 0.0,
				mbPerSecond(result.targetBytes, result.elapsedUsec));

	if (result.illegalRejected || result.errors || result.warnings)
	{
		::printf("       rejected=%u errors=%u warnings=%u\n",
					result.illegalRejected,
					result.errors,
					result.warnings);
	}
}

} // namespace


int
main(int argc, char** argv)
{
	try
	{
		Config cfg = parseArgs(argc, argv);
		TclInterpreter tcl;
		initializeStatics();
		util::Progress& progress = util::Progress::null();
		cfg.source = sys::file::normalizedName(cfg.source);
		cfg.output = sys::file::normalizedName(cfg.output);

		uint64_t totalUsec = 0;
		uint64_t bestUsec = 0;
		uint64_t worstUsec = 0;
		unsigned lastGames = 0;
		long lastTargetBytes = 0;

		::printf("source: %s\n", cfg.source.c_str());
		::printf("output: %s\n", cfg.output.c_str());
		::printf("runs: %u\n", cfg.runs);
		::printf("verify-sample: %u\n", cfg.verifySample);

		for (unsigned run = 0; run < cfg.runs; ++run)
		{
			mstl::string output(makeOutputName(cfg.output, run, cfg.runs));
			Result result = runBenchmark(cfg.source, output, cfg.encoding, progress);
			unsigned verifiedGames = verifyOutput(cfg.source, output, cfg.encoding, cfg.verifySample, progress);

			if (verifiedGames == unsigned(-1))
			{
				cleanupDatabaseFiles(output);
				return 1;
			}

			if (verifiedGames != result.games)
			{
				::fprintf(stderr,
							 "verification mismatch for %s: imported=%u reopened=%u\n",
							 output.c_str(),
							 result.games,
							 verifiedGames);
				cleanupDatabaseFiles(output);
				return 1;
			}

			printRun(run, result);

			totalUsec += result.elapsedUsec;
			bestUsec = bestUsec == 0 ? result.elapsedUsec : mstl::min(bestUsec, result.elapsedUsec);
			worstUsec = mstl::max(worstUsec, result.elapsedUsec);
			lastGames = result.games;
			lastTargetBytes = result.targetBytes;

			if (!cfg.keep)
				cleanupDatabaseFiles(output);
		}

		double averageUsec = cfg.runs ? double(totalUsec)/cfg.runs : 0.0;
		double averageSeconds = averageUsec/1000000.0;

		::printf("summary: avg=%.3fs best=%.3fs worst=%.3fs avg-rate=%.1f games/s avg-throughput=%.2f MiB/s\n",
					averageSeconds,
					seconds(bestUsec),
					seconds(worstUsec),
					averageSeconds > 0.0 ? double(lastGames)/averageSeconds : 0.0,
					averageSeconds > 0.0 ? (double(lastTargetBytes)/(1024.0*1024.0))/averageSeconds : 0.0);
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
