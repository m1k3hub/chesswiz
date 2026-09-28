// ======================================================================
// Author : $Author$
// Version: $Revision$
// Date   : $Date$
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
// Copyright: (C) 2009-2013 Gregor Cramer
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#include "tcl_search.h"

#include "tcl_base.h"
#include "tcl_game.h"

#include "db_database.h"
#include "db_search.h"
#include "cql_match.h"
#include "tcl_cql.h"
#include "db_common.h"
#include "db_game_info.h"

#include "si3/si3_encoder.h"

#include "m_string.h"
#include "m_assert.h"
#include "m_exception.h"

#include <tcl.h>
#include <ctype.h>
#include <string.h>

using namespace db;
using namespace tcl;


static char const* CmdSearch = "::scidb::view::search";


namespace {

// ---- Helper: unified range parser (Remedy 5) ----

// Parses "N" or "N-M" into (minValue, maxValue) with an upper bound of `max`.
// Used for both pawn ranges (max=15) and rating ranges (max=4000).
static bool
parseRange(Tcl_Interp* ti, Tcl_Obj* obj, unsigned max, unsigned& minValue, unsigned& maxValue)
{
	mstl::string text(Tcl_GetString(obj));
	mstl::string::size_type sep = text.find('-');

	if (sep == mstl::string::npos)
	{
		int value;
		if (Tcl_GetIntFromObj(ti, obj, &value) != TCL_OK || value < 0 || value > int(max))
			return false;
		minValue = maxValue = unsigned(value);
		return true;
	}

	mstl::string lhs(text, 0, sep);
	mstl::string rhs(text, sep + 1);
	if (lhs.empty() || rhs.empty())
		return false;

	char* end;
	long low = ::strtol(lhs.c_str(), &end, 10);
	if (*end != '\0')
		return false;
	long high = ::strtol(rhs.c_str(), &end, 10);
	if (*end != '\0')
		return false;

	if (low < 0 || high < 0 || low > high || high > long(max))
		return false;

	minValue = unsigned(low);
	maxValue = unsigned(high);
	return true;
}


// ---- Helper: date bound -> year*10000 + month*100 + day ----

// "YYYY", "YYYY.MM" or "YYYY.MM.DD"; missing parts of an upper bound extend
// to the end of the year or month.
static bool
parseDateKey(char const* text, bool upper, unsigned& key)
{
	unsigned parts[3] = { 0, 0, 0 };
	unsigned n = 0;

	while (n < 3)
	{
		if (!::isdigit(static_cast<unsigned char>(*text)))
			return false;

		while (::isdigit(static_cast<unsigned char>(*text)))
			parts[n] = 10*parts[n] + (*text++ - '0');

		++n;

		if (*text == '\0')
			break;
		if (*text++ != '.')
			return false;
	}

	if (*text != '\0' || parts[0] == 0 || parts[0] > 9999 || parts[1] > 12 || parts[2] > 31)
		return false;

	if (upper)
	{
		if (n < 2) parts[1] = 99;
		if (n < 3) parts[2] = 99;
	}

	key = 10000*parts[0] + 100*parts[1] + parts[2];
	return true;
}


// ---- Helper: decode literal pattern (exact vs glob) ----

static mstl::string
decodeLiteralPattern(char const* text, bool& exact)
{
	exact = false;
	if (text == nullptr)
		return mstl::string();

	if (*text == '=')
	{
		exact = true;
		++text;
	}

	return mstl::string(text);
}


// ---- Helper: name-search factory (Remedy 6) ----

// Constructs a SearchXxxName from a Tcl query argument. Returns null and
// reports an error if the argument is missing or empty.
template <typename T>
static SearchP
makeNameSearch(char const* cmd, char const* label, int objc, Tcl_Obj* const objv[])
{
	if (objc != 2 || *Tcl_GetString(objv[1]) == '\0')
	{
		error(cmd, label, 0, "invalid query");
		return SearchP();
	}
	bool exact = false;
	mstl::string decoded = decodeLiteralPattern(Tcl_GetString(objv[1]), exact);
	return SearchP(new T(decoded, exact));
}


// ---- Helper: material signature parsing ----

static bool
parseMaterialPart(mstl::string const& text, material::si3::Signature& sig, bool white)
{
	mstl::string const& queen = piece::utf8::asString(piece::Queen);
	mstl::string const& rook = piece::utf8::asString(piece::Rook);
	mstl::string const& bishop = piece::utf8::asString(piece::Bishop);
	mstl::string const& knight = piece::utf8::asString(piece::Knight);
	unsigned queens = 0;
	unsigned rooks = 0;
	unsigned bishops = 0;
	unsigned knights = 0;
	unsigned pawns = 0;
	bool seenPawns = false;

	for (mstl::string::size_type i = 0; i < text.size(); )
	{
		if (i + queen.size() <= text.size() && mstl::string(text, i, queen.size()) == queen)
		{
			++queens;
			i += queen.size();
		}
		else if (i + rook.size() <= text.size() && mstl::string(text, i, rook.size()) == rook)
		{
			++rooks;
			i += rook.size();
		}
		else if (i + bishop.size() <= text.size() && mstl::string(text, i, bishop.size()) == bishop)
		{
			++bishops;
			i += bishop.size();
		}
		else if (i + knight.size() <= text.size() && mstl::string(text, i, knight.size()) == knight)
		{
			++knights;
			i += knight.size();
		}
		else
		{
			unsigned char c = text[i];

			switch (::tolower(c))
			{
				case 'q': ++queens; ++i; break;
				case 'r': ++rooks; ++i; break;
				case 'b': ++bishops; ++i; break;
				case 'n': ++knights; ++i; break;

				default:
					if (!::isdigit(c))
						return false;

					seenPawns = true;
					pawns = 10*pawns + (c - '0');
					++i;
					break;
			}
		}
	}

	if (!seenPawns && queens == 0 && rooks == 0 && bishops == 0 && knights == 0)
		return false;
	if (queens > 3 || rooks > 3 || bishops > 3 || knights > 3 || pawns > 15)
		return false;

	if (white)
	{
		sig.wq = queens;
		sig.wr = rooks;
		sig.wb = bishops;
		sig.wn = knights;
		sig.wp = pawns;
	}
	else
	{
		sig.bq = queens;
		sig.br = rooks;
		sig.bb = bishops;
		sig.bn = knights;
		sig.bp = pawns;
	}

	return true;
}


static bool
parseMaterialSignature(Tcl_Interp* ti, Tcl_Obj* obj, material::si3::Signature& sig)
{
	int objc = 0;
	Tcl_Obj** objv = 0;

	if (Tcl_ListObjGetElements(ti, obj, &objc, &objv) == TCL_OK && objc == 10)
	{
		unsigned values[10];

		for (int i = 0; i < objc; ++i)
		{
			int value;
			if (Tcl_GetIntFromObj(ti, objv[i], &value) != TCL_OK || value < 0)
				return false;
			values[i] = unsigned(value);
		}

		if (	values[0] > 3 || values[1] > 3 || values[2] > 3 || values[3] > 3 || values[4] > 15
			||	values[5] > 3 || values[6] > 3 || values[7] > 3 || values[8] > 3 || values[9] > 15)
		{
			return false;
		}

		sig.wq = values[0];
		sig.wr = values[1];
		sig.wb = values[2];
		sig.wn = values[3];
		sig.wp = values[4];
		sig.bq = values[5];
		sig.br = values[6];
		sig.bb = values[7];
		sig.bn = values[8];
		sig.bp = values[9];
		return true;
	}

	mstl::string text(Tcl_GetString(obj));
	mstl::string::size_type sep = text.find(':');

	if (sep == mstl::string::npos)
		return false;

	mstl::string white(text, 0, sep);
	mstl::string black(text, sep + 1);

	return parseMaterialPart(white, sig, true)
		&& parseMaterialPart(black, sig, false);
}

} // namespace


SearchP
tcl::search::buildSearch(Database const& db, Tcl_Interp* ti, Tcl_Obj* query)
{
	int objc;
	Tcl_Obj** objv;

	Tcl_ListObjGetElements(ti, query, &objc, &objv);

	if (objc < 2)
	{
		error(CmdSearch, 0, 0, "invalid query");
		return SearchP();
	}

	static char const* subcommands[] =
	{
		"OR", "AND", "NOT", "REMOVE", "RESET", "NULL",
		"player", "event", "site", "gameevent", "annotator", "position",
		"playername", "eventname", "sitename", "annotatorname", "eco",
		"material", "rating", "ecorange", "date", "result", "cql",
		nullptr
	};
	// Must stay parallel to subcommands[]: usage() iterates until the
	// subcommands terminator and dereferences args[i] for every entry.
	static char const* args[] =
	{
		"<query>+",										// OR
		"<query>+",										// AND
		"<query>",										// NOT
		nullptr,											// REMOVE
		nullptr,											// RESET
		nullptr,											// NULL
		"<index>",										// player
		"<index>",										// event
		"<index>",										// site
		"<index>",										// gameevent
		"<name>",										// annotator
		"<idn>",											// position
		"?white|black|any? <name>",				// playername
		"<name>",										// eventname
		"<name>",										// sitename
		"<name>",										// annotatorname
		"<eco>",											// eco
		"?exact|class|pawns? <signature>",		// material
		"<type> white|black|average|both <range> ?<range>?",	// rating
		"<eco-from> <eco-to>",						// ecorange
		"<from> <to>",									// date: YYYY, YYYY.MM or YYYY.MM.DD
		"1-0|0-1|1/2-1/2",							// result
		"<cql-script>",								// cql
		nullptr
	};
	enum
	{
		Or, And, Not, Remove, Reset, Null, Player, Event, Site, GameEvent, Annotator, Position,
		PlayerName, EventName, SiteName, AnnotatorName, Eco, Material, Rating, EcoRange, DateRange,
		Result, Cql
	};

	SearchP search;

	switch (tcl::uniqueMatchObj(objv[0], subcommands))
	{
		case Or:
		{
			if (objc < 3)
			{
				error(CmdSearch, Tcl_GetString(objv[0]), 0, "at least two queries expected");
				return search;
			}

			SearchP op(new SearchOpOr);	// Remedy 10: use SearchP to prevent leaks

			for (int i = 1; i < objc; ++i)
			{
				SearchP item(buildSearch(db, ti, objv[i]));
				if (!item)
					return SearchP();	// op goes out of scope, ref count drops to 0

				static_cast<SearchOpOr*>(op.get())->append(item.release());
			}

			search = op;
			break;
		}

		case And:
		{
			if (objc < 3)
			{
				error(CmdSearch, Tcl_GetString(objv[0]), 0, "at least two queries expected");
				return search;
			}

			SearchP op(new SearchOpAnd);	// Remedy 10: use SearchP to prevent leaks

			for (int i = 1; i < objc; ++i)
			{
				SearchP item(buildSearch(db, ti, objv[i]));
				if (!item)
					return SearchP();

				static_cast<SearchOpAnd*>(op.get())->append(item.release());
			}

			search = op;
			break;
		}

		case Remove:
		case Reset:
		case Null:
			error(CmdSearch, Tcl_GetString(objv[0]), 0, "query operator not supported in nested queries");
			return search;

		case Not:
			if (objc != 2)
			{
				error(CmdSearch, "NOT", 0, "invalid query");
				return search;
			}
			search = buildSearch(db, ti, objv[1]);
			if (!search)
				return search;
			search = new SearchOpNot(search);
			break;

		case Player:
			if (objc != 2)
			{
				error(CmdSearch, "player", 0, "invalid query");
				return search;
			}
			search = new SearchPlayer(&db.player(unsignedFromObj(2, objv, 1)));
			break;

		case Event:
			if (objc != 2)
			{
				error(CmdSearch, "event", 0, "invalid query");
				return search;
			}
			search = new SearchEvent(&db.event(unsignedFromObj(2, objv, 1)));
			break;

		case GameEvent:
		{
			if (objc != 2)
			{
				error(CmdSearch, "gameevent", 0, "invalid query");
				return search;
			}
			GameInfo const& info = db.gameInfo(unsignedFromObj(2, objv, 1));
			search = new SearchGameEvent(info.eventEntry(), info.date());
			break;
		}

		case Site:
			if (objc != 2)
			{
				error(CmdSearch, "site", 0, "invalid query");
				return search;
			}
			search = new SearchSite(&db.site(unsignedFromObj(2, objv, 1)));
			break;

		case Annotator:
			if (objc != 2)
			{
				error(CmdSearch, "annotator", 0, "invalid query");
				return search;
			}
			search = new SearchAnnotator(Tcl_GetString(objv[1]));
			break;

		case Position:
		{
			if (objc != 2)
			{
				error(CmdSearch, "position", 0, "invalid query");
				return search;
			}
			int idn;
			if (Tcl_GetIntFromObj(ti, objv[1], &idn) != TCL_OK || idn < 0)
			{
				error(CmdSearch, "position", 0, "invalid query, positive IDN expected");
				return search;
			}
			search = new SearchPosition(idn);
			break;
		}

		case PlayerName:
		{
			if (objc != 2 && objc != 3)
			{
				error(CmdSearch, "playername", 0, "invalid query");
				return search;
			}

			SearchPlayerName::Mode mode = SearchPlayerName::Any;
			char const* name = 0;

			if (objc == 2)
			{
				name = Tcl_GetString(objv[1]);
			}
			else
			{
				char const* side = Tcl_GetString(objv[1]);
				if (::strcasecmp(side, "white") == 0)
					mode = SearchPlayerName::White;
				else if (::strcasecmp(side, "black") == 0)
					mode = SearchPlayerName::Black;
				else if (::strcasecmp(side, "any") == 0)
					mode = SearchPlayerName::Any;
				else
				{
					error(CmdSearch, "playername", 0, "invalid player side");
					return search;
				}

				name = Tcl_GetString(objv[2]);
			}

			if (*name == '\0')
			{
				error(CmdSearch, "playername", 0, "empty player name");
				return search;
			}

			bool exact = false;
			mstl::string decoded = decodeLiteralPattern(name, exact);
			search = new SearchPlayerName(mode, decoded, exact);
			break;
		}

		// Remedy 6: collapsed 3 copy-paste cases into makeNameSearch calls
		case EventName:
			search = makeNameSearch<SearchEventName>(CmdSearch, "eventname", objc, objv);
			break;

		case SiteName:
			search = makeNameSearch<SearchSiteName>(CmdSearch, "sitename", objc, objv);
			break;

		case AnnotatorName:
			search = makeNameSearch<SearchAnnotatorName>(CmdSearch, "annotatorname", objc, objv);
			break;

		case Eco:
			if (objc != 2 || *Tcl_GetString(objv[1]) == '\0')
			{
				error(CmdSearch, "eco", 0, "invalid query");
				return search;
			}
			search = new SearchEco(Tcl_GetString(objv[1]), db.variant());
			break;

		case EcoRange:
		{
			uint16_t from = objc == 3 ? Eco::toShort(Tcl_GetString(objv[1])) : 0;
			uint16_t to = objc == 3 ? Eco::toShort(Tcl_GetString(objv[2])) : 0;

			if (from == 0 || to == 0 || to < from)
			{
				error(CmdSearch, "ecorange", 0, "invalid ECO range");
				return search;
			}
			search = new SearchEcoRange(from, to, db.variant());
			break;
		}

		case DateRange:
		{
			unsigned from = 0;
			unsigned to = 0;

			if (objc != 3 || !parseDateKey(Tcl_GetString(objv[1]), false, from)
				|| !parseDateKey(Tcl_GetString(objv[2]), true, to) || to < from)
			{
				error(CmdSearch, "date", 0, "invalid date range, YYYY, YYYY.MM or YYYY.MM.DD expected");
				return search;
			}
			search = new SearchDate(from, to);
			break;
		}

		case Result:
		{
			char const* text = objc == 2 ? Tcl_GetString(objv[1]) : "";
			result::ID id = result::Unknown;

			if (::strcmp(text, "1-0") == 0)
				id = result::White;
			else if (::strcmp(text, "0-1") == 0)
				id = result::Black;
			else if (::strcmp(text, "1/2-1/2") == 0)
				id = result::Draw;

			if (id == result::Unknown)
			{
				error(CmdSearch, "result", 0, "invalid result, 1-0, 0-1 or 1/2-1/2 expected");
				return search;
			}
			search = new SearchResult(id);
			break;
		}

		case Cql:
		{
			if (objc != 2)
			{
				error(CmdSearch, "cql", 0, "a CQL script expected");
				return search;
			}

			char const*			script	= Tcl_GetString(objv[1]);
			::cql::Match		match;
			::cql::Match::Error	rc			= ::cql::error::No_Error;
			char const*			end		= script;

			try
			{
				end = match.parse(script, rc);
			}
			catch (mstl::exception const& exc)
			{
				error(CmdSearch, "cql", 0, "CQL parser failure: %s", exc.what());
				return search;
			}

			if (rc != ::cql::error::No_Error)
			{
				error(	CmdSearch, "cql", 0, "CQL error %s at offset %d",
						tcl::cql::errorName(rc), int(end - script));
				return search;
			}
			if (match.sections() & ::cql::Match::Section_Comments)
			{
				error(CmdSearch, "cql", 0, "CQL comment filters are not supported yet");
				return search;
			}

			search = new SearchCql(db, script);
			break;
		}

		case Material:
		{
			if (objc != 2 && objc != 3)
			{
				error(CmdSearch, "material", 0, "invalid query");
				return search;
			}

			if (objc == 2)
			{
				material::si3::Signature signature;
				if (!parseMaterialSignature(ti, objv[1], signature))
				{
					error(CmdSearch, "material", 0, "invalid material signature");
					return search;
				}

				search = new SearchMaterial(signature);
				break;
			}

			char const* mode = Tcl_GetString(objv[1]);

			if (::strcmp(mode, "exact") == 0)
			{
				material::si3::Signature signature;
				if (!parseMaterialSignature(ti, objv[2], signature))
				{
					error(CmdSearch, "material", 0, "invalid material signature");
					return search;
				}
				search = new SearchMaterial(signature);
			}
			else if (::strcmp(mode, "class") == 0)
			{
				material::si3::Signature signature;
				if (!parseMaterialSignature(ti, objv[2], signature))
				{
					error(CmdSearch, "material", 0, "invalid material signature");
					return search;
				}
				search = new SearchMaterialClass(signature);
			}
			else if (::strcmp(mode, "pawns") == 0)
			{
				int rangec = 0;
				Tcl_Obj** rangev = 0;
				if (Tcl_ListObjGetElements(ti, objv[2], &rangec, &rangev) != TCL_OK || rangec != 2)
				{
					error(CmdSearch, "material", 0, "invalid pawn range");
					return search;
				}

				unsigned whiteMin, whiteMax, blackMin, blackMax;
				if (!parseRange(ti, rangev[0], 15, whiteMin, whiteMax)		// Remedy 5
					|| !parseRange(ti, rangev[1], 15, blackMin, blackMax))
				{
					error(CmdSearch, "material", 0, "invalid pawn range");
					return search;
				}
				search = new SearchMaterialPawns(whiteMin, whiteMax, blackMin, blackMax);
			}
			else
			{
				error(CmdSearch, "material", 0, "invalid material mode");
				return search;
			}

			break;
		}

		case Rating:
		{
			if (objc != 4 && objc != 5)
			{
				error(CmdSearch, "rating", 0, "invalid query");
				return search;
			}

			rating::Type type = rating::fromString(Tcl_GetString(objv[1]));
			if (type == rating::Last)
			{
				error(CmdSearch, "rating", 0, "invalid rating type");
				return search;
			}

			char const* mode = Tcl_GetString(objv[2]);
			unsigned minA, maxA, minB, maxB;

			if (::strcmp(mode, "white") == 0)
			{
				if (!parseRange(ti, objv[3], 4000, minA, maxA))		// Remedy 5
				{
					error(CmdSearch, "rating", 0, "invalid rating range");
					return search;
				}
				search = new SearchRating(type, SearchRating::White, minA, maxA);
			}
			else if (::strcmp(mode, "black") == 0)
			{
				if (!parseRange(ti, objv[3], 4000, minA, maxA))
				{
					error(CmdSearch, "rating", 0, "invalid rating range");
					return search;
				}
				search = new SearchRating(type, SearchRating::Black, 0, 0, minA, maxA);
			}
			else if (::strcmp(mode, "average") == 0)
			{
				if (!parseRange(ti, objv[3], 4000, minA, maxA))
				{
					error(CmdSearch, "rating", 0, "invalid rating range");
					return search;
				}
				search = new SearchRating(type, SearchRating::Average, minA, maxA);
			}
			else if (::strcmp(mode, "both") == 0 && objc == 5)
			{
				if (!parseRange(ti, objv[3], 4000, minA, maxA)
					|| !parseRange(ti, objv[4], 4000, minB, maxB))
				{
					error(CmdSearch, "rating", 0, "invalid rating range");
					return search;
				}
				search = new SearchRating(type, SearchRating::Both, minA, maxA, minB, maxB);
			}
			else
			{
				error(CmdSearch, "rating", 0, "invalid rating mode");
				return search;
			}

			break;
		}

		default:
			usage(CmdSearch, Tcl_GetString(objv[0]), nullptr, subcommands, args);
			return search;
	}

	return search;
}

// vi:set ts=3 sw=3: