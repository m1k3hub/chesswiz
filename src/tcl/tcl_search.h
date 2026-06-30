// ======================================================================
// Author : $Author$
// Version: $Revision$
// Date   : $Date$
// Url    : $URL$
// ======================================================================

// ======================================================================
//    _/|            __
//   // o\         /    )           ,        /    /
//   || ._)    ----\---------__----------__-/----/__-
//   //__\          \      /   '  /    /   /    /   )
//   )___(     _(____/____(___ __/____(___/____(___/_
// ======================================================================

// ======================================================================
// Copyright: (C) 2009-2013 Gregor Cramer
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#ifndef _tcl_search_included
#define _tcl_search_included

#include <tcl.h>

#include "m_ref_counted_ptr.h"

namespace db { class Database; }
namespace db { class Search; }

typedef mstl::ref_counted_ptr<db::Search> SearchP;

namespace tcl {
namespace search {

SearchP buildSearch(db::Database const& db, Tcl_Interp* ti, Tcl_Obj* query);

} // namespace search
} // namespace tcl

#endif // _tcl_search_included

// vi:set ts=3 sw=3: