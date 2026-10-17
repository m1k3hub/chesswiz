// ======================================================================
//    _/|            __
//   // o\         /    )           ,        /    /
//   || ._)    ----\---------__----------__-/----/__-
//   //__\          \      /   '  /    /   /    /   )
//   )___(     _(____/____(___ __/____(___/____(___/_
// ======================================================================
// Copyright: (C) 2026 Michael Thomas (Chesswiz)
// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

// Tcl bindings for polyglot opening books: the reader and editor of
// src/app/app_polyglot_book.cpp. tcl/book.tcl builds the "Opening Book
// Editor" on top of these commands.
//
//   ::scidb::book::open <filename>
//       Open (or create) a polyglot book and return its handle. Only the
//       polyglot format is editable; .ctg books and scid mask files are
//       refused.
//   ::scidb::book::close <handle>
//   ::scidb::book::probe <handle> <fen> ?<variant>?
//       The moves of the position: a list of {san <S> uci <U> weight <W>
//       learn <L>}, weight first sorted (the heaviest move first).
//   ::scidb::book::add <handle> <fen> <san> ?<weight>? ?<learn>?
//       Add a move to the position (or update it); saved with save.
//   ::scidb::book::remove <handle> <fen> <san>
//   ::scidb::book::reweight <handle> <fen> <san> <weight>
//   ::scidb::book::save <handle>       write the book back to its file
//   ::scidb::book::count <handle>      the number of entries
//   ::scidb::book::modified <handle>   whether the book has unsaved edits
//   ::scidb::book::readonly <handle>
//   ::scidb::book::write <filename> <entries> ?<variant>?
//       Write a new book out of <entries>, a list of {fen san weight learn}
//       groups; weight and learn default to 1 and 0. "Create Book from
//       Database..." aggregates the games and ends up here.

#include "tcl_base.h"
#include "tcl_game.h"

#include "app_book.h"
#include "app_polyglot_book.h"

#include "db_board.h"
#include "db_common.h"
#include "db_exception.h"
#include "db_move.h"

#include "m_string.h"
#include "m_vector.h"

#include <tcl.h>
#include <string.h>

using namespace db;
using namespace app;
using namespace tcl;

namespace {

struct Handle
{
	Handle() :m_book(0), m_used(false) {}
	Handle(polyglot::Book* book) :m_book(book), m_used(true) {}

	polyglot::Book*	m_book;
	bool			m_used;
};

static mstl::vector<Handle> BookTable;


static char const* const CmdOpen		= "::scidb::book::open";
static char const* const CmdClose		= "::scidb::book::close";
static char const* const CmdProbe		= "::scidb::book::probe";
static char const* const CmdAdd			= "::scidb::book::add";
static char const* const CmdRemove		= "::scidb::book::remove";
static char const* const CmdReweight	= "::scidb::book::reweight";
static char const* const CmdSave		= "::scidb::book::save";
static char const* const CmdCount		= "::scidb::book::count";
static char const* const CmdModified	= "::scidb::book::modified";
static char const* const CmdReadonly	= "::scidb::book::readonly";
static char const* const CmdWrite		= "::scidb::book::write";


// The open book of <handle>, or an error when it was closed.
polyglot::Book*
bookFromHandle(Tcl_Interp* ti, Tcl_Obj* obj, char const* cmd)
{
	int index;

	if (	Tcl_GetIntFromObj(ti, obj, &index) != TCL_OK
		|| index < 1 || index > int(BookTable.size()) || BookTable[index - 1].m_used == false)
	{
		error(cmd, nullptr, nullptr, "unknown book handle '%s'", Tcl_GetString(obj));
		return nullptr;
	}

	return BookTable[index - 1].m_book;
}


// Parse a FEN; true (and a Tcl error) when it is not a valid position.
// Board::setup() returns the pointer where it stopped parsing, 0 on failure.
bool
setupBoardFailed(Board& board, char const* fen, variant::Type variant, char const* cmd)
{
	if (board.setup(fen, variant) == nullptr)
	{
		error(cmd, nullptr, nullptr, "invalid FEN '%s'", fen);
		return true;
	}

	return false;
}


// Parse a SAN move at <board>; TCL_ERROR (and a Tcl error message) when
// it is not a legal unambiguous move.
int
parseMove(Board& board, variant::Type variant, char const* san, Move& move, char const* cmd)
{
	move = board.parseMove(san, variant, move::MustBeUnambiguous);

	if (move.isEmpty() || !move.isValid())
		return error(cmd, nullptr, nullptr, "illegal or unknown move '%s'", san);

	return TCL_OK;
}


variant::Type
variantFromArgs(int objc, Tcl_Obj* const objv[], int index)
{
	if (index >= objc)
		return variant::Normal;

	variant::Type variant = tcl::game::variantFromObj(objv[index]);

	return variant == variant::Undetermined ? variant::Normal : variant;
}


int
cmdOpen(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 2)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<filename>");
		return TCL_ERROR;
	}

	mstl::string filename(stringFromObj(objc, objv, 1));
	Book* book = Book::open(filename);

	if (book->format() != Book::Polyglot)
	{
		delete book;
		setResult("not a polyglot book");
		return TCL_ERROR;
	}

	// Book::open built a polyglot::Book for everything but .ctg files
	polyglot::Book* polyglotBook = static_cast<polyglot::Book*>(book);

	// reuse a closed slot
	for (unsigned i = 0; i < BookTable.size(); ++i)
	{
		if (BookTable[i].m_used == false)
		{
			BookTable[i] = Handle(polyglotBook);
			setResult(int(i + 1));
			return TCL_OK;
		}
	}

	BookTable.push_back(Handle(polyglotBook));
	setResult(int(BookTable.size()));

	return TCL_OK;
}


int
cmdClose(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 2)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<handle>");
		return TCL_ERROR;
	}

	int index;

	if (	Tcl_GetIntFromObj(ti, objv[1], &index) != TCL_OK
		|| index < 1 || index > int(BookTable.size()) || BookTable[index - 1].m_used == false)
	{
		return error(CmdClose, nullptr, nullptr, "unknown book handle '%s'", Tcl_GetString(objv[1]));
	}

	delete BookTable[index - 1].m_book;
	BookTable[index - 1] = Handle();

	return TCL_OK;
}


int
cmdProbe(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc < 3 || objc > 4)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<handle> <fen> ?<variant>?");
		return TCL_ERROR;
	}

	polyglot::Book* book = bookFromHandle(ti, objv[1], CmdProbe);

	if (book == nullptr)
		return TCL_ERROR;

	Board			board;
	variant::Type	variant = variantFromArgs(objc, objv, 3);

	if (setupBoardFailed(board, stringFromObj(objc, objv, 2), variant, CmdProbe))
		return TCL_ERROR;

	Book::Entry entry;

	if (book->probePosition(board, variant, entry) == false)
	{
		setResult(Tcl_NewListObj(0, nullptr));
		return TCL_OK;
	}

	// the heaviest move first: sort the indices, the items stay in place
	mstl::vector<unsigned> order;

	for (unsigned i = 0; i < entry.items.size(); ++i)
		order.push_back(i);

	for (unsigned i = 1; i < order.size(); ++i)
	{
		for (unsigned j = i; j > 0 && entry.items[order[j]].weight > entry.items[order[j - 1]].weight; --j)
		{
			unsigned tmp(order[j]);
			order[j] = order[j - 1];
			order[j - 1] = tmp;
		}
	}

	Tcl_Obj* result = Tcl_NewListObj(0, nullptr);

	for (unsigned n = 0; n < order.size(); ++n)
	{
		unsigned	i			= order[n];
		Move		prepared	= entry.items[i].move;
		Move		move		= entry.items[i].move;

		board.prepareForPrint(prepared, variant, Board::ExternalRepresentation);

		mstl::string san;
		prepared.printSAN(san, protocol::Standard, encoding::Latin1);

		// standard chess UCI names the king's destination square
		Square to = move.to();

		if (move.isCastling() && variant::isNormalChess(variant))
		{
			Square from = move.from();
			bool kingside = sq::fyle(move.to()) > sq::fyle(from);
			to = sq::make(kingside ? sq::FyleG : sq::FyleC, sq::rank(from));
		}

		mstl::string uci;
		uci += sq::printAlgebraic(move.from());
		uci += sq::printAlgebraic(to);

		if (move.isPromotion())
		{
			char c = piece::print(move.promoted());
			if (c >= 'A' && c <= 'Z')
				c = char(c - 'A' + 'a');
			uci += c;
		}

		Tcl_Obj* item[8];
		item[0] = Tcl_NewStringObj("san", 3);
		item[1] = newObj(san);
		item[2] = Tcl_NewStringObj("uci", 3);
		item[3] = newObj(uci);
		item[4] = Tcl_NewStringObj("weight", 6);
		item[5] = newObj(unsigned(entry.items[i].weight));
		item[6] = Tcl_NewStringObj("learn", 5);
		item[7] = newObj(unsigned(	(uint32_t(entry.items[i].info.learnPoints) << 16)
										 | entry.items[i].info.learnCount));

		Tcl_ListObjAppendElement(ti, result, Tcl_NewListObj(8, item));
	}

	setResult(result);

	return TCL_OK;
}


int
cmdAdd(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc < 4 || objc > 6)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<handle> <fen> <san> ?<weight>? ?<learn>?");
		return TCL_ERROR;
	}

	polyglot::Book* book = bookFromHandle(ti, objv[1], CmdAdd);

	if (book == nullptr)
		return TCL_ERROR;

	Board			board;
	variant::Type	variant	= variant::Normal;
	unsigned		weight	= objc >= 5 ? unsignedFromObj(objc, objv, 4) : 1;
	unsigned		learn	= objc >= 6 ? unsignedFromObj(objc, objv, 5) : 0;

	if (setupBoardFailed(board, stringFromObj(objc, objv, 2), variant, CmdAdd))
		return TCL_ERROR;

	Move move;

	if (parseMove(board, variant, stringFromObj(objc, objv, 3), move, CmdAdd) != TCL_OK)
		return TCL_ERROR;

	setResult(book->addMove(board, variant, move, weight, learn));

	return TCL_OK;
}


int
cmdRemove(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc < 4 || objc > 5)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<handle> <fen> <san> ?<variant>?");
		return TCL_ERROR;
	}

	polyglot::Book* book = bookFromHandle(ti, objv[1], CmdRemove);

	if (book == nullptr)
		return TCL_ERROR;

	Board			board;
	variant::Type	variant = variantFromArgs(objc, objv, 4);

	if (setupBoardFailed(board, stringFromObj(objc, objv, 2), variant, CmdRemove))
		return TCL_ERROR;

	Move move;

	if (parseMove(board, variant, stringFromObj(objc, objv, 3), move, CmdRemove) != TCL_OK)
		return TCL_ERROR;

	setResult(book->removeMove(board, variant, move));

	return TCL_OK;
}


int
cmdReweight(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc < 5 || objc > 6)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<handle> <fen> <san> <weight> ?<variant>?");
		return TCL_ERROR;
	}

	polyglot::Book* book = bookFromHandle(ti, objv[1], CmdReweight);

	if (book == nullptr)
		return TCL_ERROR;

	Board			board;
	variant::Type	variant	= variantFromArgs(objc, objv, 5);
	unsigned		weight	= unsignedFromObj(objc, objv, 4);

	if (setupBoardFailed(board, stringFromObj(objc, objv, 2), variant, CmdReweight))
		return TCL_ERROR;

	Move move;

	if (parseMove(board, variant, stringFromObj(objc, objv, 3), move, CmdReweight) != TCL_OK)
		return TCL_ERROR;

	setResult(book->setWeight(board, variant, move, weight));

	return TCL_OK;
}


int
cmdSave(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 2)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<handle>");
		return TCL_ERROR;
	}

	polyglot::Book* book = bookFromHandle(ti, objv[1], CmdSave);

	if (book == nullptr)
		return TCL_ERROR;

	setResult(book->save());

	return TCL_OK;
}


int
cmdCount(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 2)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<handle>");
		return TCL_ERROR;
	}

	polyglot::Book* book = bookFromHandle(ti, objv[1], CmdCount);

	if (book == nullptr)
		return TCL_ERROR;

	setResult(book->countEntries());

	return TCL_OK;
}


int
cmdModified(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 2)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<handle>");
		return TCL_ERROR;
	}

	polyglot::Book* book = bookFromHandle(ti, objv[1], CmdModified);

	if (book == nullptr)
		return TCL_ERROR;

	setResult(book->isModified());

	return TCL_OK;
}


int
cmdReadonly(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 2)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<handle>");
		return TCL_ERROR;
	}

	polyglot::Book* book = bookFromHandle(ti, objv[1], CmdReadonly);

	if (book == nullptr)
		return TCL_ERROR;

	setResult(book->isReadonly());

	return TCL_OK;
}


// ::scidb::book::write <filename> <entries> ?<variant>?
//
// <entries> is a list of groups, each group a list {fen san ?weight?
// ?learn?} (weight and learn default to 1 and 0). A position may appear
// more than once; Book::write sorts and merges the duplicates, keeping
// the entry with the largest weight.
int
cmdWrite(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc < 3 || objc > 4)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<filename> <entries> ?<variant>?");
		return TCL_ERROR;
	}

	variant::Type	variant	= variantFromArgs(objc, objv, 3);
	Tcl_Obj*			list		= objv[2];
	int					size		= 0;

	if (Tcl_ListObjLength(ti, list, &size) != TCL_OK)
		return TCL_ERROR;

	polyglot::Book::RawEntries entries;

	for (int i = 0; i < size; ++i)
	{
		Tcl_Obj*	group	= nullptr;
		int			argc		= 0;
		Tcl_Obj**	objvGroup	= nullptr;

		if (Tcl_ListObjIndex(ti, list, i, &group) != TCL_OK)
			return TCL_ERROR;

		if (Tcl_ListObjGetElements(ti, group, &argc, &objvGroup) != TCL_OK)
			return TCL_ERROR;

		if (argc < 2 || argc > 4)
			return error(CmdWrite, nullptr, nullptr, "each entry must be {fen san ?weight? ?learn?}");

		Board board;

		if (setupBoardFailed(board, Tcl_GetString(objvGroup[0]), variant, CmdWrite))
			return TCL_ERROR;

		Move move;

		if (parseMove(board, variant, Tcl_GetString(objvGroup[1]), move, CmdWrite) != TCL_OK)
			return TCL_ERROR;

		polyglot::Book::RawEntry entry;

		entry.key		= polyglot::Book::hashKey(board, variant);
		entry.move		= polyglot::Book::encode(move);
		entry.weight	= argc >= 3 ? unsignedFromObj(argc, objvGroup, 2) : 1;
		entry.learn	= argc >= 4 ? unsignedFromObj(argc, objvGroup, 3) : 0;

		entries.push_back(entry);
	}

	polyglot::Book::write(stringFromObj(objc, objv, 1), entries);

	return TCL_OK;
}

} // namespace


namespace tcl {
namespace book {

void
init(Tcl_Interp* ti)
{
	createCommand(ti, CmdOpen,			cmdOpen);
	createCommand(ti, CmdClose,			cmdClose);
	createCommand(ti, CmdProbe,			cmdProbe);
	createCommand(ti, CmdAdd,			cmdAdd);
	createCommand(ti, CmdRemove,		cmdRemove);
	createCommand(ti, CmdReweight,		cmdReweight);
	createCommand(ti, CmdSave,			cmdSave);
	createCommand(ti, CmdCount,			cmdCount);
	createCommand(ti, CmdModified,		cmdModified);
	createCommand(ti, CmdReadonly,		cmdReadonly);
	createCommand(ti, CmdWrite,			cmdWrite);
}

} // namespace book
} // namespace tcl

// vi:set ts=3 sw=3: