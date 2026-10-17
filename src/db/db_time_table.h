// ======================================================================
// Author : $Author$
// Version: $Revision: 661 $
// Date   : $Date: 2013-02-23 18:03:04 -0500 (Sat, 23 Feb 2013) $
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
// Modified for Chesswiz, 2026; see docs/UPSTREAM.md
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#ifndef _db_time_table_included
#define _db_time_table_included

#include "db_move_info_set.h"

#include "m_vector.h"

namespace db {

class TimeTable
{
public:

	TimeTable();

	MoveInfoSet const& operator[](unsigned index) const;

	bool isEmpty() const;

	unsigned size() const;
	unsigned size(unsigned col) const;
	unsigned columns() const;
	unsigned types() const;

	MoveInfo const& get(unsigned index, MoveInfo::Type type) const;

	void clear();
	void cut(unsigned newSize);
	void reserve(unsigned capacity);
	void ensure(unsigned size);
	void set(unsigned index, MoveInfo const& moveInfo);
	void set(unsigned index, MoveInfoSet const& moveInfoSet);
	/// Version-aware variant: skips move-info types that are not binary-
	/// encodable at the given SCI version (docs/formats/SCI_CORRESPONDENCE_FORMAT.md §5).
	void set(unsigned index, MoveInfoSet const& moveInfoSet, unsigned sciVersion);
	void swap(TimeTable& table);

private:

	typedef mstl::vector<MoveInfoSet> Table;

	Table		m_table;
	unsigned	m_types;
	unsigned	m_size[MoveInfo::LAST];
};

} // namespace db

#include "db_time_table.ipp"

#endif // _db_time_table_included

// vi:set ts=3 sw=3:
