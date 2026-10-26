// ======================================================================
// cb2_writer.cpp -- create and append to 2CBH (ChessBase 17+) databases.
//
// Every layout constant here mirrors the reader (cb2_codec.cpp /
// cb2_index.h).  See docs/formats/2CBH_FORMAT_DESIGN.md section 17 for the
// field map and the Ghidra evidence.
//
// Copyright (C) 2026 the scidb contributors.
// ======================================================================

#include "cb2_writer.h"

#include "cb2_index.h"
#include "cb2_codec.h"
#include "cb2_flags.h"
#include "cb2_namebase.h"
#include "2cbh_move16.h"

#include "db_board.h"
#include "db_eco.h"
#include "db_tag_set.h"
#include "db_move.h"

#include "m_fstream.h"
#include "m_ifstream.h"

#include <string.h>
#include <stdio.h>

namespace db {

namespace cb2 {

namespace {

uint32_t const RecordSize = 192;
uint64_t const RecordMagic = 0x1122334455667788ull;
unsigned const RecordHeaderSize = 26;

unsigned const NamebaseBase = namebaseFirstSlot;
unsigned const NamebaseStride = namebaseStride;
unsigned const NamebaseEventOffset = namebaseEventOffset;
unsigned const NamebaseSourceOffset = namebaseSourceOffset;
// The six record capacities of a slot; they sum to NamebaseStride.
unsigned const SectionSize[6] = { 1024, 1120, 220, 1024, 314, 532 };

inline uint16_t
readLE16(unsigned char const* p) { return uint16_t(p[0] | (p[1] << 8)); }

inline uint32_t
readLE32(unsigned char const* p)
{
	return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16)
		 | (uint32_t(p[3]) << 24);
}

inline uint64_t
readLE64(unsigned char const* p)
{
	uint64_t v = 0;
	for (int i = 7; i >= 0; --i)
		v = (v << 8) | p[i];
	return v;
}

inline void
storeLE16(unsigned char* p, uint16_t v)
{
	p[0] = v & 0xff;
	p[1] = (v >> 8) & 0xff;
}

inline void
storeLE32(unsigned char* p, uint32_t v)
{
	for (unsigned i = 0; i < 4; ++i)
		p[i] = (v >> (8*i)) & 0xff;
}

inline void
storeLE64(unsigned char* p, uint64_t v)
{
	for (unsigned i = 0; i < 8; ++i)
		p[i] = (v >> (8*i)) & 0xff;
}

inline void
appendLE16(mstl::string& s, uint16_t v)
{
	s += char(v & 0xff);
	s += char((v >> 8) & 0xff);
}

inline void
appendLE32(mstl::string& s, uint32_t v)
{
	for (unsigned i = 0; i < 4; ++i)
		s += char((v >> (8*i)) & 0xff);
}

inline void
appendLE64(mstl::string& s, uint64_t v)
{
	for (unsigned i = 0; i < 8; ++i)
		s += char((v >> (8*i)) & 0xff);
}

/// The packed date used by index @0xbc and by the .2lid event slot:
/// day(5) | month(4) << 5 | year(12) << 9.
uint32_t
packDate(Date const& date)
{
	unsigned const day = date.day();
	unsigned const month = date.month();
	unsigned const year = date.year();

	if (day > 31 || month > 15 || year > 4095)
		return 0;

	return day | (month << 5) | (year << 9);
}

void
splitName(mstl::string const& name, mstl::string& last, mstl::string& first)
{
	mstl::string::size_type const comma = name.find(',');

	if (comma == mstl::string::npos)
	{
		last = name;
		first.clear();
		return;
	}

	last.assign(name, 0, comma);
	first.assign(name, comma + 1, name.size() - comma - 1);

	while (!first.empty() && (first[0] == ' ' || first[0] == '\t'))
		first.erase(mstl::string::size_type(0), mstl::string::size_type(1));
}

unsigned
parseUnsigned(mstl::string const& text)
{
	unsigned value = 0;

	for (unsigned i = 0; i < text.size(); ++i)
	{
		if (text[i] < '0' || text[i] > '9')
			break;
		value = 10 * value + unsigned(text[i] - '0');
	}

	return value;
}

/// "3", "7.5" or "4.16.4" -> (round, subround, board).
void
parseRound(mstl::string const& text, unsigned& round, unsigned& subround, unsigned& third)
{
	unsigned values[3] = { 0, 0, 0 };
	unsigned n = 0;
	mstl::string::size_type i = 0;

	while (i < text.size() && n < 3)
	{
		unsigned value = 0;
		bool any = false;

		while (i < text.size() && text[i] >= '0' && text[i] <= '9')
		{
			value = 10 * value + unsigned(text[i] - '0');
			any = true;
			++i;
		}

		if (any)
			values[n++] = value;
		if (i < text.size())
			++i;
	}

	round = values[0];
	subround = values[1];
	third = values[2];
}

unsigned
resultCode(mstl::string const& result)
{
	if (::strncmp(result.c_str(), "0-1", 3) == 0)			return 0;
	if (::strncmp(result.c_str(), "1/2", 3) == 0)		return 1;
	if (::strncmp(result.c_str(), "1-0", 3) == 0)		return 2;
	return 3;
}

/// Names and ids collected from a database (existing games when appending).
struct NameList
{
	mstl::vector<mstl::string>	names;

	unsigned find(mstl::string const& name) const
	{
		for (unsigned i = 0; i < names.size(); ++i)
			if (names[i] == name)
				return i;
		return unsigned(-1);
	}

	unsigned insert(mstl::string const& name)
	{
		unsigned const id = find(name);
		if (id != unsigned(-1))
			return id;
		names.push_back(name);
		return names.size() - 1;
	}
};

/// A namebase whose entries are a two-string pair (the source section's
/// [SourceTitle]/[Source]).  The entry's ordinal is its namebase id, which is
/// also the .2lid slot the record is stored in.
struct NamePairList
{
	mstl::vector<mstl::string>	first;
	mstl::vector<mstl::string>	second;

	unsigned find(mstl::string const& a, mstl::string const& b) const
	{
		for (unsigned i = 0; i < first.size(); ++i)
			if (first[i] == a && second[i] == b)
				return i;
		return unsigned(-1);
	}

	unsigned insert(mstl::string const& a, mstl::string const& b)
	{
		unsigned const id = find(a, b);
		if (id != unsigned(-1))
			return id;
		first.push_back(a);
		second.push_back(b);
		return first.size() - 1;
	}
};

bool
readFile(mstl::string const& name, mstl::string& data)
{
	mstl::ifstream in(name, mstl::ios_base::in | mstl::ios_base::binary);

	if (!in)
		return false;

	in.seekg(0, mstl::ios_base::end);
	long const size = in.tellg();
	in.seekg(0, mstl::ios_base::beg);

	if (size < 0)
		return false;

	data.resize(size_t(size));

	if (size > 0 && !in.read(data.begin(), size))
		return false;

	return true;
}

bool
writeFile(mstl::string const& name, mstl::string const& data)
{
	mstl::ofstream out(name, mstl::ios_base::out | mstl::ios_base::binary
							 | mstl::ios_base::trunc);

	if (!out)
		return false;

	if (!data.empty() && !out.write(data.data(), data.size()))
		return false;

	return bool(out);
}

/// One game ready to be written.
struct Encoded
{
	mstl::string	payload;			///< .2cbg record payload (type in `type`)
	uint16_t			type;
	mstl::string	white, black, event, site, annotator, source, sourceTitle;
	unsigned			annotatorId;		///< player id of the annotator, ~0 = none
	unsigned			sourceId;			///< source section id, ~0 = none
	mstl::string	round, result, eco;
	unsigned			whiteElo, blackElo;
	uint32_t			date;
	unsigned			medals;
	unsigned			plies;
};

bool
encodePayload(WriteGame const& game, Encoded& out)
{
	out.type = 1;

	if (game.setup == -2)
	{
		if (game.moves.empty())
			return false;

		for (unsigned i = 0; i < game.moves.size(); ++i)
			appendLE16(out.payload, game.moves[i]);

		out.type = game.recordType ? game.recordType : 1;
		return true;
	}

	if (game.setup >= 0 && game.setup <= 959)
	{
		if (game.moves.empty())
			return false;

		appendLE16(out.payload, Move16_None);
		appendLE16(out.payload, uint16_t(game.setup));
		appendLE16(out.payload, Move16_GameStart);

		for (unsigned i = 1; i < game.moves.size(); ++i)
			appendLE16(out.payload, game.moves[i]);

		out.type = 2;
		return true;
	}

	if (game.setup == 1000)
	{
		Board board;
		bool const parsed = game.fen.empty()
									? false
									: board.setup(game.fen.c_str(), variant::Normal) != 0;

		if (!parsed)
			return false;
		if (game.moves.empty())
			return false;

		appendLE16(out.payload, Move16_None);
		appendLE16(out.payload, 1000);
		appendLE16(out.payload, Move16_GameStart);
		// two-word setup header: side-to-move flags (0 = White) and castling
		// rights (0 = none), exactly the layout the reader skips.
		appendLE16(out.payload, 0);

		for (unsigned sq16 = 0; sq16 < 64; ++sq16)
		{
			unsigned const sq = toScidbSquare(sq16);
			unsigned const pce = toMove16Piece(board.pieceAt(sq));

			if (pce == 0)
				continue;

			uint16_t code;

			if (!findPlacementCode(pce, sq16, code))
				return false;

			appendLE16(out.payload, code);
		}

		appendLE16(out.payload, Move16_GameStart);

		for (unsigned i = 1; i < game.moves.size(); ++i)
			appendLE16(out.payload, game.moves[i]);

		out.type = 2;
		return true;
	}

	// standard start position: the stream is copied verbatim
	if (game.moves.empty())
		return false;

	for (unsigned i = 0; i < game.moves.size(); ++i)
		appendLE16(out.payload, game.moves[i]);

	out.type = game.recordType ? game.recordType : 1;
	return true;
}

void
buildIndexRecord(	unsigned char* rec,
							uint64_t gameOffset,
							uint64_t annotationOffset,
							Encoded const& game,
							uint32_t whiteId,
							uint32_t blackId,
							uint32_t eventId,
							uint32_t annotatorId,
							uint32_t sourceId)
{
	::memset(rec, 0, RecordSize);

	storeLE16(rec + 0x00, 1);
	storeLE16(rec + 0x02, 0x0101);
	storeLE64(rec + 0x08, gameOffset);
	storeLE64(rec + 0x10, annotationOffset);	// .2cba record offset
	storeLE64(rec + 0x18, whiteId);
	storeLE64(rec + 0x20, blackId);
	storeLE64(rec + 0x28, eventId);
	// Annotator and source references; ~0 means "no reference".
	//   +0x30  annotator: a *player* id (ChessBase models the annotator as a
	//          person, see cb2::Codec::getAnnotator; the +0x93c namebase
	//          section is a different, unidentified one)
	//   +0x38  source: id of a record of the .2lid source section (+0x860)
	//   +0x40/+0x48  white/black team, +0x50 game title (unused here)
	// CBase26's reference repair walks exactly these fields with these
	// namebases, and the classic CBH record keeps the same order.
	storeLE64(rec + 0x30, annotatorId == unsigned(-1) ? ~uint64_t(0) : uint64_t(annotatorId));
	storeLE64(rec + 0x38, sourceId == unsigned(-1) ? ~uint64_t(0) : uint64_t(sourceId));
	storeLE64(rec + 0x40, ~uint64_t(0));			// WhiteTeam
	storeLE64(rec + 0x48, ~uint64_t(0));			// BlackTeam
	storeLE64(rec + 0x50, ~uint64_t(0));			// game title

	rec[0x58] = uint8_t(resultCode(game.result) & 3);

	unsigned round = 0, subround = 0, third = 0;

	parseRound(game.round, round, subround, third);
	storeLE16(rec + 0x5a, uint16_t(round));
	storeLE16(rec + 0x5c, uint16_t(subround));
	storeLE16(rec + 0x5e, uint16_t(third));

	storeLE16(rec + 0x60, uint16_t(game.whiteElo));
	storeLE16(rec + 0x70, uint16_t(game.blackElo));

	unsigned const eco = game.eco.empty() ? 0 : Eco::toShort(game.eco.c_str());

	if (eco > 0 && eco <= 500)
		storeLE16(rec + 0x80, uint16_t(128u * eco));

	storeLE16(rec + 0x82, uint16_t(game.medals));
	storeLE16(rec + 0x8a, uint16_t(game.plies / 2));

	rec[0xbc] = game.date & 0xff;
	rec[0xbd] = (game.date >> 8) & 0xff;
	rec[0xbe] = (game.date >> 16) & 0xff;
}

/// The 184-byte .2lid structural header.
void
buildNamebaseHeader(	unsigned char* header,
								unsigned players,
								unsigned events,
								unsigned sources,
								unsigned annotators,
								unsigned other)
{
	::memset(header, 0, NamebaseBase);

	unsigned const count[6] = { players, events, sources, annotators, 0, other };
	unsigned char* p = header;

	p[0] = 0; p[1] = 0; p[2] = 0; p[3] = uint8_t(NamebaseBase);
	p[4] = 0; p[5] = 0; p[6] = 0; p[7] = 6;
	p += 8;

	for (unsigned s = 0; s < 6; ++s)
	{
		unsigned const capacity = SectionSize[s];

		p[0] = capacity >> 24; p[1] = capacity >> 16;
		p[2] = capacity >> 8;  p[3] = capacity;
		p[4] = 0; p[5] = 0; p[6] = 0; p[7] = 0;
		p[8] = count[s] >> 24; p[9] = count[s] >> 16;
		p[10] = count[s] >> 8; p[11] = count[s];
		p[12] = 0xff; p[13] = 0xff; p[14] = 0xff; p[15] = 0xff;
		p[16] = 0xff; p[17] = 0xff; p[18] = 0xff; p[19] = 0xff;
		p += 20;
	}

	p[0] = 0xff; p[1] = 0xff; p[2] = 0xff; p[3] = 0xff;
	p += 4;

	for (unsigned s = 0; s < 6; ++s)
	{
		p[0] = 0; p[1] = 0; p[2] = 0; p[3] = 1;
		p[4] = 0; p[5] = 0; p[6] = 0; p[7] = s;
		p += 8;
	}

	p[0] = 0; p[1] = 0; p[2] = 0; p[3] = 1;
}

/// Write a two-string name record ([SourceTitle]/[Source], or the annotator
/// name) into @a q.  @a q points into a zero-filled slot, so the record's
/// trailing eight bytes are already zero.
void
storeNameRecord(unsigned char* q, mstl::string const& first, mstl::string const& second)
{
	if (first.empty() && second.empty())
		return;

	storeLE32(q + 0, uint32_t(20 + first.size() + second.size()));
	storeLE32(q + 4, uint32_t(first.size()));
	::memcpy(q + 8, first.data(), first.size());

	unsigned char* r = q + 8 + first.size();
	storeLE32(r, uint32_t(second.size()));
	::memcpy(r + 4, second.data(), second.size());
}

void
buildSlot(	unsigned char* slot,
				mstl::string const& player,
				mstl::string const& site,
				mstl::string const& event,
				uint32_t eventDate,
				mstl::string const& sourceTitle,
				mstl::string const& source)
{
	::memset(slot, 0, NamebaseStride);

	if (!player.empty())
	{
		mstl::string last, first;
		splitName(player, last, first);

		unsigned const total = 4 + 4 + last.size() + 4 + first.size() + 20;

		storeLE32(slot + 0, total);
		storeLE32(slot + 4, uint32_t(last.size()));
		::memcpy(slot + 8, last.data(), last.size());

		unsigned char* r = slot + 8 + last.size();
		storeLE32(r, uint32_t(first.size()));
		::memcpy(r + 4, first.data(), first.size());

		unsigned char* tail = r + 4 + first.size();
		// 8 zero bytes, then the 12-byte player-record signature
		tail[8] = 0xff; tail[9] = 0xff; tail[10] = 0xff; tail[11] = 0xff;
		tail[12] = 0x08; tail[13] = 0x00; tail[14] = 0x00; tail[15] = 0x00;
		tail[16] = 0xff; tail[17] = 0xff; tail[18] = 0xff; tail[19] = 0xff;
	}

	if (!event.empty())
	{
		unsigned char* q = slot + NamebaseEventOffset;

		// The leading word is the record's total length: 4 (this word) + 2
		// (site length) + 2 (padding) + site + 2 + 2 (event length + padding)
		// + event + 4 (packed EventDate) + a 100-byte trailing area, exactly
		// as CBase26 writes it (validated on the genuine fixtures).
		storeLE32(q + 0, uint32_t(116 + site.size() + event.size()));
		storeLE16(q + 4, uint16_t(site.size()));
		::memcpy(q + 8, site.data(), site.size());

		unsigned char* r = q + 8 + site.size();
		storeLE16(r, uint16_t(event.size()));
		::memcpy(r + 4, event.data(), event.size());

		storeLE32(r + 4 + event.size(), eventDate);
	}

	// Source section (+0x860), in the record grammar CBase26 writes for it
	// (validated on the genuine fixtures, see cb2_namebase.h):
	//   [u32 total = 20 + len1 + len2][u32 len1][str1][u32 len2][str2][8 bytes]
	// The annotator is not stored here: it is a player record, see
	// buildIndexRecord().
	storeNameRecord(slot + NamebaseSourceOffset, sourceTitle, source);

	// sixth section: CBase26 stores a single usage byte in slot 0
	slot[2902] = 4;
}

/// Read the player names of an existing .2lid (same signature walk as the
/// reader) and the event triples.
bool
scanNamebase(	mstl::string const& data,
					NameList& players,
					NameList& events,
					mstl::vector<mstl::string>& eventSite,
					mstl::vector<uint32_t>& eventDate)
{
	unsigned char const* lid = reinterpret_cast<unsigned char const*>(data.data());
	size_t const size = data.size();

	if (size < NamebaseBase)
		return false;

	static unsigned char const sig[12] =
	{
		0xff, 0xff, 0xff, 0xff, 0x08, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff
	};

	size_t pos = NamebaseBase;

	while (pos + 12 <= size)
	{
		size_t i = pos;
		while (i + 12 <= size && ::memcmp(lid + i, sig, 12) != 0)
			++i;
		if (i + 12 > size)
			break;

		size_t const end = i + 12;
		size_t const lo = (i + 8 > 320) ? i + 8 - 320 : 0;

		for (size_t start = i + 4; start-- > lo; )
		{
			uint32_t const total = readLE32(lid + start);

			if (start + total != end || total <= 20 || total >= 320)
				continue;

			uint32_t const llen = readLE32(lid + start + 4);

			if (llen == 0 || llen >= 80 || start + 8 + llen + 4 > size)
				continue;

			size_t const fo = start + 8 + llen;
			uint32_t const flen = readLE32(lid + fo);

			if (flen >= 80 || fo + 4 + flen != end - 20)
				continue;

			mstl::string last(reinterpret_cast<char const*>(lid + start + 8), llen);
			mstl::string first(reinterpret_cast<char const*>(lid + fo + 4), flen);

			players.insert(first.empty() ? last : last + ", " + first);
			break;
		}

		pos = end;
	}

	size_t const slots = (size - NamebaseBase) / NamebaseStride;

	for (unsigned slot = 0; slot < slots; ++slot)
	{
		size_t const a = NamebaseBase + size_t(slot) * NamebaseStride
							 + NamebaseEventOffset;

		if (a + 8 > size)
			break;

		uint32_t const siteLen = readLE16(lid + a + 4);

		if (siteLen > 80 || a + 8 + siteLen + 4 > size)
			continue;

		size_t const b = a + 8 + siteLen;
		uint32_t const eventLen = readLE16(lid + b);

		if (eventLen == 0 || eventLen > 90 || b + 8 + eventLen > size)
			continue;

		mstl::string const site(reinterpret_cast<char const*>(lid + a + 8), siteLen);
		mstl::string const event(reinterpret_cast<char const*>(lid + b + 4), eventLen);

		if (events.insert(event) == events.names.size() - 1)
		{
			eventSite.push_back(site);
			eventDate.push_back(readLE32(lid + b + 4 + eventLen));
		}
	}

	return true;
}

/// Read a two-string name section (the source section at +0x860) of an
/// existing .2lid; entry i is the record of slot i.
void
scanSlotNames(	mstl::string const& lid,
					size_t sectionOffset,
					mstl::vector<mstl::string>& titles,
					mstl::vector<mstl::string>& names)
{
	unsigned char const* data = reinterpret_cast<unsigned char const*>(lid.data());
	unsigned const slots = namebaseSlotCount(lid.size());

	titles.clear();
	names.clear();

	for (unsigned slot = 0; slot < slots; ++slot)
	{
		SlotName rec;

		if (readSlotName(data, lid.size(), sectionOffset, slot, rec))
		{
			titles.push_back(mstl::string(rec.title, rec.titleLength));
			names.push_back(mstl::string(rec.name, rec.nameLength));
		}
		else
		{
			titles.push_back(mstl::string());
			names.push_back(mstl::string());
		}
	}
}

/// Read the game record payloads of an existing .2cbg, in index order.
bool
scanGameData(	mstl::string const& index,
					mstl::string const& data,
					mstl::vector<mstl::string>& payloads,
					mstl::vector<uint16_t>& types)
{
	IndexLayout layout;

	if (!readIndexLayout(reinterpret_cast<unsigned char const*>(index.data()),
								index.size(), index.size(), layout))
		return false;

	unsigned char const* g = reinterpret_cast<unsigned char const*>(data.data());

	for (unsigned i = 0; i < layout.gameCount; ++i)
	{
		uint64_t const offset =
			readLE64(reinterpret_cast<unsigned char const*>(index.data())
					 + size_t(i + 1) * layout.recordSize + 0x08);

		if (offset + RecordHeaderSize + 8 > data.size()
			 || readLE64(g + offset) != RecordMagic)
			return false;

		uint32_t const dsz = readLE32(g + offset + 8);
		uint32_t const esz = readLE32(g + offset + 0x0c);

		if (offset + RecordHeaderSize + dsz + esz + 8 > data.size())
			return false;

		payloads.push_back(mstl::string(
			reinterpret_cast<char const*>(g + offset + RecordHeaderSize), dsz));
		types.push_back(readLE16(g + offset + 0x18));
	}

	return true;
}

bool
writeDatabaseInt(	mstl::string const& rootname,
							mstl::vector<WriteGame> const& games,
							mstl::string* error)
{
	mstl::vector<Encoded> encoded(games.size());
	NameList players, events;
	NamePairList sources;
	mstl::vector<mstl::string> eventSite;
	mstl::vector<uint32_t> eventDate;

	for (unsigned i = 0; i < games.size(); ++i)
	{
		Encoded& e = encoded[i];
		WriteGame const& g = games[i];

		e.white = g.white;
		e.black = g.black;
		e.event = g.event;
		e.site = g.site;
		e.round = g.round;
		e.result = g.result;
		e.eco = g.eco;
		e.whiteElo = g.whiteElo;
		e.blackElo = g.blackElo;
		e.date = packDate(g.date);
		e.sourceTitle = g.sourceTitle;
		e.source = g.source;
		e.annotator = g.annotator;
		e.medals = g.medals;
		e.plies = 0;

		if (!encodePayload(g, e))
		{
			if (error) *error = "cannot encode game";
			return false;
		}

		// Move count: skip the start-position prefix with the reader's own
		// parser (it understands the compact and explicit setup forms), then
		// count the mainline codes up to the first terminator.
		{
			unsigned char const* p =
				reinterpret_cast<unsigned char const*>(e.payload.data());
			uint32_t size = uint32_t(e.payload.size());
			db::Board start;
			db::TagSet tags;

			e.plies = 0;

			if (prepareGame(e.type, p, size, start, tags))
			{
				for (uint32_t k = 0; k < size / 2; ++k)
				{
					uint16_t const code = readLE16(p + 2*k);

					if (code == Move16_Terminator)
						break;
					if (code == Move16_None || code == Move16_Marker
						 || code == Move16_GameStart)
						continue;
					if (code < Move16_None)
						++e.plies;
				}
			}
		}

		players.insert(e.white);
		players.insert(e.black);
		unsigned const eventId = events.insert(e.event);

		while (eventSite.size() <= eventId)
		{
			eventSite.push_back(mstl::string());
			eventDate.push_back(0);
		}

		if (eventSite[eventId].empty())
		{
			eventSite[eventId] = e.site;
			eventDate[eventId] = e.date;
		}

		// The source is a namebase of its own (.2lid +0x860); the annotator
		// is a *player* record (ChessBase models the annotator as a person,
		// see cb2::Codec::getAnnotator), so it is inserted into the player
		// list -- after all real players, so ids stay stable.
		e.sourceId = (e.source.empty() && e.sourceTitle.empty())
					 ? unsigned(-1)
					 : sources.insert(e.sourceTitle, e.source);
	}

	for (unsigned i = 0; i < encoded.size(); ++i)
	{
		Encoded& e = encoded[i];
		e.annotatorId = e.annotator.empty() ? unsigned(-1) : players.insert(e.annotator);
	}

	// ------------------------------------------------------------------
	// .2cbg records
	// ------------------------------------------------------------------
	mstl::string gameData;
	mstl::vector<uint32_t> offsets(games.size());
	mstl::vector<uint32_t> annOffsets(games.size());

	uint32_t offset = 12;
	uint32_t annOffset = 12;

	for (unsigned i = 0; i < encoded.size(); ++i)
	{
		annOffsets[i] = annOffset;
		annOffset += uint32_t(RecordHeaderSize + 4 + 8);
	}

	for (unsigned i = 0; i < encoded.size(); ++i)
	{
		offsets[i] = offset;

		// CBase26 always reserves a zero-filled extra block (the genuine
		// fixtures carry 98..199 bytes, sized to align the record).
		unsigned const extra = 100;
		uint64_t const total = RecordHeaderSize + encoded[i].payload.size() + extra + 8;

		appendLE64(gameData, RecordMagic);
		appendLE32(gameData, uint32_t(encoded[i].payload.size()));
		appendLE32(gameData, extra);
		appendLE64(gameData, 0);					// sub-field
		appendLE16(gameData, encoded[i].type);
		gameData.append(encoded[i].payload);
		for (unsigned k = 0; k < extra; ++k)
			gameData += char(0);
		appendLE64(gameData, total);

		offset += uint32_t(total);
	}

	// ------------------------------------------------------------------
	// index
	// ------------------------------------------------------------------
	mstl::string index;
	{
		unsigned char header[RecordSize];

		::memset(header, 0, sizeof(header));
		storeLE16(header + 0x08, 0x0026);
		storeLE16(header + 0x0a, uint16_t(RecordSize));
		storeLE32(header + 0x0c, 0x00000500);
		storeLE64(header + 0x10, uint64_t(games.size()) + 1);
		index.assign(reinterpret_cast<char const*>(header), RecordSize);
	}

	for (unsigned i = 0; i < encoded.size(); ++i)
	{
		unsigned char rec[RecordSize];

		buildIndexRecord(	rec,
								offsets[i],
								annOffsets[i],
								encoded[i],
								players.find(encoded[i].white),
								players.find(encoded[i].black),
								events.find(encoded[i].event),
								encoded[i].annotatorId,
								encoded[i].sourceId);
		index.append(reinterpret_cast<char const*>(rec), RecordSize);
	}

	// ------------------------------------------------------------------
	// .2lid
	// ------------------------------------------------------------------
	unsigned numSlots = players.names.size();

	if (numSlots < events.names.size())	numSlots = events.names.size();
	if (numSlots < sources.first.size())	numSlots = sources.first.size();
	if (numSlots == 0)						numSlots = 1;

	mstl::string lid;

	{
		unsigned char header[NamebaseBase];

		buildNamebaseHeader(	header,
									players.names.size(),
									events.names.size(),
									sources.first.size(),
									0,										// no annotator section
									1);
		lid.assign(reinterpret_cast<char const*>(header), NamebaseBase);
	}

	for (unsigned slot = 0; slot < numSlots; ++slot)
	{
		mstl::string s(NamebaseStride, '\0');

		buildSlot(reinterpret_cast<unsigned char*>(s.begin()),
					 slot < players.names.size() ? players.names[slot] : mstl::string(),
					 slot < events.names.size() ? eventSite[slot] : mstl::string(),
					 slot < events.names.size() ? events.names[slot] : mstl::string(),
					 slot < eventDate.size() ? eventDate[slot] : 0,
					 slot < sources.first.size() ? sources.first[slot] : mstl::string(),
					 slot < sources.second.size() ? sources.second[slot] : mstl::string());
		lid.append(s);
	}

	// ------------------------------------------------------------------
	// write
	// ------------------------------------------------------------------
	mstl::string cbg;
	appendLE64(cbg, uint64_t(12 + gameData.size()));
	appendLE16(cbg, 12);
	appendLE16(cbg, 0x0500);
	cbg.append(gameData);

	// The annotation stream holds CBase's four-byte "no annotations" marker
	// per game, so every index record points at a valid record.
	mstl::string cba;
	appendLE64(cba, uint64_t(12 + games.size() * 38));
	appendLE16(cba, 12);
	appendLE16(cba, 0x0000);

	for (unsigned i = 0; i < games.size(); ++i)
	{
		appendLE64(cba, RecordMagic);
		appendLE32(cba, 4);
		appendLE32(cba, 0);
		appendLE64(cba, 0);
		appendLE16(cba, 0x2000);
		cba += char(0xff); cba += char(0xff);
		cba += char(0xff); cba += char(0x7f);
		appendLE64(cba, 26 + 4 + 8);
	}

	if (!writeFile(rootname + ".2cbg", cbg)
		 || !writeFile(rootname + ".2cba", cba)
		 || !writeFile(rootname + ".2lid", lid)
		 || !writeFile(rootname + ".2cbh", index))
	{
		if (error) *error = "cannot write database files";
		return false;
	}

	return true;
}

} // anonymous namespace


WriteGame::WriteGame()
	:whiteElo(0)
	,blackElo(0)
	,medals(0)
	,setup(-1)
	,recordType(0)
{
}


bool
encodeMoveStream(	Board const& board,
							mstl::vector<Move> const& moves,
							mstl::vector<uint16_t>& stream)
{
	stream.clear();
	stream.push_back(Move16_GameStart);

	Board position(board);

	for (unsigned i = 0; i < moves.size(); ++i)
	{
		uint16_t code;

		if (!encodeMove16(position, moves[i], code))
			return false;

		stream.push_back(code);

		Move move(moves[i]);
		position.prepareForPrint(move, variant::Normal, Board::ExternalRepresentation);
		position.doMove(move, variant::Normal);
	}

	stream.push_back(Move16_Terminator);
	return true;
}


bool
writeDatabase(	mstl::string const& rootname,
					mstl::vector<WriteGame> const& games,
					mstl::string* error)
{
	if (rootname.empty())
	{
		if (error) *error = "empty database name";
		return false;
	}

	return writeDatabaseInt(rootname, games, error);
}


bool
appendToDatabase(	mstl::string const& rootname,
						mstl::vector<WriteGame> const& games,
						mstl::string* error)
{
	mstl::string index, lid, data;

	if (!readFile(rootname + ".2cbh", index)
		 || !readFile(rootname + ".2lid", lid)
		 || !readFile(rootname + ".2cbg", data))
	{
		// no existing database: create one
		return writeDatabase(rootname, games, error);
	}

	IndexLayout layout;

	if (!readIndexLayout(reinterpret_cast<unsigned char const*>(index.data()),
								index.size(), index.size(), layout))
	{
		if (error) *error = "invalid existing database";
		return false;
	}

	mstl::vector<mstl::string> payloads;
	mstl::vector<uint16_t> types;

	if (!scanGameData(index, data, payloads, types))
	{
		if (error) *error = "invalid existing game data";
		return false;
	}

	// Rebuild the database from the existing payloads plus the new games so
	// the index and namebase stay consistent.
	mstl::vector<WriteGame> all;
	unsigned char const* idx =
		reinterpret_cast<unsigned char const*>(index.data());

	mstl::string lidText(lid);

	NameList players, events;
	mstl::vector<mstl::string> eventSite;
	mstl::vector<uint32_t> eventDate;
	mstl::vector<mstl::string> sourceTitle, sourceName;

	scanNamebase(lidText, players, events, eventSite, eventDate);
	scanSlotNames(lidText, namebaseSourceOffset, sourceTitle, sourceName);

	for (unsigned i = 0; i < payloads.size(); ++i)
	{
		unsigned char const* rec = idx + size_t(i + 1) * layout.recordSize;
		WriteGame g;

		g.moves.clear();

		for (unsigned k = 0; k < payloads[i].size() / 2; ++k)
			g.moves.push_back(readLE16(reinterpret_cast<unsigned char const*>
												(payloads[i].data()) + 2*k));

		g.setup = -2;
		g.recordType = types[i];

		uint64_t const white = readLE64(rec + 0x18);
		uint64_t const black = readLE64(rec + 0x20);
		uint64_t const event = readLE64(rec + 0x28);

		if (white < players.names.size())	g.white = players.names[unsigned(white)];
		if (black < players.names.size())	g.black = players.names[unsigned(black)];
		if (event < events.names.size())	g.event = events.names[unsigned(event)];
		if (event < eventSite.size())		g.site = eventSite[unsigned(event)];

		unsigned const round = readLE16(rec + 0x5a);
		unsigned const sub = readLE16(rec + 0x5c);

		if (sub)
		{
			char buf[32];
			::snprintf(buf, sizeof(buf), "%u.%u", round, sub);
			g.round = buf;
		}
		else
		{
			char buf[32];
			::snprintf(buf, sizeof(buf), "%u", round);
			g.round = buf;
		}

		unsigned const result = rec[0x58] & 3;
		g.result = result == 0 ? "0-1" : result == 1 ? "1/2-1/2"
					  : result == 2 ? "1-0" : "*";

		g.whiteElo = readLE16(rec + 0x60);
		g.blackElo = readLE16(rec + 0x70);

		unsigned const date = uint32_t(rec[0xbc]) | (uint32_t(rec[0xbd]) << 8)
									| (uint32_t(rec[0xbe]) << 16);
		g.date = Date((date >> 9) & 0xfff, (date >> 5) & 0xf, date & 0x1f);

		// The per-game source (index +0x38), annotator (index +0x30) and medal
		// word (+0x82) are carried over so appending does not lose them.
		uint64_t const sourceId = readLE64(rec + 0x38);
		uint64_t const annotatorId = readLE64(rec + 0x30);

		if (sourceId < sourceName.size())
		{
			g.sourceTitle = sourceTitle[unsigned(sourceId)];
			g.source = sourceName[unsigned(sourceId)];
		}

		if (annotatorId < players.names.size())
			g.annotator = players.names[unsigned(annotatorId)];

		g.medals = readLE16(rec + 0x82);

		unsigned const ecoKey = readLE16(rec + 0x80);

		if (ecoKey)
		{
			// key = 128 * (0-based code + 1)
			unsigned const code = (ecoKey >> 7) - 1u;
			char buf[16];
			::snprintf(buf, sizeof(buf), "%c%02u", 'A' + code / 100, code % 100);
			g.eco = buf;
		}

		all.push_back(g);
	}

	for (unsigned i = 0; i < games.size(); ++i)
		all.push_back(games[i]);

	return writeDatabaseInt(rootname, all, error);
}

} // namespace cb2
} // namespace db
