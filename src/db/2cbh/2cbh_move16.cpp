// ======================================================================
// Move16 decode table lookup (see 2cbh_move16.h for the descriptor
// layout and 2cbh_move16_table.cpp for the embedded data).
// ======================================================================

#include "2cbh_move16.h"

namespace db
{

namespace cb2
{

namespace
{

inline uint32_t word1Of(unsigned i)
{
   // side entry = two words: [code<<16 | w1low16][w1high16]
   unsigned const* t = sideTable();
   return (t[2*i] & 0xffffu) | (t[2*i + 1] << 16);
}

inline uint16_t sideCode(unsigned i)
{
   return uint16_t(sideTable()[2*i] >> 16);
}

} // anonymous namespace

bool decodeMove16(uint16_t code, Move16Descriptor& desc)
{
   unsigned const* table = packedTable();

   if (code == 0 || unsigned(code) >= packedTableSize())
      return false;

   unsigned const w = table[code];
   desc.from     = uint8_t( w        & 0x3fu);
   desc.to       = uint8_t((w >>  6) & 0x3fu);
   desc.piece    = uint8_t((w >> 12) & 0xfu);
   desc.captured = uint8_t((w >> 16) & 0xfu);
   desc.hasWord1 = ((w >> 20) & 1u) != 0;
   desc.word1From  = 0;
   desc.word1To    = 0;
   desc.word1Piece = 0;
   desc.word1Cap   = 0;

   if (desc.hasWord1)
   {
      // binary search in the side table (sorted by code)
      unsigned lo = 0;
      unsigned hi = sideTableSize() / 2u;
      while (lo < hi)
      {
         unsigned const mid = (lo + hi) / 2u;
         uint16_t const c = sideCode(mid);
         if (c < code)
            lo = mid + 1;
         else if (c > code)
            hi = mid;
         else
         {
            uint32_t const w1 = word1Of(mid);
            // word1 stores the second descriptor as raw bytes:
            // [from:8][to:8][piece:8][captured:8]
            desc.word1From  = uint8_t( w1        & 0x3fu);
            desc.word1To    = uint8_t((w1 >>  8) & 0x3fu);
            desc.word1Piece = uint8_t((w1 >> 16) & 0xffu);
            desc.word1Cap   = uint8_t((w1 >> 24) & 0xffu);
            return true;
         }
      }
      desc.hasWord1 = false; // inconsistent data -- ignore
   }
   return true;
}

} // namespace cb2

} // namespace db
