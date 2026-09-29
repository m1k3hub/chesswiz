// ======================================================================
// Runs one game of a database through a parsed CQL query.
// ======================================================================

#ifndef _cql_game_matcher_included
#define _cql_game_matcher_included

#include "db_common.h"

namespace db { class Database; }

namespace cql {

class Match;

/// The first mainline ply (0 = the start position) at which game <index>
/// of <db> satisfies <match>, or -1. A query with only game-information
/// filters answers 0 for a matching game. <match> should be freshly parsed:
/// nested position lists keep match counts that Match::newGame does not
/// reach. Positions inside variations are visited only when the query uses
/// :variations or :variationsonly.
int matchGame(db::Database const& db, db::variant::Type variant, unsigned index, Match& match);

} // namespace cql

#endif // _cql_game_matcher_included

// vi:set ts=3 sw=3:
