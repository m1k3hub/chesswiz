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

#include "jpeg_bit_stream.h"
#include "jpeg_stream.h"

using namespace JPEG;


BitStream::BitStream(Stream& stream)
	:m_stream(stream)
	,m_bitsLeft(0)
	,m_bits(0)
	,m_eos(false)
{
}


void
BitStream::clear()
{
	skipBits();
	m_eos = false;
}


void
BitStream::readBits()
{
	if (m_eos)
		return;

	do
	{
		int c = m_stream.readByte();

		if (c == -1)
		{
			m_eos = true;
			return;
		}

		m_bits = (m_bits << 8) | c;
		m_bitsLeft += 8;
	}
	while (m_bitsLeft < MaxBits);
}

// vi:set ts=3 sw=3:
