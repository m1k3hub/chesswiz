// ======================================================================
// Author : $Author$
// Version: $Revision: 609 $
// Date   : $Date: 2013-01-02 12:35:19 -0500 (Wed, 02 Jan 2013) $
// Url    : $URL$
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

#ifndef _mstl_iostream_included
#define _mstl_iostream_included

#include "m_istream.h"
#include "m_ostream.h"

namespace mstl {

struct iostream : public istream, public ostream {};

} // namespace mstl

#endif // _mstl_iostream_included

// vi:set ts=3 sw=3:
