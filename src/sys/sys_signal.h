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

#ifndef _sys_signal_included
#define _sys_signal_included

namespace sys {
namespace signal {

bool sendInterrupt(long pid);
bool sendTerminate(long pid);

} // namespace signal
} // namespace sys

#endif // _sys_signal_included

// vi:set ts=3 sw=3:
