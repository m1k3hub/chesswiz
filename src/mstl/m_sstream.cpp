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

#include "m_sstream.h"
#include "m_stdio.h"
#include "m_assert.h"

#include <stdlib.h>

using namespace mstl;


ostringstream::ostringstream()
	:m_buf(0)
	,m_size(0)
{
#ifdef _WIN32
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
#ifdef _WIN32
	int64_t pos = ::_ftelli64(m_fp);
	if (pos < 0 || ::_fseeki64(m_fp, 0, SEEK_END)) M_RAISE("string stream seek failed");
	int64_t size = ::_ftelli64(m_fp);
	if (size < 0 || ::_fseeki64(m_fp, 0, SEEK_SET)) M_RAISE("string stream seek failed");
	string result;
	result.resize(size_t(size));
	size_t count = ::fread(result.data(), 1, result.size(), m_fp);
	int seekResult = ::_fseeki64(m_fp, pos, SEEK_SET);
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

#ifdef _WIN32
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
#ifdef _WIN32
	if ((m_fp = ::tmpfile()) == 0)
#else
	if ((m_fp = ::fmemopen(m_buf.data(), m_buf.size(), "r")) == 0)
#endif
		M_RAISE("fmemopen() failed");
#ifdef _WIN32
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

#ifdef _WIN32
	if ((m_fp = ::tmpfile()) == 0)
#else
	if ((m_fp = ::fmemopen(m_buf.data(), m_buf.size(), "r")) == 0)
#endif
		M_RAISE("fmemopen() failed");
#ifdef _WIN32
	if (::fwrite(m_buf.data(), 1, m_buf.size(), m_fp) != m_buf.size())
		M_RAISE("string stream write failed");
	::rewind(m_fp);
#endif
}

// vi:set ts=3 sw=3:
