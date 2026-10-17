// ======================================================================
// Author : $Author$
// Version: $Revision: 609 $
// Date   : $Date: 2013-01-02 12:35:19 -0500 (Wed, 02 Jan 2013) $
// Url    : $URL$
// ======================================================================

// ======================================================================
// Copyright: (C) 2009-2013 Gregor Cramer
// Modified for Chesswiz, 2026; see docs/UPSTREAM.md
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#include "u_misc.h"

#include <string.h>

#ifdef _WIN32

# include <windows.h>
static char Separator = '\\';

#else

# include <sys/time.h>
# include <time.h>

static char Separator = '/';

#endif


using namespace util;


char util::misc::file::pathSeparator() { return Separator; }


bool
util::misc::file::hasSuffix(mstl::string const& path)
{
	char const* p = ::strrchr(path.c_str(), '.');

	if (!p || p == path.c_str())
		return false;

	return !::strchr(p + 1, Separator);
}


mstl::string
util::misc::file::dirname(mstl::string const& path)
{
	char const* p = ::strrchr(path.c_str(), Separator);

	if (!p)
		return mstl::string::empty_string;

	return mstl::string(path.begin(), p + 1);
}


mstl::string
util::misc::file::basename(mstl::string const& path)
{
	char const* p = ::strrchr(path.c_str(), Separator);

	if (!p)
		return path;

	return mstl::string(p + 1, path.end());
}


mstl::string
util::misc::file::rootname(mstl::string const& path)
{
	char const* p = ::strrchr(path.c_str(), '.');

	if (!p || p == path.c_str())
		return path;

	char const* q = ::strchr(p + 1, Separator);

	if (q)
		return path;

	return mstl::string(path.c_str(), p - path.c_str());
}


mstl::string
util::misc::file::suffix(mstl::string const& path)
{
	char const* p = ::strrchr(path.c_str(), '.');

	if (!p || p == path.c_str())
		return mstl::string::empty_string;

	return ::strchr(p + 1, Separator) ? mstl::string::empty_string : mstl::string(p + 1);
}


bool
util::misc::time::getCurrentTime(struct tm& result)
{
#ifdef _WIN32

	SYSTEMTIME t;
	::GetLocalTime(&t);

	result.year = t.wYear - 1900;
	result.mon  = t.wMonth - 1;
	result.mday = t.wDay;
	result.hour = t.wHour;
	result.min  = t.wMinute;
	result.sec  = t.wSecond;

#else

	::time_t sec = ::time(0);

	struct ::tm t;
	::localtime_r(&sec, &t);

	result.sec  = t.tm_sec;
	result.min  = t.tm_min;
	result.hour = t.tm_hour;
	result.mday = t.tm_mday;
	result.mon  = t.tm_mon;
	result.year = t.tm_year;

#endif

	return true;
}

// vi:set ts=3 sw=3:
