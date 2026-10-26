// ======================================================================
// CB2 (ChessBase 17+ "2CBH") Database Codec — read-only.
//
// Opens `.2cbh` databases (index + `.2cbg` game data + `.2lid` namebase),
// decodes mainlines through the embedded Move16 table and feeds the
// standard Consumer protocol.
//
// Format spec: docs/formats/2CBH_FORMAT_DESIGN.md
//  - .2cbh: 192-byte index records; games start at record #1;
//    @0x08 = the .2cbg record offset, @0x18/@0x20 = the player IDs,
//    @0x28 = the event ID, byte 0x58 & 3 = the result.
//  - .2cbg: game records in insertion order (deleted games leave
//    unreferenced records); data = [0xfffc][Move16 codes][0xffff].
//  - .2lid: the player namebase; the 0-based signature-record ordinal
//    equals the player ID.
// ======================================================================

#include "cb2_codec.h"
#include "cb2_elo.h"
#include "cb2_eco.h"
#include "cb2_index.h"
#include "2cbh_move16.h"
#include "2cbh_annotations.h"

#include "db_move_node.h"
#include "db_var_consumer.h"
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
#include "db_annotation.h"
#include "db_mark_set.h"

#include "sys_utf8_codec.h"
#include "sys_utf8.h"

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

/// ChessBase packs dates as day(5) | month(4) << 5 | year(12) << 9; the same
/// packing is used by the index (+0xbc) and by the .2lid event record.
void unpackDate(unsigned packed, unsigned& year, unsigned& month, unsigned& day)
{
   day = packed & 0x1fu;
   month = (packed >> 5) & 0x0fu;
   year = (packed >> 9) & 0xfffu;
}

/// One .2cbg game record (header + payload).
struct GameRecord
{
   mstl::string   data;   ///< payload (token stream)
   uint16_t       type;   ///< record type (1 = standard chess)
   uint32_t       size;   ///< payload size in bytes
};

/// Read one .2cbg record (header + payload) at `offset`.
bool
readGameRecord(mstl::fstream& strm, uint32_t offset, GameRecord& rec)
{
   strm.clear();
   strm.seekg(offset, mstl::ios_base::beg);

   unsigned char header[0x1a];
   if (!strm.read(reinterpret_cast<char*>(header), sizeof(header)))
      return false;
   if (readLE64(header) != 0x1122334455667788ull)
      return false;

   // dataSize is the length of the data field that starts at record +0x1a
   // (the record header ends there); the extra field follows the data.  This
   // is verified byte-exactly on the fixtures: the data runs from +0x1a to
   // the mainline terminator and the u64 record size trailer sits right after
   // the extra field (26 + dataSize + extraSize + 8).
   uint32_t const dataSize = readLE32(header + 0x08);
   rec.type = readLE16(header + 0x18);
   rec.size = dataSize;
   rec.data.assign(rec.size, '\0');

   return rec.size == 0 || strm.read(rec.data.begin(), rec.size);
}

/// Apply one code of a "position setup" block.  CBase26 stores an arbitrary
/// start position as one Move16 code per occupied square (writer
/// 0x1401e8310 enumerates the squares 0..63 and calls the square/piece code
/// builder 0x14021a1e0); the reader's bitboard builder treats each code as a
/// transition `piece` from `from` to `to`, so a lone piece code carries the
/// square in `to`.
bool
placeSetupPiece(Board& board, uint16_t code, variant::Type variant)
{
   Move16Descriptor d;
   if (!decodeMove16(code, d) || d.piece == 0)
      return false;

   unsigned const square = toScidbSquare(d.to);
   unsigned const type = toScidbPiece(d.piece);
   color::ID const color = d.piece >= 9 ? db::color::Black : db::color::White;

   if (square >= 64 || type == piece::None)
      return false;
   return board.setAt(square, piece::piece(piece::Type(type), color), variant);
}

/// Build a start position from a 64-square setup block.  `first` is the index
/// of the first code word; codes are stored until a token >= 0xfffb (the
/// following 0xfffc game-start token).  Castling rights are derived from the
/// placement: a king on its home rank with a rook on the same rank allows the
/// castle towards that rook, which is exactly Scidb's Chess960 convention.
bool
buildSetupBoard(uint16_t const* words, uint32_t count, uint32_t first,
                color::ID toMove, variant::Type variant, Board& board,
                uint32_t& next)
{
   Board b;
   b.clear();

   uint32_t i = first;
   for (; i < count && words[i] < Move16_None; ++i)
   {
      if (!placeSetupPiece(b, words[i], variant))
         return false;
   }
   if (i >= count)
      return false;

   for (unsigned ci = 0; ci < 2; ++ci)
   {
      color::ID const c = ci == 0 ? db::color::White : db::color::Black;
      unsigned const base = (c == db::color::White ? 0 : 56);
      unsigned king = 64;
      for (unsigned sq = base; sq < base + 8; ++sq)
      {
         if (b.pieceAt(sq) == piece::piece(piece::King, c))
            king = sq;
      }
      if (king == 64)
         continue;   // castling is impossible without a king on its home rank
      for (unsigned sq = base; sq < base + 8; ++sq)
      {
         if (b.pieceAt(sq) == piece::piece(piece::Rook, c))
         {
            if (sq > king)
               b.setCastleShort(c, sq);
            else
               b.setCastleLong(c, sq);
         }
      }
   }

   b.setToMove(toMove);
   b.setPlyNumber(1);
   b.setMoveNumber(1);
   board = b;
   next = i;
   return true;
}

/// Replay a Move16 mainline on `board`; used to pick the interpretation of an
/// undecoded setup header (flag-word count and side to move) that makes the
/// stored game legal.  Stops at the first 0xffff (mainline terminator).
bool
replayMainline(Board board, uint16_t const* words, uint32_t count,
                variant::Type variant)
{
   for (uint32_t i = 0; i < count; ++i)
   {
      uint16_t const code = words[i];

      if (code == Move16_Terminator)
         return true;
      if (code >= Move16_None)
         continue;

      Move16Descriptor d;
      Move move;
      if (!decodeMove16(code, d) || !resolveMove16(board, d, move))
         return false;
      board.prepareForPrint(move, variant, Board::ExternalRepresentation);
      board.doMove(move, variant);
   }
   return false;
}

/// Feed one line (mainline or variation) of a .2cbg token stream into a
/// consumer, in PGN order: an own move is emitted first, then the child
/// variations attached at its marker (they replace it; the base
/// Consumer's variation stack rewinds the board automatically).
/// A marker value M is the number of own moves before the RAV's
/// insertion point (the internal 0xfffd records exactly that count):
/// the RAV is fed directly after own[M - 1] (as the PGN renders it) and
/// replaces that move.
/// A .2cba item at position X is the post-comment of the move at .2cba
/// walk position X (0-based, document = PGN order, RAV content counted).
bool
feedLine( db::Consumer& consumer,
          Board const& entryBoard,
          mstl::vector<uint16_t> const& own,
          mstl::vector<uint32_t> const& markers,
          mstl::vector<uint32_t> const& kids,
          mstl::vector<CbgNode> const& pool,
          mstl::vector<CbaItem> const& items,
          unsigned& nextItem,
          bool annotationsOk,
          unsigned& feed)
{
   Board board(entryBoard);
   unsigned ki = 0;

   for (unsigned vi = 0; vi < own.size(); ++vi)
   {
      while (ki < kids.size() && ki < markers.size() && markers[ki] <= vi)
         ++ki;

      bool const hasKids = ki < kids.size() && ki < markers.size() && markers[ki] == vi + 1;
      Board before;
      if (hasKids)
         before = board;

      Move move;
      Move16Descriptor d;
      if (!decodeMove16(own[vi], d) || !resolveMove16(board, d, move))
         return false;

      mstl::string text;
      db::Comment comment;
      Annotation annotation;
      unsigned itemNag = nag::Null;

      if (annotationsOk)
      {
         while ( nextItem < items.size()
                  && items[nextItem].position < feed)
            ++nextItem;   // stale item: skipped (defensive)

         while ( nextItem < items.size()
                  && items[nextItem].position == feed)
         {
            if (!text.empty())
               text += '\n';
            if (items[nextItem].nag && itemNag == nag::Null)
               itemNag = items[nextItem].nag;
            text += items[nextItem].text;
            ++nextItem;
         }

         if (!text.empty())
            comment = db::Comment(text, 0);
      }

      board.prepareForPrint(move, variant::Normal, Board::ExternalRepresentation);

      if (itemNag != nag::Null || !comment.isEmpty())
      {
         MarkSet marks;
         if (itemNag != nag::Null)
            annotation = Annotation(nag::ID(itemNag));
         consumer.putMove(move, annotation, db::Comment(), comment, marks);
      }
      else
      {
         consumer.putMove(move);
      }

      board.doMove(move, variant::Normal);
      ++feed;

      while (ki < kids.size() && ki < markers.size() && markers[ki] == vi + 1)
      {
         consumer.startVariation();
         bool ok = feedLine( consumer, before,
                             pool[kids[ki]].own, pool[kids[ki]].markers,
                             pool[kids[ki]].kids, pool,
                             items, nextItem, annotationsOk, feed);
         consumer.finishVariation();
         if (!ok)
            return false;
         ++ki;
      }
   }

   return true;
}

/// Feed one .2cbg game record into a consumer: split the token stream,
/// parse the variation tree (docs/formats/2CBH_FORMAT_DESIGN.md section 4.2) and emit
/// mainline + variations in PGN order.
///
/// Each root marker counts mainline moves before the insertion point.
/// parseCbgTree returns the zero-based ply replaced by that variation.
///
/// Returns the mainline ply count; false on desync (the caller should
/// skipGame).
bool
walkGame( db::Consumer& consumer,
          unsigned char const* data,
          uint32_t dataSize,
          mstl::vector<CbaItem> const& items,
          bool annotationsOk,
          unsigned& plyCount)
{
   if (dataSize < 4 || (dataSize & 1u) || readLE16(data) != Move16_GameStart)
      return false;
   uint32_t const n = dataSize / 2u;
   bool terminated = false;
   mstl::vector<uint16_t> mainline;
   mstl::vector<uint32_t> rootMarkers;
   uint32_t j = 0;

   // Root markers are recorded as MOVE COUNTS (the number of mainline
   // moves before the marker), not as token indices: the count survives
   // stray special tokens (e.g. a 0xfffb sub-structure word) that would
   // otherwise shift the token -> ply arithmetic by one.  Never observed
   // in the 863,538-game corpus, but the count form is immune regardless
   // (scid-code GLM pass, cross-implementation review 2026-09-07).
   for (; j < n; ++j)
   {
      uint16_t code = readLE16(data + 2*j);
      if (code == db::cb2::Move16_GameStart)
         continue;
      if (code == db::cb2::Move16_Terminator)
      {
         terminated = true;
         ++j;
         break;
      }
      if (code == db::cb2::Move16_Marker)
      {
         rootMarkers.push_back(uint32_t(mainline.size()));
         continue;
      }
      if (code >= db::cb2::Move16_None)
         continue;
      mainline.push_back(code);
   }

   if (!terminated)
      return false;

   uint16_t const* region = reinterpret_cast<uint16_t const*>(data) + j;
   uint32_t const regionWords = n > j ? n - j : 0u;

   mstl::vector<CbgNode> pool;
   mstl::vector<uint32_t> rootsDoc;
   mstl::vector<uint32_t> rootInsert;
   bool const treeOk =
      parseCbgTree(region, regionWords, rootMarkers, pool, rootsDoc, rootInsert);

   // A malformed variation tree with variation data present would lose
   // the RAV content silently and shift the .2cba walk positions
   // (misplaced comments): refuse the whole record instead.
   if (!treeOk && (!rootMarkers.empty() || regionWords != 0u))
      return false;

   // doc-order root replaced plies: rootInsert[i] is the 0-based ply
   // replaced by doc root #i (see parseCbgTree); feedLine works with the
   // "count" convention (attach after own[M - 1]), so pass replaced + 1.
   mstl::vector<uint32_t> attach;
   attach.reserve(rootsDoc.size());

   for (unsigned i = 0; i < rootsDoc.size(); ++i)
   {
      attach.push_back(rootInsert[i] + 1);
   }

   unsigned nextItem = 0;
   Board board(consumer.startBoard());
   unsigned feed = 0;

   if ( !feedLine( consumer, board, mainline, attach, rootsDoc, pool,
                   items, nextItem, annotationsOk, feed))
      return false;

   // trailing comments: after the last move of the .2cba walk
   if (annotationsOk)
   {
      mstl::string text;

      while (nextItem < items.size() && items[nextItem].position == feed)
      {
         if (!text.empty())
            text += '\n';
         text += items[nextItem].text;
         ++nextItem;
      }

      if (!text.empty())
         consumer.putTrailingComment(db::Comment(text, 0));
   }

   plyCount = mainline.size();
   return true;
}

} // anonymous namespace


bool
prepareGame(uint16_t type, unsigned char const*& data, uint32_t& size,
            Board& board, TagSet& tags)
{
    board = Board::standardBoard(variant::Normal);

    if (type != 1 && type != 2)
        return false;

    // Both record types may carry an explicit start position.  The stream is
    //   [0xfffb] [compact position (type 2 only)] [setup block] [0xfffc] moves
    // where the setup block is absent when a compact position (0..959) is
    // stored and one Move16 code per occupied square is present otherwise
    // (position 1000 = arbitrary setup; type 1 can also carry the block).
    if (size < 4 || readLE16(data) != Move16_None)
        return size >= 4 && (size & 1u) == 0 && readLE16(data) == Move16_GameStart;

    uint32_t const count = size / 2u;
    uint16_t const* const words = reinterpret_cast<uint16_t const*>(data);
    unsigned prefix = 1;                        // 0xfffb

    if (type == 2)
    {
        if (count < 2)
            return false;
        unsigned const position = words[1];
        if (position < 960)
        {
            // Scidb reserves idn 0; Scharnagl position 0 lives at idn 960.
            board.setup(position ? position : 960, variant::Normal);
            data += 4;
            size -= 4;
            tags.set(tag::SetUp, "1");
            tags.set(tag::Fen, board.toFen(variant::Normal, Board::Shredder));
            return size >= 4 && (size & 1u) == 0
                    && readLE16(data) == Move16_GameStart;
        }
        if (position != 1000)
            return false;
        prefix = 2;                             // 0xfffb, 1000
    }

    // Arbitrary setup: the 4-byte header that CBase26's own reader skips
    // (0x1401590d0) is followed directly by the square codes.  The block
    // layout in files written by CBase26's position writer (0x1401e8310) is
    // two bytes longer (a u16 field before the side-to-move byte), so accept
    // both widths, and also both sides to move, taking the interpretation
    // that makes the stored mainline replay legally.
    for (unsigned headerWords = 2; headerWords <= 4; headerWords += 1)
    {
        if (prefix + headerWords >= count)
            break;

        // CBase26's writer stores the side to move in the byte after the
        // leading u16 of a three-word header; prefer it, then the other side.
        color::ID first = db::color::White;
        if (headerWords >= 3)
        {
            unsigned char const* p =
                reinterpret_cast<unsigned char const*>(words + prefix + 1);
            if (p[0] == 1)
                first = db::color::Black;
        }

        for (unsigned k = 0; k < 2; ++k)
        {
            color::ID const toMove = k == 0 ? first
                                    : (first == db::color::White ? db::color::Black
                                                                 : db::color::White);
            Board candidate;
            uint32_t next = 0;

            if (!buildSetupBoard(words, count, prefix + headerWords, toMove,
                                 variant::Normal, candidate, next))
                continue;
            if (next >= count || words[next] != Move16_GameStart)
                continue;
            if (!replayMainline(candidate, words + next + 1, count - next - 1,
                                variant::Normal))
                continue;

            board = candidate;
            unsigned const skip = 2u * next;
            data += skip;
            size -= skip;
            tags.set(tag::SetUp, "1");
            tags.set(tag::Fen, board.toFen(variant::Normal, Board::Shredder));
            return size >= 4 && (size & 1u) == 0
                    && readLE16(data) == Move16_GameStart;
        }
    }

    return false;
}


/// Public wrapper over walkGame (see above); drives the consumer with
/// the full game protocol (startGame/startMoveSection are the caller's
/// responsibility).  See the declaration in cb2_codec.h.
bool
walkGameRaw(	Consumer& consumer,
					unsigned char const* data,
					uint32_t dataSize,
					mstl::vector<CbaItem> const& items,
					bool annotationsOk,
					unsigned& plyCount)
{
	return walkGame(consumer, data, dataSize, items, annotationsOk, plyCount);
}


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
	// The tags the .2cbh index supplies (see doOpen). An empty set here made
	// Database::getInfoTags drop every tag, so the game list and the
	// assistant saw blank players/event/date although the index has them.
	static tag::TagSet infoTags;

	if (infoTags.none())
	{
		infoTags.set(tag::Event);
		infoTags.set(tag::Site);
		infoTags.set(tag::Date);
		infoTags.set(tag::Round);
		infoTags.set(tag::White);
		infoTags.set(tag::Black);
		infoTags.set(tag::Result);
		infoTags.set(tag::Eco);
		infoTags.set(tag::WhiteElo);
		infoTags.set(tag::BlackElo);
		infoTags.set(tag::EventDate);
		infoTags.set(tag::Annotator);
	}

	return infoTags;
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
	IndexLayout layout;
	if (!readIndexLayout(cbh, cbhData.size(), cbhData.size(), layout))
		IO_RAISE(Index, Corrupted, "invalid or truncated 2CBH index");
	unsigned const recordSize = layout.recordSize;
	m_numGames = layout.gameCount;

	mstl::string gameName(rootname + ".2cbg");
	checkPermissions(gameName);
	openFile(m_gameStream, gameName, Readonly);

	// ------------------------------------------------------------------
	// annotations (.2cba): one record per game, reached via index @0x10;
	// optional — annotation decode is skipped when the file is absent
	// ------------------------------------------------------------------
	m_annotationOffsets.clear();
	// ECO keys come from the index itself (independent of .2cba presence):
	// @0x80 holds ChessBase's 16-bit ECO key `(base + 1) << 7 | sub`, where
	// `sub` is a sub-variation number (0 = none) and keys above 0xfa7f mean
	// "no ECO". CBase26 renders the key as "B12" or, with a sub-variation,
	// as "B12/34" (formatter at 0x140c66e50; getter/setter 0x1401e3ba0 and
	// 0x1401e4370 clamp everything above 0xfa7f to 0). The raw key is kept
	// here so the ECO tag can carry the full form.
	m_ecoValues.clear();
	m_ecoValues.reserve(m_numGames);
	for (unsigned k = 0; k < m_numGames; ++k)
	{
		unsigned char const* rec = cbh + (size_t(k) + 1) * recordSize;
		m_ecoValues.push_back(readLE16(rec + 0x80));
	}

	{
		mstl::string cbaName(rootname + ".2cba");
		mstl::ifstream cbaStrm(cbaName, mstl::ios_base::in | mstl::ios_base::binary);
		if (cbaStrm)
		{
			openFile(m_annotationStream, cbaName, Readonly);
			m_annotationOffsets.reserve(m_numGames);
			for (unsigned k = 0; k < m_numGames; ++k)
			{
				unsigned char const* rec = cbh + (size_t(k) + 1) * recordSize;
				m_annotationOffsets.push_back(uint32_t(readLE32(rec + 0x10)));
			}
		}
	}

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
			sys::utf8::Codec textCodec(sys::utf8::Codec::utf8());  // for forceValidUtf8; .2lid text is UTF-8
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
					bool printable = true;
					for (uint32_t j = 0; j < llen; ++j)
					{
						unsigned char ch = lid[start + 8 + j];
						if (ch < 32)
							printable = false;
					}
					if (printable && llen > 0)
					{
						mstl::string last(reinterpret_cast<char const*>(&lid[start + 8]), llen);
						mstl::string first(reinterpret_cast<char const*>(&lid[fo + 4]), flen);
						mstl::string full = first.empty() ? last : (last + ", " + first);
						if (!sys::utf8::validate(full))
							textCodec.forceValidUtf8(full);
						m_playerMap.container().push_back(
							BaseMap::value_type(ordinal, base.insertPlayer(full, 0, (1 << 24) - 1)));
					}
					break;
				}
				++ordinal;
				pos = end;
			}

			// ------------------------------------------------------------------
			// event/site namebase: the .2lid is a slot array (stride
			// 0x108a from 0xb8); the player record lives at slot+0 (id = the
			// slot ordinal, which is why the signature walk above works), the
			// event pair at slot+0x400:
			//   [u32 x][u16 siteLen][site][u16 pad][u16 evLen][event][pad][u32 year]
			// The event id = the SAME slot ordinal (independent dense counters
			// over one slot array; slot 234 holds player 'Kural, Jaroslav' and
			// event 'Munchen Open' simultaneously).  siteLen 0 is valid
			// (site-less events); both lengths 0 = deleted slots.
			// Reverse-engineered in the scid-code project (GLM pass,
			// 2026-09-07); validated against the source PGN: game 0 ->
			// 'Munchen Open'/'Munchen open', game 500000 -> 'World Rapid
			// 2024'/'New York USA'; 99.5% of games resolve.
			// ------------------------------------------------------------------
			unsigned char const* lp = reinterpret_cast<unsigned char const*>(lidData.data());

			if (lsize >= 0xb8 + 0x108a)
			{
				size_t const nslots = (lsize - 0xb8) / 0x108a;

				for (size_t slot = 0; slot < nslots; ++slot)
				{
					size_t a = 0xb8 + slot * 0x108a + 0x400;
					if (a + 8 > lsize)
						break;

					uint32_t siteLen = uint32_t(lp[a + 4]) | (uint32_t(lp[a + 5]) << 8);
					if (siteLen > 80 || a + 8 + siteLen + 4 > lsize)
						continue;

					mstl::string site(reinterpret_cast<char const*>(lp + a + 8), siteLen);
					bool text = true;
					for (uint32_t j = 0; j < siteLen; ++j)
						if (lp[a + 8 + j] < 32)
							text = false;
					if (!text)
						continue;

					size_t b = a + 8 + siteLen;
					uint32_t evLen = uint32_t(lp[b]) | (uint32_t(lp[b + 1]) << 8);
					if (evLen == 0 || evLen > 90 || b + 4 + evLen > lsize)
						continue;

					mstl::string event(reinterpret_cast<char const*>(lp + b + 4), evLen);
					text = true;
					for (uint32_t j = 0; j < evLen; ++j)
						if (lp[b + 4 + j] < 32)
							text = false;
					if (!text)
						continue;

					// .2lid text is UTF-8 (data-verified in the
					// cross-implementation review: the corpus contains
					// c3 b8 = oe, c3 bc = ue and e4 b8 ad = CJK 'zhong',
					// which cp1252 cannot encode; the source PGN stores
					// the identical UTF-8 bytes).  Pass through; validate
					// defensively.
					if (!sys::utf8::validate(site))
						textCodec.forceValidUtf8(site);
					if (!sys::utf8::validate(event))
						textCodec.forceValidUtf8(event);

					NamebaseSite* siteEntry = namebase(Namebase::Site).insertSite(
						site.empty() ? mstl::string("?") : site,
						country::Unknown, (1 << 20));

					// The event date follows the event text as the same 3-byte
					// packed date the index uses at +0xbc (verified against the
					// Grenke fixture: 2026.04.01 -> 0x0fd481, the game's own
					// [EventDate] tag).
					size_t const datePos = b + 4 + evLen;
					unsigned evYear = 0, evMonth = 0, evDay = 0;
					if (datePos + 3 <= lsize)
					{
						unsigned packed = unsigned(lp[datePos])
											 | (unsigned(lp[datePos + 1]) << 8)
											 | (unsigned(lp[datePos + 2]) << 16);
						unpackDate(packed, evYear, evMonth, evDay);
						if (!Date::isValid(evYear, evMonth, evDay))
							evYear = evMonth = evDay = 0;
					}

					NamebaseEvent* entry = namebase(Namebase::Event).insertEvent(
						event, unsigned(slot), evYear, evMonth, evDay,
						event::Unknown, time::Unknown, db::event::Undetermined,
						(1 << 20), siteEntry);
					entry->site()->incrRef();
					entry->incrRef();
					m_eventMap.container().push_back(
						BaseMap::value_type(unsigned(slot), entry));

					// Source/annotator record of the same slot, at slot+0x860
					// (player area 0x400 + event area 0x460):
					//   [u32 total][u32 sourceTitleLen][sourceTitle]
					//   [u32 annotatorLen][annotator][8 zero bytes]
					// Verified against the Grenke fixture: 'playchess.com' /
					// 'ChessBase' -> [SourceTitle]/[Source], and CBase26 emits
					// the annotator tag from the same record.
					size_t const sa = 0xb8 + slot * 0x108a + 0x860;
					if (sa + 12 <= lsize)
					{
						uint32_t const total = uint32_t(lp[sa])
											| (uint32_t(lp[sa + 1]) << 8)
											| (uint32_t(lp[sa + 2]) << 16)
											| (uint32_t(lp[sa + 3]) << 24);
						uint32_t const titleLen = uint32_t(lp[sa + 4])
											| (uint32_t(lp[sa + 5]) << 8);
						if (total > 8 && total < 0x200 && titleLen < 0x100
								&& sa + 8 + titleLen + 4 <= lsize)
						{
							size_t const ap = sa + 8 + titleLen;
							uint32_t const annotatorLen = uint32_t(lp[ap])
											| (uint32_t(lp[ap + 1]) << 8);
							if (annotatorLen > 0 && annotatorLen < 0x100
									&& ap + 4 + annotatorLen <= lsize)
							{
								mstl::string annotator(
									reinterpret_cast<char const*>(lp + ap + 4), annotatorLen);
								bool ok = true;
								for (uint32_t j = 0; j < annotatorLen; ++j)
									if (lp[ap + 4 + j] < 32)
										ok = false;
								if (ok)
								{
									if (!sys::utf8::validate(annotator))
										textCodec.forceValidUtf8(annotator);
									Namebase& annotations = namebase(Namebase::Annotator);
									NamebaseEntry* aentry = annotations.insert(
										annotator, unsigned(slot), (1 << 20));
									aentry->incrRef();
									m_annotatorMap.container().push_back(
										BaseMap::value_type(unsigned(slot), aentry));
								}
							}
						}
					}
				}

				m_eventMap.qsort();
				m_annotatorMap.qsort();
			}
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
		unsigned char const* rec = cbh + (size_t(k) + 1) * recordSize;
		GameInfo& info = infoList.push_back();

		info.m_gameOffset = unsigned(readLE32(rec + 0x08));
		info.m_eco = ecoShortCode(m_ecoValues[k]);
		info.m_player[color::White] = getPlayer(unsigned(readLE32(rec + 0x18) & 0xffffffu));
		info.m_player[color::Black] = getPlayer(unsigned(readLE32(rec + 0x20) & 0xffffffu));
		info.m_event = getEvent(unsigned(readLE32(rec + 0x28) & 0xffffffu));
		info.m_annotator = getAnnotator(unsigned(readLE32(rec + 0x28) & 0xffffffu));

		// round/subround: validated against the source PGN on 352
		// date-verified games (round 7.5 -> 0x5a = 7, 0x5c = 5; scid-code
		// GLM pass, 2026-09-07).
		info.m_round = rec[0x5a];
		info.m_subround = rec[0x5c];

		unsigned char f58 = rec[0x58];
		switch (f58 & 3)
		{
			case 0:  info.m_result = result::Black; break;
			case 1:  info.m_result = result::Draw; break;
			case 2:  info.m_result = result::White; break;
			default: info.m_result = result::Unknown; break;
		}

		{
			// date: 3-byte packed at @0xBC (LE): day(5)|month(4)<<5|year(12)<<9
			unsigned p24 = rec[0xBC]
						 | (rec[0xBD] << 8)
						 | (rec[0xBE] << 16);
			unsigned dday = p24 & 0x1f;
			unsigned dmon = (p24 >> 5) & 0xf;
			unsigned dyr = (p24 >> 9) & 0xfff;
			info.m_dateYear = Date::encodeYearTo10Bits(dyr);
			info.m_dateMonth = dmon;
			info.m_dateDay = dday;
		}

		// Elo: plain u16 LE, White @0x60, Black @0x70 -- offsets, evidence
		// and empirical validation: cb2_elo.h (shared with 2cbh2pgn).
		{
			unsigned whiteElo = readIndexElo(rec, color::White);
			unsigned blackElo = readIndexElo(rec, color::Black);

			if (rating::isValid(whiteElo))
			{
				info.m_pd[color::White].elo = whiteElo;
				if (info.m_player[color::White] != m_illegalPlayer)
					info.m_player[color::White]->setElo(whiteElo);
			}

			if (rating::isValid(blackElo))
			{
				info.m_pd[color::Black].elo = blackElo;
				if (info.m_player[color::Black] != m_illegalPlayer)
					info.m_player[color::Black]->setElo(blackElo);
			}
		}

		// record length: peek the .2cbg record header
		m_gameStream.clear();
		m_gameStream.seekg(info.m_gameOffset + 8, mstl::ios_base::beg);
		unsigned char h[22];
		if (m_gameStream.read(reinterpret_cast<char*>(h), sizeof(h)))
		{
			info.setGameRecordLength(readLE32(h));
			if (readLE16(h + 16) == 2 && readLE16(h + 18) == Move16_None)
			{
				unsigned position = readLE16(h + 20);
				if (position < 960)
					info.m_positionId = position ? position : 960;
			}
		}
	}

	// Restore namebase consistency: the lazy player/event/annotator/site
	// insertions above inserted entries with frequency 0 and the reference
	// counts are bumped while the index is read.  Update every base
	// unconditionally: Namebases::update() skips bases still marked
	// consistent, and an early update (before the index loop) left the player
	// base consistent with used() == 0, which made the database summary
	// report "players: 0" for a database whose games were all loaded lazily.
	// The explicit update is what keeps a Chess960-only database at the right
	// player count.
	{
		Namebase* bases[] =
		{
			&namebase(Namebase::Player),  &namebase(Namebase::Site),
			&namebase(Namebase::Event),   &namebase(Namebase::Annotator),
		};
		for (unsigned i = 0; i < sizeof(bases)/sizeof(bases[0]); ++i)
		{
			bases[i]->update();
			bases[i]->setNextId(1u << 20);
		}
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


/// The per-game annotator: CBase26 keeps it in the source record of the event
/// slot (slot+0x860 of the .2lid), so it is resolved through the game's event
/// id.  Falls back to the namebase's empty annotator.
NamebaseEntry*
Codec::getAnnotator(unsigned id)
{
	BaseMap::iterator p = m_annotatorMap.find(id);
	NamebaseEntry* entry;

	if (p != m_annotatorMap.end())
	{
		entry = p->second;
	}
	else
	{
		entry = namebase(Namebase::Annotator).emptyAnnotator();
	}

	entry->incrRef();
	return entry;
}


void
Codec::applyEcoTag(TagSet& tags, unsigned gameIndex)
{
	// ECO from the index key @0x80 (see doOpen); the key keeps ChessBase's
	// sub-variation number in its low seven bits.
	char buf[16];

	if (gameIndex < m_ecoValues.size()
		&& formatEcoKey(m_ecoValues[gameIndex], buf, sizeof(buf)))
	{
		tags.set(tag::Eco, buf);
	}
}


bool
Codec::loadAnnotationItems(unsigned gameIndex, mstl::vector<CbaItem>& items)
{
	if (m_annotationOffsets.empty() || gameIndex >= m_annotationOffsets.size())
		return false;

	uint32_t cbaOff = m_annotationOffsets[gameIndex];

	if (!m_annotationStream.is_open() || cbaOff == 0x7fffffffu)
		return false;

	m_annotationStream.clear();
	m_annotationStream.seekg(cbaOff, mstl::ios_base::beg);

	unsigned char hdr[0x1a];
	if (!m_annotationStream.read(reinterpret_cast<char*>(hdr), sizeof(hdr))
			|| readLE64(hdr) != 0x1122334455667788ull)
		return false;

	// As in .2cbg, the data field starts at +0x10 with the 8-byte sub-field
	// and the 2-byte type word, so the item stream starts at +0x1a.
	uint32_t const cbaDataSize = readLE32(hdr + 0x08);
	if (cbaDataSize < 10)
		return false;
	uint32_t const adSize = cbaDataSize;
	mstl::string adata(adSize, '\0');

	if (adSize > 0 && !m_annotationStream.read(adata.begin(), adSize))
		return false;

	return parseCbaItems(
		reinterpret_cast<unsigned char const*>(adata.data()), adSize, items);
}


save::State
Codec::doDecoding(	db::Consumer& consumer,
						TagSet& tags,
						GameInfo const& info,
						unsigned gameIndex)
{
	GameRecord rec;
	if (!readGameRecord(m_gameStream, info.gameOffset(), rec))
		return save::DecodingFailed;
	unsigned char const* moves = reinterpret_cast<unsigned char const*>(rec.data.data());
	uint32_t moveSize = rec.size;
	Board startBoard;
	if (!prepareGame(rec.type, moves, moveSize, startBoard, tags))
		return save::UnsupportedVariant;
	applyEcoTag(tags, gameIndex);
	if (!consumer.startGame(tags))
		return save::UnsupportedVariant;
	consumer.startMoveSection();

	mstl::vector<CbaItem> items;
	bool annotationsOk = loadAnnotationItems(gameIndex, items);

	unsigned plyCount = 0;

	if (!walkGame(consumer, moves, moveSize, items, annotationsOk, plyCount))
		return consumer.skipGame(tags);

	char buf[32];
	::snprintf(buf, sizeof(buf), "%u", plyCount);
	tags.set(tag::PlyCount, buf);

	consumer.finishMoveSection(result::fromString(tags.value(tag::Result)));
	return consumer.finishGame(tags);
}


void
Codec::doDecoding(GameData& data, GameInfo& info, unsigned gameIndex, mstl::string* encoding)
{
	// The GUI's Database::loadGame(index, Game&) path: build the move
	// tree through a VarConsumer and install it into the GameData.
	GameRecord rec;

	if ( !readGameRecord(m_gameStream, info.gameOffset(), rec)
			|| rec.size == 0)
	{
		throw DecodingFailedException("2CBH: cannot decode game %u", gameIndex);
	}

	TagSet tags;
	info.setupTags(tags, variant::Normal);
	applyEcoTag(tags, gameIndex);
	unsigned char const* moves = reinterpret_cast<unsigned char const*>(rec.data.data());
	uint32_t moveSize = rec.size;
	Board startBoard;
	if (!prepareGame(rec.type, moves, moveSize, startBoard, tags))
		throw DecodingFailedException("2CBH: unsupported start position in game %u", gameIndex);
	VarConsumer consumer(startBoard);


	if (!consumer.startGame(tags))
		throw DecodingFailedException("2CBH: cannot decode game %u", gameIndex);

	consumer.startMoveSection();

	mstl::vector<CbaItem> items;
	bool annotationsOk = loadAnnotationItems(gameIndex, items);

	unsigned plyCount = 0;

	if (!walkGame(consumer, moves, moveSize, items, annotationsOk, plyCount))
	{
		throw DecodingFailedException("2CBH: cannot decode game %u", gameIndex);
	}

	char buf[32];
	::snprintf(buf, sizeof(buf), "%u", plyCount);
	tags.set(tag::PlyCount, buf);

	consumer.finishMoveSection(result::fromString(tags.value(tag::Result)));
	consumer.finishGame(tags);

	// Install the decoded tree.  The GameData header node must keep its
	// identity (the Game's cursor may point at it), so graft the chain:
	// drop any existing content, then splice in the decoded line.
	MoveNode* tree = consumer.release();
	delete data.m_startNode->removeNext();
	data.m_startNode->setNext(tree->removeNext());
	delete tree;
	data.m_startBoard = startBoard;
	info.m_positionId = startBoard.computeIdn(variant::Normal);
	data.m_tags = tags;
	info.m_plyCount = mstl::min(GameInfo::MaxPlyCount, plyCount);
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
	strm.seekg(0, mstl::ios_base::beg);
	unsigned char header[24];
	IndexLayout layout;
	if (size < 0 || !strm.read(reinterpret_cast<char*>(header), sizeof(header))
			|| !readIndexLayout(header, sizeof(header), uint64_t(size), layout)
			|| layout.gameCount > 0x7fffffffu)
		return false;
	numGames = int(layout.gameCount);
	type = db::type::Unspecific;
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
