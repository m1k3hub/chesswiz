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
// Copyright: (C) 2010-2013 Gregor Cramer
// Copyright: (C) 2026 Michael Thomas (Chesswiz)
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#ifndef _sys_thread_group_included
#define _sys_thread_group_included

#include "sys_thread.h"
#include "m_string.h"

#include "m_vector.h"

namespace sys {

// Owns a set of worker threads. Simplifies the common pattern of
// starting a thread per work chunk, joining them, and propagating the
// first exception thrown by any worker. Worker objects themselves are
// owned by the caller.
class ThreadGroup
{
public:
	ThreadGroup();
	~ThreadGroup();

	// Start a new thread running the given runnable. Returns false if the
	// thread could not be started. On failure no thread is recorded and
	// the caller remains responsible for the runnable's lifetime.
	bool start(Thread::Runnable const& runnable);

	// Wait for all started threads. If any worker threw, the first caught
	// exception is re-thrown as an mstl::exception. All threads are deleted
	// during join or destruction.
	void join();

	// Same as join() but never throws. Returns true if all workers succeeded.
	// On failure, failMsg is set to the first worker's exception message.
	// Use this when cleanup must run before re-throwing.
	bool joinNoThrow(mstl::string& failMsg);

	unsigned size() const;
	bool empty() const;

private:
	ThreadGroup(ThreadGroup const&);
	ThreadGroup& operator=(ThreadGroup const&);

	mstl::vector<Thread*> m_threads;
};

} // namespace sys

#endif // _sys_thread_group_included

// vi:set ts=3 sw=3:
