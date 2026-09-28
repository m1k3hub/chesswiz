// ======================================================================
// Tcl bindings for the CQL (Chess Query Language) matcher in src/db/cql.
//
//   ::scidb::cql::parse  <script>
//       -> {ok 1 sections {positions ...} standard 0|1}
//        | {ok 0 error <Name> offset <n>}
//   ::scidb::cql::match  <database> <variant> <index> <script>
//       -> the first mainline ply at which the game satisfies the query
//          (0 = the start position), or -1. A position filter counts its
//          matches over the game (:matchcount), so a game matches from the
//          first satisfying position on; decoding stops there. A script
//          with only game-information filters answers 0 for a match.
//   ::scidb::cql::search <database> <variant> <script> ?<max>?
//       -> the indices of the matching games, at most <max> of them.
//   ::scidb::cql::position <fen> <script> ?<move>?
//       -> 1 when the position satisfies the query, else 0. With <move>
//          (SAN or LAN, played from <fen>) the move filters test that move
//          and the position filters the position after it; without one a
//          query with move filters is an error. Game-information filters
//          are an error: there is no game.
//
// The matcher only reads games; nothing is written. Positions inside
// variations are not visited (CQL's default is the main line). Comment
// filters are refused until they are wired to the comment stream.
// ======================================================================

#include "tcl_cql.h"
#include "tcl_application.h"
#include "tcl_base.h"
#include "tcl_game.h"

#include "app_application.h"
#include "app_cursor.h"

#include "cql_match.h"
#include "cql_game_matcher.h"

#include "db_board.h"
#include "db_database.h"
#include "db_move.h"
#include "db_game_info.h"

#include "m_exception.h"
#include "m_string.h"

#include <tcl.h>

using namespace db;
using namespace tcl;
using namespace tcl::app;

static char const* CmdParse	= "::scidb::cql::parse";
static char const* CmdMatch	= "::scidb::cql::match";
static char const* CmdSearch	= "::scidb::cql::search";
static char const* CmdPosition	= "::scidb::cql::position";

static char const* ErrorNames[] =
{
	"No_Error", "Unexpected_Comma", "Missing_Parameter", "Invalid_Keyword",
	"Invalid_Relation_Keyword", "Range_Expected", "Pattern_Expected", "Integer_Expected",
	"Invalid_Square_Designator", "Invalid_Evaluation_Mode", "Positive_Integer_Expected",
	"Double_Quote_Expected", "Unterminated_String", "Empty_String_Not_Allowed", "Invalid_Date",
	"Syntax_Error_In_Date", "Empty_Date_Range", "Illegal_Date", "Illegal_Date_Offset",
	"Invalid_Eco_Code", "Invalid_Rating_Type", "Invalid_Country_Code", "Illegal_Country_Code",
	"Invalid_Event_Mode", "Invalid_Event_Type", "Invalid_Game_Flag", "Invalid_Tag_Name",
	"Invalid_Gender", "Invalid_Result", "Invalid_Termination", "Invalid_Time_Mode",
	"Invalid_Title", "Invalid_Variant", "Invalid_Fen", "Invalid_Promotion_Ranks",
	"Invalid_FICS_Position", "Invalid_IDN", "Invalid_Range_Argument", "Invalid_Evaluation_View",
	"Invalid_Special_Marker", "Position_Number_Expected", "Integer_Out_Of_Range",
	"Unexpected_Token", "Left_Parenthesis_Expected", "Right_Parenthesis_Expected",
	"Trailing_Characters", "Keyword_Match_Expected", "Keyword_Position_Expected",
	"Position_List_Expected", "Keyword_Match_Or_Position_Expected", "Relation_List_Expected",
	"Position_List_Is_Not_Allowed", "Unmatched_Bracket", "Empty_Piece_Designator",
	"Invalid_Designator", "Any_Fyle_Not_Allowed_In_Range", "Any_Rank_Not_Allowed_In_Range",
	"Invalid_Fyle_In_Square_Designator", "Invalid_Rank_In_Square_Designator",
	"Missing_Rank_In_Square_Designator", "Not_Implemented",
};




// Parses <script> into <match>: Parsed, or Rejected with {ok 0 error NAME
// offset N} as the result when <report> (a plain message otherwise), or
// Failed when the parser itself broke (the message is the result).
enum ParseState { Parsed, Rejected, Failed };

static ParseState
parseScript(::cql::Match& match, char const* script, bool report)
{
	::cql::Match::Error error = ::cql::error::No_Error;
	char const* end = script;

	try
	{
		end = match.parse(script, error);
	}
	catch (mstl::exception const& exc)
	{
		setResult(Tcl_ObjPrintf("CQL parser failure: %s", exc.what()));
		return Failed;
	}

	if (error == ::cql::error::No_Error)
		return Parsed;

	if (report)
	{
		Tcl_Obj* objs[6] =
		{
			Tcl_NewStringObj("ok", -1), Tcl_NewIntObj(0),
			Tcl_NewStringObj("error", -1), Tcl_NewStringObj(tcl::cql::errorName(error), -1),
			Tcl_NewStringObj("offset", -1), Tcl_NewIntObj(int(end - script)),
		};
		setResult(6, objs);
	}
	else
	{
		setResult(Tcl_ObjPrintf("CQL error %s at offset %d", tcl::cql::errorName(error), int(end - script)));
	}
	return Rejected;
}


static int
cmdParse(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 2)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<script>");
		return TCL_ERROR;
	}

	::cql::Match match;

	switch (parseScript(match, stringFromObj(objc, objv, 1), true))
	{
		case Parsed:	break;
		case Rejected:	return TCL_OK;
		case Failed:	return TCL_ERROR;
	}

	unsigned sections = match.sections();
	Tcl_Obj* list = Tcl_NewListObj(0, nullptr);

	if (sections & ::cql::Match::Section_GameInfo)
		Tcl_ListObjAppendElement(ti, list, Tcl_NewStringObj("gameinfo", -1));
	if (sections & ::cql::Match::Section_Moves)
		Tcl_ListObjAppendElement(ti, list, Tcl_NewStringObj("moves", -1));
	if (sections & ::cql::Match::Section_Positions)
		Tcl_ListObjAppendElement(ti, list, Tcl_NewStringObj("positions", -1));
	if (sections & ::cql::Match::Section_Comments)
		Tcl_ListObjAppendElement(ti, list, Tcl_NewStringObj("comments", -1));
	if (sections & ::cql::Match::Section_Flags)
		Tcl_ListObjAppendElement(ti, list, Tcl_NewStringObj("flags", -1));

	Tcl_Obj* objs[6] =
	{
		Tcl_NewStringObj("ok", -1), Tcl_NewIntObj(1),
		Tcl_NewStringObj("sections", -1), list,
		Tcl_NewStringObj("standard", -1), Tcl_NewIntObj(match.isStandard()),
	};
	setResult(6, objs);
	return TCL_OK;
}


static bool
refuseComments(::cql::Match const& match)
{
	if (match.sections() & ::cql::Match::Section_Comments)
	{
		setResult("CQL comment filters are not supported yet");
		return true;
	}
	return false;
}


static int
cmdMatch(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 5)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant> <index> <script>");
		return TCL_ERROR;
	}

	char const*		base		= stringFromObj(objc, objv, 1);
	variant::Type	variant	= tcl::game::variantFromObj(objc, objv, 2);
	int				index		= intFromObj(objc, objv, 3);
	::cql::Match		match;

	if (parseScript(match, stringFromObj(objc, objv, 4), false) != Parsed || refuseComments(match))
		return TCL_ERROR;

	Database const& db = scidb->cursor(base, variant).database();

	if (index < 0 || unsigned(index) >= db.countGames())
	{
		setResult(Tcl_ObjPrintf("game index %d out of range", index));
		return TCL_ERROR;
	}

	int ply = -1;

	try
	{
		ply = ::cql::matchGame(db, variant, unsigned(index), match);
	}
	catch (mstl::exception const& exc)
	{
		setResult(Tcl_ObjPrintf("CQL matcher failure: %s", exc.what()));
		return TCL_ERROR;
	}

	setResult(ply);
	return TCL_OK;
}


static int
cmdSearch(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 4 && objc != 5)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant> <script> ?<max>?");
		return TCL_ERROR;
	}

	char const*		base		= stringFromObj(objc, objv, 1);
	variant::Type	variant	= tcl::game::variantFromObj(objc, objv, 2);
	char const*		script	= stringFromObj(objc, objv, 3);
	unsigned			maxHits	= objc == 5 ? unsigned(intFromObj(objc, objv, 4)) : 0u;

	{
		::cql::Match match;

		if (parseScript(match, script, false) != Parsed || refuseComments(match))
			return TCL_ERROR;
	}

	Database const&		db = scidb->cursor(base, variant).database();
	Tcl_Obj*					list = Tcl_NewListObj(0, nullptr);
	unsigned					hits = 0;

	try
	{
		for (unsigned i = 0, n = db.countGames(); i < n && (maxHits == 0 || hits < maxHits); ++i)
		{
			// a fresh matcher per game: nested position lists keep match
			// counts that Match::newGame does not reach
			::cql::Match match;
			::cql::Match::Error error;
			match.parse(script, error);

			if (::cql::matchGame(db, variant, i, match) >= 0)
			{
				Tcl_ListObjAppendElement(ti, list, Tcl_NewIntObj(i));
				++hits;
			}
		}
	}
	catch (mstl::exception const& exc)
	{
		Tcl_DecrRefCount(list);
		setResult(Tcl_ObjPrintf("CQL matcher failure: %s", exc.what()));
		return TCL_ERROR;
	}

	setResult(list);
	return TCL_OK;
}


static int
cmdPosition(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 3 && objc != 4)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<fen> <script> ?<move>?");
		return TCL_ERROR;
	}

	variant::Type	variant	= variant::Normal;
	char const*		fen		= stringFromObj(objc, objv, 1);
	char const*		san		= objc == 4 ? stringFromObj(objc, objv, 3) : nullptr;
	::cql::Match	match;

	if (parseScript(match, stringFromObj(objc, objv, 2), false) != Parsed || refuseComments(match))
		return TCL_ERROR;

	if (match.sections() & ::cql::Match::Section_GameInfo)
	{
		setResult("CQL game-information filters need a game");
		return TCL_ERROR;
	}
	if ((match.sections() & ::cql::Match::Section_Moves) && san == nullptr)
	{
		setResult("CQL move filters need a move");
		return TCL_ERROR;
	}

	Board board;

	if (board.setup(fen, variant) == nullptr)
	{
		setResult(Tcl_ObjPrintf("invalid FEN '%s'", fen));
		return TCL_ERROR;
	}

	bool result = true;

	try
	{
		GameInfo info;

		if (san)
		{
			Move move = board.parseMove(san, variant);

			if (!move.isLegal())
			{
				setResult(Tcl_ObjPrintf("illegal move '%s'", san));
				return TCL_ERROR;
			}

			if (match.sections() & ::cql::Match::Section_Moves)
				result = match.match(board, move, variant);

			board.doMove(move, variant);
		}

		if (result)
			result = match.match(info, board, variant, 0);
	}
	catch (mstl::exception const& exc)
	{
		setResult(Tcl_ObjPrintf("CQL matcher failure: %s", exc.what()));
		return TCL_ERROR;
	}

	setResult(result);
	return TCL_OK;
}


namespace tcl {
namespace cql {

char const*
errorName(int error)
{
	unsigned i = unsigned(error);
	return i < sizeof(ErrorNames)/sizeof(ErrorNames[0]) ? ErrorNames[i] : "Unknown_Error";
}


void
init(Tcl_Interp* ti)
{
	createCommand(ti, CmdParse,	cmdParse);
	createCommand(ti, CmdMatch,	cmdMatch);
	createCommand(ti, CmdSearch,	cmdSearch);
	createCommand(ti, CmdPosition,	cmdPosition);
}

} // namespace cql
} // namespace tcl

// vi:set ts=3 sw=3:
