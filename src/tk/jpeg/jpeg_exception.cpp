// ======================================================================
// Author : $Author$
// Version: $Revision: 609 $
// Date   : $Date: 2013-01-02 12:35:19 -0500 (Wed, 02 Jan 2013) $
// Url    : $URL$
// ======================================================================

// ======================================================================
// Copyright: (C) 2008-2013 Gregor Cramer
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#include "jpeg_exception.h"

#include <stdarg.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

using namespace JPEG;


Exception::Exception(char const* fmt, ...)
{
	m_msg = static_cast<char*>(::malloc(1024));

	va_list args;
	va_start(args, fmt);
	vsnprintf(const_cast<char*>(m_msg), 1024, fmt, args);
	va_end(args);
}


Exception::Exception(Exception const& exc)
	:m_msg(::strdup(exc.m_msg))
{
}


Exception::~Exception() throw()
{
	::free(m_msg);
}


char const*
Exception::what (void) const throw()
{
	return m_msg;
}

// vi:set ts=3 sw=3:
