// ======================================================================
// 2cbh2pgn -- headless converter: ChessBase 17+ (2CBH/2CBG) -> PGN.
//
// Reads a .2cbh database (index + .2cbg game data), decodes every
// game's mainline through the embedded Move16 table and writes PGN.
//
// Limitations (see 2CBH_FORMAT_DESIGN.md):
//   - player/event names are not yet resolved (the .2lgd ID->offset
//     mapping is not decoded yet); placeholders are emitted
//   - the game result is not yet located in the format; "*" is emitted
//   - only standard-chess games (record type 1) are converted
//
// Usage: 2cbh2pgn <prefix> <out.pgn> [maxGames]
// ======================================================================

#include "2cbh_move16.h"
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

// Move16 squares are file-major (sq = file*8 + rank), scidb is rank-major.
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

   // .2cbg records are stored sequentially in index order; walk them.
   unsigned cbgOff = readLE16(cbg + 8); // header size (12)
   if (cbgOff < 12 || cbgOff > 4096)
      cbgOff = 12;

   for (unsigned k = 0; k < maxGames; ++k)
   {
      // locate record k (sequential walk)
      // (cbgOff advanced at the end of the loop body)
      if (cbgOff + 0x1a > cbgData.size())
         break;
      uint64_t magic = 0;
      for (int i = 7; i >= 0; --i)
         magic = (magic << 8) | cbg[cbgOff + i];
      if (magic != 0x1122334455667788ull)
      {
         ++skipped;
         // try to resync: scan forward for the next magic
         unsigned p = cbgOff + 1;
         while (p + 8 <= cbgData.size())
         {
            uint64_t m2 = 0;
            for (int i = 7; i >= 0; --i)
               m2 = (m2 << 8) | cbg[p + i];
            if (m2 == 0x1122334455667788ull)
               break;
            ++p;
         }
         cbgOff = p;
         --k;
         continue;
      }
      uint32_t dataSize = readLE32(cbg + cbgOff + 0x08);
      uint32_t extraSize = readLE32(cbg + cbgOff + 0x0c);
      uint16_t type = readLE16(cbg + cbgOff + 0x18);
      unsigned char const* data = cbg + cbgOff + 0x1a;

      if (type != 1)
      {
         ++skipped;
         cbgOff += 16 + dataSize + extraSize + 18;
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

      ::fprintf(out,
                "[Event \"?\"]\n"
                "[Site \"?\"]\n"
                "[Date \"????.??.??\"]\n"
                "[Round \"?\"]\n"
                "[White \"Player %lu\"]\n"
                "[Black \"Player %lu\"]\n"
                "[Result \"*\"]\n\n",
                (unsigned long) readLE32(cbh + (256u + k) * recordSize + 0x18) & 0xffffffu,
                (unsigned long) readLE32(cbh + (256u + k) * recordSize + 0x20) & 0xffffffu);
      ::fprintf(out, "%s*\n\n", movetext.c_str());
   }

   ::fclose(out);
   ::printf("converted=%u skipped=%u failed=%u of %u\n",
            converted, skipped, failed, maxGames);
   return failed ? 1 : 0;
}
