// ======================================================================
// Count cipher for ChessBase Chess960 CBH game decoding
// ======================================================================
//
// ChessBase encodes Chess960 move bytes with an evolving count cipher
// instead of the move-index count used by standard chess:
//
//   count_0 = g(lc_0)                             // universal seed table
//   count_p = H0(count_{p-1}, lc_{p-1}, lc_p, p)  // universal 4-input byte fn
//   raw_p   = InverseMoveNumberLookup[lc_p] + count_p   (mod 256)
//
// The 4th input p is the 0-based ply index (ChessBase 26 oracle,
// 2026-07-26: adding the ply drops table conflicts from 12.5% to 0%).
// Additionally, ChessBase occasionally encodes a move in bracketed form
// [M, X1..Xk, M] (k=1..3): the move byte repeated around k cipher-
// transparent parameter bytes which do not advance the count chain.
//
// This class loads the recovered H0 and g tables from
// src/count_cipher_universal.json and provides lookups.
// The tables are stored in static storage so they are loaded only once.

#ifndef _cbh_count_cipher_included
#define _cbh_count_cipher_included

#include "m_string.h"
#include "m_map.h"

#include <stdint.h>

namespace db {
namespace cbh {

class CountCipher
{
public:

	CountCipher();

	/// Load H0 and g tables from the JSON file.  Returns true on success.
	/// The path defaults to a well-known location if empty.
	/// Tables are loaded once into static storage; subsequent calls are no-ops.
	bool load(mstl::string const& path = mstl::string());

	/// True if the tables have been loaded.
	bool isLoaded() const;

	/// Look up H0(count_prev, lc_prev, lc, ply).  Returns 0xffff if not found.
	unsigned lookupH0(unsigned countPrev, unsigned lcPrev, unsigned lc, unsigned ply) const;

	/// Look up g(lc) -- the seed count for the first move.  Returns 0xffff if not found.
	unsigned lookupG(unsigned lc) const;

	/// Look up P1(cnt, X1, ply) for 0xeb triple parameter byte 1.
	/// X1 = (promo-2)<<6|to.  Returns 0xffff if not found.
	unsigned lookupP1(unsigned cnt, unsigned x1, unsigned ply) const;

	/// Look up P2(c1, X2, ply) for 0xeb triple parameter byte 2.
	/// X2 = from square.  Returns 0xffff if not found.
	unsigned lookupP2(unsigned c1, unsigned x2, unsigned ply) const;

	/// Number of H0 entries loaded.
	unsigned h0Size() const;

	/// Number of g entries loaded.
	unsigned gSize() const;

	/// Reverse index entry: (lc -> count_next) for a given (count_prev, lc_prev).
	struct Candidate { unsigned lc; unsigned countNext; };

	/// Get all H0 candidates for a given (countPrev, lcPrev) state.
	/// Returns a pointer to an array of candidates and its length.
	static Candidate const* getCandidates(unsigned countPrev, unsigned lcPrev, unsigned& n);

private:

	typedef mstl::map<uint64_t,unsigned> Table;



	static uint64_t makeKey(unsigned a, unsigned b, unsigned c, unsigned d);



	static Table* s_h0;
	static Table* s_g;
	static Table* s_p1;
	static Table* s_p2;
	static bool s_loaded;

	/// Reverse index: for each (countPrev << 8 | lcPrev), a list of (lc, countNext).
	static Candidate s_index[65536][8];
	static unsigned s_indexSize[65536];
};

} // namespace cbh
} // namespace db

#endif // _cbh_count_cipher_included

// vi:set ts=3 sw=3:
