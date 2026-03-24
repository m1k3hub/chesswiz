// ======================================================================
// Author : $Author: gcramer $
// Version: $Revision: 1411 $
// Date   : $Date: 2017-08-12 07:08:17 -0400 (Sat, 12 Aug 2017) $
// Url    : $HeadURL: https://svn.code.sf.net/p/scidb/code/trunk/src/eco/eco_visitor.ipp $
// ======================================================================

// ======================================================================
//    _/|            __
//   // o\         /    )           ,        /    /
//   || ._)    ----\---------__----------__-/----/__-
//   //__\          \      /   '  /    /   /    /   )
//   )___(     _(____/____(___ __/____(___/____(___/_
// ======================================================================

// ======================================================================
// Copyright: (C) 2014-2017 Gregor Cramer
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

namespace eco {

inline auto Visitor::board() const -> db::Board const&	{ return m_board; }
inline auto Visitor::level() const -> unsigned				{ return m_level; }

} // namespace eco

// vi:set ts=3 sw=3:
