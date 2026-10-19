// ======================================================================
//    _/|            __
//   // o\         /    )           ,        /    /
//   || ._)    ----\---------__----------__-/----/__-
//   //__\          \      /   '  /    /   /    /   )
//   )___(     _(____/____(___ __/____(___/____(___/_
// ======================================================================
//
// Tcl bindings for the chess-anatomy fact extractor -- see tcl_ai.h.
//
// ======================================================================

#include "tcl_ai.h"
#include "tcl_game.h"
#include "tcl_application.h"
#include "tcl_base.h"

#include "app_application.h"

#include "db_board.h"
#include "db_chess_facts.h"
#include "db_eco.h"
#include "db_eco_table.h"
#include "db_game.h"
#include "db_line.h"
#include "db_move.h"

#include "m_string.h"

#include <tcl.h>
#include <stdio.h>
#include <string.h>

using namespace db;
using namespace tcl;
using namespace tcl::app;

static char const* CmdFacts     = "::scidb::ai::facts";
static char const* CmdText      = "::scidb::ai::text";
static char const* CmdMoveFacts = "::scidb::ai::moveFacts";
static char const* CmdClaim     = "::scidb::ai::claim";
static char const* CmdClaimFor  = "::scidb::ai::claimFor";
static char const* CmdEco       = "::scidb::ai::eco";

static int
sideFrom(char const* s)
{
	if (s == 0) return 0;
	if (::strcmp(s, "white") == 0 || ::strcmp(s, "w") == 0) return 1;
	if (::strcmp(s, "black") == 0 || ::strcmp(s, "b") == 0) return 2;
	return -1;
}

static bool
setupBoard(Board& board, char const* fen)
{
	return board.setup(fen, variant::Normal) != 0;
}

static int
cmdFacts(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	mstl::string result;

	if (objc == 1)
	{
		ChessFacts::toJson(Scidb->game().currentBoard(), Scidb->game().variant(), result);
	}
	else if (objc == 2)
	{
		Board board;

		if (!setupBoard(board, stringFromObj(objc, objv, 1)))
		{
			setResult("invalid FEN");
			return TCL_ERROR;
		}

		ChessFacts::toJson(board, variant::Normal, result);
	}
	else
	{
		Tcl_WrongNumArgs(ti, 1, objv, "?fen?");
		return TCL_ERROR;
	}

	setResult(result);
	return TCL_OK;
}

static int
cmdText(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	mstl::string result;

	if (objc == 1)
	{
		ChessFacts::toText(Scidb->game().currentBoard(), Scidb->game().variant(), result);
	}
	else if (objc == 2)
	{
		Board board;

		if (!setupBoard(board, stringFromObj(objc, objv, 1)))
		{
			setResult("invalid FEN");
			return TCL_ERROR;
		}

		ChessFacts::toText(board, variant::Normal, result);
	}
	else
	{
		Tcl_WrongNumArgs(ti, 1, objv, "?fen?");
		return TCL_ERROR;
	}

	setResult(result);
	return TCL_OK;
}

static int
cmdMoveFacts(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc < 2 || objc > 4)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "move ?fen? ?variant?");
		return TCL_ERROR;
	}

	char const* const	token = stringFromObj(objc, objv, 1);
	mstl::string		result;

	if (objc >= 3)
	{
		Board board;
		variant::Type const variant = objc == 4 ? tcl::game::variantFromObj(objv[3]) : variant::Normal;

		if (!board.setup(stringFromObj(objc, objv, 2), variant))
		{
			setResult("invalid FEN");
			return TCL_ERROR;
		}

		Move move = board.parseMove(token, variant);

		if (move.isEmpty() || !move.isValid())
		{
			setResult("illegal or unknown move");
			return TCL_ERROR;
		}

		ChessFacts::toMoveJson(board, move, variant, result);
	}
	else
	{
		Board const&		board = Scidb->game().currentBoard();
		variant::Type const	variant = Scidb->game().variant();

		Move move = board.parseMove(token, variant);

		if (move.isEmpty() || !move.isValid())
		{
			setResult("illegal or unknown move");
			return TCL_ERROR;
		}

		ChessFacts::toMoveJson(board, move, variant, result);
	}

	setResult(result);
	return TCL_OK;
}

static int
cmdClaim(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc < 2 || objc > 3)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "term ?white|black?");
		return TCL_ERROR;
	}

	char const* const term = stringFromObj(objc, objv, 1);
	int side = 0;

	if (objc == 3)
	{
		side = sideFrom(stringFromObj(objc, objv, 2));
		if (side < 0) { setResult("side must be white or black"); return TCL_ERROR; }
	}

	bool known = false;
	bool const holds = ChessFacts::claim(Scidb->game().currentBoard(), term, side, known);

	if (!known) { setResult("unknown claim term"); return TCL_ERROR; }

	setResult(holds);
	return TCL_OK;
}

static int
cmdClaimFor(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc < 3 || objc > 4)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "fen term ?white|black?");
		return TCL_ERROR;
	}

	Board board;

	if (!setupBoard(board, stringFromObj(objc, objv, 1)))
	{
		setResult("invalid FEN");
		return TCL_ERROR;
	}

	char const* const term = stringFromObj(objc, objv, 2);
	int side = 0;

	if (objc == 4)
	{
		side = sideFrom(stringFromObj(objc, objv, 3));
		if (side < 0) { setResult("side must be white or black"); return TCL_ERROR; }
	}

	bool known = false;
	bool const holds = ChessFacts::claim(board, term, side, known);

	if (!known) { setResult("unknown claim term"); return TCL_ERROR; }

	setResult(holds);
	return TCL_OK;
}

static int
cmdEco(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc < 2 || objc > 3)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "moves ?startFen?");
		return TCL_ERROR;
	}

	variant::Type const variant = variant::Normal;

	Board startBoard;

	if (objc == 3)
	{
		if (!setupBoard(startBoard, stringFromObj(objc, objv, 2)))
		{
			setResult("invalid FEN");
			return TCL_ERROR;
		}
	}
	else
	{
		startBoard = Board::standardBoard(variant);
	}

	EcoTable const& table = EcoTable::specimen(variant::Index_Normal);

	if (!table.isLoaded())
	{
		setResult("ECO table not loaded (::scidb::app::load eco <path>)");
		return TCL_ERROR;
	}

	Board		board(startBoard);
	uint16_t		buf[opening::Max_Line_Length];
	unsigned		n = 0;
	int			ntoks;
	Tcl_Obj**	toks;

	// split as a Tcl list: no fixed-size copy that could cut a move in half
	if (Tcl_ListObjGetElements(ti, objv[1], &ntoks, &toks) != TCL_OK)
		return TCL_ERROR;

	// the ECO classification only needs the opening prefix
	if (ntoks > int(opening::Max_Line_Length))
		ntoks = int(opening::Max_Line_Length);

	for (int i = 0; i < ntoks; ++i)
	{
		Move move = board.parseMove(Tcl_GetString(toks[i]), variant);

		if (move.isEmpty() || !move.isValid())
		{
			setResult("illegal or unknown move");
			return TCL_ERROR;
		}

		buf[n++] = uint16_t(move.index());
		board.doMove(move, variant);
	}

	Line line(buf, n);
	Eco const eco = table.getEco(startBoard, line);
	EcoTable::Opening const& opening = table.getOpening(eco);

	mstl::string code = eco.asShortString();
	mstl::string name;

	for (unsigned i = 0; i < EcoTable::Num_Name_Parts; ++i)
	{
		mstl::string const& part = opening.part[i];

		if (part.empty())
			continue;
		if (!name.empty())
			name += " / ";
		name += part;
	}

	Tcl_Obj* dict = Tcl_NewDictObj();
	Tcl_DictObjPut(ti, dict, Tcl_NewStringObj("code", -1), Tcl_NewStringObj(code.c_str(), int(code.size())));
	Tcl_DictObjPut(ti, dict, Tcl_NewStringObj("name", -1), Tcl_NewStringObj(name.c_str(), int(name.size())));
	Tcl_SetObjResult(ti, dict);
	return TCL_OK;
}


namespace tcl {
namespace ai {

void
init(Tcl_Interp* ti)
{
	createCommand(ti, CmdFacts,		cmdFacts);
	createCommand(ti, CmdText,		cmdText);
	createCommand(ti, CmdMoveFacts,	cmdMoveFacts);
	createCommand(ti, CmdClaim,		cmdClaim);
	createCommand(ti, CmdClaimFor,	cmdClaimFor);
	createCommand(ti, CmdEco,			cmdEco);
}

} // namespace ai
} // namespace tcl

// vi:set ts=3 sw=3:
