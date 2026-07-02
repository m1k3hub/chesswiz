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
	join();
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

	if (!thread->start(runnable))
	{
		delete thread;
		return false;
	}

	m_threads.push_back(thread);
	return true;
}


void
ThreadGroup::join()
{
	bool failed = false;
	mstl::string failMsg;

	for (unsigned i = 0; i < m_threads.size(); ++i)
	{
		m_threads[i]->join();

		if (!failed && m_threads[i]->exception())
		{
			failed = true;
			failMsg = m_threads[i]->exception()->what();
		}

		delete m_threads[i];
	}

	m_threads.clear();

	if (failed)
		M_RAISE("%s", failMsg.c_str());
}

// vi:set ts=3 sw=3:
