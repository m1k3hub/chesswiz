// ======================================================================
// Author : $Author: gcramer $
// Version: $Revision: 1411 $
// Date   : $Date: 2017-08-12 07:08:17 -0400 (Sat, 12 Aug 2017) $
// Url    : $HeadURL: https://svn.code.sf.net/p/scidb/code/trunk/src/eco/eco_tree_writer.h $
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

#ifndef _eco_tree_writer_included
#define _eco_tree_writer_included

#include "eco_writer.h"

#include "m_stack.h"
#include "m_bitfield.h"

namespace eco {

class Branch;
class Node;
class Name;

class TreeWriter : public Writer
{
public:

	TreeWriter(mstl::ostream& strm);

	void print(Node const* root) override;
	void visit(Node const& node) override;
	auto branch(Branch const& branch) -> bool override;
	void finishBranch(Branch const&) override;

private:

	using BranchStack	= mstl::stack<Branch const*>;
	using NameStack	= mstl::stack<Name const*>;
	using LevelStack	= mstl::stack<unsigned>;
	using ParentStack	= mstl::stack<Node const*>;
	using LineBits		= mstl::bitfield<uint64_t>;

	void dumpLine(Node const& node);

	BranchStack		m_branchStack;
	NameStack		m_nameStack;
	LevelStack		m_levelStack;
	LevelStack		m_depthStack;
	ParentStack		m_parentStack;
	unsigned			m_transpositionLevel;
	bool				m_break;
	LineBits			m_lineBits;
};

} // namespace eco

#endif // _eco_tree_writer_included

// vi:set ts=3 sw=3:
