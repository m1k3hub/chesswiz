// ======================================================================
// $RCSfile: tk_image.cpp,v $
// $Revision: 1372 $
// $Date: 2017-08-04 13:56:11 -0400 (Fri, 04 Aug 2017) $
// $Author: gregor $
// ======================================================================

// ======================================================================
//    _/|            __
//   // o\         /    )           ,        /    /
//   || ._)    ----\---------__----------__-/----/__-
//   //__\          \      /   '  /    /   /    /   )
//   )___(     _(____/____(___ __/____(___/____(___/_
// ======================================================================

// ======================================================================
// Copyright: (C) 2011-2013 Gregor Cramer
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#include "db_eco_table.h"
#include "db_database.h"
#include "db_pgn_reader.h"
#include "db_exception.h"
#include "db_log.h"
#include "db_game_data.h"
#include "db_consumer.h"
#include "db_tag_set.h"

#include "si3/si3_consumer.h"
#include "si3/si3_encoder.h"
#include "si3/si3_codec.h"

#include "cbh/cbh_game_decoder.h"

#include "u_progress.h"

#include "sys_utf8_codec.h"
#include "sys_file.h"
#include "sys_thread_group.h"
#include "sys_thread.h"
#include "sys_info.h"

#include "tcl_base.h"

#include "m_ifstream.h"

#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <tcl.h>

#ifdef BROKEN_LINKER_HACK
# include "db_board.h"
# include "db_board_base.h"
# include "db_home_pawns.h"
# include "db_signature.h"
# include "sci_encoder.h"
#endif

using namespace db;


static unsigned rejected = 0;

struct ImportStats
{
	ImportStats() :written(0), rejected(0), warnings(0), errors(0) {}
	unsigned written;
	unsigned rejected;
	unsigned warnings;
	unsigned errors;
};

static bool newNewline = false;


namespace tcl { namespace bits { Tcl_Interp* interp; } }


struct TclInterpreter
{
	TclInterpreter()	{ tcl::bits::interp = Tcl_CreateInterp(); }
	~TclInterpreter()	{ Tcl_DeleteInterp(tcl::bits::interp); }
};


struct Progress : public util::Progress
{
	void update(unsigned progress) override
	{
		::printf(".");
		::fflush(stdout);
	}

	void finish() throw() override {}
};


struct Tracer : public util::Progress
{
	void update(unsigned progress) override
	{
		::printf("Game number %u\n", progress);
	}

	void finish() throw() override {}
};


struct Log : public db::Log
{
	Log() :warningCount(0), errorCount(0) {}

	bool error(save::State code, unsigned gameNumber)
	{
		char const* msg = 0;

		switch (code)
		{
			case save::Ok:								return true;
			case save::UnsupportedVariant:		++rejected; return true;
			case save::DecodingFailed:				++rejected; return true;
			case save::GameTooLong:					msg = "Game too long"; break;
			case save::FileSizeExeeded:			msg = "File size exeeded"; break;
			case save::TooManyGames:				msg = "Too many games"; break;
			case save::TooManyPlayerNames:		msg = "Too many player names"; break;
			case save::TooManyEventNames:			msg = "Too many event names"; break;
			case save::TooManySiteNames:			msg = "Too many site names"; break;
			case save::TooManyRoundNames:			msg = "Too many round names"; break;
			case save::TooManyAnnotatorNames:	return true; // cannot happen
		}

		::fflush(stdout);
		++errorCount;
		::fprintf(	stderr,
						"%s: %s (#%u)\n",
						code == db::save::GameTooLong ? "Warning" : "Error",
						msg,
						gameNumber);

		return code == save::GameTooLong;
	}

	void warning(Warning code, unsigned gameNumber) { ++warningCount; }

	unsigned warningCount;
	unsigned errorCount;
};


static void
printImportSummary(mstl::string const& srcPath,
						 mstl::string const& dstPath,
						 mstl::string const& encoding,
						 ImportStats const& stats)
{
	printf("\nSummary: source='%s' format=cbh destination='%s' encoding=%s\n",
				srcPath.c_str(),
				dstPath.c_str(),
				encoding.c_str());
	printf("written=%u rejected=%u warnings=%u errors=%u\n",
				stats.written,
				stats.rejected,
				stats.warnings,
				stats.errors);
}


typedef si3::Consumer::TagBits TagBits;

static char const* ConvertTo		= "utf-8";
static char const* ConvertFrom	= "auto";


static TagBits
getDefaultTags()
{
	TagBits defaultTags;

	defaultTags.set(tag::Board);
	defaultTags.set(tag::EventCountry);
	defaultTags.set(tag::EventType);
	defaultTags.set(tag::Mode);
	defaultTags.set(tag::Remark);
	defaultTags.set(tag::TimeControl);
	defaultTags.set(tag::TimeMode);
	defaultTags.set(tag::WhiteClock);
	defaultTags.set(tag::WhiteFideId);
	defaultTags.set(tag::WhiteTeam);
	defaultTags.set(tag::WhiteTitle);
	defaultTags.set(tag::BlackClock);
	defaultTags.set(tag::BlackFideId);
	defaultTags.set(tag::BlackTeam);
	defaultTags.set(tag::BlackTitle);

	return defaultTags;
}


static void
loadEcoFile()
{
	mstl::string path(SHAREDIR "/data/eco.bin");
	mstl::ifstream stream(path, mstl::ios_base::in | mstl::ios_base::binary);

	if (!stream)
	{
		fprintf(stderr, "cannot open ECO file '%s'", path.c_str());
		exit(1);
	}

	EcoTable::specimen(variant::Normal).load(stream, variant::Normal);
}


static void
printHelpAndExit(int rc)
{
	printf("Usage: cbh2si4 [options ...] <ChessBase database> [destination database]\n");
	printf("\n");
	printf("Options:\n");
	printf("  --              Only file names after this\n");
	printf("  --help          Print Help (this message) and exit\n");
	printf("  --force         Overwrite existing destination files\n");
	printf("  --convertto <encoding>\n");
	printf("                  Use this encoding for output database\n");
	printf("                  (default is '%s')\n", ConvertTo);
	printf("  --convertfrom <encoding>\n");
	printf("                  The encoding of the ChessBase database\n");
	printf("                  (default is '%s')\n", ::ConvertFrom);
	printf("  --tags <comma-separated-tag-list>\n");
	printf("                  Export only the tags given with this list\n");
	printf("                  (but mandatory tags will be always exported)\n");
	printf("  --unusual-tags  Export unusual tags (otherwise ignore these tags)\n");
	printf("  --all-tags      Export all tags (overrules option --tags)\n");
	printf("                  (but ignore unusual tags except --unusual-tags is given)\n");
	printf("  --no-tags       Do not export any tag (except mandatory tags)\n");
	printf("                  (overrules --tags, --all-tags, but not --unusual-tags)\n");
	printf("  --list-encodings\n");
	printf("                  List all known encodings\n");
	printf("  --list-mandatory-tags\n");
	printf("                  List all mandatory tags\n");
	printf("  --list-default-tags\n");
	printf("                  List all default tags\n");
	printf("  --list-usual-tags\n");
	printf("                  List all usual tags (includes mandatory tags)\n");
	printf("\n");
	exit(rc);
}


static bool
isForbiddenEncoding(mstl::string const& encoding)
{
	return	encoding == "ascii"
			|| encoding == "identity"
			|| encoding == "dingbats"
			|| encoding == "ebcdic"
			|| encoding == "symbol"
			|| encoding == "unicode";
}


static void
printEncodingsAndExit(int rc)
{
	sys::utf8::Codec::EncodingList encodings;
	sys::utf8::Codec::getEncodingList(encodings);

	sys::utf8::Codec::EncodingList::const_iterator i = encodings.begin();
	sys::utf8::Codec::EncodingList::const_iterator e = encodings.end();

	while (i != e)
	{
		sys::utf8::Codec::EncodingList::const_iterator next = i + 1;

		if (!isForbiddenEncoding(*i))
		{
			printf("%s", i->c_str());

			if (next != e)
				printf(", ");
		}

		i = next;
	}

	printf("\n");
	exit(rc);
}


static void
checkEncoding(mstl::string const& encoding)
{
	if (isForbiddenEncoding(encoding))
	{
		fprintf(stderr, "Encoding '%s' is not allowed\n", encoding.c_str());
		exit(1);
	}

	sys::utf8::Codec::EncodingList encodings;
	sys::utf8::Codec::getEncodingList(encodings);

	sys::utf8::Codec::EncodingList::const_iterator i = encodings.begin();
	sys::utf8::Codec::EncodingList::const_iterator e = encodings.end();

	for ( ; i != e; ++i)
	{
		if (*i == encoding)
			return;
	}

	fprintf(stderr, "Unknown encoding '%s'\n", encoding.c_str());
	exit(1);
}


static void
printDefaultTagsAndExit(int rc)
{
	char const* comma = "";
	TagBits defaultTags = getDefaultTags();

	for (unsigned i = 0; i < 64; ++i)
	{
		if (defaultTags.test(i))
		{
			printf("%s%s", comma, tag::toName(tag::ID(i)).c_str());
			comma = ",";
		}
	}

	printf("\n");
	exit(rc);
}


static void
printUsualTagsAndExit(int rc)
{
	for (unsigned i = 0; i < tag::BughouseTag; ++i)
	{
		if (i > 0)
			printf(",");
		printf("%s", tag::toName(tag::ID(i)).c_str());
	}

	printf("\n");
	exit(rc);
}


static void
printMandatoryTagsAndExit(int rc)
{
	mstl::string	tagList;
	tag::TagSet		mandatoryTags(si3::Encoder::infoTags());

	for (unsigned i = mandatoryTags.find_first(); i != tag::TagSet::npos; i = mandatoryTags.find_next(i))
	{
		if (!tagList.empty())
			tagList += ',';
		tagList += tag::toName(tag::ID(i));
	}

	printf("%s\n", tagList.c_str());
	::exit(rc);
}


static void
checkTagList(mstl::string& tagList)
{
	char* s = tagList.data();
	char* e = s;

	while (true)
	{
		while (*e && *e != ',')
			++e;

		if (!PgnReader::validateTagName(s, e - s))
		{
			fprintf(stderr, "Invalid tag name '%s'.\n", mstl::string(s, e).c_str());
			exit(1);
		}

		if (tag::fromName(s, e - s) == tag::ExtraTag)
		{
			fprintf(stderr, "'%s' is an unusual tag and cannot be included.\n", mstl::string(s, e).c_str());
			fprintf(stderr, "Probably you might use option --unusual-tags.\n");
			exit(1);
		}

		if (*e == '\0')
			return;

		s = ++e;
	}
}


static void
setTagList(TagBits& result, mstl::string const& tagList)
{
	char const* s = tagList;
	char const* e = s;

	while (true)
	{
		while (*e && *e != ',')
			++e;

		result.set(tag::fromName(s, e - s));

		if (*e == '\0')
			return;

		s = ++e;
	}
}


static void
logIOError(IOException const& exc, unsigned gameNumber = 0)
{
	char const* error	= 0;
	char const* file	= 0;

	switch (exc.errorType())
	{
		case IOException::Create_Failed:				error = "no permissions to create files"; break;
		case IOException::Open_Failed:				error = "open failed"; break;
		case IOException::Unknown_Error_Type:		error = "unknown error type"; break;
		case IOException::Unknown_Version:			error = "unknown file version"; break;
		case IOException::Unexpected_Version:		error = "unexpected file version"; break;
		case IOException::Corrupted:					error = "corrupted data"; break;
		case IOException::Invalid_Data:				error = "invalid data (file possibly corrupted)"; break;
		case IOException::Read_Error:					error = "read error"; break;
		case IOException::Load_Failed:				error = "load failed (too many event entries)"; break;

		case IOException::Read_Only:
		case IOException::Write_Failed:
		case IOException::Encoding_Failed:
		case IOException::Max_File_Size_Exceeded:
		case IOException::Not_Original_Version:
		case IOException::Cannot_Create_Thread:
			return; // cannot happen
	}

	switch (exc.fileType())
	{
		case IOException::Unspecified:	break;
		case IOException::Index:			file = "index"; break;
		case IOException::Game:				file = "game"; break;
		case IOException::Namebase:		file = "namebase"; break;
		case IOException::Annotation:		file = "annotation"; break;
		case IOException::PgnFile:			/* cannot happen */ break;
		case IOException::BookFile:		/* cannot happen */ break;
		case IOException::Archive:		/* cannot happen */ break;
	}

	mstl::string msg("Error");

	if (file)
	{
		msg.append(" in ");
		msg.append(file);
		msg.append(" file");
	}

	msg.append(": ");
	msg.append(error);

	if (gameNumber > 0)
		msg.format(" (#%d)", gameNumber);

	fflush(stdout);
	if (::newNewline)
		printf("\n");
	fflush(stdout);
	fprintf(stderr, "%s\n", msg.c_str());
	::newNewline = false;

	switch (exc.errorType())
	{
		case IOException::Unknown_Error_Type:
		case IOException::Create_Failed:
		case IOException::Open_Failed:
		case IOException::Unknown_Version:
		case IOException::Unexpected_Version:
		case IOException::Write_Failed:
		case IOException::Max_File_Size_Exceeded:
		case IOException::Not_Original_Version:
		case IOException::Read_Only:
			fprintf(stderr, "Abort.\n");
			exit(1);

		case IOException::Read_Error:
		case IOException::Corrupted:
		case IOException::Invalid_Data:
		case IOException::Encoding_Failed:
		case IOException::Load_Failed:
		case IOException::Cannot_Create_Thread:
			break;
	}
}


static unsigned
exportGames(Database& src, Consumer& dst, ::util::Progress& progress, ::Log& log)
{
	unsigned numGames = src.countGames();

	util::ProgressWatcher watcher(progress, numGames);
	progress.setFrequency(mstl::min(200u, mstl::max(numGames/1000, 50u)));

	unsigned reportAfter	= progress.frequency();
	unsigned count			= 0;
	unsigned countGames	= 0;

	for (unsigned i = 0; i < numGames; ++i)
	{
		if (reportAfter == count)
		{
			progress.update(count);
			reportAfter += progress.frequency();
			::newNewline = true;
		}
		count += 1;

		try
		{
			save::State state = src.exportGame(i, dst);

			if (state == save::Ok)
				++countGames;
			else if (!log.error(state, i + 1))
				return countGames;
		}
		catch (IOException const& exc)
		{
			logIOError(exc, i + 1);
		}
		catch (...)
		{
			printf("\n");
			fflush(stdout);
			fprintf(stderr, "*** Exception catched while decoding game #%u\n", count);
			throw;
		}
	}

	return countGames;
}


static unsigned
computeWorkerCount(unsigned nGames)
{
	char const* value = ::getenv("SCIDB_MAINTENANCE_THREADS");

	if (value && *value)
	{
		long forced = ::strtol(value, 0, 10);
		if (forced > 0)
			return unsigned(forced);
	}

	unsigned processors = sys::info::numberOfProcessors();

	if (processors < 2 || nGames < 20000)
		return 1;

	unsigned maxWorkers = nGames/10000;
	if (maxWorkers == 0)
		return 1;

	if (processors > maxWorkers)
		processors = maxWorkers;

	return mstl::max(1u, processors);
}


struct DecodeWorker
{
	DecodeWorker(Database& src_,
					 mstl::vector<GameData*>& results_,
					 unsigned chunkStart_,
					 unsigned first_,
					 unsigned last_)
		:src(src_)
		,results(results_)
		,chunkStart(chunkStart_)
		,first(first_)
		,last(last_)
	{
	}

	void operator() ()
	{
		for (unsigned i = first; i < last; ++i)
		{
			GameData* data = new GameData();

			try
			{
				GameInfo& info = src.gameInfo(i);
				src.codec().decodeGame(*data, info, i, 0);
				results[i - chunkStart] = data;
			}
			catch (DecodingFailedException const&)
			{
				delete data;
				results[i - chunkStart] = 0;
			}
			catch (mstl::exception const&)
			{
				delete data;
				results[i - chunkStart] = 0;
			}
		}
	}

	Database&					src;
	mstl::vector<GameData*>&	results;
	unsigned						chunkStart;
	unsigned						first;
	unsigned						last;
};


static save::State
reencodeGame(GameData& data, GameInfo const& info, variant::Type variant, Consumer& consumer)
{
	TagSet tags;
	info.setupTags(tags, variant);

	// Merge the extra tags produced during decode (Source, EventCategory,
	// team tags, FEN/SetUp) into the standard tag set. Skip the placeholder
	// tags that GameData's constructor initializes, since setupTags() already
	// set the correct values for those.
	for (tag::ID i = data.m_tags.findFirst(); i <= tag::LastTag; i = data.m_tags.findNext(i))
	{
		if (i == tag::Event || i == tag::Site || i == tag::Date || i == tag::Round
			|| i == tag::White || i == tag::Black || i == tag::Result)
			continue;

		tags.set(i, data.m_tags.value(i));
	}

	consumer.setGameFlags(info.flags());
	consumer.setLangFlags(info.langFlags());

	if (info.isGuidingText())
	{
		// The decode phase stored the guiding-text title in the Event tag;
		// restore it (setupTags() left a placeholder '?').
		if (data.m_tags.contains(tag::Event))
			tags.set(tag::Event, data.m_tags.value(tag::Event));

		tags.set(tag::Remark, "GUIDING_TEXT");

		if (!consumer.startGame(tags))
		{
			consumer.finalizeGame();
			return save::UnsupportedVariant;
		}

		if (!data.m_guidingText.empty())
			consumer.putPrecedingComment(Comment(data.m_guidingText, 0), Annotation(), MarkSet());

		consumer.startMoveSection();
		consumer.finishMoveSection(result::Unknown);
		save::State rc = consumer.finishGame(tags);
		consumer.finalizeGame();
		return rc;
	}

	if (!consumer.startGame(tags, data.m_startBoard))
	{
		consumer.finalizeGame();
		return save::UnsupportedVariant;
	}

	consumer.startMoveSection();
	cbh::GameDecoder::traverse(consumer, data.m_startNode);

	char buf[32];
	::snprintf(buf, sizeof(buf), "%u", info.plyCount());
	tags.set(tag::PlyCount, buf);

	consumer.finishMoveSection(result::fromString(tags.value(tag::Result)));
	save::State rc = consumer.finishGame(tags);
	consumer.finalizeGame();
	return rc;
}


static unsigned
exportGamesParallel(Database& src, Consumer& dst, util::Progress& progress, ::Log& log)
{
	unsigned numGames = src.countGames();
	unsigned nWorkers = computeWorkerCount(numGames);

	if (nWorkers == 1)
		return exportGames(src, dst, progress, log);

	util::ProgressWatcher watcher(progress, numGames);
	progress.setFrequency(mstl::min(200u, mstl::max(numGames/1000, 50u)));

	unsigned countGames = 0;
	unsigned reportAfter = progress.frequency();
	unsigned count = 0;

	const unsigned chunkSize = 1000;

	for (unsigned chunkStart = 0; chunkStart < numGames; chunkStart += chunkSize)
	{
		unsigned chunkEnd = mstl::min(chunkStart + chunkSize, numGames);
		unsigned chunkGames = chunkEnd - chunkStart;

		// Phase 1: decode the chunk in parallel.
		mstl::vector<GameData*> results(chunkGames, static_cast<GameData*>(0));
		mstl::vector<DecodeWorker*> workers;
		sys::ThreadGroup group;

		unsigned perWorker = (chunkGames + nWorkers - 1)/nWorkers;
		workers.reserve(nWorkers);

		for (unsigned w = 0; w < nWorkers; ++w)
		{
			unsigned first = w*perWorker;
			unsigned last = mstl::min(first + perWorker, chunkGames);

			if (first >= last)
				break;

			DecodeWorker* worker = new DecodeWorker(src, results, chunkStart, chunkStart + first, chunkStart + last);
			workers.push_back(worker);

			if (!group.start(sys::Thread::Runnable(&DecodeWorker::operator(), worker)))
			{
				workers.pop_back();
				delete worker;

				// Fall back to serial decode for the remaining games.
				for (unsigned i = first; i < chunkGames; ++i)
				{
					GameData* data = new GameData();
					try
					{
						GameInfo& info = src.gameInfo(chunkStart + i);
						src.codec().decodeGame(*data, info, chunkStart + i, 0);
						results[i] = data;
					}
					catch (...)
					{
						delete data;
						results[i] = 0;
					}
				}
				break;
			}
		}

		mstl::string failMsg;
		bool ok = group.joinNoThrow(failMsg);

		// Phase 2: re-encode and write in order.
		for (unsigned i = 0; i < chunkGames; ++i)
		{
			if (reportAfter == count)
			{
				progress.update(count);
				reportAfter += progress.frequency();
				::newNewline = true;
			}
			count += 1;

			GameData* data = results[i];

			if (!data)
			{
				++rejected;
				continue;
			}

			try
			{
				save::State state = reencodeGame(*data, src.gameInfo(chunkStart + i), src.variant(), dst);

				if (state == save::Ok)
					++countGames;
				else if (!log.error(state, chunkStart + i + 1))
				{
					delete data;
					for (unsigned j = i + 1; j < chunkGames; ++j)
						delete results[j];
					for (unsigned j = 0; j < workers.size(); ++j)
						delete workers[j];
					return countGames;
				}
			}
			catch (IOException const& exc)
			{
				logIOError(exc, chunkStart + i + 1);
			}
			catch (...)
			{
				printf("\n");
				fflush(stdout);
				fprintf(stderr, "*** Exception catched while encoding game #%u\n", count);
				throw;
			}

			delete data;
		}

		for (unsigned j = 0; j < workers.size(); ++j)
			delete workers[j];

		if (!ok)
		{
			fflush(stdout);
			fprintf(stderr, "\n%s\n", failMsg.c_str());
			exit(1);
		}
	}

	return countGames;
}


int
main(int argc, char* argv[])
{
#ifdef BROKEN_LINKER_HACK

		// HACK!
		// This hack is required for insane systems like Debian Wheezy,
		// and Ubuntu Oneiric. The static object initialization is not
		// properly working on these systems (among other problems).
		db::tag::initialize();
		db::castling::initialize();
		db::board::base::initialize();
		db::Board::initialize();
		db::HomePawns::initialize();
		db::Signature::initialize();
		db::sci::Encoder::initialize();

#endif

	mstl::backtrace::disable();

	TclInterpreter	tclInterpreter;
	mstl::string	convertto(::ConvertTo);
	mstl::string	convertfrom(::ConvertFrom);
	bool				force(false);
	bool				serial(false);
	bool				allTags(false);
	bool				noTags(false);
	bool				defaultTags(true);
	bool				extraTags(false);
	mstl::string	givenTags;

	int i = 1;

	for ( ; i < argc && argv[i][0] == '-'; ++i)
	{
		if (strcmp(argv[i], "--") == 0)
			break;

		if (strcmp(argv[i], "--help") == 0)
		{
			printHelpAndExit(0);
		}
		else if (strcmp(argv[i], "--convertto") == 0)
		{
			if (++i == argc)
				printHelpAndExit(1);
			convertto.assign(argv[i]);
			checkEncoding(convertto);
		}
		else if (strcmp(argv[i], "--convertfrom") == 0)
		{
			if (++i == argc)
				printHelpAndExit(1);
			convertfrom.assign(argv[i]);
			if (convertfrom != "auto")
				checkEncoding(convertfrom);
		}
		else if (strcmp(argv[i], "--tags") == 0)
		{
			if (++i == argc)
				printHelpAndExit(1);
			givenTags = argv[i];
			checkTagList(givenTags);
			defaultTags = false;
		}
		else if (strcmp(argv[i], "--all-tags") == 0)
		{
			allTags = true;
		}
		else if (strcmp(argv[i], "--no-tags") == 0)
		{
			noTags = true;
		}
		else if (strcmp(argv[i], "--unusual-tags") == 0)
		{
			extraTags = true;
		}
		else if (strcmp(argv[i], "--list-encodings") == 0)
		{
			printEncodingsAndExit(0);
		}
		else if (strcmp(argv[i], "--list-default-tags") == 0)
		{
			printDefaultTagsAndExit(0);
		}
		else if (strcmp(argv[i], "--list-mandatory-tags") == 0)
		{
			printMandatoryTagsAndExit(0);
		}
		else if (strcmp(argv[i], "--list-usual-tags") == 0)
		{
			printUsualTagsAndExit(0);
		}
		else if (strcmp(argv[i], "--force") == 0)
		{
			force = true;
		}
		else if (strcmp(argv[i], "--serial") == 0)
		{
			serial = true;
		}
		else
		{
			fprintf(stderr, "Unrecognized option '%s'.\n\n", argv[i]);
			printHelpAndExit(1);
		}
	}

	if (!sys::utf8::Codec::checkEncoding(convertto))
	{
		fprintf(stderr, "Unknown encoding '%s'.\n\n", convertto.c_str());
		printEncodingsAndExit(1);
	}

	if (convertfrom != "auto" && !sys::utf8::Codec::checkEncoding(convertfrom))
	{
		fprintf(stderr, "Unknown encoding '%s'.\n\n", convertfrom.c_str());
		printEncodingsAndExit(1);
	}

	if (i == argc)
	{
		fprintf(stderr, "No input database specified.\n\n");
		printHelpAndExit(1);
	}

	mstl::string cbhPath(argv[i++]);

	if (	cbhPath.size() < 4
		|| (	strcmp(cbhPath.c_str() + cbhPath.size() - 4, ".cbh") != 0
			&& strcmp(cbhPath.c_str() + cbhPath.size() - 4, ".cbf") != 0
			&& strcmp(cbhPath.c_str() + cbhPath.size() - 4, ".CBF") != 0
			&& strcmp(cbhPath.c_str() + cbhPath.size() - 4, ".CBH") != 0))
	{
		cbhPath.append(".cbh");
	}

	if (access(sys::file::internalName(cbhPath), F_OK) != 0)
	{
		fprintf(stderr, "Cannot open file '%s'.\n", cbhPath.c_str());
		exit(1);
	}

	mstl::string si4Path;

	if (i < argc)
	{
		si4Path.append(sys::file::normalizedName(argv[i]));
	}
	else
		{
			si4Path.assign(cbhPath);
			mstl::string::size_type n = si4Path.rfind('/');

			if (n != mstl::string::npos)
				si4Path.erase(mstl::string::size_type(0), n + 1);

			if (	si4Path.size() >= 4
				&& (	strcmp(si4Path.c_str() + si4Path.size() - 4, ".cbh") == 0
					|| strcmp(si4Path.c_str() + si4Path.size() - 4, ".cbf") == 0
					|| strcmp(si4Path.c_str() + si4Path.size() - 4, ".CBF") == 0))
			{
				si4Path.erase(si4Path.size() - 4);
			}
		}

	if (si4Path.empty())
	{
		fprintf(stderr, "Empty destination file name is not allowed.\n");
		exit(1);
	}

	if (si4Path.size() < 4 || strcmp(si4Path.c_str() + si4Path.size() - 4, ".si4") != 0)
		si4Path.append(".si4");
	
	if (!force && access(sys::file::internalName(si4Path), R_OK) == 0)
	{
		fprintf(stderr, "Database '%s' already exists.\n", si4Path.c_str());
		exit(1);
	}

	TagBits tagList;

	if (!noTags)
	{
		if (allTags)
			tagList.set();
		else if (defaultTags)
			tagList = getDefaultTags();
		else
			setTagList(tagList, givenTags);
	}

	try
	{
		loadEcoFile();

		Progress progress;

		Database	src(cbhPath, convertfrom, permission::ReadOnly, progress);
		Database	dst(si4Path, convertto, storage::OnDisk, variant::Normal);
		::Log log;
		ImportStats stats;
		si3::Consumer consumer(	format::Scid4,
										dynamic_cast<si3::Codec&>(dst.codec()),
										convertto,
										tagList,
										extraTags);

		dst.setType(src.type());
		printf("Convert '%s' to '%s' ", cbhPath.c_str(), si4Path.c_str());
		fflush(stdout);
		::newNewline = true;
		unsigned numGames = serial
								? exportGames(src, consumer, progress, log)
								: exportGamesParallel(src, consumer, progress, log);
		stats.written = numGames;
		stats.rejected = rejected;
		stats.warnings = log.warningCount;
		stats.errors = log.errorCount;
		dst.save(progress);
		printf("\n%u game(s) written.", numGames);
		if (rejected > 0)
			printf("\n%u game(s) rejected.", rejected);
		printf("\n");
		printImportSummary(cbhPath, si4Path, convertto, stats);
		fflush(stdout);
		dst.close();
		src.close();
	}
	catch (IOException const& exc)
	{
		logIOError(exc);
		exit(1);
	}
	catch (mstl::exception const& exc)
	{
		fflush(stdout);
		fprintf(stderr, "\n%s\n", exc.what());
		exit(1);
	}

	return 0;
}

// vi:set ts=3 sw=3:
