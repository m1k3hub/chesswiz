// ======================================================================
//    _/|            __
//   // o\         /    )           ,        /    /
//   || ._)    ----\---------__----------__-/----/__-
//   //__\          \      /   '  /    /   /    /   )
//   )___(     _(____/____(___ __/____(___/____(___/_
// ======================================================================
//
// Chess anatomy fact extractor.
//
// This is the *grounding layer* for language-model features: every chess
// fact a generated sentence may mention is computed here, deterministically,
// from the board.  The LLM is never asked to look at a FEN and reason about
// it; it is handed this structure and may only describe it.
//
// The extractor deliberately covers chess-native concepts -- pawn islands,
// isolated / doubled / backward / passed pawns, bishop pair, opposite-coloured
// bishops, bad bishops, knight outposts, rook files, king shield, pins,
// hanging pieces, mobility, development and game phase -- because generic
// "material + eval" fact packs are what make LLM chess commentary sound
// hollow and get facts wrong.
//
// ======================================================================

#ifndef _db_chess_facts_included
#define _db_chess_facts_included

#include "db_common.h"

namespace mstl { class string; }

namespace db {

class Board;
class Move;

class ChessFacts
{
public:
	/// Serialize the position's chess anatomy as JSON.
	static void toJson(Board const& board, variant::Type variant, mstl::string& result);

	/// Serialize the deterministic facts of a single move (and the deltas it
	/// causes) as JSON.  The board is the position *before* the move.
	static void toMoveJson(Board const& board,
								Move const& move,
								variant::Type variant,
								mstl::string& result);

	/// Query a named chess claim (used by the language-layer claim checker).
	/// <side> is 0 = either, 1 = white, 2 = black.  Sets <known> false for an
	/// unknown term.
	static bool claim(Board const& board, char const* term, int side, bool& known);

	/// Human-readable rendering (for tests / debugging).
	static void toText(Board const& board, variant::Type variant, mstl::string& result);
};

} // namespace db

#endif // _db_chess_facts_included

// vi:set ts=3 sw=3:
