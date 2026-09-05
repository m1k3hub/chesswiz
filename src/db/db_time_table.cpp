// ======================================================================
// Author : $Author$
// Version: $Revision: 851 $
// Date   : $Date: 2013-06-24 11:15:00 -0400 (Mon, 24 Jun 2013) $
// Url    : $URL$
// ======================================================================

// ======================================================================
//    _/|            __
//   // o\         /    )           ,        /    /
//   || ._)    ----\---------__----------__-/----/__-
//   //__\          \      /   '  /    /   /    /   )
//   )___(     _(____/____(___ __/____(___/____(___/_
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

#include "db_time_table.h"

#include "m_utility.h"
#include "m_bit_functions.h"
#include "m_assert.h"

#include <string.h>

using namespace db;


TimeTable::TimeTable()
	:m_types(0)
{
	::memset(m_size, 0, sizeof(m_size));
}


void
TimeTable::clear()
{
	m_table.clear();
	::memset(m_size, 0, sizeof(m_size));
}


void
TimeTable::cut(unsigned newSize)
{
	M_REQUIRE(newSize <= size());

	m_table.resize(newSize);
	::memset(m_size, 0, sizeof(m_size));

	for (unsigned i = 0; i < m_table.size(); ++i)
	{
		for (unsigned t = 0; t < MoveInfo::LAST; ++t)
		{
			if (!m_table[i][t].isEmpty())
				m_size[t] = i + 1;
		}
	}
}


void
TimeTable::ensure(unsigned size)
{
	m_table.reserve(size);

	while (m_table.size() < size)
	{
		m_table.push_back();
		m_table.back().resize(MoveInfo::LAST);
	}
}


void
TimeTable::set(unsigned index, MoveInfo const& moveInfo)
{
	M_REQUIRE(index < size());
	M_REQUIRE(!moveInfo.isEmpty());

	unsigned col = moveInfo.content() - 1;

	// docs §4.3.2/§5: never populate correspondence columns
	if (!MoveInfo::isEncodable(moveInfo.content(), 95))
		return;

	m_table[index][col] = moveInfo;
	m_size[col] = mstl::max(m_size[col], index + 1);
	m_types |= 1 << col;
}


void
TimeTable::set(unsigned index, MoveInfoSet const& moveInfoSet)
{
	// docs/SCI_CORRESPONDENCE_FORMAT.md §4.3.2/§5: correspondence durations
	// have no time-table representation in any current version; population
	// must reject them so table serialization cannot desynchronize.
	set(index, moveInfoSet, 95);
}


void
TimeTable::set(unsigned index, MoveInfoSet const& moveInfoSet, unsigned sciVersion)
{
	unsigned size = index + 1;

	if (m_table.size() < size)
		ensure(size);

	MoveInfoSet& set = m_table[index];

	set.resize(MoveInfo::LAST);

	for (unsigned i = 0; i < moveInfoSet.count(); ++i)
	{
		static_assert(MoveInfo::None == 0, "wrong index access");

		MoveInfo const&	info	= moveInfoSet[i];

		// docs/SCI_CORRESPONDENCE_FORMAT.md §4.3.2/§5: correspondence
		// durations have no time-table representation in ANY version; other
		// types without a binary representation at this version never enter.
		if (	!MoveInfo::isEncodable(info.content(), sciVersion)
				||	info.content() == MoveInfo::CorrespondenceClock
				||	info.content() == MoveInfo::CorrespondenceElapsed)
			continue;

		unsigned				col	= info.content() - 1;

		M_ASSERT(!info.isEmpty());

		set[col] = info;
		m_size[col] = mstl::max(m_size[col], size);
		m_types |= 1 << col;
	}
}


unsigned
TimeTable::columns() const
{
	return mstl::bf::count_bits(m_types);
}

// vi:set ts=3 sw=3:
