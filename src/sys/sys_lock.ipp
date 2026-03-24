// ======================================================================
// Author : $Author: gcramer $
// Version: $Revision: 1340 $
// Date   : $Date: 2017-08-01 05:41:03 -0400 (Tue, 01 Aug 2017) $
// Url    : $HeadURL: https://svn.code.sf.net/p/scidb/code/trunk/src/sys/sys_lock.ipp $
// ======================================================================

// ======================================================================
// Copyright: (C) 2014 Gregor Cramer
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#include "sys_mutex.h"

namespace sys {

inline Lock::Lock(Mutex* mutex) :m_mutex(mutex) { if (m_mutex) m_mutex->lock(); }
inline Lock::~Lock() { if (m_mutex) m_mutex->release(); }

} // namespace sys

// vi:set ts=3 sw=3:
