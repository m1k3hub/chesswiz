// ======================================================================
// Move16 decode table lookup (see 2cbh_move16.h for the descriptor
// layout and 2cbh_move16_table.cpp for the embedded data).
// ======================================================================

#include "2cbh_move16.h"

#include "db_board.h"
#include "db_move.h"
#include "db_move_list.h"

#include "m_vector.h"

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


unsigned
toMove16Piece(unsigned scidbPiece)
{
   piece::ID const id = piece::ID(scidbPiece);
   unsigned const type = piece::type(id);
   unsigned m16;

   switch (type)
   {
      case piece::King:   m16 = 1; break;
      case piece::Queen:  m16 = 2; break;
      case piece::Knight: m16 = 3; break;
      case piece::Bishop: m16 = 4; break;
      case piece::Rook:   m16 = 5; break;
      case piece::Pawn:   m16 = 6; break;
      default:            return 0;
   }

   return piece::isBlack(id) ? m16 + 8 : m16;
}


bool
resolveMove16(Board const& board, Move16Descriptor const& d, Move& move)
{
   unsigned const from = toScidbSquare(d.from);
   unsigned const to = toScidbSquare(d.to);
   unsigned rookFrom = 0;
   unsigned promoType = 0;
   bool isPromotion = false;
   bool isCastling = false;

   if (d.hasWord1)
   {
      if (d.piece == 6 || d.piece == 14)
      {
         if (d.word1From == d.to && d.word1To == d.to)
         {
            // The promoted piece uses the same numbering as word0.piece:
            // 1..6 = K,Q,N,B,R,P.
            switch (d.word1Piece & 7)
            {
               case 2:  promoType = piece::Queen; break;
               case 3:  promoType = piece::Knight; break;
               case 4:  promoType = piece::Bishop; break;
               case 5:  promoType = piece::Rook; break;
               default: return false;
            }
            isPromotion = true;
         }
      }
      else if ((d.piece == 1 || d.piece == 9)
               && (d.word1Piece == 5 || d.word1Piece == 13))
      {
         rookFrom = toScidbSquare(d.word1From);
         isCastling = true;
      }
   }

   db::MoveList legalMoves;
   board.generateMoves(variant::Normal, legalMoves);
   board.filterLegalMoves(legalMoves, variant::Normal);

   for (unsigned mi = 0; mi < legalMoves.size(); ++mi)
   {
      Move const& m = legalMoves[mi];

      if (m.isCastling() != isCastling)
         continue;
      if (m.from() != from)
         continue;

      if (isCastling)
      {
         // The descriptor's second transition names the rook's *start* square,
         // but the Move16 table is a fixed table: its castling codes carry the
         // standard a-/h-file rook, while ChessBase uses the same code for a
         // Chess960 position whose castling rook stands elsewhere (a database
         // CBase26 wrote for FEN "4k3/8/8/8/8/8/8/1R2K1R1 w BG -" stores the
         // ordinary long-castling code 0xb129 although the rook is on b1).
         // Enforce the rook's start square only when the descriptor's square
         // really holds the castling rook; the king and the rook's
         // *destination* are what identify the move.
         piece::ID const rook = piece::piece(piece::Rook,
                                             board.sideToMove());
         if (m.castlingKingTo() != to
             || m.castlingRookTo() != toScidbSquare(d.word1To))
            continue;
         if (board.pieceAt(rookFrom) == rook && m.to() != rookFrom)
            continue;
      }
      else if (m.to() != to)
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
      return true;
   }

   return false;
}


namespace
{

/// Lazily built index: (from, to, moving piece) -> candidate codes.
typedef mstl::vector<mstl::vector<uint16_t> > CodeIndex;

struct IndexKey
{
   unsigned hash(unsigned key) const { return key; }
};

// The key has at most 6 + 6 + 4 = 16 bits (from, to, piece), so a flat
// 64 K table of small vectors is compact enough and never rehashes.
CodeIndex const&
codeIndex()
{
   static CodeIndex* index = 0;

   if (index == 0)
   {
      index = new CodeIndex(1u << 16);
      unsigned const* table = packedTable();

      for (unsigned code = 1; code < packedTableSize(); ++code)
      {
         unsigned const w = table[code];
         unsigned const from = w & 0x3fu;
         unsigned const to = (w >> 6) & 0x3fu;
         unsigned const pce = (w >> 12) & 0xfu;
         (*index)[from | (to << 6) | (pce << 12)].push_back(uint16_t(code));
      }
   }

   return *index;
}

} // anonymous namespace


bool
encodeMove16(Board const& board, Move const& move, uint16_t& code)
{
   unsigned const from = toScidbSquare(move.from());
   unsigned const m16piece = toMove16Piece(board.pieceAt(move.from()));

   if (m16piece == 0)
      return false;

   // Castling descriptors carry the king's destination in word0.to.
   unsigned const to = move.isCastling() ? toScidbSquare(move.castlingKingTo())
                                         : toScidbSquare(move.to());

   CodeIndex const& index = codeIndex();
   mstl::vector<uint16_t> const& candidates = index[from | (to << 6) | (m16piece << 12)];

   Move resolved;

   for (unsigned i = 0; i < candidates.size(); ++i)
   {
      Move16Descriptor d;

      if (!decodeMove16(candidates[i], d))
         continue;
      if (!resolveMove16(board, d, resolved))
         continue;
      if (resolved.from() != move.from() || resolved.to() != move.to())
         continue;
      if (resolved.isCastling() != move.isCastling())
         continue;

      if (move.isCastling())
      {
         if (resolved.castlingKingTo() != move.castlingKingTo()
             || resolved.castlingRookTo() != move.castlingRookTo())
            continue;
      }
      else if (move.isPromotion())
      {
         if (!resolved.isPromotion() || resolved.promoted() != move.promoted())
            continue;
      }
      else if (resolved.isPromotion())
         continue;

      code = candidates[i];
      return true;
   }

   return false;
}


bool
findPlacementCode(unsigned m16piece, unsigned m16square, uint16_t& code)
{
   CodeIndex const& index = codeIndex();
   mstl::vector<uint16_t> const& candidates =
      index[(m16square & 0x3f) | ((m16square & 0x3f) << 6) | ((m16piece & 0xf) << 12)];

   for (unsigned i = 0; i < candidates.size(); ++i)
   {
      Move16Descriptor d;

      if (!decodeMove16(candidates[i], d))
         continue;
      if (d.from == d.to && d.piece == m16piece && d.captured == 0 && !d.hasWord1)
      {
         code = candidates[i];
         return true;
      }
   }

   return false;
}


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
