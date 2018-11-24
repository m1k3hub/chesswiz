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

#include "sys_signal.h"

#ifdef __WIN32__

bool sys::signal::sendInterrupt(long pid) { return false; }

#else

# include <signal.h>

bool
sys::signal::sendInterrupt(long pid)
{
	return ::kill(pid, SIGINT) == 0;
}


bool
sys::signal::sendTerminate(long pid)
{
	return ::kill(pid, SIGTERM) == 0;
}

#endif

// vi:set ts=3 sw=3:
