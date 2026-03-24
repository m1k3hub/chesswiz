// ======================================================================
// Shared database maintenance helpers.
// ======================================================================

#include "db_maintenance.h"

#include "db_database.h"
#include "db_database_codec.h"
#include "db_game_info.h"

#include "u_byte_stream.h"
#include "u_crc.h"

#include "m_map.h"
#include "m_pair.h"

using namespace db;

namespace db {
namespace maintenance {

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
	typedef mstl::pair<uint32_t, unsigned> Entry;
	mstl::vector<Entry> entries;

	unsigned nGames = db.countGames();
	entries.reserve(nGames);

	for (unsigned i = 0; i < nGames; ++i)
	{
		if (!db.gameInfo(i).isDeleted())
			entries.push_back(Entry(db.computeChecksum(i), i));
	}

	entries.qsort([](Entry const& a, Entry const& b) -> int {
		return a.first < b.first ? -1 : a.first > b.first ? 1 : 0;
	});

	DuplicateGroups result;

	for (unsigned i = 0, n = entries.size(); i < n; )
	{
		unsigned j = i + 1;
		while (j < n && entries[j].first == entries[i].first)
			++j;

		if (j - i > 1)
		{
			mstl::map<uint64_t, DuplicateGroup> groups;

			for (unsigned k = i; k < j; ++k)
			{
				unsigned index = entries[k].second;
				util::ByteStream data = db.codec().getGame(db.gameInfo(index));
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

		i = j;
	}

	return result;
}


EcoStatsList
computeEcoStats(Database const& db, variant::Type variant)
{
	mstl::map<mstl::string, EcoStats> stats;

	for (unsigned i = 0, n = db.countGames(); i < n; ++i)
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

	EcoStatsList result;
	result.reserve(stats.size());

	for (mstl::map<mstl::string, EcoStats>::const_iterator it = stats.begin(); it != stats.end(); ++it)
		result.push_back(it->second);

	return result;
}

} // namespace maintenance
} // namespace db

