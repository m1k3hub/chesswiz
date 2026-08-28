// ======================================================================
// CB2 (ChessBase 17+ "2CBH") Database Codec — read-only.
//
// Opens `.2cbh` databases (index + `.2cbg` game data + `.2lid` namebase),
// decodes mainlines through the embedded Move16 table and feeds the
// standard Consumer protocol.
//
// Format spec: 2CBH_FORMAT_DESIGN.md
//  - .2cbh: 192-byte index records; games start at record #256;
//    @0x08 = the .2cbg record offset, @0x18/@0x20 = the player IDs,
//    @0x28 = the event ID, byte 0x58 & 3 = the result.
//  - .2cbg: game records in insertion order (deleted games leave
//    unreferenced records); data = [0xfffc][Move16 codes][0xffff].
//  - .2lid: the player namebase; the 0-based signature-record ordinal
//    equals the player ID.
// ======================================================================

#include "cb2_codec.h"
#include "2cbh_move16.h"

#include "db_move_node.h"
#include "u_progress.h"
#include "m_string.h"
#include "m_ifstream.h"
#include "m_fstream.h"

#include <stdio.h>

#include "db_common.h"
#include "db_consumer.h"
#include "db_exception.h"
#include "db_game_data.h"
#include "db_board.h"
#include "db_move_list.h"

#include "sys_utf8_codec.h"

#include "m_ifstream.h"
#include "m_string.h"

#include <stdio.h>
#include <stdlib.h>

namespace db {

namespace cb2 {

namespace
{

uint64_t readLE64(unsigned char const* p)
{
	uint64_t v = 0;
	for (int i = 7; i >= 0; --i)
		v = (v << 8) | p[i];
	return v;
}

uint32_t readLE32(unsigned char const* p)
{
	return uint32_t(p[0]) | (uint32_t(p[1]) << 8)
		 | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}

uint16_t readLE16(unsigned char const* p)
{
	return uint16_t(p[0] | (p[1] << 8));
}

// Move16 squares are file-major (sq = file*8 + rank), scidb is rank-major.
inline unsigned toScidbSquare(unsigned m16sq)
{
	return ((m16sq & 7) << 3) | (m16sq >> 3);
}

unsigned toScidbPiece(unsigned m16piece)
{
	switch (m16piece & 7)
	{
		case 1:  return piece::King;
		case 2:  return piece::Queen;
		case 3:  return piece::Knight;
		case 4:  return piece::Bishop;
		case 5:  return piece::Rook;
		case 6:  return piece::Pawn;
		default: return piece::None;
	}
}

char const* const ResultTag[4] = { "0-1", "1/2-1/2", "1-0", "*" };

} // anonymous namespace


Codec::Codec()
	:m_numGames(0)
	,m_illegalPlayer(0)
{
}


Codec::~Codec() throw()
{
	close();
}


bool Codec::isWritable() const { return false; }
bool Codec::encodingFailed() const { return false; }
bool Codec::usingAsyncReader() const { return false; }
DatabaseCodec::Format Codec::format() const { return format::ChessBase2; }

unsigned Codec::maxGameRecordLength() const { return 1u << 26; }
unsigned Codec::maxGameLength() const { return 1023; }
unsigned Codec::maxGameCount() const { return (1u << 26); }
unsigned Codec::maxPlayerCount() const { return (1 << 20); }
unsigned Codec::maxEventCount() const { return (1 << 20); }
unsigned Codec::maxSiteCount() const { return (1 << 20); }
unsigned Codec::maxAnnotatorCount() const { return (1 << 20); }
unsigned Codec::minYear() const { return 1470; }
unsigned Codec::maxYear() const { return 2100; }
unsigned Codec::maxDescriptionLength() const { return 0; }
unsigned Codec::gameFlags() const { return 0; }

mstl::string const&
Codec::defaultEncoding() const
{
	static mstl::string encoding(sys::utf8::Codec::utf8());
	return encoding;
}


mstl::string const&
Codec::extension() const
{
	static mstl::string ext("2cbh");
	return ext;
}


mstl::string const&
Codec::encoding() const
{
	return m_encoding;
}


tag::TagSet
Codec::tagFilter(Section section, TagSet const& tags) const
{
	return tag::TagSet();
}


void
Codec::setEncoding(mstl::string const& encoding)
{
	m_encoding = encoding;
}


void
Codec::reset()
{
}


void
Codec::close()
{
	if (m_gameStream.is_open())
		m_gameStream.close();
	if (m_annotationStream.is_open())
		m_annotationStream.close();
}


void
Codec::doOpen(mstl::string const& encoding)
{
	M_THROW(Exception("cannot create 2CBH databases"));
}


void
Codec::doOpen(mstl::string const& rootname, mstl::string const& encoding)
{
	M_THROW(Exception("cannot create 2CBH databases"));
}


void
Codec::doOpen(	mstl::string const& rootname,
					mstl::string const& originalSuffix,
					mstl::string const& encoding,
					util::Progress& progress)
{
	M_REQUIRE(originalSuffix == "2cbh");

	setEncoding(encoding);
	setVariant(variant::Normal);
	setType(type::Unspecific);

	// ------------------------------------------------------------------
	// index (.2cbh)
	// ------------------------------------------------------------------
	mstl::string indexName(rootname + ".2cbh");
	checkPermissions(indexName);

	mstl::string cbhData;
	{
		mstl::ifstream strm(indexName, mstl::ios_base::in | mstl::ios_base::binary);
		if (!strm)
			IO_RAISE(Index, Open_Failed, "cannot open '%s'", indexName.c_str());
		strm.seekg(0, mstl::ios_base::end);
		long size = strm.tellg();
		strm.seekg(0, mstl::ios_base::beg);
		cbhData.resize(size);
		if (size > 0)
			strm.read(cbhData.begin(), size);
	}

	unsigned char const* cbh = reinterpret_cast<unsigned char const*>(cbhData.data());
	unsigned const recordSize = readLE16(cbh + 0x0a);
	m_numGames = unsigned(cbhData.size() / recordSize) - 256u;

	mstl::string gameName(rootname + ".2cbg");
	checkPermissions(gameName);
	openFile(m_gameStream, gameName, Readonly);

	// ------------------------------------------------------------------
	// player namebase (.2lid): the 0-based signature-slot ordinal is the
	// player ID used by the index.
	// ------------------------------------------------------------------
	{
		mstl::string lidName(rootname + ".2lid");
		mstl::string lidData;
		mstl::ifstream lidStrm(lidName, mstl::ios_base::in | mstl::ios_base::binary);
		if (lidStrm)
		{
			lidStrm.seekg(0, mstl::ios_base::end);
			long size = lidStrm.tellg();
			lidStrm.seekg(0, mstl::ios_base::beg);
			mstl::string lidData(size, '\0');
			if (size > 0)
				lidStrm.read(lidData.begin(), size);
			lidStrm.close();

			unsigned char const* lid =
				reinterpret_cast<unsigned char const*>(lidData.data());
			size_t const lsize = size_t(size);
			static unsigned char const sig[12] = {
				0xff, 0xff, 0xff, 0xff, 0x08, 0x00, 0x00, 0x00,
				0xff, 0xff, 0xff, 0xff };

			Namebase& base = namebase(Namebase::Player);
			base.reserve(10000u, (1 << 24) - 1);

			size_t pos = 0xb8;
			unsigned ordinal = 0;
			while (ordinal < (1u << 20))
			{
				size_t i = pos;
				while (i + 12 <= size_t(size))
				{
					if (::memcmp(lid + i, sig, 12) == 0)
						break;
					++i;
				}
				if (i + 12 > lsize)
					break;
				size_t end = i + 12;
				size_t lo = (i + 8 > 320) ? i + 8 - 320 : 0;
				for (size_t start = i + 4; start-- > lo;)
				{
					uint32_t total = uint32_t(lid[start])
										 | (uint32_t(lid[start + 1]) << 8)
										 | (uint32_t(lid[start + 2]) << 16)
										 | (uint32_t(lid[start + 3]) << 24);
					if (start + total != end || total <= 20 || total >= 320)
						continue;
					uint32_t llen = uint32_t(lid[start + 4])
										 | (uint32_t(lid[start + 5]) << 8);
					if (llen == 0 || llen >= 80 || start + 8 + llen + 4 > lsize)
						continue;
					size_t fo = start + 8 + llen;
					uint32_t flen = uint32_t(lid[fo])
										 | (uint32_t(lid[fo + 1]) << 8);
					if (flen >= 80 || fo + 4 + flen != end - 20)
						continue;
					bool ascii = true;
					for (uint32_t j = 0; j < llen; ++j)
					{
						unsigned char ch = lid[start + 8 + j];
						if (!(32 <= ch && ch < 127))
							ascii = false;
					}
					if (ascii && llen > 0)
					{
						mstl::string last(reinterpret_cast<char const*>(&lid[start + 8]), llen);
						mstl::string first(reinterpret_cast<char const*>(&lid[fo + 4]), flen);
						mstl::string full = first.empty() ? last : (last + ", " + first);
						m_playerMap.container().push_back(
							BaseMap::value_type(ordinal, base.insertPlayer(full, 0, (1 << 24) - 1)));
					}
					break;
				}
				++ordinal;
				pos = end;
			}
			base.setNextId(1u << 20);
			m_playerMap.qsort();
		}
	}

	// ------------------------------------------------------------------
	// game index
	// ------------------------------------------------------------------
	util::ProgressWatcher watcher(progress, m_numGames);
	progress.message("read-index");

	GameInfoList& infoList = gameInfoList();
	infoList.reserve(m_numGames);

	for (unsigned k = 0; k < m_numGames; ++k)
	{
		unsigned char const* rec = cbh + (256u + k) * recordSize;
		GameInfo& info = infoList.push_back();

		info.m_gameOffset = unsigned(readLE32(rec + 0x08));
		info.m_player[color::White] = getPlayer(unsigned(readLE32(rec + 0x18) & 0xffffffu));
		info.m_player[color::Black] = getPlayer(unsigned(readLE32(rec + 0x20) & 0xffffffu));
		info.m_event = getEvent(unsigned(readLE32(rec + 0x28) & 0xffffffu));

		unsigned char f58 = rec[0x58];
		switch (f58 & 3)
		{
			case 0:  info.m_result = result::Black; break;
			case 1:  info.m_result = result::Draw; break;
			case 2:  info.m_result = result::White; break;
			default: info.m_result = result::Unknown; break;
		}

		info.m_dateYear = Date::Zero10Bits;
		info.m_dateMonth = 0;
		info.m_dateDay = 0;

		// record length: peek the .2cbg record header
		m_gameStream.clear();
		m_gameStream.seekg(info.m_gameOffset + 8, mstl::ios_base::beg);
		unsigned char h[4];
		if (m_gameStream.read(reinterpret_cast<char*>(h), 4))
			info.setGameRecordLength(readLE32(h));
	}
}


NamebasePlayer*
Codec::getPlayer(unsigned id)
{
	BaseMap::iterator p = m_playerMap.find(id);

	if (p != m_playerMap.end())
	{
		static_cast<NamebasePlayer*>(p->second)->incrRef();
		return static_cast<NamebasePlayer*>(p->second);
	}

	if (m_illegalPlayer == 0)
	{
		m_illegalPlayer = namebase(Namebase::Player).insertPlayer(
								"? (illegal reference)", 0, m_playerMap.size() + 1);
	}

	m_illegalPlayer->incrRef();
	return m_illegalPlayer;
}


NamebaseEvent*
Codec::getEvent(unsigned id)
{
	BaseMap::iterator p = m_eventMap.find(id);

	if (p != m_eventMap.end())
	{
		NamebaseEvent* event = static_cast<NamebaseEvent*>(p->second);
		if (event->frequency() == 0)
			event->site()->incrRef();
		event->incrRef();
		return event;
	}

	// lazy placeholder event (the .2lcd event namebase is not decoded yet)
	char idbuf[32];
	::snprintf(idbuf, sizeof(idbuf), "%u", id);
	mstl::string name("Event ");
	name.append(idbuf);
	NamebaseSite* site = namebase(Namebase::Site).insertSite("?");
	NamebaseEvent* event = namebase(Namebase::Event).insertEvent(
		name, id, (1 << 20), site);
	event->site()->incrRef();
	event->incrRef();
	m_eventMap.container().push_back(BaseMap::value_type(id, event));
	m_eventMap.qsort();
	return event;
}


save::State
Codec::doDecoding(	db::Consumer& consumer,
						TagSet& tags,
						GameInfo const& info,
						unsigned gameIndex)
{
	if (!consumer.startGame(tags))
		return save::UnsupportedVariant;

	consumer.startMoveSection();

	m_gameStream.clear();
	m_gameStream.seekg(info.gameOffset(), mstl::ios_base::beg);

	unsigned char header[0x1a];
	if (!m_gameStream.read(reinterpret_cast<char*>(header), sizeof(header)))
	{
		consumer.finishMoveSection(result::Unknown);
		return consumer.finishGame(tags);
	}

	if (readLE64(header) != 0x1122334455667788ull)
	{
		consumer.finishMoveSection(result::Unknown);
		return consumer.finishGame(tags);
	}

	uint32_t const dataSize = readLE32(header + 0x08);
	uint16_t const type = readLE16(header + 0x18);

	if (type != 1)
	{
		// Chess960 (type 2) and other variants are not supported yet
		char buf[32];
		::snprintf(buf, sizeof(buf), "%u", 0u);
		tags.set(tag::PlyCount, buf);
		tags.set(tag::Result, "*");
		consumer.finishMoveSection(result::Unknown);
		return consumer.finishGame(tags);
	}

	mstl::string record(dataSize, '\0');
	if (dataSize > 0)
		m_gameStream.read(record.begin(), dataSize);

	unsigned char const* data = reinterpret_cast<unsigned char const*>(record.data());
	Board board(Board::standardBoard(variant::Normal));
	unsigned moves = 0;

	for (uint32_t j = 0; j + 1 < dataSize / 2u; ++j)
	{
		uint16_t code = readLE16(data + 2*j);
		if (code == db::cb2::Move16_GameStart)
			continue;
		if (code == db::cb2::Move16_Terminator)
			break;
		if (code >= db::cb2::Move16_None)
			continue;

		db::cb2::Move16Descriptor d;
		if (!db::cb2::decodeMove16(code, d))
			break;

		unsigned from = ((d.from & 7) << 3) | (d.from >> 3);
		unsigned to = ((d.to & 7) << 3) | (d.to >> 3);
		unsigned toAlt = to;
		unsigned promoType = 0;
		bool isPromotion = false;

		if (d.hasWord1)
		{
			unsigned wf = ((d.word1From & 7) << 3) | (d.word1From >> 3);
			if (d.piece == 6 || d.piece == 14)
			{
				if (d.word1From == d.to && d.word1To == d.to)
				{
					promoType = toScidbPiece(d.word1Piece);
					isPromotion = true;
				}
			}
			else if (d.word1Piece == 5 || d.word1Piece == 13)
			{
				toAlt = wf;	// scidb castling: king to the rook square
			}
		}

		db::MoveList legalMoves;
		board.generateMoves(variant::Normal, legalMoves);
		board.filterLegalMoves(legalMoves, variant::Normal);

		Move move;
		bool found = false;
		for (unsigned mi = 0; mi < legalMoves.size(); ++mi)
		{
			Move const& m = legalMoves[mi];
			if (m.from() != from || (m.to() != to && m.to() != toAlt))
				continue;
			if (isPromotion)
			{
				if (!m.isPromotion() || m.promoted() != promoType)
					continue;
			}
			else if (m.isPromotion())
			{
				continue;
			}
			move = m;
			found = true;
			break;
		}

		if (!found)
			break;

		board.prepareForPrint(move, variant::Normal, Board::ExternalRepresentation);
		consumer.putMove(move);
		board.doMove(move, variant::Normal);
		++moves;
	}

	char buf[32];
	::snprintf(buf, sizeof(buf), "%u", moves);
	tags.set(tag::PlyCount, buf);

	consumer.finishMoveSection(result::fromString(tags.value(tag::Result)));
	return consumer.finishGame(tags);
}


void
Codec::doDecoding(GameData& data, GameInfo& info, unsigned gameIndex, mstl::string* encoding)
{
	M_THROW(Exception("2CBH: raw game data access is not supported"));
}


unsigned
Codec::doDecoding(	::util::BlockFileReader* reader,
						GameInfo const& info,
						uint16_t* line,
						unsigned length,
						Board& startBoard,
						bool useStartBoard)
{
	M_THROW(Exception("2CBH: async decoding is not supported"));
}


bool
Codec::getAttributes(	mstl::string const& filename,
							int& numGames,
							db::type::ID& type,
							mstl::string* description)
{
	mstl::ifstream strm(filename, mstl::ios_base::in | mstl::ios_base::binary);
	if (!strm)
		return false;
	strm.seekg(0, mstl::ios_base::end);
	long size = strm.tellg();
	numGames = int(size / long(192)) - 256;
	if (numGames < 0)
		return false;
	if (description)
	{
		*description = "";
		type = db::type::Unspecific;
	}
	return true;
}


void
Codec::getSuffixes(mstl::string const& filename, StringList& result)
{
	result.push_back("2cbh");
	result.push_back("2cbg");
	result.push_back("2cba");
	result.push_back("2lid");
	result.push_back("2lcd");
	result.push_back("2lgd");
}

} // namespace cb2
} // namespace db