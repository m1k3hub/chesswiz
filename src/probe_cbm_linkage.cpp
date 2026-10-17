// ======================================================================
// probe_cbm_linkage — ChessBase .cbm bag-to-game linkage analysis tool
// ======================================================================
// Per docs/CBM_FORMAT_DESIGN.md §5.6 the .cbm binary region is a serialized
// property store (field names like "FWSize"/"Flags0..17" at 80-byte
// intervals with 3-byte .cbg offsets) rather than a flat offset table,
// established on the CB Light fixture. This probe validates that
// grammar corpus-wide (the CBM168 bases + CB Light) and hypothesis-tests
// the linkage values against ground truth:
//
//   ground truth = guiding-text reports (CBH bit-31 records) whose HTML
//   bodies carry CBLink(tag_game,...) anchors and <IMG>/CBLink media
//   references (src/tcl/tcl_media_extract.h). A bag whose text region
//   lists a report's media files is attributable to that report's games.
//
// Per base the probe dumps: bag manifests, u32/u24 value histograms vs
// the CBH game count and the .cbg size, property-store field names with
// their 3-byte .cbg clusters, media-holder candidates (non-report
// records with large .cbg spans), and the ground-truth bag/report
// correlation including any u32 that equals an anchored game index.
//
// Usage: probe_cbm_linkage <rootname> [<rootname> ...]
// (rootname WITHOUT the .cbm suffix; the companion .cbh must exist)
// ======================================================================

#include "db/db_board.h"
#include "db/db_board_base.h"
#include "db/db_eco_table.h"
#include "db/db_home_pawns.h"
#include "db/db_signature.h"
#include "db/sci/sci_encoder.h"
#include "db/cbh/cbh_codec.h"
#include "db/db_database.h"
#include "db/db_database_codec.h"
#include "db/db_game.h"
#include "db/db_game_data.h"
#include "db/db_game_info.h"
#include "db/db_multi_base.h"
#include "db/db_namebase.h"
#include "db/db_namebase_entry.h"

#include "tcl/tcl_media_extract.h"

#include "m_fstream.h"
#include "m_string.h"
#include "m_vector.h"
#include "u_progress.h"

#include <cctype>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <algorithm>
#include <cctype>
#include <tcl.h>
#include "tcl/tcl_base.h"
#include "tcl/tcl_base.h"

// standalone probe: provide the interpreter pointer declaration + definition
// that the application normally supplies via tcl_base.cpp/tcl_base.cpp
namespace tcl { namespace bits { extern Tcl_Interp* interp; } }
namespace tcl { namespace bits { Tcl_Interp* interp = nullptr; } }

using namespace db;

namespace {

// The probe needs the protected GameInfoList; widen the access without
// touching library headers (a using-declaration on a member function
// relaxes its access in the derived class).
struct ProbeCodec : public cbh::Codec
{
	using DatabaseCodec::gameInfoList;
	using DatabaseCodec::namebase;
	// NOTE: Codec::decodeGuidingTextBody is private, so the probe reads
	// guiding-text bodies itself (readGuidingTextBody below) using the
	// format documented in cbh_codec.cpp.
};


inline uint32_t leU32(unsigned char const* p)
{
	return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}


inline uint32_t leU24(unsigned char const* p)
{
	return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16);
}


bool
readFile(mstl::string const& path, mstl::vector<unsigned char>& data)
{
	mstl::ifstream strm(path, mstl::ios_base::in | mstl::ios_base::binary);

	if (!strm)
		return false;

	strm.seekg(0, mstl::ios_base::end);
	int64_t size = strm.tellg();
	strm.seekg(0, mstl::ios_base::beg);

	if (size <= 0 || size > (1ll << 30))
		return false;

	data.resize(size_t(size));

	return bool(strm.read(reinterpret_cast<char*>(data.data()), size_t(size)));
}


struct BagView
{
	unsigned									index;
	uint32_t									value;
	mstl::vector<mstl::string>			files;
	unsigned									declaredCount;
	unsigned									textEnd;
	mstl::vector<uint32_t>				u32s;
	mstl::vector<uint32_t>				u24s;
	mstl::vector<mstl::pair<mstl::string, unsigned> >	properties;

	BagView():index(0), value(0), declaredCount(0), textEnd(0) {}
};


void
parseBag(unsigned char const* rec, unsigned recSize, BagView& bag)
{
	if (recSize < 8 || leU32(rec) != 0xFFFFFFFFu)
		return;

	bag.value = leU32(rec + 4);

	unsigned textEnd = 8;

	while (textEnd < recSize && ((rec[textEnd] >= 0x20 && rec[textEnd] < 0x7f) || rec[textEnd] == '\n'))
		++textEnd;

	bag.textEnd = textEnd;

	unsigned pos = 8;

	if (pos + 10 <= textEnd && ::memcmp(rec + pos, "FilesUsed\n", 10) == 0)
	{
		pos += 10; // "FilesUsed\n"

		char line[256];

		unsigned len = 0;

		while (pos + len < textEnd && rec[pos + len] != '\n' && len + 1 < sizeof(line))
		{
			line[len] = rec[pos + len];
			++len;
		}

		line[len] = '\0';
		pos += len + 1;
		bag.declaredCount = unsigned(::atoi(line));

		while (pos < textEnd)
		{
			len = 0;

			while (pos + len < textEnd && rec[pos + len] != '\n' && len + 1 < sizeof(line))
			{
				line[len] = rec[pos + len];
				++len;
			}

			line[len] = '\0';
			pos += len + 1;

			if (len > 0)
				bag.files.push_back(mstl::string(line));
		}
	}

	unsigned binStart = textEnd;

	while (binStart < recSize && rec[binStart] == 0)
		++binStart;

	for (unsigned p = binStart; p + 4 <= recSize; p += 4)
		bag.u32s.push_back(leU32(rec + p));

	if (binStart < recSize)
	{
		for (unsigned p = binStart; p + 3 <= recSize; ++p)
			bag.u24s.push_back(leU24(rec + p));
	}

	// property-store scan: null-terminated printable tokens of length 3..40
	unsigned p = binStart;

	while (p < recSize)
	{
		unsigned len = 0;

		while (p + len < recSize && rec[p + len] >= 0x21 && rec[p + len] < 0x7f && len < 40)
			++len;

		if (len >= 3 && p + len < recSize && rec[p + len] == 0)
		{
			char name[41];

			::memcpy(name, rec + p, len);
			name[len] = '\0';
			bag.properties.push_back(mstl::make_pair(mstl::string(name), p));
			p += len + 1;
		}
		else
		{
			++p;
		}
	}
}


struct GroundTruth
{
	unsigned									reportIndex;
	mstl::string								event;
	mstl::vector<mstl::string>			media;			// unique media filenames of the report
	mstl::vector<unsigned>				anchoredGames;	// CBH record indices of anchored games
};


// fold a header name into the manifest key (lastname only), mirroring
// buildMediaLinkCache in tcl_database.cpp
void
nameKey(mstl::string const& name, mstl::string& out)
{
	mstl::string::size_type comma = name.find(',');

	out.clear();

	mstl::string const& part = (comma == mstl::string::npos) ? name : mstl::string(name, 0, comma);

	for (unsigned i = 0; i < part.size(); ++i)
	{
		unsigned char c = (unsigned char)part[i];

		if (std::isalnum(c))
			out += char(std::tolower(c));
	}
}


void
eventKey(mstl::string const& event, mstl::string& out)
{
	out.clear();

	for (unsigned i = 0; i < event.size(); ++i)
	{
		unsigned char c = (unsigned char)event[i];

		if (std::isalnum(c))
			out += char(std::tolower(c));
	}
}


// Read a guiding-text body straight from the .cbg. Mirrors the format
// documented in Codec::decodeGuidingTextBody (which is private): 8-byte
// header (u32 size with bit 31 = "not encoded", type, u16 title count),
// LP-strings for the titles, then the body (type 1: one LP-string; other
// types: repeated [u32 length][text] sections with separators). Encoded
// records are skipped (cannot be decoded without the CBH cipher).
void
readGuidingTextBody(	mstl::ifstream& cbg,
							uint32_t gameOffset,
							mstl::string& title,
							mstl::string& body,
							bool& encoded)
{
	cbg.clear();
	cbg.seekg(gameOffset, mstl::ios_base::beg);

	char header[8];

	if (!cbg.read(header, sizeof(header)))
	{
		encoded = false;
		return;
	}

	uint32_t size = leU32((unsigned char const*)header);

	encoded = (size & 0x80000000u) == 0;

	if (encoded)
		return;

	size = (size & 0x3fffffffu) - sizeof(header);

	unsigned type = (unsigned char)header[4];
	unsigned numTitles = leU32((unsigned char const*)header + 6) & 0xFFFFu;

	mstl::vector<char> buf(size);

	if (!cbg.read(buf.data(), size))
	{
		encoded = true; // treat as unreadable
		return;
	}

	unsigned pos = 0;

	// titles
	for (unsigned i = 0; i < numTitles && pos + 4 <= size; ++i)
	{
		pos += 2; // language
		unsigned length = buf[pos] | (unsigned(buf[pos + 1]) << 8);
		pos += 2;

		if (pos + length > size)
			return;

		if (title.empty() || pos > 0)
			title.assign(buf.data() + pos, length);

		pos += length;
	}

	// body
	if (type == 1)
	{
		if (pos + 7 > size)
			return;

		pos += 1; // language
		pos += 4; // id
		unsigned length = buf[pos] | (unsigned(buf[pos + 1]) << 8);
		pos += 2;

		if (pos + length > size)
			return;

		body.assign(buf.data() + pos, length);
	}
	else
	{
		pos += 1; // language
		pos += 4; // title id

		while (pos + 4 <= size)
		{
			uint32_t length = leU32((unsigned char const*)(buf.data() + pos));
			pos += 4;

			if (pos + length > size)
				return;

			mstl::string str(buf.data() + pos, length);
			body.append(str);
			pos += length;

			if (pos < size)
				++pos; // nul byte?
		}
	}
}


} // anonymous namespace


int
main(int argc, char** argv)
{
	// Statics: loadGame() aborts with kingOnBoard() without Board::initialize()
	// (the same call works inside the application because the app initializes
	// statics at startup).  Mirrors probe_cbllight's initStuff().  Also load
	// the opening table: getGameInfo()/loadGame() recurse into
	// EcoTable::getOpening and overflow the stack otherwise.
	tag::initialize();
	castling::initialize();
	board::base::initialize();
	Board::initialize();
	HomePawns::initialize();
	Signature::initialize();
	sci::Encoder::initialize();

	// the encoding codec needs a live Tcl interpreter (Tcl_GetEncoding)
	Tcl_FindExecutable(argv[0]);
	Tcl_Interp* ti = Tcl_CreateInterp();
	tcl::bits::interp = ti;

	// Load the opening table AFTER the interpreter exists (EcoTable's
	// Loader constructs a sys::utf8::Codec, which calls Tcl_GetEncoding):
	// getGameInfo()/loadGame() recurse into EcoTable::getOpening and
	// overflow the stack otherwise.
	{
		char const* candidates[] = {
			::getenv("SCIDB_ECO_FILE") ? ::getenv("SCIDB_ECO_FILE") : "",
			"data/eco.bin",
			"/media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/src/data/eco.bin",
		};
		for (unsigned ci = 0; ci < sizeof(candidates)/sizeof(candidates[0]); ++ci)
		{
			if (*candidates[ci] == '\0') continue;
			mstl::ifstream strm(candidates[ci], mstl::ios_base::in | mstl::ios_base::binary);
			if (strm)
			{
				EcoTable::specimen(variant::Normal).load(strm, variant::Normal);
				break;
			}
		}
	}

	if (argc < 2)
	{
		::fprintf(stderr, "usage: %s <rootname> [<rootname> ...]\n", argv[0]);
		return 1;
	}

	util::Progress& progress = util::Progress::null();

	for (int a = 1; a < argc; ++a)
	{
		mstl::string rootname(argv[a]);

		::printf("===============================================================\n");
		::printf("BASE: %s\n", rootname.c_str());

		mstl::vector<unsigned char> cbm;

		if (!readFile(rootname + ".cbm", cbm))
		{
			::printf("  no/unreadable .cbm\n");
			continue;
		}

		// open through MultiBase (the codec requires an attached Database)
		MultiBase* multi = 0;

		try
		{
			multi = new MultiBase(rootname + ".cbh", "automatic", permission::ReadOnly, progress);
		}
		catch (...)
		{
			::printf("  cannot open .cbh\n");
			continue;
		}

		Database& database = *multi->database();
		unsigned countGames = database.countGames();

		int64_t cbgSize = 0;
		{
			mstl::ifstream s(rootname + ".cbg", mstl::ios_base::in | mstl::ios_base::binary);

			if (s)
			{
				s.seekg(0, mstl::ios_base::end);
				cbgSize = s.tellg();
			}
		}

		::printf("games=%u cbgSize=%lld\n", countGames, (long long)cbgSize);

		// media-holder candidates: non-report records whose .cbg span is
		// much larger than a normal game (> 64 KiB)
		mstl::vector<mstl::pair<uint32_t, uint32_t> > spans; // (start, length) by record

		for (unsigned i = 0; i < countGames; ++i)
			spans.push_back(mstl::make_pair(database.gameInfo(i).gameOffset(), 0u));

		for (unsigned x = 0; x + 1 < spans.size(); ++x)
		for (unsigned y = x + 1; y < spans.size(); ++y)
			if (spans[y].first < spans[x].first)
			{
				mstl::pair<uint32_t, uint32_t> tmp = spans[x];
				spans[x] = spans[y];
				spans[y] = tmp;
			}

		for (unsigned i = 0; i + 1 < countGames; ++i)
			spans[i].second = spans[i + 1].first - spans[i].first;

		if (countGames > 0)
			spans[countGames - 1].second = uint32_t(cbgSize > 0 ? cbgSize - spans[countGames - 1].first : 0);

		mstl::vector<unsigned> holders;

		for (unsigned i = 0; i < countGames; ++i)
		{
			if (!database.gameInfo(i).isGuidingText() && spans[i].second > 65536)
				holders.push_back(i);
		}

		// sanity: does a normal game load?
		for (unsigned i = 0; i < countGames; ++i)
		{
			if (database.gameInfo(i).isGuidingText())
				continue;

			Game g0;
			int rc0 = -1;
			mstl::string e0;

			try
			{
				rc0 = int(database.loadGame(i, g0));
			}
			catch (...)
			{
				e0 = "threw";
			}

			::printf("  [normal-game load %u: rc=%d err='%s' body=%u]\n",
						i, rc0, e0.c_str(), unsigned(g0.data().m_guidingText.size()));
			break;
		}

		::printf("holder candidates (span > 64K):");
		for (unsigned i = 0; i < holders.size() && i < 12; ++i)
			::printf(" [%u](%uB)", holders[i], spans[holders[i]].second);
		::printf("\n");

		// --- ground truth from the guiding texts ---------------------------
		mstl::ifstream cbgStream(rootname + ".cbg", mstl::ios_base::in | mstl::ios_base::binary);
		mstl::vector<GroundTruth> truth;

		for (unsigned i = 0; i < countGames; ++i)
		{
			GameInfo const& info = database.gameInfo(i);

			if (!info.isGuidingText())
				continue;

			GroundTruth gt;

			gt.reportIndex = i;
			gt.event = info.event();

			// the body is encoded (bit 31 clear); the full decode lives in the
			// game loader (Database::loadGame)
			Game game;

			int loaded = -1;
			mstl::string err;

			try
			{
				loaded = int(database.loadGame(i, game));
			}
			catch (std::exception const& e)
			{
				err = e.what();
			}
			catch (...)
			{
				err = "unknown";
			}

			::printf("  [load %u: rc=%d err='%s']\n", i, loaded, err.c_str());

			if (loaded != int(load::Ok))
				continue;

			mstl::string const& body = game.data().m_guidingText;

			if (body.empty())
			{
				truth.push_back(gt);
				continue;
			}

			mstl::vector<mstl::string> files;
			mstl::vector<int> types;
			tcl_media::extractGuidingTextMedia(body, files, types);

			for (unsigned r = 0; r < files.size(); ++r)
			{
				bool known = false;

				for (unsigned q = 0; q < gt.media.size() && !known; ++q)
					known = (gt.media[q] == files[r]);

				if (!known)
					gt.media.push_back(files[r]);
			}

			mstl::vector<tcl_media::GuidingTextGameBlock> blocks;
			tcl_media::extractGuidingTextGameBlocks(body, blocks);

			// resolve anchored games by header matching (buildMediaLinkCache
			// rules: lastname keys + year/round + event substring)
			mstl::string wkey, bkey, ekey;

			for (unsigned b = 0; b < blocks.size(); ++b)
			{
				tcl_media::GuidingTextGameBlock const& block = blocks[b];

				nameKey(block.white, wkey);
				nameKey(block.black, bkey);
				eventKey(block.event, ekey);

				if (wkey.empty() || bkey.empty())
					continue;

				for (unsigned g = 0; g < countGames; ++g)
				{
					GameInfo const& gi = database.gameInfo(g);

					if (gi.isGuidingText())
						continue;

					Namebase const& players = database.namebase(Namebase::Player);

					NamebasePlayer const* wp = gi.playerEntry(color::White);
					NamebasePlayer const* bp = gi.playerEntry(color::Black);

					if (!wp || !bp)
						continue;

					mstl::string gw, gb, ge;

					nameKey(wp->name(), gw);

					if (gw != wkey)
						continue;

					nameKey(bp->name(), gb);

					if (gb != bkey)
						continue;

					if (block.year != 0 && unsigned(gi.date().year()) != block.year)
						continue;

					if (block.round != 0 && gi.round() != block.round)
						continue;

					if (!ekey.empty())
					{
						mstl::string gev;
						eventKey(gi.event(), gev);

						if (gev.find(ekey) == mstl::string::npos)
							continue;
					}

					gt.anchoredGames.push_back(g);
					break; // first match per anchor (record order)
				}
			}

			truth.push_back(gt);
		}

		::printf("ground truth: %u guiding texts\n", unsigned(truth.size()));

		for (unsigned t = 0; t < truth.size() && t < 14; ++t)
		{
			::printf("  report[%u] event='%s' media=%u anchored=%u\n",
						truth[t].reportIndex, truth[t].event.c_str(),
						unsigned(truth[t].media.size()), unsigned(truth[t].anchoredGames.size()));

			if (!truth[t].anchoredGames.empty())
			{
				::printf("    anchored games:");
				for (unsigned k = 0; k < truth[t].anchoredGames.size() && k < 10; ++k)
					::printf(" %u", truth[t].anchoredGames[k]);
				::printf("\n");
			}
		}

		// --- bags -----------------------------------------------------------
		uint32_t version		= leU32(cbm.data() + 0);
		uint32_t recordSize	= leU32(cbm.data() + 4);
		uint32_t numRecords	= leU32(cbm.data() + 8);

		::printf("cbm: version=%u recordSize=%u numRecords=%u\n", version, recordSize, numRecords);

		if (recordSize == 0 || numRecords == 0 || numRecords == 0xFFFFFFFFu)
			continue;

		unsigned headerSize = (uint64_t(32) + uint64_t(numRecords) * recordSize == cbm.size()) ? 32 : 28;

		mstl::vector<BagView> bags(numRecords);

		for (unsigned i = 0; i < numRecords; ++i)
		{
			uint64_t off = headerSize + uint64_t(i) * recordSize;

			if (off + recordSize > cbm.size())
				break;

			parseBag(cbm.data() + off, recordSize, bags[i]);
			bags[i].index = i;
		}

		// --- per-bag dump + hypothesis stats --------------------------------
		unsigned totalU32s = 0;
		unsigned u32BelowGames = 0;
		unsigned u32BelowCbg = 0;
		unsigned totalU24s = 0;
		unsigned u24BelowCbg = 0;
		unsigned propertyEntries = 0;
		mstl::map<mstl::string, unsigned> propertyNames;
		unsigned bagGameIndexHits = 0;

		for (unsigned i = 0; i < bags.size(); ++i)
		{
			BagView const& bag = bags[i];

			::printf("\n-- bag %u (value=%u files=%u declared=%u)\n",
						i, bag.value, unsigned(bag.files.size()), bag.declaredCount);

			for (unsigned f = 0; f < bag.files.size() && f < 8; ++f)
				::printf("   file[%u] %s\n", f, bag.files[f].c_str());

			if (bag.files.size() > 8)
				::printf("   ... %u more\n", unsigned(bag.files.size()) - 8);

			totalU32s += bag.u32s.size();
			totalU24s += bag.u24s.size();

			unsigned bg = 0;
			unsigned bc = 0;

			for (unsigned k = 0; k < bag.u32s.size(); ++k)
			{
				if (bag.u32s[k] < countGames)
					++bg;
				if (bag.u32s[k] < cbgSize)
					++bc;
			}

			for (unsigned k = 0; k < bag.u24s.size(); ++k)
			{
				if (bag.u24s[k] > 0 && bag.u24s[k] < cbgSize)
					++bc;
			}

			u32BelowGames += bg;
			u32BelowCbg += bc;
			u24BelowCbg += bc;

			::printf("   u32s=%u (<games:%u <cbg:%u)  u24s=%u (<cbg:%u)\n",
						unsigned(bag.u32s.size()), bg, bc, unsigned(bag.u24s.size()), bc);

			for (unsigned k = 0; k < bag.properties.size(); ++k)
			{
				++propertyEntries;
				++propertyNames[bag.properties[k].first];
			}

			if (!bag.properties.empty())
			{
				::printf("   properties(%u):", unsigned(bag.properties.size()));

				for (unsigned k = 0; k < bag.properties.size() && k < 10; ++k)
					::printf(" %s@%u", bag.properties[k].first.c_str(), bag.properties[k].second);

				::printf("\n");
			}

			// ground truth correlation: which report shares this bag's files?
			int bestReport = -1;
			unsigned bestOverlap = 0;

			for (unsigned t = 0; t < truth.size(); ++t)
			{
				unsigned overlap = 0;

				for (unsigned f = 0; f < bag.files.size(); ++f)
				{
					bool known = false;

					for (unsigned q = 0; q < truth[t].media.size() && !known; ++q)
						known = (truth[t].media[q] == bag.files[f]);

					if (known)
						++overlap;
				}

				if (overlap > bestOverlap)
				{
					bestOverlap = overlap;
					bestReport = int(t);
				}
			}

			if (bestReport >= 0 && bestOverlap > 0)
			{
				GroundTruth const& gt = truth[bestReport];

				::printf("   GT: report[%u] overlap=%u/%u anchored=%u\n",
							gt.reportIndex, bestOverlap, unsigned(gt.anchoredGames.size()));

				// does any u32/u24 equal an anchored game index?
				for (unsigned k = 0; k < bag.u32s.size(); ++k)
				{
					for (unsigned g = 0; g < gt.anchoredGames.size(); ++g)
					{
						if (bag.u32s[k] == gt.anchoredGames[g])
							::printf("   HIT: u32[%u]=%u == anchored game %u\n",
										k, bag.u32s[k], gt.anchoredGames[g]);
					}
				}
			}
		}

		::printf("\nSUMMARY %s: u32=%u belowGames=%u belowCbg=%u | u24=%u belowCbg=%u | properties=%u distinct=%u\n",
					rootname.c_str(), totalU32s, u32BelowGames, u32BelowCbg,
					totalU24s, u24BelowCbg, propertyEntries, unsigned(propertyNames.size()));

		if (!propertyNames.empty())
		{
			::printf("property names:");
			for (mstl::map<mstl::string, unsigned>::iterator it = propertyNames.begin(); it != propertyNames.end(); ++it)
				::printf(" %s(x%u)", it->first.c_str(), it->second);
			::printf("\n");
		}
	}

	return 0;
}

// vi:set ts=3 sw=3: