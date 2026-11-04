// ======================================================================
// Author : $Author$
// Version: $Revision: 688 $
// Date   : $Date: 2013-03-29 12:55:41 -0400 (Fri, 29 Mar 2013) $
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
// Modified for Chesswiz, 2026; see docs/UPSTREAM.md
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#include "sci_decoder_position.h"
#include "db_exception.h"
#include "m_assert.h"
#include <string.h>
#include <ctype.h>

namespace db {
namespace sci {
namespace decoder {

// The main decoder caches start positions; the legacy decoders keep the plain setup.
#define _SCI_START_CACHE 1
#include "sci_decoder_position_impl.ipp"

Position::StartCache	Position::s_startCache;
sys::Mutex		Position::s_startCacheLock;

} // namespace decoder
} // namespace sci
} // namespace db

// vi:set ts=3 sw=3:
