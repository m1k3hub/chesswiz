// ======================================================================
// Author : Michael Thomas
// ======================================================================
// Copyright: (C) 2026 Michael Thomas (Chesswiz)
// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

// Local Syzygy endgame tablebases, probed through Fathom (fathom/, MIT):
//
//   ::scidb::tb::init <folder>   load the tables of a folder (paths separated
//                                as on the platform); returns the largest
//                                piece count covered, 0 for none
//   ::scidb::tb::largest         that number again
//   ::scidb::tb::probe <fen>     the verdict, or "" when the position is not
//                                covered (too many pieces, castling rights,
//                                tables missing):
//       {category C dtz N checkmate B stalemate B moves {{uci U category C dtz N} ...}}
//   with the categories of the Lichess tablebase API: the position's from the
//   side to move's view, each move's from the view of the side to move after
//   it (win, cursed-win, draw, blessed-loss, loss), so tcl/tablebase.tcl
//   summarises both sources the same way.

#include "tcl_base.h"

#include <tcl.h>
#include <string.h>
#include <stdlib.h>

#include "fathom/tbprobe.c"

namespace {

bool Initialized = false;

char const* const Category[5] = { "loss", "blessed-loss", "draw", "cursed-win", "win" };


// Bitboards (bit 0 = a1) and state out of a FEN; false on a malformed one.
struct Position
{
	uint64_t white = 0, black = 0;
	uint64_t kings = 0, queens = 0, rooks = 0, bishops = 0, knights = 0, pawns = 0;
	unsigned rule50 = 0, castling = 0, ep = 0;
	bool turn = true;
};

bool
parseFen(char const* fen, Position& p)
{
	int rank = 7, file = 0;
	char const* s = fen;

	for ( ; *s && *s != ' '; ++s)
	{
		char c = *s;
		if (c == '/') { --rank; file = 0; continue; }
		if (c >= '1' && c <= '8') { file += c - '0'; continue; }
		if (rank < 0 || file > 7) return false;

		uint64_t bit = uint64_t(1) << (rank*8 + file++);
		bool isWhite = (c >= 'A' && c <= 'Z');
		(isWhite ? p.white : p.black) |= bit;

		switch (c | 0x20)
		{
			case 'k': p.kings |= bit; break;
			case 'q': p.queens |= bit; break;
			case 'r': p.rooks |= bit; break;
			case 'b': p.bishops |= bit; break;
			case 'n': p.knights |= bit; break;
			case 'p': p.pawns |= bit; break;
			default: return false;
		}
	}
	if (*s++ != ' ') return false;
	if (*s != 'w' && *s != 'b') return false;
	p.turn = (*s++ == 'w');
	while (*s == ' ') ++s;

	// castling rights: the tables do not cover them
	if (*s == '-') ++s;
	else for ( ; *s && *s != ' '; ++s) p.castling = 1;
	while (*s == ' ') ++s;

	if (*s >= 'a' && *s <= 'h' && s[1] >= '1' && s[1] <= '8')
	{
		p.ep = (s[1] - '1')*8 + (s[0] - 'a');
		s += 2;
	}
	else if (*s == '-')
	{
		++s;
	}
	while (*s == ' ') ++s;
	if (*s >= '0' && *s <= '9') p.rule50 = unsigned(atoi(s));
	return true;
}


Tcl_Obj*
uciMove(unsigned res)
{
	static char const Promo[] = { 0, 'q', 'r', 'b', 'n' };
	unsigned from = TB_GET_FROM(res), to = TB_GET_TO(res), promo = TB_GET_PROMOTES(res);
	char buf[6] = { char('a' + (from & 7)), char('1' + (from >> 3)),
						 char('a' + (to & 7)), char('1' + (to >> 3)), 0, 0 };
	if (promo > 0 && promo < 5) buf[4] = Promo[promo];
	return Tcl_NewStringObj(buf, -1);
}


void
appendPair(Tcl_Obj* list, char const* key, Tcl_Obj* value)
{
	Tcl_ListObjAppendElement(0, list, Tcl_NewStringObj(key, -1));
	Tcl_ListObjAppendElement(0, list, value);
}


int
cmdInit(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 2)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "folder");
		return TCL_ERROR;
	}
	char const* path = Tcl_GetString(objv[1]);
	if (Initialized) tb_free();
	Initialized = (*path && tb_init(path));
	Tcl_SetObjResult(ti, Tcl_NewIntObj(Initialized ? int(TB_LARGEST) : 0));
	return TCL_OK;
}


int
cmdLargest(ClientData, Tcl_Interp* ti, int, Tcl_Obj* const[])
{
	Tcl_SetObjResult(ti, Tcl_NewIntObj(Initialized ? int(TB_LARGEST) : 0));
	return TCL_OK;
}


int
cmdProbe(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 2)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "fen");
		return TCL_ERROR;
	}

	Position p;
	if (!Initialized || !parseFen(Tcl_GetString(objv[1]), p) || p.castling)
		return TCL_OK;	// "": not covered
	if (unsigned(__builtin_popcountll(p.white | p.black)) > TB_LARGEST)
		return TCL_OK;

	unsigned results[TB_MAX_MOVES];
	unsigned res = tb_probe_root(p.white, p.black, p.kings, p.queens, p.rooks, p.bishops,
										  p.knights, p.pawns, p.rule50, p.castling, p.ep, p.turn, results);
	if (res == TB_RESULT_FAILED)
		return TCL_OK;

	Tcl_Obj* out = Tcl_NewListObj(0, 0);
	bool mate = (res == TB_RESULT_CHECKMATE);
	bool stale = (res == TB_RESULT_STALEMATE);
	// at checkmate the side to move has lost
	unsigned wdl = mate ? TB_LOSS : TB_GET_WDL(res);
	appendPair(out, "category", Tcl_NewStringObj(Category[wdl], -1));
	appendPair(out, "dtz", Tcl_NewIntObj(int(TB_GET_DTZ(res))));
	appendPair(out, "checkmate", Tcl_NewStringObj(mate ? "true" : "false", -1));
	appendPair(out, "stalemate", Tcl_NewStringObj(stale ? "true" : "false", -1));

	Tcl_Obj* moves = Tcl_NewListObj(0, 0);
	if (!mate && !stale)
	{
		for (unsigned i = 0; results[i] != TB_RESULT_FAILED; ++i)
		{
			Tcl_Obj* move = Tcl_NewListObj(0, 0);
			appendPair(move, "uci", uciMove(results[i]));
			// the move's WDL is the mover's; the category is the opponent's
			appendPair(move, "category", Tcl_NewStringObj(Category[4 - TB_GET_WDL(results[i])], -1));
			appendPair(move, "dtz", Tcl_NewIntObj(int(TB_GET_DTZ(results[i]))));
			Tcl_ListObjAppendElement(0, moves, move);
		}
	}
	appendPair(out, "moves", moves);
	Tcl_SetObjResult(ti, out);
	return TCL_OK;
}

} // namespace


namespace tcl {
namespace tablebase {

void
init(Tcl_Interp* ti)
{
	Tcl_CreateObjCommand(ti, "::scidb::tb::init",    cmdInit,    0, 0);
	Tcl_CreateObjCommand(ti, "::scidb::tb::largest", cmdLargest, 0, 0);
	Tcl_CreateObjCommand(ti, "::scidb::tb::probe",   cmdProbe,   0, 0);
}

} // namespace tablebase
} // namespace tcl

// vi:set ts=3 sw=3:
