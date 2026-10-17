// ======================================================================
// Author : $Author$
// Version: $Revision: 957 $
// Date   : $Date: 2013-09-30 17:11:24 +0200 (Mon, 30 Sep 2013) $
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
// Copyright: (C) 2013 Gregor Cramer
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#ifndef _app_polyglot_book_included
#define _app_polyglot_book_included

#include "app_book.h"

#include "u_rkiss.h"

namespace db { class Move; }
namespace sys  { namespace file { class Mapping; } }
namespace mstl { template <typename Key, typename Value> class hash; }
namespace mstl { class ifstream; }
namespace mstl { template <typename T> class vector; }

namespace app {
namespace polyglot {

class Book : public app::Book
{
public:

	Book(mstl::string const& filename);
	~Book();

	bool isReadonly() const override;
	bool isOpen() const override;
	bool isEmpty() const override;
	bool isModified() const override;
	bool isPersistent() const override;

	Format format() const override;

	db::Move probeMove(db::Board const& position, db::variant::Type variant, Choice choice) override;
	bool probePosition(db::Board const& position, db::variant::Type variant, Entry& result) override;

	bool remove(db::Board const& position, db::variant::Type variant) override;
	bool modify(db::Board const& position, db::variant::Type variant, Entry const& entry) override;
	bool add(db::Board const& position, db::variant::Type variant, Entry const& entry) override;

	// --------------------------------------------------------------------
	// Writing and editing (the opening book editor)
	// --------------------------------------------------------------------

	// A raw polyglot entry as it is stored in the file: the hash key of the
	// position, the encoded move, the move's weight, and the learn field
	// (learn points in the high half, learn count in the low one, the
	// reader's n and sum).
	struct RawEntry
	{
		RawEntry();

		uint64_t	key;
		uint16_t	move;
		uint16_t	weight;
		uint32_t	learn;
	};

	typedef mstl::vector<RawEntry> RawEntries;

	// The polyglot hash key of <position> (the standard polyglot Zobrist keys).
	static uint64_t hashKey(db::Board const& position, db::variant::Type variant);

	// The polyglot encoding of <move> as in the polyglot spec: from and to
	// square and the promoted (or dropped) piece; castling as the king
	// moving two squares.
	static uint16_t encode(db::Move move);

	// Write a polyglot book: the entries are sorted by key (and move) and
	// written as 16-byte records; an empty list writes an empty book.
	static void write(mstl::string const& filename, RawEntries const& entries);

	// Add a move to the position (updates weight and learn when the move is
	// already in the book); saved with save().
	bool addMove(  db::Board const& position,
					  db::variant::Type variant,
					  db::Move move,
					  unsigned weight,
					  unsigned learn);

	// Remove a move from the position; true when the move was in the book.
	bool removeMove(db::Board const& position, db::variant::Type variant, db::Move move);

	// Change the weight of a move; true when the move was in the book.
	bool setWeight(db::Board const& position, db::variant::Type variant, db::Move move, unsigned weight);

	// Write the book back to its file; false when it is read only.
	bool save();

	// The number of entries (moves over all positions).
	unsigned countEntries() const;

private:

	typedef sys::file::Mapping Mapping;
	typedef mstl::hash<uint64_t, Entry> Map;

	struct MyEntry
	{
		uint64_t key;
		uint16_t move;
		uint16_t weight;
		uint16_t n;
		uint16_t sum;

		void fill(db::Byte const* src);
		void write(db::Byte* dst) const;
	};

	bool readEntry(unsigned offset, MyEntry& entry);
	void writeEntry();
	unsigned findKey(uint64_t key);
	void readScidMaskFile(mstl::ifstream& strm);

	// The whole book as raw entries, the editor's model. It is loaded when
	// the file is opened and is what the editor reads and changes; save()
	// turns it back into a polyglot file.
	void loadModel();
	bool findEntry(uint64_t key, uint16_t move, unsigned& index) const;

	Format			m_format;
	Mapping*			m_mapping;
	Map*				m_entryMap;
	unsigned			m_bookSize;
	unsigned			m_currentOffs;
	MyEntry			m_current;
	bool				m_someRemoved;
	bool				m_someModified;
	unsigned			m_used;
	util::RKiss		m_rkiss;

	RawEntries		m_model;			// the raw entries, sorted by key and move
	bool				m_modelLoaded;
	bool				m_modelModified;
};

} // namespace polyglot
} // namespace app

#endif // _app_polyglot_book_included

// vi:set ts=3 sw=3:
