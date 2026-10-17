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

#include "m_sstream.h"
#include "m_stdio.h"
#include "m_assert.h"

#include <stdlib.h>

using namespace mstl;


ostringstream::ostringstream()
	:m_buf(0)
	,m_size(0)
{
#if defined(_WIN32) || defined(__APPLE__)
	if ((m_fp = ::tmpfile()) == 0)
#else
	if ((m_fp = ::open_memstream(&m_buf, &m_size)) == 0)
#endif
		M_RAISE("open_memstream() failed");

	setmode(out | binary);
}


ostringstream::~ostringstream() throw()
{
	::fclose(m_fp);
	::free(m_buf);
	m_fp = 0;
}


string
ostringstream::str() const
{
	::fflush(m_fp);
#if defined(_WIN32) || defined(__APPLE__)
	int64_t pos = ::ftello(m_fp);
	if (pos < 0 || ::fseeko(m_fp, 0, SEEK_END)) M_RAISE("string stream seek failed");
	int64_t size = ::ftello(m_fp);
	if (size < 0 || ::fseeko(m_fp, 0, SEEK_SET)) M_RAISE("string stream seek failed");
	string result;
	result.resize(size_t(size));
	size_t count = ::fread(result.data(), 1, result.size(), m_fp);
	int seekResult = ::fseeko(m_fp, pos, SEEK_SET);
	if (count != result.size() || seekResult) M_RAISE("string stream read failed");
	return result;
#else
	return m_buf ? string(m_buf, m_size) : string::empty_string;
#endif
}


void
ostringstream::str(mstl::string const& s)
{
	if (m_fp)
	{
		::fclose(m_fp);
		::free(m_buf);

		m_fp = 0;
		m_buf = 0;
		m_size = 0;
	}

#if defined(_WIN32) || defined(__APPLE__)
	if ((m_fp = ::tmpfile()) == 0)
#else
	if ((m_fp = ::open_memstream(&m_buf, &m_size)) == 0)
#endif
		M_RAISE("open_memstream() failed");

	setmode(out | binary);
	write(s);
}


istringstream::istringstream(string const& str)
	:m_buf(str)
{
#if defined(_WIN32) || defined(__APPLE__)
	if ((m_fp = ::tmpfile()) == 0)
#else
	if ((m_fp = ::fmemopen(m_buf.data(), m_buf.size(), "r")) == 0)
#endif
		M_RAISE("fmemopen() failed");
#if defined(_WIN32) || defined(__APPLE__)
	if (::fwrite(m_buf.data(), 1, m_buf.size(), m_fp) != m_buf.size())
		M_RAISE("string stream write failed");
	::rewind(m_fp);
#endif

	setmode(in | binary);
}


istringstream::~istringstream() throw()
{
	::fclose(m_fp);
	m_fp = 0;
}


void
istringstream::str(string const& str)
{
	m_buf = str;
	::fclose(m_fp);

#if defined(_WIN32) || defined(__APPLE__)
	if ((m_fp = ::tmpfile()) == 0)
#else
	if ((m_fp = ::fmemopen(m_buf.data(), m_buf.size(), "r")) == 0)
#endif
		M_RAISE("fmemopen() failed");
#if defined(_WIN32) || defined(__APPLE__)
	if (::fwrite(m_buf.data(), 1, m_buf.size(), m_fp) != m_buf.size())
		M_RAISE("string stream write failed");
	::rewind(m_fp);
#endif
}

// vi:set ts=3 sw=3:
