// ======================================================================
// Author : $Author: gcramer $
// Version: $Revision: 1473 $
// Date   : $Date: 2018-04-11 08:32:51 -0400 (Wed, 11 Apr 2018) $
// Url    : $URL: https://svn.code.sf.net/p/scidb/code/trunk/src/app/app_thread.ipp $
// ======================================================================

// ======================================================================
//    _/|            __
//   // o\         /    )           ,        /    /
//   || ._)    ----\---------__----------__-/----/__-
//   //__\          \      /   '  /    /   /    /   )
//   )___(     _(____/____(___ __/____(___/____(___/_
// ======================================================================

// ======================================================================
// Copyright: (C) 2013 Gregor Cramer
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

namespace app {

inline Thread::Thread() :m_cursor(0) {}

inline bool Thread::isWorkingOn(Cursor const& cursor) const	{ return &cursor == m_cursor; }
inline void Thread::setWorkingOn(Cursor const* cursor)		{ m_cursor = cursor; }


inline
void
Thread::signal(Signal signal, Cursor const& cursor)
{
	if (isWorkingOn(cursor))
		this->signal(signal);
}

} // namespace app

// vi:set ts=3 sw=3:
