/*
  Narration for Stockfish — structured, shadow-only position facts.
  Copyright (C) 2026 — integrated into Scidb.

  Emits machine-readable JSON describing the engine's view of a position
  (material, pawn structure, control, king safety).  It never influences
  search or evaluation; the language layer narrates this output.
*/

#ifndef NARRATION_H_INCLUDED
#define NARRATION_H_INCLUDED

#include <string>

namespace Stockfish {

class Position;

namespace Narration {

std::string json(const Position& pos);

}  // namespace Narration
}  // namespace Stockfish

#endif  // NARRATION_H_INCLUDED
