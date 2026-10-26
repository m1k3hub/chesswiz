// ======================================================================
// 2cbh2pgn -- headless converter: ChessBase 17+ (2CBH/2CBG) -> PGN.
//
// Reads a .2cbh database (index + .2cbg game data + .2lid namebase +
// .2cba annotations) and writes PGN.  Games are emitted through the
// codec's variation walk (db::cb2::walkGameRaw): mainline + nested RAV
// variations + comments/NAGs in document order, via db::PgnWriter.
//
// Limitations (see docs/formats/2CBH_FORMAT_DESIGN.md):
//   - standard chess (type 1) and Chess960 starts (type 2) are supported
//
// Usage: 2cbh2pgn <prefix> <out.pgn> [maxGames]
// ======================================================================

#include "2cbh_move16.h"
#include "2cbh_annotations.h"
#include "cb2_codec.h"
#include "cb2_elo.h"
#include "cb2_index.h"

#include <string>
#include <vector>
#include "db_common.h"

#include "db_board.h"
#include "db_pgn_writer.h"
#include "db_tag_set.h"
#include "db_var_consumer.h"

#include "sys_utf8_codec.h"
#include "m_fstream.h"
#include "m_string.h"

#include <string>
#include <vector>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <tcl.h>

// sys::utf8::Codec resolves encodings through the Tcl encoding engine,
// so a live interpreter is required (same pattern as cdb2sci).
namespace tcl { namespace bits { Tcl_Interp* interp = nullptr; } }


namespace
{

uint32_t readLE32(unsigned char const* p)
{
   return uint32_t(p[0]) | (uint32_t(p[1]) << 8)
        | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}

uint16_t readLE16(unsigned char const* p)
{
   return uint16_t(p[0] | (p[1] << 8));
}

uint64_t readLE64(unsigned char const* p)
{
   uint64_t v = 0;
   for (int i = 7; i >= 0; --i)
      v = (v << 8) | p[i];
   return v;
}

bool loadFile(char const* name, std::string& data)
{
   FILE* fh = fopen(name, "rb");
   if (!fh)
      return false;
   fseek(fh, 0, SEEK_END);
   long sz = ftell(fh);
   fseek(fh, 0, SEEK_SET);
   data.resize(sz);
   bool ok = fread(&data[0], 1, sz, fh) == (size_t)sz;
   fclose(fh);
   return ok;
}

// Walk the .2lid namebase: player records end with the signature
// ff ff ff ff 08 00 00 00 ff ff ff ff; the record's 0-based ordinal among
// ALL signature slots equals the player ID used in the .2cbh index.
// Slot layout: [total][lastLen][last][firstLen][first][tail 20 bytes].
// Event/site namebase: the .2lid is a fixed-slot array (stride 0x108a,
// first slot at 0xb8) whose slots carry an event pair at +0x400:
//   [u32 x][u16 siteLen][site][u16 pad][u16 evLen][event][pad][u32 year]
// The event id stored in the game index (@0x28, 3 bytes LE) is the slot
// ordinal.  Reverse-engineered in the scid-code project (GLM pass,
// 2026-09-07); validated against the source PGN (game 0 ->
// 'Munchen Open'/'Munchen open'); ~99.5% of games resolve (deleted slots
// stay unnamed).  See docs/formats/2CBH_FORMAT_DESIGN.md section 3.8.7.
void loadEvents(unsigned char const* lid, size_t size,
                mstl::vector<std::string>& out_events,
                mstl::vector<std::string>& out_sites)
{
   if (size < 0xb8 + 0x108a)
      return;

   size_t const nslots = (size - 0xb8) / 0x108a;

   out_events.resize(nslots);
   out_sites.resize(nslots);

   for (size_t slot = 0; slot < nslots; ++slot)
   {
      size_t a = 0xb8 + slot * 0x108a + 0x400;
      if (a + 8 > size)
         break;

      uint32_t siteLen = uint32_t(lid[a + 4]) | (uint32_t(lid[a + 5]) << 8);
      if (siteLen > 80 || a + 8 + siteLen + 4 > size)
         continue;

      std::string site(reinterpret_cast<char const*>(lid + a + 8), siteLen);
      bool text = true;
      for (uint32_t j = 0; j < siteLen; ++j)
         if (static_cast<unsigned char>(site[j]) < 32)
            text = false;
      if (!text)
         continue;

      size_t b = a + 8 + siteLen;
      uint32_t evLen = uint32_t(lid[b]) | (uint32_t(lid[b + 1]) << 8);
      if (evLen == 0 || evLen > 90 || b + 4 + evLen > size)
         continue;

      std::string event(reinterpret_cast<char const*>(lid + b + 4), evLen);
      for (uint32_t j = 0; j < evLen; ++j)
         if (static_cast<unsigned char>(event[j]) < 32)
            text = false;
      if (!text)
         continue;

      // .2lid text is UTF-8 (data-verified: c3 b8 = oe, c3 bc = ue,
      // e4 b8 ad = CJK); pass through unchanged.
      out_sites[slot] = site;
      out_events[slot] = event;
   }
}


void loadNames(unsigned char const* lid, size_t size,
               mstl::vector<std::string>& out_names)
{
   static unsigned char const sig[12] = {
      0xff, 0xff, 0xff, 0xff, 0x08, 0x00, 0x00, 0x00,
      0xff, 0xff, 0xff, 0xff };

   size_t pos = 0xb8;
   unsigned ordinal = 0;
   while (ordinal < 200000u)
   {
      size_t i = pos;
      while (i + 12 <= size)
      {
         if (::memcmp(lid + i, sig, 12) == 0)
            break;
         ++i;
      }
      if (i + 12 > size)
         break;
      size_t end = i + 12;
      // the record starts at end - total; total is stored at the start
      size_t lo = (i + 8 > 320) ? i + 8 - 320 : 0;
      for (size_t start = i + 4; start-- > lo;)
      {
         uint32_t total = uint32_t(lid[start])
                        | (uint32_t(lid[start+1]) << 8)
                        | (uint32_t(lid[start+2]) << 16)
                        | (uint32_t(lid[start+3]) << 24);
         if (start + total != end || total <= 20 || total >= 320)
             continue;
         uint32_t llen = uint32_t(lid[start+4]) | (uint32_t(lid[start+5]) << 8);
         if (llen == 0 || llen >= 80 || start + 8 + llen + 4 > size)
             continue;
         size_t fo = start + 8 + llen;
         uint32_t flen = uint32_t(lid[fo]) | (uint32_t(lid[fo+1]) << 8);
         if (flen >= 80 || fo + 4 + flen != end - 20)
             continue;
         // Names are UTF-8; reject controls, not non-ASCII letters.
         bool printable = true;
         for (uint32_t j = 0; j < llen; ++j)
         {
            unsigned char ch = lid[start + 8 + j];
            if (ch < 32)
               printable = false;
         }
         if (printable && ordinal < out_names.size())
         {
            std::string last(reinterpret_cast<char const*>(&lid[start + 8]), llen);
            std::string first(reinterpret_cast<char const*>(&lid[fo + 4]), flen);
            out_names[ordinal] = first.empty() ? last
                                               : last + ", " + first;
         }
         break;
      }
      ++ordinal;
      pos = end;
   }
}

} // anonymous namespace

int main(int argc, char* argv[])
{
   tcl::bits::interp = ::Tcl_CreateInterp();
   db::Board::initialize();
   if (argc < 3)
   {
      ::fprintf(stderr, "usage: 2cbh2pgn <prefix> <output.pgn> [maxGames]\n");
      return 1;
   }

   std::string prefix(argv[1]);
   if (prefix.size() > 5 && prefix.substr(prefix.size() - 5) == ".2cbh")
      prefix.erase(prefix.size() - 5);
   unsigned maxGames = (argc > 3) ? unsigned(::atoi(argv[3])) : 0u;

   std::string cbhData;
   std::string cbgData;
   if (!loadFile((prefix + ".2cbh").c_str(), cbhData))
   {
      ::fprintf(stderr, "cannot read %s.2cbh\n", prefix.c_str());
      return 1;
   }
   if (!loadFile((prefix + ".2cbg").c_str(), cbgData))
   {
      ::fprintf(stderr, "cannot read %s.2cbg\n", prefix.c_str());
      return 1;
   }
   std::string cbaData;
   bool haveCba = loadFile((prefix + ".2cba").c_str(), cbaData);
   if (!haveCba)
      ::fprintf(stderr, "# no .2cba annotations file, comments disabled\n");

   // player names from the .2lid namebase (ID == slot ordinal)
   mstl::vector<std::string> names(200000u);
   mstl::vector<std::string> eventNames;
   mstl::vector<std::string> siteNames;
   {
      std::string lidData;
      if (loadFile((prefix + ".2lid").c_str(), lidData))
      {
         loadNames(reinterpret_cast<unsigned char const*>(lidData.c_str()),
                   lidData.size(), names);
         loadEvents(reinterpret_cast<unsigned char const*>(lidData.c_str()),
                    lidData.size(), eventNames, siteNames);
         unsigned named = 0;
         for (unsigned i = 0; i < names.size(); ++i)
            if (!names[i].empty())
               ++named;
         unsigned namedEvents = 0;
         for (unsigned i = 0; i < eventNames.size(); ++i)
            if (!eventNames[i].empty())
               ++namedEvents;
         ::fprintf(stderr, "# namebase: %u of %u slots named, %u event slots (lidData=%zu bytes)\n",
                   named, unsigned(names.size()), namedEvents, lidData.size());
      }
   }

   unsigned char const* cbh = (unsigned char const*)cbhData.c_str();
   unsigned char const* cbg = (unsigned char const*)cbgData.c_str();
   db::cb2::IndexLayout layout;
   if (!db::cb2::readIndexLayout(cbh, cbhData.size(), cbhData.size(), layout)) {
      ::fprintf(stderr, "invalid or truncated 2CBH index\n"); return 1;
   }
   unsigned const recordSize = layout.recordSize;
   unsigned const gameCount = layout.gameCount;
   if (maxGames == 0 || maxGames > gameCount)
      maxGames = gameCount;

   mstl::ofstream outStream(argv[2], mstl::ios_base::out);
   if (!outStream)
   {
      ::fprintf(stderr, "cannot create %s\n", argv[2]);
      return 1;
   }

   // PGN emission through the codec's variation walk: mainline + nested
   // RAVs + comments/NAGs in document order.  Names are UTF-8
   // pass-through from the .2lid, so the PGN encoding is UTF-8.
   unsigned const pgnFlags =	db::Writer::Flag_Include_Variations
										| db::Writer::Flag_Include_Comments
										| db::Writer::Flag_Include_Annotation;
   db::PgnWriter writer(	db::format::ChessBase2,
   								outStream,
									sys::utf8::Codec::utf8(),
									db::PgnWriter::Unix,
									pgnFlags);
   writer.start();

   unsigned converted = 0;
   unsigned skipped = 0;
   unsigned failed = 0;
   unsigned annotationGames = 0;

   // Each .2cbh index record points to its .2cbg record via the offset
   // at 0x08 (the .2cbg itself is in insertion order, which differs from
   // the index order; deleted games leave unreferenced records).
   for (unsigned k = 0; k < maxGames; ++k)
   {
      unsigned long cbgOff = (unsigned long) readLE32(cbh + (size_t(k) + 1) * recordSize + 0x08);
      if (cbgOff + 0x1a > cbgData.size()) {
         ++failed;
         continue;
      }
      uint64_t magic = 0;
      for (int i = 7; i >= 0; --i)
         magic = (magic << 8) | cbg[cbgOff + i];
      if (magic != 0x1122334455667788ull)
      {
         ++skipped;
         continue;
      }
      uint32_t dataSize = readLE32(cbg + cbgOff + 0x08);
      uint16_t type = readLE16(cbg + cbgOff + 0x18);
      unsigned char const* data = cbg + cbgOff + 0x1a;

      if (dataSize > cbgData.size() - cbgOff - 0x1a)
      {
         ++failed;
         continue;
      }

      // .2cba annotation items (comments/NAGs), keyed by document walk
      // position; db::cb2::walkGameRaw places them, also inside RAVs.
      mstl::vector<db::cb2::CbaItem> items;
      bool annotationsOk = false;
      unsigned long cbaOff = (unsigned long) readLE32(cbh + (size_t(k) + 1) * recordSize + 0x10);
      if (haveCba && cbaOff != 0x7fffffffu && cbaOff + 0x1a < cbaData.size())
      {
         unsigned char const* arec = (unsigned char const*) cbaData.c_str() + cbaOff;
         if (readLE64(arec) == 0x1122334455667788ull)
         {
            uint32_t const adSize = readLE32(arec + 0x08);
            if (cbaOff + 0x1a + adSize <= cbaData.size()
                  && db::cb2::parseCbaItems(arec + 0x1a, adSize, items)
                  && !items.empty())
               annotationsOk = true;
         }
      }
      if (annotationsOk)
         ++annotationGames;

      unsigned long wid = readLE32(cbh + (size_t(k) + 1) * recordSize + 0x18) & 0xffffffu;
      unsigned long bid = readLE32(cbh + (size_t(k) + 1) * recordSize + 0x20) & 0xffffffu;
      // event id: 3 bytes LE @0x28 = .2lid slot ordinal (see loadEvents)
      unsigned long eid = readLE32(cbh + (size_t(k) + 1) * recordSize + 0x28) & 0xffffffu;
      // round/subround: u8 @0x5a, u8 @0x5c ('7.5' style; validated on 352
      // date-verified games against the source PGN, scid-code GLM pass)
      unsigned roundNo = cbh[(size_t(k) + 1) * recordSize + 0x5a];
      unsigned subRound = cbh[(size_t(k) + 1) * recordSize + 0x5c];
      // date: 3 bytes at @0xBC packed as day(5) | month(4) << 5 | year(12) << 9
      unsigned p24 = cbh[(size_t(k) + 1) * recordSize + 0xBC]
                   | (cbh[(size_t(k) + 1) * recordSize + 0xBD] << 8)
                   | (cbh[(size_t(k) + 1) * recordSize + 0xBE] << 16);
      unsigned dday = p24 & 0x1f;
      unsigned dmon = (p24 >> 5) & 0xf;
      unsigned dyear = (p24 >> 9) & 0xfff;
      char dateBuf[16] = "????.??.??";
      if (dday > 0)
         ::snprintf(dateBuf, sizeof(dateBuf), "%04d.%02d.%02d", dyear, dmon, dday);
      else if (dmon > 0)
         ::snprintf(dateBuf, sizeof(dateBuf), "%04d.%02d.??", dyear, dmon);
      else if (dyear > 0)
         ::snprintf(dateBuf, sizeof(dateBuf), "%04d.??.??", dyear);
      std::string wname = (wid < names.size() && !names[wid].empty())
                        ? names[wid]
                        : ("Player " + std::to_string(wid));
      std::string bname = (bid < names.size() && !names[bid].empty())
                        ? names[bid]
                        : ("Player " + std::to_string(bid));
      // result: byte 0x58 low 2 bits (0 = 0-1, 1 = 1/2-1/2, 2 = 1-0)
      unsigned char f58 = cbh[(size_t(k) + 1) * recordSize + 0x58];
      char const* resultStr = "*";
      switch (f58 & 3)
      {
         case 0:  resultStr = "0-1"; break;
         case 1:  resultStr = "1/2-1/2"; break;
         case 2:  resultStr = "1-0"; break;
         default: break;
      }
      // ECO: index @0x80 = 128 * (base + 1), base = 0-based ECO code
      // (A00 = 0 .. E99 = 499); low 7 bits unused.  Verified on 57146
      // identity-matched twin pairs (see docs/formats/2CBH_FORMAT_DESIGN.md section
      // 2.3).  ChessBase's sub-letter suffix is not stored in the index.
      char ecoBuf[8] = "";
      {
         unsigned eco16 = readLE16(cbh + (size_t(k) + 1) * recordSize + 0x80);
         if (eco16 >= 128u && eco16 <= 64000u && (eco16 & 127u) == 0u)
         {
            unsigned base = (eco16 >> 7) - 1u;
            char const letter = "ABCDE"[base / 100u];
            ::snprintf(ecoBuf, sizeof(ecoBuf), "%c%02u", letter, base % 100u);
         }
      }
      // Elo: plain u16 LE, White @0x60, Black @0x70 -- offsets, evidence
      // and empirical validation: cb2_elo.h (shared with cb2::Codec).
      unsigned char const* eloRec = cbh + (size_t(k) + 1) * recordSize;
      unsigned whiteElo = db::cb2::readIndexElo(eloRec, db::color::White);
      unsigned blackElo = db::cb2::readIndexElo(eloRec, db::color::Black);

      db::TagSet tags;
      std::string const eventStr = (eid < eventNames.size() && !eventNames[eid].empty())
                                 ? eventNames[eid] : "?";
      std::string const siteStr = (eid < siteNames.size() && !siteNames[eid].empty())
                                ? siteNames[eid] : "?";
      tags.set(db::tag::Event, mstl::string(eventStr.c_str()));
      tags.set(db::tag::Site, mstl::string(siteStr.c_str()));
      tags.set(db::tag::Date, mstl::string(dateBuf));
      if (roundNo > 0)
      {
         char roundBuf[16];
         if (subRound > 0)
            ::snprintf(roundBuf, sizeof(roundBuf), "%u.%u", roundNo, subRound);
         else
            ::snprintf(roundBuf, sizeof(roundBuf), "%u", roundNo);
         tags.set(db::tag::Round, mstl::string(roundBuf));
      }
      else
         tags.set(db::tag::Round, "?");
      tags.set(db::tag::White, mstl::string(wname.c_str()));
      tags.set(db::tag::Black, mstl::string(bname.c_str()));
      tags.set(db::tag::Result, mstl::string(resultStr));
      if (ecoBuf[0])
         tags.set(db::tag::Eco, mstl::string(ecoBuf));
      if (db::rating::isValid(whiteElo))
         tags.set(db::tag::WhiteElo, whiteElo);
      if (db::rating::isValid(blackElo))
         tags.set(db::tag::BlackElo, blackElo);

      db::Board startBoard;
      if (!db::cb2::prepareGame(type, data, dataSize, startBoard, tags))
      {
         ++failed;
         continue;
      }

      // First pass: validate the walk so a desync cannot produce a
      // truncated PGN game (the old flat converter skipped these too).
      unsigned plyCount = 0;
      {
         db::VarConsumer validator(startBoard);
         if (   !validator.startGame(tags)
             || !db::cb2::walkGameRaw( validator, data, dataSize,
                                       items, annotationsOk, plyCount))
         {
            ++failed;
            continue;
         }
         validator.finalizeGame();
      }

      // Second pass: emit through the PGN writer (variations included).
      if (!writer.startGame(tags))
      {
         ++failed;
         continue;
      }
      writer.startMoveSection();
      bool const emitted = db::cb2::walkGameRaw(  writer, data, dataSize,
                                                  items, annotationsOk, plyCount);
      tags.set(db::tag::PlyCount, plyCount);
      writer.finishMoveSection(db::result::fromString(resultStr));
      writer.finishGame(tags);
      writer.finalizeGame();   // pop the game line: next startGame asserts finalized()
      if (!emitted)
      {
         ++failed;
         continue;
      }
      ++converted;
   }

   writer.finish();
   ::printf("converted=%u skipped=%u failed=%u of %u"
            "\n# annotations: games-with-annotation-items=%u\n",
            converted, skipped, failed, maxGames, annotationGames);
   return failed ? 1 : 0;
}
