// ======================================================================
// Author : $Author: gcramer $
// Version: $Revision: 1339 $
// Date   : $Date: 2017-07-31 15:09:29 -0400 (Mon, 31 Jul 2017) $
// Url    : $HeadURL: https://svn.code.sf.net/p/scidb/code/trunk/src/sys/sys_lock.h $
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

#ifndef _sys_lock_included
#define _sys_lock_included

namespace sys {

class Mutex;

class Lock
{
public:

	Lock(Mutex* mutex);
	~Lock();

private:

	Mutex* m_mutex;
};

} // namespace sys

#include "sys_lock.ipp"

#endif // _sys_lock_included

// vi:set ts=3 sw=3:
