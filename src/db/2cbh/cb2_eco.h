// ======================================================================
// ChessBase 17+ (2CBH) ECO key decoding.
//
// The 192-byte index record keeps an ECO key at +0x80 (u16 LE):
//
//   key = (base + 2) << 7 | sub        (base = 0 for A00 .. 499 for E99)
//
// CBase26's getter (0x1401e3ba0) and setter (0x1401e4370) clamp every value
// above 0xfa7f to zero ("no ECO"), and the PGN formatter (0x140c66e50)
// derives `base = (key >> 7) - 1` and renders the three-character code plus
// "/NN" when the low seven bits (a sub-variation number) are non-zero.
//
// Shared by cb2::Codec and the 2cbh2pgn converter, like cb2_elo.h, so the
// game list, the consumer path and the converter cannot drift apart.
//
// Copyright (C) 2026 the scidb contributors.
// ======================================================================

#ifndef _db_cb2_eco_included
#define _db_cb2_eco_included

#include <stddef.h>
#include <stdint.h>

namespace db { namespace cb2 {

/// True if the key carries an ECO code.  Note that A00 is base 0, so the
/// base value alone cannot be used to test for "no ECO".
inline bool isValidEcoKey(unsigned key)
{
   return key != 0 && key <= 0xfa7f && ((key >> 7) - 1u) < 500u;
}

/// The 0-based ECO code number stored in `key` (0 = A00).  Use
/// isValidEcoKey() to distinguish A00 from "no ECO".
inline unsigned ecoBase(unsigned key)
{
   if (!isValidEcoKey(key))
      return 0;
   return (key >> 7) - 1u;
}

/// Format `key` like CBase26 does: "B12", or "B12/34" when a sub-variation
/// number is stored.  Returns false (leaving `buf` alone) if the key carries
/// no valid ECO code.  `size` must be at least 8.
inline bool formatEcoKey(unsigned key, char* buf, size_t size)
{
   if (!isValidEcoKey(key) || size < 8)
      return false;

   unsigned const base = ecoBase(key);

   buf[0] = char('A' + base/100u);
   buf[1] = char('0' + (base/10u) % 10u);
   buf[2] = char('0' + base % 10u);

   unsigned const sub = key & 0x7fu;

   if (sub == 0)
   {
      buf[3] = '\0';
   }
   else
   {
      buf[3] = '/';
      buf[4] = char('0' + (sub/10u) % 10u);
      buf[5] = char('0' + sub % 10u);
      buf[6] = '\0';
   }
   return true;
}

/// The value GameInfo::m_eco expects: Scidb's 1-based "short" ECO code
/// (Eco::toShort()), i.e. base + 1, or 0 for "no ECO".
inline unsigned ecoShortCode(unsigned key)
{
   return isValidEcoKey(key) ? ecoBase(key) + 1u : 0u;
}

} }
#endif
