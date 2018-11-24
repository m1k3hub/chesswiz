// ======================================================================
// Author : $Author: gcramer $
// Version: $Revision: 1339 $
// Date   : $Date: 2017-07-31 15:09:29 -0400 (Mon, 31 Jul 2017) $
// Url    : $URL: https://svn.code.sf.net/p/scidb/code/trunk/src/util/u_piped_progress.ipp $
// ======================================================================

// ======================================================================
// Copyright: (C) 2017 Gregor Cramer
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

namespace util {

inline sys::Thread& PipedProgress::thread() { return m_thread; }

} // namespace util

// vi:set ts=3 sw=3:
