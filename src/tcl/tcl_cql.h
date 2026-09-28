// ======================================================================
// Tcl bindings for the CQL matcher (src/db/cql) -- see tcl_cql.cpp.
// ======================================================================

#ifndef _tcl_cql_included
#define _tcl_cql_included

extern "C" { struct Tcl_Interp; }

namespace tcl {
namespace cql {

void init(Tcl_Interp* ti);

/// The name of a ::cql::error::Type ("Invalid_Keyword", ...).
char const* errorName(int error);

} // namespace cql
} // namespace tcl

#endif // _tcl_cql_included

// vi:set ts=3 sw=3:
