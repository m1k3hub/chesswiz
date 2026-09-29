// ======================================================================
// Shared database maintenance helpers.
// ======================================================================

#include "db_maintenance.h"

#include "db_database.h"
#include "db_database_codec.h"
#include "db_game_info.h"
#include "db_game_data.h"
#include "db_move_node.h"
#include "sys_utf8.h"

#include <algorithm>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

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


// Key-only normalization: no tags, namebase entries or database records are edited.
// Result stays out of the blocking hash so unknown results can match decided ones.
// Union roots retain a decided result: an unknown cannot bridge opposite results.
// This deliberately constrains transitivity where the two requirements conflict.
// Blocking/sorting is O(G log G); compatibility edges cost O(B^2) per block.
// Unknown headers cannot safely be hashed, so undecodable games share a fallback
// block, verified using headers, variant, IDN and known ply count. Empty decoded
// games retain their start position. FEN counters are ignored, but castling, side
// to move and en-passant rights are retained, including Chess960 rook files.
// Player identity prefers FIDE, then DSB, ECF and ICCF IDs in their own namespaces.
// ECO is deliberately unused: a soft check cannot affect duplicate membership.
struct NormalizedGame
{
	std::string players[2], event, site, position;
	std::vector<uint16_t> moves;
	unsigned ids[2][4], date[3], round, plies, idn, variant, result;
	bool decoded;
};

static std::string
foldText(mstl::string const& text)
{
	std::string result;
	for (char const* p = text.c_str(); *p; )
	{
		sys::utf8::uchar c;
		p = sys::utf8::nextChar(p, c);
		if (c >= 0x300 && c <= 0x36f)
			continue;
		c = sys::utf8::toLower(c);
		if (c == 0xdf || c == 0xe6 || c == 0x153 || c == 0xfe)
		{
			result += c == 0xdf ? "ss" : c == 0xe6 ? "ae" : c == 0x153 ? "oe" : "th";
			continue;
		}
		if (c >= 0x80 && c <= 0xff)
		{
			mstl::string letter, mapped;
			sys::utf8::append(letter, c);
			sys::utf8::latin1::map(letter, mapped);
			c = sys::utf8::getChar(mapped.c_str());
		}
		// Latin Extended-A letters not covered by the existing Latin-1 map.
		static char const* const groups[] = { "āăą", "ćĉċč", "ďđ", "ēĕėęě", "ĝğġģ", "ĥħ",
			"ĩīĭįı", "ĵ", "ķ", "ĺļľŀł", "ńņň", "ōŏő", "ŕŗř", "śŝşš", "ţťŧ", "ũūŭůűų", "ŵ", "ŷ", "źżž" };
		char const* letters = "acdeghijklnorstuwyz";
		for (unsigned i = 0; c >= 0x100 && i < sizeof(groups)/sizeof(*groups); ++i)
		{
			for (char const* q = groups[i]; *q; )
			{
				sys::utf8::uchar d;
				q = sys::utf8::nextChar(q, d);
				if (c == d) c = letters[i];
			}
		}
		if (sys::utf8::isAlnum(c))
		{
			mstl::string letter;
			sys::utf8::append(letter, c);
			result += letter.c_str();
		}
		else if (sys::utf8::isSpace(c) && !result.empty() && result.back() != ' ')
			result += ' ';
	}
	if (!result.empty() && result.back() == ' ') result.pop_back();
	return result;
}

static std::vector<std::string>
words(std::string const& text)
{
	std::istringstream stream(text);
	std::vector<std::string> result;
	std::string word;
	while (stream >> word) result.push_back(word);
	return result;
}

static std::string
playerKey(mstl::string const& name)
{
	std::string raw(name.c_str());
	size_t comma = raw.find(',');
	std::replace(raw.begin(), raw.end(), ',', ' ');
	std::replace(raw.begin(), raw.end(), '.', ' ');
	std::vector<std::string> parts = words(foldText(mstl::string(raw.c_str())));
	parts.erase(std::remove_if(parts.begin(), parts.end(), [](std::string const& s) {
		return s == "gm" || s == "im" || s == "fm" || s == "cm" || s == "wgm"
			|| s == "wim" || s == "wfm" || s == "wcm" || s == "dr";
	}), parts.end());
	if (parts.empty()) return "";
	if (comma == std::string::npos && parts.size() > 1)
		std::rotate(parts.begin(), parts.end() - 1, parts.end());
	std::string result = parts[0];
	for (unsigned i = 1; i < parts.size(); ++i) result += " " + parts[i];
	return result;
}

static bool
compatibleName(std::string const& a, std::string const& b)
{
	if (a.empty() || b.empty()) return true;
	std::vector<std::string> x = words(a), y = words(b);
	if (x[0] != y[0]) return false;
	for (unsigned i = 1; i < std::min(x.size(), y.size()); ++i)
	{
		if (x[i] != y[i] && !(x[i][0] == y[i][0] && (x[i].size() == 1 || y[i].size() == 1)))
			return false;
	}
	return true;
}

static std::string
placeKey(mstl::string const& text, bool site)
{
	std::string raw(text.c_str());
	if (site && raw.size() >= 5 && raw.back() == ')' && raw[raw.size() - 5] == '(')
		raw.erase(raw.size() - 5);
	std::vector<std::string> parts = words(foldText(mstl::string(raw.c_str())));
	std::string result;
	for (unsigned i = 0; i < parts.size(); ++i)
	{
		std::string const& s = parts[i];
		size_t n = s.find_first_not_of("0123456789");
		if ((s.size() == 4 && n == std::string::npos)
			|| (n > 0 && n != std::string::npos && (s.substr(n) == "st" || s.substr(n) == "nd"
				|| s.substr(n) == "rd" || s.substr(n) == "th"))) continue;
		if (!result.empty()) result += ' ';
		result += s;
	}
	return result;
}

static bool
knownEqual(unsigned a, unsigned b) { return !a || !b || a == b; }

static bool
compatibleHeaders(NormalizedGame const& a, NormalizedGame const& b)
{
	if (a.decoded != b.decoded || a.variant != b.variant || !knownEqual(a.idn, b.idn)
		|| !knownEqual(a.plies, b.plies) || !knownEqual(a.round, b.round)
		|| !knownEqual(a.result, b.result)) return false;
	for (unsigned i = 0; i < 2; ++i)
	{
		bool identified = false;
		for (unsigned federation = 0; federation < 4; ++federation)
		{
			if (a.ids[i][federation] && b.ids[i][federation])
			{
				if (a.ids[i][federation] != b.ids[i][federation]) return false;
				identified = true;
				break;
			}
		}
		if (!identified && !compatibleName(a.players[i], b.players[i])) return false;
	}
	for (unsigned i = 0; i < 3; ++i)
		if (!knownEqual(a.date[i], b.date[i])) return false;
	return (a.event.empty() || b.event.empty() || a.event == b.event)
		&& (a.site.empty() || b.site.empty() || a.site == b.site)
		&& (!a.decoded || !b.decoded || (a.position == b.position && a.moves == b.moves));
}

struct NormalizedWorker
{
	Database& database;
	std::vector<NormalizedGame>& games;
	::util::BlockFileReader* reader;
	unsigned first, last;
	mstl::vector<DuplicateEntry> entries;

	NormalizedWorker(Database& db, std::vector<NormalizedGame>& data, unsigned begin, unsigned end)
		:database(db), games(data), reader(db.isReadonly() ? db.openAsyncReader() : 0), first(begin), last(end) {}
	~NormalizedWorker() { if (reader) database.closeAsyncReader(reader); }

	void operator() ()
	{
		std::vector<uint16_t> line(database.codec().maxGameLength() + 1);
		for (unsigned index = first; index < last; ++index)
		{
			GameInfo const& info = database.gameInfo(index);
			if (info.isDeleted()) continue;
			NormalizedGame& key = games[index];
			for (unsigned c = 0; c < 2; ++c)
			{
				key.players[c] = playerKey(info.playerName(color::ID(c)));
				key.ids[c][0] = info.fideID(color::ID(c));
				Player const* player = info.player(color::ID(c));
				if (player)
				{
					if (!key.ids[c][0]) key.ids[c][0] = player->fideID();
					key.ids[c][1] = player->dsbID();
					key.ids[c][2] = player->ecfID();
					key.ids[c][3] = player->iccfID();
				}
			}
			Date date = info.date();
			if (!date.year()) date = info.eventDate();
			key.date[0] = date.year(); key.date[1] = date.month(); key.date[2] = date.day();
			key.event = placeKey(info.event(), false);
			key.site = placeKey(info.site(), true);
			key.round = info.round(); key.idn = info.idn(); key.plies = info.plyCount();
			key.variant = database.variant();
			if (database.variant() == variant::Antichess)
				key.variant = info.isGiveaway() ? variant::Giveaway : variant::Suicide;
			key.result = info.result() == result::White ? 1 : info.result() == result::Black ? 2 : info.result() == result::Draw ? 3 : 0;
			key.decoded = false;
			Board board;
			try
			{
				if (reader)
				{
					unsigned count = database.codec().decodeGame(reader, info, line.data(), line.size(), board, false);
					// A full buffer may be truncated: never compare its prefix as a game.
					if (count < line.size())
					{
						key.moves.assign(line.begin(), line.begin() + count);
						key.decoded = true;
					}
				}
				else
				{
					GameData data;
					GameInfo copy(info);
					database.codec().decodeGame(data, copy, index);
					board = data.m_startBoard;
					for (MoveNode const* node = data.m_startNode->next(); node && !node->atLineEnd(); node = node->next())
						key.moves.push_back(node->move().index());
					key.decoded = true;
				}
			}
			catch (mstl::exception const&) { key.moves.clear(); }
			uint32_t hash = 0;
			if (key.decoded)
			{
				std::vector<std::string> fen = words(board.toFen(variant::Type(key.variant), Board::Shredder).c_str());
				for (unsigned i = 0; i < std::min(size_t(4), fen.size()); ++i) key.position += fen[i] + " ";
				key.plies = key.moves.size();
				hash = ::util::crc::compute(0, key.position.data(), key.position.size());
				for (unsigned i = 0; i < key.moves.size(); ++i) hash = ::util::crc::compute(hash, key.moves[i]);
			}
			entries.push_back(DuplicateEntry(hash, index));
		}
	}
};

static DuplicateGroups
findNormalizedDuplicates(Database& db)
{
	std::vector<NormalizedGame> games(db.countGames());
	mstl::vector<DuplicateEntry> entries;
	unsigned count = db.isReadonly() ? computeWorkerCount(db.countGames()) : 1;
	unsigned chunk = (db.countGames() + count - 1)/count;
	std::vector<std::unique_ptr<NormalizedWorker> > workers;
	sys::ThreadGroup threads;
	for (unsigned first = 0; first < db.countGames(); first += chunk)
	{
		workers.emplace_back(new NormalizedWorker(db, games, first, std::min(first + chunk, db.countGames())));
		NormalizedWorker* worker = workers.back().get();
		if (!worker->reader || count == 1 || !threads.start(sys::Thread::Runnable(&NormalizedWorker::operator(), worker)))
			(*worker)();
	}
	mstl::string failure;
	bool ok = threads.joinNoThrow(failure);
	if (!ok) M_RAISE("%s", failure.c_str());
	for (unsigned i = 0; i < workers.size(); ++i) appendDuplicateEntries(entries, workers[i]->entries);
	entries.qsort([](DuplicateEntry const& a, DuplicateEntry const& b) -> int {
		if (a.first != b.first) return a.first < b.first ? -1 : 1;
		return a.second < b.second ? -1 : a.second > b.second ? 1 : 0;
	});
	DuplicateGroups result;
	mstl::vector<DuplicateRange> ranges;
	collectDuplicateRanges(entries, ranges);
	for (unsigned r = 0; r < ranges.size(); ++r)
	{
		unsigned first = ranges[r].first, size = ranges[r].second - first;
		std::vector<unsigned> parent(size), results(size);
		for (unsigned i = 0; i < size; ++i) { parent[i] = i; results[i] = games[entries[first + i].second].result; }
		auto root = [&parent](unsigned i) { while (parent[i] != i) { parent[i] = parent[parent[i]]; i = parent[i]; } return i; };
		for (unsigned i = 0; i < size; ++i)
			for (unsigned j = i + 1; j < size; ++j)
			{
				unsigned a = root(i), b = root(j);
				if (a == b || !knownEqual(results[a], results[b])) continue;
				if (!compatibleHeaders(games[entries[first + i].second], games[entries[first + j].second])) continue;
				if (a > b) std::swap(a, b);
				parent[b] = a;
				if (!results[a]) results[a] = results[b];
			}
		mstl::map<unsigned, DuplicateGroup> groups;
		for (unsigned i = 0; i < size; ++i) groups[root(i)].push_back(entries[first + i].second);
		for (auto const& group : groups) if (group.second.size() > 1) result.push_back(group.second);
	}
	return result;
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


static DuplicateGroups
findExactDuplicates(Database& db)
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

		// merge before cleanup: if a merge throws, still free every worker
		try
		{
			for (unsigned i = 0; i < workers.size(); ++i)
				appendDuplicateEntries(entries, workers[i]->entries);
		}
		catch (...)
		{
			for (unsigned i = 0; i < workers.size(); ++i)
				delete workers[i];
			throw;
		}

		for (unsigned i = 0; i < workers.size(); ++i)
			delete workers[i];

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

	// merge before cleanup: if a merge throws, still free workers and readers
	try
	{
		for (unsigned i = 0; i < workers.size(); ++i)
			appendDuplicateGroups(result, workers[i]->groups);
	}
	catch (...)
	{
		for (unsigned i = 0; i < workers.size(); ++i)
		{
			delete workers[i];
			db.closeAsyncReader(readers[i]);
		}
		throw;
	}

	for (unsigned i = 0; i < workers.size(); ++i)
	{
		delete workers[i];
		db.closeAsyncReader(readers[i]);
	}

	if (!ok2)
		M_RAISE("%s", failMsg2.c_str());

	for (unsigned i = serialFirst; i < ranges.size(); ++i)
		resolveDuplicateRange(result, db, entries, ranges[i].first, ranges[i].second, 0);

	return result;
}


DuplicateGroups
findDuplicates(Database& db, DuplicateMode mode)
{
	// Keep separate return paths in helpers: mstl::vector requires copy elision.
	return mode == Normalized ? findNormalizedDuplicates(db) : findExactDuplicates(db);
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

		// merge before cleanup: if a merge throws, still free every worker
		try
		{
			for (unsigned i = 0; i < workers.size(); ++i)
				mergeEcoStats(stats, workers[i]->stats);
		}
		catch (...)
		{
			for (unsigned i = 0; i < workers.size(); ++i)
				delete workers[i];
			throw;
		}

		for (unsigned i = 0; i < workers.size(); ++i)
			delete workers[i];

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
