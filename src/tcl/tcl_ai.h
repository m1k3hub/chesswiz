// ======================================================================
//    _/|            __
//   // o\         /    )           ,        /    /
//   || ._)    ----\---------__----------__-/----/__-
//   //__\          \      /   '  /    /   /    /   )
//   )___(     _(____/____(___ __/____(___/____(___/_
// ======================================================================
//
// Tcl bindings for the chess-anatomy fact extractor (db_chess_facts).
//
//   ::scidb::ai::facts ?fen?          -> JSON anatomy (current board if no fen)
//   ::scidb::ai::text  ?fen?          -> human-readable anatomy
//   ::scidb::ai::moveFacts move ?fen? -> JSON facts for one move
//
// These are the grounding commands a language layer is allowed to describe.
// Nothing here reasons about chess; it only reports what the extractor found.
//
// ======================================================================

#ifndef _tcl_ai_included
#define _tcl_ai_included

extern "C" { struct Tcl_Interp; }

namespace tcl {
namespace ai {

void init(Tcl_Interp* ti);

} // namespace ai
} // namespace tcl

#endif // _tcl_ai_included

// vi:set ts=3 sw=3:
