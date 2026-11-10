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

#include "u_lzo_byte_stream.h"
#include "u_exception.h"

#include "m_fstream.h"
#include "m_assert.h"

#include <string.h>

using namespace util;


LzoByteStream::~LzoByteStream() throw() {}


// A frame is a kind byte (Raw or Compressed), the stored length as two
// big-endian bytes, and the stored bytes. A raw frame holds 1..Chunk_Size
// bytes; a compressed one holds fewer than Chunk_Size bytes and decodes
// to at most Chunk_Size bytes.

LzoByteStream::LzoByteStream(mstl::fstream& strm)
	:ByteStream(m_in, Chunk_Size)
	,m_strm(strm)
{
	// nothing to read yet; writing fills m_in
	m_getp = m_endp;
}


void
LzoByteStream::flush()
{
	overflow(0);
}


void
LzoByteStream::readFrame()
{
	unsigned remaining = this->remaining();

	if (remaining > Additional_Size)
		U_RAISE("LZO stream: additional buffer size is too small");

	::memmove(m_out, m_getp, remaining);

	unsigned char head[3];

	if (!m_strm.read(reinterpret_cast<char*>(head), 3))
		U_RAISE("LZO stream: unexpected end of stream");

	unsigned stored = (unsigned(head[1]) << 8) | head[2];
	unsigned char* dst = m_out + remaining;
	unsigned decoded;

	switch (head[0])
	{
		case Raw:
			if (stored == 0 || stored > Chunk_Size)
				U_RAISE("LZO stream: corrupt data");
			if (!m_strm.read(reinterpret_cast<char*>(dst), stored))
				U_RAISE("LZO stream: unexpected end of stream");
			decoded = stored;
			break;

		case Compressed:
			if (stored == 0 || stored >= Chunk_Size)
				U_RAISE("LZO stream: corrupt data");
			if (!m_strm.read(reinterpret_cast<char*>(m_in), stored))
				U_RAISE("LZO stream: unexpected end of stream");
			decoded = Lzo::decompress(m_in, stored, dst, Chunk_Size);
			if (decoded == 0)
				U_RAISE("LZO stream: corrupt data");
			break;

		default:
			U_RAISE("LZO stream: corrupt data");
	}

	m_base = m_getp = m_out;
	m_putp = m_endp = dst + decoded;
}


void
LzoByteStream::underflow(unsigned size)
{
	do
		readFrame();
	while (remaining() < size);
}


void
LzoByteStream::overflow(unsigned)
{
	M_ASSERT(!m_owner);

	unsigned size = m_putp - m_in;

	if (size == 0)
		return;

	ByteStream src(m_in, size);
	ByteStream dst(m_out, m_out + Buf_Size);
	unsigned char kind = Compressed;

	if (!Lzo::compress(src, dst))
	{
		dst.swap(src);
		kind = Raw;
	}

	char head[3] = { char(kind), char(dst.size() >> 8), char(dst.size() & 0xff) };

	if (!m_strm.write(head, 3) || !m_strm.write(reinterpret_cast<char const*>(dst.data()), dst.size()))
		U_RAISE("LZO stream: write failed");

	m_base = m_putp = m_in;
	m_endp = m_in + Chunk_Size;
	m_getp = m_endp;
}

// vi:set ts=3 sw=3:
