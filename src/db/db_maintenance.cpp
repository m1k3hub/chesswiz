// ======================================================================
// Shared database maintenance helpers.
// ======================================================================

#include "db_maintenance.h"

#include "db_database.h"
#include "db_database_codec.h"
#include "db_game_info.h"

#include "sys_info.h"
#include "sys_lock.h"
#include "sys_mutex.h"
#include "sys_thread_group.h"

#include "u_byte_stream.h"
#include "u_crc.h"

#include "m_map.h"
#include "m_pair.h"
#include "m_exception.h"
#include "m_string.h"

#include <stdlib.h>

using namespace db;

namespace db {
namespace maintenance {

namespace {

typedef mstl::map<mstl::string, EcoStats> EcoStatsMap;
typedef mstl::pair<uint32_t, unsigned> DuplicateEntry;
typedef mstl::pair<unsigned, unsigned> DuplicateRange;

enum { MinParallelGamesPerWorker = 10000 };

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

	if (processors < 2 || nGames < MinParallelGamesPerWorker*2)
		return 1;

	unsigned maxWorkers = nGames/MinParallelGamesPerWorker;
	if (maxWorkers == 0)
		return 1;

	if (processors > maxWorkers)
		processors = maxWorkers;

	return mstl::max(1u, processors);
}


static void
accumulateEcoStats(EcoStatsMap& stats, Database const& db, variant::Type variant, unsigned first, unsigned last)
{
	for (unsigned i = first; i < last; ++i)
	{
		GameInfo const& info = db.gameInfo(i);

		if (info.isDeleted())
			continue;

		mstl::string eco = info.eco(variant).asShortString();
		if (eco.empty())
			eco = "?";

		EcoStats& stat = stats[eco];
		stat.eco = eco;
		++stat.total;

		switch (info.result())
		{
			case result::White: ++stat.white; break;
			case result::Draw:  ++stat.draws; break;
			case result::Black: ++stat.black; break;
			default: break;
		}
	}
}


static void
mergeEcoStats(EcoStatsMap& target, EcoStatsMap const& source)
{
	for (EcoStatsMap::const_iterator it = source.begin(); it != source.end(); ++it)
	{
		EcoStats& stat = target[it->first];
		stat.eco = it->second.eco;
		stat.total += it->second.total;
		stat.white += it->second.white;
		stat.draws += it->second.draws;
		stat.black += it->second.black;
	}
}


static void
collectDuplicateEntries(mstl::vector<DuplicateEntry>& entries,
							 Database const& db,
							 unsigned first,
							 unsigned last)
{
	for (unsigned i = first; i < last; ++i)
	{
		if (!db.gameInfo(i).isDeleted())
			entries.push_back(DuplicateEntry(db.computeChecksum(i), i));
	}
}


static void
appendDuplicateEntries(mstl::vector<DuplicateEntry>& target, mstl::vector<DuplicateEntry> const& source)
{
	for (unsigned i = 0; i < source.size(); ++i)
		target.push_back(source[i]);
}


static void
collectDuplicateRanges(mstl::vector<DuplicateEntry> const& entries, mstl::vector<DuplicateRange>& ranges)
{
	for (unsigned i = 0, n = entries.size(); i < n; )
	{
		unsigned j = i + 1;

		while (j < n && entries[j].first == entries[i].first)
			++j;

		if (j - i > 1)
			ranges.push_back(DuplicateRange(i, j));

		i = j;
	}
}


static void
appendDuplicateGroups(DuplicateGroups& target, DuplicateGroups const& source)
{
	for (unsigned i = 0; i < source.size(); ++i)
		target.push_back(source[i]);
}


static void
resolveDuplicateRange(	DuplicateGroups& result,
								Database& db,
								mstl::vector<DuplicateEntry> const& entries,
								unsigned first,
								unsigned last,
								::util::BlockFileReader* reader)
{
	mstl::map<uint64_t, DuplicateGroup> groups;

	for (unsigned k = first; k < last; ++k)
	{
		unsigned index = entries[k].second;
		util::ByteStream data = db.codec().getGame(db.gameInfo(index), reader);
		uint32_t movesChecksum = ::util::crc::compute(0, data.data(), data.size());
		uint64_t key = (uint64_t(entries[k].first) << 32) | movesChecksum;

		groups[key].push_back(index);
	}

	for (mstl::map<uint64_t, DuplicateGroup>::const_iterator it = groups.begin(); it != groups.end(); ++it)
	{
		if (it->second.size() > 1)
			result.push_back(it->second);
	}
}


struct EcoStatsWorker
{
	EcoStatsWorker(Database const& database_, variant::Type variant_, unsigned first_, unsigned last_)
		:database(database_)
		,variant(variant_)
		,first(first_)
		,last(last_)
	{
	}

	void operator() ()
	{
		accumulateEcoStats(stats, database, variant, first, last);
	}

	Database const& database;
	variant::Type variant;
	unsigned first;
	unsigned last;
	EcoStatsMap stats;
};


struct DuplicateEntryWorker
{
	DuplicateEntryWorker(Database const& database_, unsigned first_, unsigned last_)
		:database(database_)
		,first(first_)
		,last(last_)
	{
	}

	void operator() ()
	{
		collectDuplicateEntries(entries, database, first, last);
	}

	Database const& database;
	unsigned first;
	unsigned last;
	mstl::vector<DuplicateEntry> entries;
};


struct DuplicateGroupWorker
{
	DuplicateGroupWorker(Database& database_,
							 mstl::vector<DuplicateEntry> const& entries_,
							 mstl::vector<DuplicateRange> const& ranges_,
							 ::util::BlockFileReader* reader_,
							 unsigned first_,
							 unsigned last_)
		:database(database_)
		,entries(entries_)
		,ranges(ranges_)
		,reader(reader_)
		,first(first_)
		,last(last_)
	{
	}

	void operator() ()
	{
		for (unsigned i = first; i < last; ++i)
		{
			resolveDuplicateRange(groups,
									 database,
									 entries,
									 ranges[i].first,
									 ranges[i].second,
									 reader);
		}
	}

	Database& database;
	mstl::vector<DuplicateEntry> const& entries;
	mstl::vector<DuplicateRange> const& ranges;
	::util::BlockFileReader* reader;
	unsigned first;
	unsigned last;
	DuplicateGroups groups;
};

} // namespace

EcoStats::EcoStats()
	:total(0)
	,white(0)
	,draws(0)
	,black(0)
{
}


DuplicateGroups
findDuplicates(Database& db)
{
	unsigned nGames = db.countGames();
	unsigned nWorkers = computeWorkerCount(nGames);

	if (!db.isReadonly())
		nWorkers = 1;

	mstl::vector<DuplicateEntry> entries;
	entries.reserve(nGames);

	if (nWorkers == 1)
	{
		collectDuplicateEntries(entries, db, 0, nGames);
	}
	else
	{
		mstl::vector<DuplicateEntryWorker*> workers;
		sys::ThreadGroup group;
		unsigned chunkSize = (nGames + nWorkers - 1)/nWorkers;
		unsigned serialFirst = nGames;

		workers.reserve(nWorkers);

		for (unsigned i = 0; i < nWorkers; ++i)
		{
			unsigned first = i*chunkSize;
			unsigned last = mstl::min(first + chunkSize, nGames);

			if (first >= last)
				break;

			DuplicateEntryWorker* worker = new DuplicateEntryWorker(db, first, last);
			workers.push_back(worker);

			if (!group.start(sys::Thread::Runnable(&DuplicateEntryWorker::operator(), worker)))
			{
				workers.pop_back();
				delete worker;
				serialFirst = first;
				break;
			}
		}

		mstl::string failMsg1;
		bool ok1 = group.joinNoThrow(failMsg1);

		for (unsigned i = 0; i < workers.size(); ++i)
		{
			appendDuplicateEntries(entries, workers[i]->entries);
			delete workers[i];
		}

		if (!ok1)
			M_RAISE("%s", failMsg1.c_str());

		if (serialFirst < nGames)
			collectDuplicateEntries(entries, db, serialFirst, nGames);
	}

	entries.qsort([](DuplicateEntry const& a, DuplicateEntry const& b) -> int {
		if (a.first != b.first)
			return a.first < b.first ? -1 : 1;
		// Tiebreak on game index so the ordering (and thus which game is
		// treated as the original within a duplicate group) is deterministic.
		return a.second < b.second ? -1 : a.second > b.second ? 1 : 0;
	});

	DuplicateGroups result;
	mstl::vector<DuplicateRange> ranges;
	collectDuplicateRanges(entries, ranges);

	if (ranges.empty())
		return result;

	db.codec().sync();
	::util::BlockFileReader* probeReader = db.openAsyncReader();

	if (!probeReader || nWorkers == 1)
	{
		if (probeReader)
			db.closeAsyncReader(probeReader);

		for (unsigned i = 0; i < ranges.size(); ++i)
			resolveDuplicateRange(result, db, entries, ranges[i].first, ranges[i].second, 0);

		return result;
	}

	db.closeAsyncReader(probeReader);

	unsigned nGroupWorkers = mstl::min(nWorkers, unsigned(ranges.size()));
	unsigned chunkSize = (ranges.size() + nGroupWorkers - 1)/nGroupWorkers;
	mstl::vector<DuplicateGroupWorker*> workers;
	mstl::vector<::util::BlockFileReader*> readers;
	sys::ThreadGroup group;

	workers.reserve(nGroupWorkers);
	readers.reserve(nGroupWorkers);
	unsigned serialFirst = ranges.size();

	for (unsigned i = 0; i < nGroupWorkers; ++i)
	{
		unsigned first = i*chunkSize;
		unsigned last = mstl::min(first + chunkSize, unsigned(ranges.size()));

		if (first >= last)
			break;

		::util::BlockFileReader* reader = db.openAsyncReader();
		if (!reader)
		{
			serialFirst = first;
			break;
		}

		readers.push_back(reader);
		DuplicateGroupWorker* worker = new DuplicateGroupWorker(db, entries, ranges, reader, first, last);
		workers.push_back(worker);

		if (!group.start(sys::Thread::Runnable(&DuplicateGroupWorker::operator(), worker)))
		{
			workers.pop_back();
			delete worker;
			db.closeAsyncReader(readers.back());
			readers.pop_back();
			serialFirst = first;
			break;
		}
	}

	mstl::string failMsg2;
	bool ok2 = group.joinNoThrow(failMsg2);

	for (unsigned i = 0; i < workers.size(); ++i)
	{
		appendDuplicateGroups(result, workers[i]->groups);
		delete workers[i];
		db.closeAsyncReader(readers[i]);
	}

	if (!ok2)
		M_RAISE("%s", failMsg2.c_str());

	for (unsigned i = serialFirst; i < ranges.size(); ++i)
		resolveDuplicateRange(result, db, entries, ranges[i].first, ranges[i].second, 0);

	return result;
}


EcoStatsList
computeEcoStats(Database const& db, variant::Type variant)
{
	EcoStatsMap stats;
	unsigned nGames = db.countGames();
	unsigned nWorkers = computeWorkerCount(nGames);

	if (nWorkers == 1)
	{
		accumulateEcoStats(stats, db, variant, 0, nGames);
	}
	else
	{
		mstl::vector<EcoStatsWorker*> workers;
		sys::ThreadGroup group;
		unsigned chunkSize = (nGames + nWorkers - 1)/nWorkers;
		unsigned serialFirst = nGames;

		workers.reserve(nWorkers);

		for (unsigned i = 0; i < nWorkers; ++i)
		{
			unsigned first = i*chunkSize;
			unsigned last = mstl::min(first + chunkSize, nGames);

			if (first >= last)
				break;

			EcoStatsWorker* worker = new EcoStatsWorker(db, variant, first, last);
			workers.push_back(worker);

			if (!group.start(sys::Thread::Runnable(&EcoStatsWorker::operator(), worker)))
			{
				workers.pop_back();
				delete worker;
				serialFirst = first;
				break;
			}
		}

		mstl::string failMsg3;
		bool ok3 = group.joinNoThrow(failMsg3);

		for (unsigned i = 0; i < workers.size(); ++i)
		{
			mergeEcoStats(stats, workers[i]->stats);
			delete workers[i];
		}

		if (!ok3)
			M_RAISE("%s", failMsg3.c_str());

		if (serialFirst < nGames)
			accumulateEcoStats(stats, db, variant, serialFirst, nGames);
	}

	EcoStatsList result;
	result.reserve(stats.size());

	for (mstl::map<mstl::string, EcoStats>::const_iterator it = stats.begin(); it != stats.end(); ++it)
		result.push_back(it->second);

	return result;
}

} // namespace maintenance
} // namespace db
