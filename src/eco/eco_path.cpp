// ======================================================================
// Author : $Author: gcramer $
// Version: $Revision: 1411 $
// Date   : $Date: 2017-08-12 07:08:17 -0400 (Sat, 12 Aug 2017) $
// Url    : $HeadURL: https://svn.code.sf.net/p/scidb/code/trunk/src/eco/eco_path.cpp $
// ======================================================================

// ======================================================================
//    _/|            __
//   // o\         /    )           ,        /    /
//   || ._)    ----\---------__----------__-/----/__-
//   //__\          \      /   '  /    /   /    /   )
//   )___(     _(____/____(___ __/____(___/____(___/_
// ======================================================================

// ======================================================================
// Copyright: (C) 2014-2017 Gregor Cramer
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#include "eco_path.h"

#include "m_utility.h"

#include <stdio.h>

using namespace eco;

Path::BitLenghtList Path::m_bitLengthList;


void Path::setBitLengthList(BitLenghtList const& bitLengthList)
{
	for (unsigned i = 0; i < bitLengthList.size(); ++i)
	{
		if (i == m_bitLengthList.size())
			m_bitLengthList.push_back(bitLengthList[i]);
		else
			m_bitLengthList[i] = mstl::max(m_bitLengthList[i], bitLengthList[i]);
	}
}


void Path::dumpBitLengths()
{
	char const* comma = "";
	unsigned total = 0;

	fprintf(stderr, "Bit lengths: ");

	for (unsigned length : m_bitLengthList)
	{
		fprintf(stderr, "%s%u", comma, length);
		total += length;
		comma = ", ";
	}

	fprintf(stderr, " (total: %u) (length: %u)\n\n", total, m_bitLengthList.size());
}

// vi:set ts=3 sw=3:
