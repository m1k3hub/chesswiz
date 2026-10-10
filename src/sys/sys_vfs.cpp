// ======================================================================
// Author : $Author$
// Version: $Revision: 662 $
// Date   : $Date: 2013-02-24 17:35:15 -0500 (Sun, 24 Feb 2013) $
// Url    : $URL$
// ======================================================================

// ======================================================================
// Copyright: (C) 2012-2013 Gregor Cramer
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#include "sys_vfs.h"

#include "m_string.h"


#if defined(__WIN32__)

#include <windows.h>

int64_t
sys::vfs::freeSize(mstl::string const& path)
{
	// mstl::string is char based, so use the ANSI variant; wide-char
	// paths (and conversion via MultiByteToWideChar) become relevant
	// once paths are stored as UTF-16 on Windows.
	ULARGE_INTEGER availableForUser;
	ULARGE_INTEGER total;
	ULARGE_INTEGER free;

	BOOL result = ::GetDiskFreeSpaceExA(
		path.c_str(),
		&availableForUser,
		&total,
		&free);

	return result ? int64_t(availableForUser.QuadPart) : int64_t(-1);
}

#elif defined(__unix__) || defined(__MacOSX__)

# if defined(HAVE_STATVFS)

#include <unistd.h>
#include <sys/statvfs.h>

int64_t
sys::vfs::freeSize(mstl::string const& path)
{
	struct ::statvfs vfs;

	if (::statvfs(path, &vfs) == -1)
		return -1;

	return vfs.f_bsize*(::geteuid() == 0 ? vfs.f_bfree : vfs.f_bavail);
}

# else

int64_t sys::vfs::freeSize(mstl::string const&) { return -1; }

# endif
#endif

// vi:se ts=3 sw=3:
