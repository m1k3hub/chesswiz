// ======================================================================
// 2cbh2pgn -- headless converter: ChessBase 17+ (2CBH/2CBG) -> PGN.
//
// Reads a .2cbh database (index + .2cbg game data), decodes every
// game's mainline through the embedded Move16 table and writes PGN.
//
// Limitations (see 2CBH_FORMAT_DESIGN.md):
//   - player/event names are not yet resolved (the .2lgd ID->offset
//     mapping is not decoded yet); placeholders are emitted
//   - only standard-chess games (record type 1) are converted
//
// Usage: 2cbh2pgn <prefix> <out.pgn> [maxGames]
// ======================================================================

#include "2cbh_move16.h"

#include <string>
#include <vector>
#include "db_common.h"

#include "db_board.h"
#include "db_move.h"

#include "m_string.h"
#include "m_ifstream.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

using db::Board;
using db::Move;
using namespace db::piece;
using namespace db::variant;


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

bool loadFile(char const* name, mstl::string& data)
{
   mstl::ifstream strm(name, mstl::ios_base::in | mstl::ios_base::binary);
   if (!strm)
      return false;
   strm.seekg(0, mstl::ios_base::end);
   long size = strm.tellg();
   strm.seekg(0, mstl::ios_base::beg);
   data.resize(size);
   if (size > 0)
   {
      strm.read(data.begin(), size);
   }
   return true;
}

// Walk the .2lid namebase: player records end with the signature
// ff ff ff ff 08 00 00 00 ff ff ff ff; the record's 0-based ordinal among
// ALL signature slots equals the player ID used in the .2cbh index.
// Slot layout: [total][lastLen][last][firstLen][first][tail 20 bytes].
void loadNames(unsigned char const* lid, size_t size,
               std::vector<std::string>& out_names)
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
         // valid record: read the name if ASCII
         bool ascii = true;
         for (uint32_t j = 0; j < llen; ++j)
         {
            unsigned char ch = lid[start + 8 + j];
            if (!(32 <= ch && ch < 127))
               ascii = false;
         }
         if (ascii && ordinal < out_names.size())
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

// Move16 squares are file-major (sq = file*8 + rank), scidb is rank-major.// Move16 squares are file-major (sq = file*8 + rank), scidb is rank-major.
inline unsigned toScidbSquare(unsigned m16sq)
{
   return ((m16sq & 7) << 3) | (m16sq >> 3);
}

// Move16 piece numbering -> scidb piece::ID (1=pawn .. 6=king)
unsigned toScidbPiece(unsigned m16piece)
{
   switch (m16piece & 7)
   {
      case 1:  return King;
      case 2:  return Queen;
      case 3:  return Knight;
      case 4:  return Bishop;
      case 5:  return Rook;
      case 6:  return Pawn;
      default: return db::piece::None;
   }
}

} // anonymous namespace

int main(int argc, char* argv[])
{
   Board::initialize();
   if (argc < 3)
   {
      ::fprintf(stderr, "usage: 2cbh2pgn <prefix> <output.pgn> [maxGames]\n");
      return 1;
   }

   mstl::string prefix(argv[1]);
   if (prefix.size() > 5 && prefix.substr(prefix.size() - 5) == ".2cbh")
      prefix.erase(prefix.size() - 5);
   unsigned maxGames = (argc > 3) ? unsigned(::atoi(argv[3])) : 0u;

   mstl::string cbhData;
   mstl::string cbgData;
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

   // player names from the .2lid namebase (ID == slot ordinal)
   std::vector<std::string> names(200000u);
   {
      mstl::string lidData;
      if (loadFile((prefix + ".2lid").c_str(), lidData))
      {
         loadNames(reinterpret_cast<unsigned char const*>(lidData.data()),
                   lidData.size(), names);
         unsigned named = 0;
         for (unsigned i = 0; i < names.size(); ++i)
            if (!names[i].empty())
               ++named;
         ::fprintf(stderr, "# namebase: %u of %u slots named (lidData=%zu bytes)\n",
                   named, unsigned(names.size()), lidData.size());
      }
   }

   unsigned char const* cbh = reinterpret_cast<unsigned char const*>(cbhData.data());
   unsigned char const* cbg = reinterpret_cast<unsigned char const*>(cbgData.data());

   unsigned const recordSize = readLE16(cbh + 0x0a);
   unsigned const gameCount = unsigned(cbhData.size() / recordSize) - 256u;
   if (maxGames == 0 || maxGames > gameCount)
      maxGames = gameCount;

   ::FILE* out = ::fopen(argv[2], "wb");
   if (!out)
   {
      ::fprintf(stderr, "cannot create %s\n", argv[2]);
      return 1;
   }

   unsigned converted = 0;
   unsigned skipped = 0;
   unsigned failed = 0;

   // Each .2cbh index record points to its .2cbg record via the offset
   // at 0x08 (the .2cbg itself is in insertion order, which differs from
   // the index order; deleted games leave unreferenced records).
   for (unsigned k = 0; k < maxGames; ++k)
   {
      unsigned long cbgOff = (unsigned long) readLE32(cbh + (256u + k) * recordSize + 0x08);
      if (cbgOff + 0x1a > cbgData.size())
         break;
      uint64_t magic = 0;
      for (int i = 7; i >= 0; --i)
         magic = (magic << 8) | cbg[cbgOff + i];
      if (magic != 0x1122334455667788ull)
      {
         ++skipped;
         continue;
      }
      uint32_t dataSize = readLE32(cbg + cbgOff + 0x08);
      uint32_t extraSize = readLE32(cbg + cbgOff + 0x0c);
      uint16_t type = readLE16(cbg + cbgOff + 0x18);
      unsigned char const* data = cbg + cbgOff + 0x1a;

      if (type != 1)
      {
         ++skipped;
         continue;
      }

      Board board(Board::standardBoard(Normal));

      mstl::string movetext;
      unsigned nShorts = dataSize / 2u;
      unsigned moves = 0;
      bool ok = true;

      for (unsigned j = 0; j < nShorts && ok; ++j)
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
         {
            ++failed;
            ok = false;
            break;
         }

         unsigned from = toScidbSquare(d.from);
         unsigned to = toScidbSquare(d.to);
         unsigned promoType = 0;
         bool isPromotion = false;

         if (d.hasWord1
             && (d.piece == 6 || d.piece == 14)
             && d.word1From == d.to
             && d.word1To == d.to)
         {
            promoType = toScidbPiece(d.word1Piece);
            isPromotion = true;
         }

         // find the matching legal move generated by the board (this
         // gets castling/ep/double-push flags right, unlike manual
         // move construction)
         Move move;
         {
            db::MoveList legalMoves;
            board.generateMoves(Normal, legalMoves);
            board.filterLegalMoves(legalMoves, Normal);
            // ChessBase encodes castling as king e1->g1; scidb uses the
            // internal Chess960 representation (king to the rook square),
            // so also accept the rook square from the second descriptor.
            unsigned to2 = (d.hasWord1
                            && (d.word1Piece == 5 || d.word1Piece == 13))
                           ? toScidbSquare(d.word1From) : to;
            bool found = false;
            for (unsigned mi = 0; mi < legalMoves.size(); ++mi)
            {
               Move const& m = legalMoves[mi];
               if (m.from() != from || (m.to() != to && m.to() != to2))
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
            {
               ++failed;
               ok = false;
               break;
            }
         }

         board.prepareForPrint(move, Normal, Board::ExternalRepresentation);
         mstl::string san;
         move.printSAN(san, db::protocol::Standard, db::encoding::Latin1);

         if (moves % 2 == 0)
         {
            char buf[16];
            ::sprintf(buf, "%u. ", moves / 2 + 1);
            movetext += buf;
         }
         movetext += san;
         movetext += ' ';
         ++moves;

         board.doMove(move, Normal);
      }

      cbgOff += 16 + dataSize + extraSize + 18;
      if (!ok)
         continue;
      ++converted;

      unsigned long wid = readLE32(cbh + (256u + k) * recordSize + 0x18) & 0xffffffu;
      unsigned long bid = readLE32(cbh + (256u + k) * recordSize + 0x20) & 0xffffffu;
      std::string wname = (wid < names.size() && !names[wid].empty())
                        ? names[wid]
                        : ("Player " + std::to_string(wid));
      std::string bname = (bid < names.size() && !names[bid].empty())
                        ? names[bid]
                        : ("Player " + std::to_string(bid));
      // result: byte 0x58 low 2 bits (0 = 0-1, 1 = 1/2-1/2, 2 = 1-0)
      unsigned char f58 = cbh[(256u + k) * recordSize + 0x58];
      char const* result = "*";
      switch (f58 & 3)
      {
         case 0:  result = "0-1"; break;
         case 1:  result = "1/2-1/2"; break;
         case 2:  result = "1-0"; break;
         default: break;
      }
      ::fprintf(out,
                "[Event \"?\"]\n"
                "[Site \"?\"]\n"
                "[Date \"????.??.??\"]\n"
                "[Round \"?\"]\n"
                "[White \"%s\"]\n"
                "[Black \"%s\"]\n"
                "[Result \"%s\"]\n\n",
                wname.c_str(), bname.c_str(), result);
      ::fprintf(out, "%s%s\n\n", movetext.c_str(), result);
   }

   ::fclose(out);
   ::printf("converted=%u skipped=%u failed=%u of %u\n",
            converted, skipped, failed, maxGames);
   return failed ? 1 : 0;
}
