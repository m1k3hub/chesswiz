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

#include "sys_thread_group.h"

#include "m_string.h"

using namespace sys;


ThreadGroup::ThreadGroup() {}


ThreadGroup::~ThreadGroup()
{
	try { join(); }
	catch (...) { /* swallow — never throw from destructor */ }
}


unsigned
ThreadGroup::size() const
{
	return m_threads.size();
}


bool
ThreadGroup::empty() const
{
	return m_threads.empty();
}


bool
ThreadGroup::start(Thread::Runnable const& runnable)
{
	Thread* thread = new Thread;

	// push before start so push_back exception won't leak a running thread
	try
	{
		m_threads.push_back(thread);
	}
	catch (...)
	{
		delete thread;	// not yet started, safe to destroy
		throw;
	}

	if (!thread->start(runnable))
	{
		m_threads.pop_back();
		delete thread;
		return false;
	}

	return true;
}


bool
ThreadGroup::joinNoThrow(mstl::string& failMsg)
{
	bool failed = false;
	failMsg.clear();

	// join everything first: no allocation may interrupt this loop,
	// otherwise remaining threads stay unjoined (and this must not throw
	// when reached from the destructor).
	for (unsigned i = 0; i < m_threads.size(); ++i)
		m_threads[i]->join();

	for (unsigned i = 0; i < m_threads.size(); ++i)
	{
		if (!failed && m_threads[i]->exception())
		{
			failed = true;
			try { failMsg = m_threads[i]->exception()->what(); } catch (...) {}
		}
	}

	for (unsigned i = 0; i < m_threads.size(); ++i)
		delete m_threads[i];

	m_threads.clear();
	return !failed;
}


void
ThreadGroup::join()
{
	mstl::string failMsg;

	if (!joinNoThrow(failMsg))
		M_RAISE("%s", failMsg.c_str());
}

// vi:set ts=3 sw=3:
