// ======================================================================
// 2cbh_probe -- standalone validation tool for the 2CBH codec work.
//
// Reads a ChessBase 17+ database (.2cbh index + .2cbg game data) and
// decodes every game's mainline through the embedded Move16 table,
// printing the moves in UCI notation plus selected index fields.
// ======================================================================

#include "2cbh_move16.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <string>
#include <vector>

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

bool loadFile(char const* name, std::vector<unsigned char>& data)
{
   FILE* fh = fopen(name, "rb");
   if (!fh)
      return false;
   fseek(fh, 0, SEEK_END);
   long n = ftell(fh);
   fseek(fh, 0, SEEK_SET);
   data.resize(size_t(n));
   bool ok = fread(&data[0], 1, size_t(n), fh) == size_t(n);
   fclose(fh);
   return ok;
}

void squareName(unsigned sq, char* buf)
{
   buf[0] = char('a' + (sq >> 3));
   buf[1] = char('1' + (sq & 7));
   buf[2] = '\0';
}

char const* promotionSuffix(uint8_t piece)
{
   switch (piece)
   {
      case 2:
      case 10:  return "q";
      case 3:
      case 11:  return "n";
      case 4:
      case 12:  return "b";
      case 5:
      case 13:  return "r";
      default:  return "";
   }
}

} // anonymous namespace

int main(int argc, char* argv[])
{
   if (argc < 2)
   {
      fprintf(stderr, "usage: 2cbh_probe <prefix> [maxGames]\n");
      return 1;
   }

   std::string prefix(argv[1]);
   if (prefix.size() > 5 && prefix.compare(prefix.size() - 5, 5, ".2cbh") == 0)
      prefix.erase(prefix.size() - 5);
   unsigned maxGames = (argc > 2) ? unsigned(atoi(argv[2])) : 20u;

   std::vector<unsigned char> cbh;
   std::vector<unsigned char> cbg;
   if (!loadFile((prefix + ".2cbh").c_str(), cbh))
   {
      fprintf(stderr, "cannot read %s.2cbh\n", prefix.c_str());
      return 1;
   }
   if (!loadFile((prefix + ".2cbg").c_str(), cbg))
   {
      fprintf(stderr, "cannot read %s.2cbg\n", prefix.c_str());
      return 1;
   }

   unsigned const recordSize = readLE16(&cbh[0x0a]);
   unsigned long const totalCount = (unsigned long) readLE64(&cbh[0x10]);
   unsigned const headerRecords = 256u;
   unsigned const gameCount = unsigned(cbh.size() / recordSize) - headerRecords;
   if (maxGames > gameCount)
      maxGames = gameCount;

   printf("# recordSize=%u totalRecords=%lu games=%u probing=%u\n",
          recordSize, totalCount, gameCount, maxGames);

   unsigned decoded = 0;
   unsigned unterminated = 0;

   for (unsigned i = 0; i < maxGames; ++i)
   {
      unsigned char const* rec = &cbh[(headerRecords + i) * recordSize];
      unsigned long cbgOffset = (unsigned long) readLE64(rec + 0x08);

      if (cbgOffset + 0x1a > cbg.size())
         continue;

      unsigned char const* recg = &cbg[cbgOffset];
      uint64_t magic = readLE64(recg);
      if (magic != 0x1122334455667788ull)
      {
         fprintf(stderr, "game %u: bad magic at .2cbg offset 0x%lx\n",
                 i, cbgOffset);
         continue;
      }
      uint32_t dataSize = readLE32(recg + 0x08);
      uint16_t type     = readLE16(recg + 0x18);

      if (type != 1 && type != 2)
         continue; // unsupported record type

      unsigned const nShorts = dataSize / 2u;
      std::string line;
      line.reserve(8u * dataSize);
      bool terminated = false;
      unsigned moves = 0;

      for (unsigned j = 0; j < nShorts; ++j)
      {
         uint16_t code = readLE16(recg + 0x1a + 2*j);
         if (code == db::cb2::Move16_GameStart)
            continue;
         if (code == db::cb2::Move16_Terminator)
         {
            terminated = true;
            break;
         }
         if (code >= db::cb2::Move16_None) // 0xfffb / 0xfffd markers
            continue;

         db::cb2::Move16Descriptor d;
         if (!db::cb2::decodeMove16(code, d))
         {
            fprintf(stderr, "game %u: bad code 0x%04x\n", i, unsigned(code));
            break;
         }
         char a[8], b[8];
         squareName(d.from, a);
         squareName(d.to, b);
         line += a;
         line += b;
         if (d.hasWord1
             && (d.piece == 6 || d.piece == 14)
             && d.word1From == d.to && d.word1To == d.to)
         {
            // promotion: append the promoted piece letter
            switch (d.word1Piece)
            {
               case 2:
               case 10: line += 'q'; break;
               case 3:
               case 11: line += 'n'; break;
               case 4:
               case 12: line += 'b'; break;
               case 5:
               case 13: line += 'r'; break;
               default: break;
            }
         }
         line += ' ';
         ++moves;
      }

      printf("G %u %u %d\n", i, moves, terminated ? 1 : 0);
      printf("%s\n", line.c_str());
      if (terminated)
         ++decoded;
   }

   printf("# decoded=%u of %u\n", decoded, maxGames);
   return 0;
}