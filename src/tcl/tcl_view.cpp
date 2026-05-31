// ======================================================================
// Author : $Author$
// Version: $Revision: 1522 $
// Date   : $Date: 2018-09-16 09:56:42 -0400 (Sun, 16 Sep 2018) $
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

#include "tcl_view.h"

#include "tcl_progress.h"
#include "tcl_application.h"
#include "tcl_pgn_reader.h"
#include "tcl_game.h"
#include "tcl_exception.h"
#include "tcl_log.h"
#include "tcl_obj.h"
#include "tcl_base.h"

#include "app_application.h"
#include "app_cursor.h"
#include "app_view.h"

#include "db_query.h"
#include "db_search.h"
#include "db_database.h"

#include "u_match.h"

#include "T_Controller.h"

#include "sys_utf8_codec.h"
#include "sys_file.h"

#include "m_ofstream.h"
#include "m_sstream.h"
#include "m_vector.h"
#include "m_algorithm.h"
#include "m_tuple.h"
#include "m_map.h"
#include "m_ref_counted_ptr.h"
#include "m_assert.h"

#include <tcl.h>
#include <ctype.h>

using namespace db;
using namespace app;
using namespace tcl;
using namespace tcl::app;

static char const* CmdClose			= "::scidb::view::close";
static char const* CmdCopy				= "::scidb::view::copy";
static char const* CmdCount			= "::scidb::view::count";
static char const* CmdEnumTags		= "::scidb::view::enumTags";
static char const* CmdExport			= "::scidb::view::export";
static char const* CmdFind				= "::scidb::view::find";
static char const* CmdMap				= "::scidb::view::map";
static char const* CmdNew				= "::scidb::view::new";
static char const* CmdOpen				= "::scidb::view::open?";
static char const* CmdPrint			= "::scidb::view::print";
static char const* CmdSearch			= "::scidb::view::search";
static char const* CmdSetTreeFilter	= "::scidb::view::setTreeFilter";
static char const* CmdStrip			= "::scidb::view::strip";
static char const* CmdSubscribe		= "::scidb::view::subscribe";
static char const* CmdUnsubscribe	= "::scidb::view::unsubscribe";


namespace {

struct MySubscriber : public Cursor::Subscriber
{
	typedef mstl::tuple<Obj,Obj,Obj,variant::Type> Tuple;

	void addProc(Tcl_Obj* base, variant::Type variant, Tcl_Obj* proc, Tcl_Obj* arg)
	{
		M_ASSERT(base);
		M_ASSERT(proc);

		m_list.push_back(Tuple(proc, arg, base, variant));
		m_list.back().get<0>().ref();
		m_list.back().get<1>().ref();
		m_list.back().get<2>().ref();
	}

	void removeProc(Tcl_Obj* base, variant::Type variant, Tcl_Obj* proc, Tcl_Obj* arg)
	{
		List::iterator i = mstl::find(m_list.begin(), m_list.end(), Tuple(proc, arg, base, variant));

		if (i == m_list.end())
		{
			fprintf(stderr, "Warning: view::unsubscribe failed\n");
		}
		else
		{
			i->get<0>().deref();
			i->get<1>().deref();
			i->get<2>().deref();
			m_list.erase(i);
		}
	}

	void close(mstl::string const& name, variant::Type variant, unsigned view) override
	{
		Tcl_Obj* u = tcl::game::objFromVariant(variant);
		Tcl_Obj* v = Tcl_NewIntObj(view);

		Tcl_IncrRefCount(v);

		for (unsigned i = 0; i < m_list.size(); ++i)
		{
			Tuple const& data = m_list[i];

			if (name == Tcl_GetString(data.get<2>()) && variant == data.get<3>())
			{
				if (data.get<1>())
					invoke(__func__, data.get<0>()(), data.get<1>()(), data.get<2>()(), u, v, nullptr);
				else
					invoke(__func__, data.get<0>()(), data.get<2>()(), u, v, nullptr);
			}
		}

		Tcl_DecrRefCount(v);
	}

	typedef mstl::vector<Tuple> List;

	List m_list;
};


typedef mstl::ref_counted_ptr<MySubscriber> SubscriberP;
typedef mstl::map<mstl::string, SubscriberP> SubscriberMap;
typedef mstl::ref_counted_ptr<Search> SearchP;

static SubscriberMap subscriberMap;

static bool parseMaterialPart(mstl::string const& text, material::si3::Signature& sig, bool white);
static bool parseMaterialSignature(Tcl_Interp* ti, Tcl_Obj* obj, material::si3::Signature& sig);
static bool parsePawnRange(Tcl_Interp* ti, Tcl_Obj* obj, unsigned& minValue, unsigned& maxValue);
static bool parseRatingRange(Tcl_Interp* ti, Tcl_Obj* obj, unsigned& minValue, unsigned& maxValue);
static mstl::string decodeLiteralPattern(char const* text, bool& exact);
static mstl::string makeSubscriberKey(mstl::string const& base, variant::Type variant)
{
	mstl::string key(base);
	char buf[32];
	::snprintf(buf, sizeof(buf), "%d", int(variant));
	key += ':';
	key += buf;
	return key;
}

} // namespace


static SearchP
buildSearch(Database const& db, Tcl_Interp* ti, Tcl_Obj* query)
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
		"material", "rating",
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
		nullptr
	};
	enum
	{
		Or, And, Not, Remove, Reset, Null, Player, Event, Site, GameEvent, Annotator, Position,
		PlayerName, EventName, SiteName, AnnotatorName, Eco, Material, Rating
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

			SearchOpOr* op = new SearchOpOr;

			for (int i = 1; i < objc; ++i)
			{
				SearchP item(buildSearch(db, ti, objv[i]));
				if (!item)
					return SearchP();

				op->append(item.release());
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

			SearchOpAnd* op = new SearchOpAnd;

			for (int i = 1; i < objc; ++i)
			{
				SearchP item(buildSearch(db, ti, objv[i]));
				if (!item)
					return SearchP();

				op->append(item.release());
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
				error(CmdSearch, "event", 0, "invalid query");
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

		case EventName:
			if (objc != 2 || *Tcl_GetString(objv[1]) == '\0')
			{
				error(CmdSearch, "eventname", 0, "invalid query");
				return search;
			}
		{
			bool exact = false;
			mstl::string decoded = decodeLiteralPattern(Tcl_GetString(objv[1]), exact);
			search = new SearchEventName(decoded, exact);
		}
			break;

		case SiteName:
			if (objc != 2 || *Tcl_GetString(objv[1]) == '\0')
			{
				error(CmdSearch, "sitename", 0, "invalid query");
				return search;
			}
		{
			bool exact = false;
			mstl::string decoded = decodeLiteralPattern(Tcl_GetString(objv[1]), exact);
			search = new SearchSiteName(decoded, exact);
		}
			break;

		case AnnotatorName:
			if (objc != 2 || *Tcl_GetString(objv[1]) == '\0')
			{
				error(CmdSearch, "annotatorname", 0, "invalid query");
				return search;
			}
		{
			bool exact = false;
			mstl::string decoded = decodeLiteralPattern(Tcl_GetString(objv[1]), exact);
			search = new SearchAnnotatorName(decoded, exact);
		}
			break;

		case Eco:
			if (objc != 2 || *Tcl_GetString(objv[1]) == '\0')
			{
				error(CmdSearch, "eco", 0, "invalid query");
				return search;
			}
			search = new SearchEco(Tcl_GetString(objv[1]), db.variant());
			break;

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
				if (!parsePawnRange(ti, rangev[0], whiteMin, whiteMax)
					|| !parsePawnRange(ti, rangev[1], blackMin, blackMax))
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
				if (!parseRatingRange(ti, objv[3], minA, maxA))
				{
					error(CmdSearch, "rating", 0, "invalid rating range");
					return search;
				}
				search = new SearchRating(type, SearchRating::White, minA, maxA);
			}
			else if (::strcmp(mode, "black") == 0)
			{
				if (!parseRatingRange(ti, objv[3], minA, maxA))
				{
					error(CmdSearch, "rating", 0, "invalid rating range");
					return search;
				}
				search = new SearchRating(type, SearchRating::Black, 0, 0, minA, maxA);
			}
			else if (::strcmp(mode, "average") == 0)
			{
				if (!parseRatingRange(ti, objv[3], minA, maxA))
				{
					error(CmdSearch, "rating", 0, "invalid rating range");
					return search;
				}
				search = new SearchRating(type, SearchRating::Average, minA, maxA);
			}
			else if (::strcmp(mode, "both") == 0 && objc == 5)
			{
				if (!parseRatingRange(ti, objv[3], minA, maxA)
					|| !parseRatingRange(ti, objv[4], minB, maxB))
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


namespace {

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


static bool
parsePawnRange(Tcl_Interp* ti, Tcl_Obj* obj, unsigned& minValue, unsigned& maxValue)
{
	mstl::string text(Tcl_GetString(obj));
	mstl::string::size_type sep = text.find('-');

	if (sep == mstl::string::npos)
	{
		int value;
		if (Tcl_GetIntFromObj(ti, obj, &value) != TCL_OK || value < 0 || value > 15)
			return false;
		minValue = maxValue = unsigned(value);
		return true;
	}

	mstl::string lhs(text, 0, sep);
	mstl::string rhs(text, sep + 1);
	if (lhs.size() == 0 || rhs.size() == 0)
		return false;

	int low = ::atoi(lhs.c_str());
	int high = ::atoi(rhs.c_str());

	if (low < 0 || high < 0 || low > high || high > 15)
		return false;

	minValue = unsigned(low);
	maxValue = unsigned(high);
	return true;
}


static bool
parseRatingRange(Tcl_Interp* ti, Tcl_Obj* obj, unsigned& minValue, unsigned& maxValue)
{
	mstl::string text(Tcl_GetString(obj));
	mstl::string::size_type sep = text.find('-');

	if (sep == mstl::string::npos)
	{
		int value;
		if (Tcl_GetIntFromObj(ti, obj, &value) != TCL_OK || value < 0 || value > 4000)
			return false;
		minValue = maxValue = unsigned(value);
		return true;
	}

	mstl::string lhs(text, 0, sep);
	mstl::string rhs(text, sep + 1);
	if (lhs.empty() || rhs.empty())
		return false;

	int low = ::atoi(lhs.c_str());
	int high = ::atoi(rhs.c_str());

	if (low < 0 || high < 0 || low > high || high > 4000)
		return false;

	minValue = unsigned(low);
	maxValue = unsigned(high);
	return true;
}

} // namespace


bool
tcl::view::buildTagSet(Tcl_Interp* ti, char const* cmd, Tcl_Obj* allowedTags, ::db::tag::TagSet& tagBits)
{
	Tcl_Obj**	tags;
	int			tagCount;
	bool			extraTags	= false;

	if (Tcl_ListObjGetElements(ti, allowedTags, &tagCount, &tags) != TCL_OK)
		return error(cmd, 0, 0, "invalid tag list");

	if (tagCount == 0)
	{
		tagBits.set();
		extraTags = true;
	}
	else
	{
		for (int i = 0; i < tagCount; ++i)
		{
			if (*Tcl_GetString(tags[i]))
			{
				tag::ID tag = tag::fromName(Tcl_GetString(tags[i]));

				if (tag == tag::ExtraTag)
					extraTags = true;
				else
					tagBits.set(tag);
			}
		}
	}

	return extraTags;
}


int
tcl::view::makeLangList(Tcl_Interp* ti,
								char const* cmd,
								Tcl_Obj* languageList,
								mstl::vector<mstl::string>& langs)
{
	mstl::vector<mstl::string> languages;

	int			significant;
	Tcl_Obj**	objv;
	int			objc;

	if (Tcl_ListObjGetElements(ti, languageList, &objc, &objv) != TCL_OK)
		return error(cmd, 0, 0, "invalid language list");

	for (int i = 0; i < objc; ++i)
	{
		Tcl_Obj** objs;
		int n;

		if (Tcl_ListObjGetElements(ti, objv[i], &n, &objs) != TCL_OK || n != 2)
		{
			error(cmd, 0, 0, "invalid language list");
			return -1;
		}

		char const* lang = Tcl_GetString(objs[0]);

		if (*lang == '*')
			return 0;

		if (boolFromObj(n, objs, 1))
			langs.push_back(lang);
		else
			languages.push_back(lang);
	}

	significant = langs.size();
	langs += languages;

	return significant;
}


static int
cmdNew(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 8 && objc != 9)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> ?<variant>? <games> <players> <annotators> <positions> <events> <sites>");
		return TCL_ERROR;
	}

	char const*		base		= stringFromObj(objc, objv, 1);
	variant::Type	variant	= variant::Undetermined;
	unsigned			n			= 2;

	if (objc > 8)
		variant = tcl::game::variantFromObj(objv[n++]);

	::app::View::UpdateModeList updateMode;

	for (unsigned i = 0; i < U_NUMBER_OF(updateMode); ++i)
	{
		char const* arg = stringFromObj(objc, objv, i + n);

		if (::strcmp(arg, "master") == 0)
			updateMode[i] = View::AddNewGames;
		else if (::strcmp(arg, "slave") == 0)
			updateMode[i] = View::LeaveEmpty;
		else if (::strcmp(arg, "unused") == 0)
			updateMode[i] = View::NotNeeded;
		else
			return error(CmdNew, 0, 0, "unknown resize mode '%s'", arg);
	}

	setResult(scidb->cursor(base, variant).newView(updateMode));
	return TCL_OK;
}


static int
cmdClose(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 3 && objc != 4)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> ?<variant>? <view>");
		return TCL_ERROR;
	}

	int view = intFromObj(objc, objv, objc > 3 ? 3 : 2);
	variant::Type variant = objc > 3 ? tcl::game::variantFromObj(objv[2]) : variant::Undetermined;

	scidb->cursor(Tcl_GetString(objv[1]), variant).closeView(view);
	return TCL_OK;
}


static int
cmdOpen(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	static char const* subcommands[] = { "games", "players", "annotators", "events", "sites", 0 };
	// One entry per subcommand: usage() dereferences args[] in lockstep with subcommands[].
	static char const* args[] =
	{
		"<database> <variant> <view>",	// games
		"<database> <variant> <view>",	// players
		"<database> <variant> <view>",	// annotators
		"<database> <variant> <view>",	// events
		"<database> <variant> <view>",	// sites
		nullptr
	};
	enum { Cmd_Games, Cmd_Players, Cmd_Annotators, Cmd_Events, Cmd_Sites };

	if (objc != 5)
		return usage(CmdOpen, nullptr, nullptr, subcommands, args);

	char const*		database	= stringFromObj(objc, objv, 2);
	variant::Type	variant	= tcl::game::variantFromObj(objc, objv, 3);

	int index	= tcl::uniqueMatchObj(objv[1], subcommands);
	int view		= intFromObj(objc, objv, 4);

	switch (index)
	{
		case Cmd_Games:
			setResult(Scidb->cursor(database, variant).isViewOpen(view));
			return TCL_OK;

		case Cmd_Players:
			setResult(Scidb->cursor(database, variant).isViewOpen(view));
			return TCL_OK;

		case Cmd_Annotators:
			setResult(Scidb->cursor(database, variant).isViewOpen(view));
			return TCL_OK;

		case Cmd_Events:
			setResult(Scidb->cursor(database, variant).isViewOpen(view));
			return TCL_OK;

		case Cmd_Sites:
			setResult(Scidb->cursor(database, variant).isViewOpen(view));
			return TCL_OK;
	}

	return usage(CmdOpen, nullptr, nullptr, subcommands, args);
}


static int
cmdCount(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	static char const* subcommands[] =
	{
		"games", "players", "annotators", "positions", "events", "sites", nullptr
	};
	// One entry per subcommand: usage() dereferences args[] in lockstep with subcommands[].
	static char const* args[] =
	{
		"<database> <variant> <view>",	// games
		"<database> <variant> <view>",	// players
		"<database> <variant> <view>",	// annotators
		"<database> <variant> <view>",	// positions
		"<database> <variant> <view>",	// events
		"<database> <variant> <view>",	// sites
		nullptr
	};
	enum { Cmd_Games, Cmd_Players, Cmd_Annotators, Cmd_Positions, Cmd_Events, Cmd_Sites };

	if (objc != 5)
		return usage(CmdCount, nullptr, nullptr, subcommands, args);

	char const* database = stringFromObj(objc, objv, 2);
	variant::Type variant = tcl::game::variantFromObj(objc, objv, 3);

	int index	= tcl::uniqueMatchObj(objv[1], subcommands);
	int view		= intFromObj(objc, objv, 4);

	table::Type type;

	switch (index)
	{
		case Cmd_Games:		type = table::Games; break;
		case Cmd_Players:		type = table::Players; break;
		case Cmd_Annotators:	type = table::Annotators; break;
		case Cmd_Positions:	type = table::Positions; break;
		case Cmd_Events:		type = table::Events; break;
		case Cmd_Sites:		type = table::Sites; break;
		default:					return usage(CmdCount, nullptr, nullptr, subcommands, args);
	}

	setResult(Scidb->cursor(database, variant).view(view).count(type));
	return TCL_OK;
}


static int
cmdFind(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	static char const* subcommands[] = { "player", "event", "site", "annotator", 0 };
	// One entry per subcommand: usage() dereferences args[] in lockstep with subcommands[].
	static char const* args[] =
	{
		"<database> <variant> <view>",	// player
		"<database> <variant> <view>",	// event
		"<database> <variant> <view>",	// site
		"<database> <variant> <view>",	// annotator
		nullptr
	};
	enum { Cmd_Player, Cmd_Event, Cmd_Site, Cmd_Annotator };

	if (objc != 6 && objc != 7)
	{
		Tcl_WrongNumArgs(
			ti,
			1,
			objv,
			"player|event|site|annotator <database> <variant> <view> <string> ?<start-index>?");
		return TCL_ERROR;
	}

	int index = tcl::uniqueMatchObj(objv[1], subcommands);

	char const*		database(stringFromObj(objc, objv, 2));
	variant::Type	variant(tcl::game::variantFromObj(objv[3]));
	int				view(intFromObj(objc, objv, 4));
	util::Pattern 	pattern(stringFromObj(objc, objv, 5));
	int				startIndex(objc == 6 ? 0 : intFromObj(objc, objv, 6) + 1);

	View const& v = Scidb->cursor(database, variant).view(view);

	switch (index)
	{
		case Cmd_Player:
			setResult(v.findPlayer(pattern, startIndex));
			break;

		case Cmd_Event:
			setResult(v.findEvent(pattern, startIndex));
			break;

		case Cmd_Site:
			setResult(v.findSite(pattern, startIndex));
			break;

		case Cmd_Annotator:
			setResult(v.findAnnotator(pattern, startIndex));
			break;

		default:
			return usage(CmdFind, nullptr, nullptr, subcommands, args);
	}

	return TCL_OK;
}


static int
cmdSearch(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc < 5 || 7 < objc)
	{
		Tcl_WrongNumArgs(
			ti,
			1,
			objv,
			"<database> ?<variant>? <view> <operator> <none|events|sites|players> ?<query>?");
		return TCL_ERROR;
	}

	unsigned n = *Tcl_GetString(objv[2]) == '-' || isdigit(*Tcl_GetString(objv[2])) ? 0 : 1;

	char const*		database	= Tcl_GetString(objv[1]);
	char const*		ops		= Tcl_GetString(objv[3 + n]);
	variant::Type	variant	= n ? tcl::game::variantFromObj(objv[2]) : variant::Undetermined;

	Query::Operator op;

	if (strcmp(ops, "null") == 0)
		op = Query::Null;
	else if (strcmp(ops, "or") == 0)
		op = Query::Or;
	else if (strcmp(ops, "and") == 0)
		op = Query::And;
	else if (strcmp(ops, "not") == 0)
		op = Query::Not;
	else if (strcmp(ops, "reset") == 0)
		op = Query::Reset;
	else if (strcmp(ops, "remove") == 0)
		op = Query::Remove;
	else
		return error(CmdSearch, 0, 0, "invalid operator %s", ops);

	char const* f = Tcl_GetString(objv[4 + n]);
	unsigned filter = Application::None;

	switch (f[0])
	{
		case 'n': break;												// none
		case 'e': filter |= Application::Events; break;		// events
		case 'p': filter |= Application::Players; break;	// players
		case 's': filter |= Application::Sites; break;		// sites

		default:  return error(CmdSearch, 0, 0, "invalid filter argument %s", f);
	}

	int view;

	if (Tcl_GetIntFromObj(ti, objv[2 + n], &view) != TCL_OK)
		return error(CmdSearch, 0, 0, "unsigned integer expected for view");

	// NOTE: we don't like to interrupt tree search!
	Cursor const& cursor = Scidb->cursor(database, variant);

	SearchP search;

	if (objc >= int(6 + n))
		search = buildSearch(cursor.database(), ti, objv[5 + n]);

	if (!search && objc == int(6 + n))
		return TCL_ERROR;

	scidb->searchGames(	const_cast<Cursor&>(cursor),
								Query(mstl::ref_counted_ptr<Search>(search), op),
								view,
								filter);

	return TCL_OK;
}


static int
cmdSetTreeFilter(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 4 && objc != 5)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> ?<variant>? <view> <row-or-identity>");
		return TCL_ERROR;
	}

	unsigned n = objc == 5 ? 1 : 0;
	char const* database = stringFromObj(objc, objv, 1);
	variant::Type variant = n ? tcl::game::variantFromObj(objv[2]) : variant::Undetermined;
	unsigned view = unsignedFromObj(objc, objv, 2 + n);
	char const* rowOrIdentity = stringFromObj(objc, objv, 3 + n);
	Cursor& cursor = scidb->cursor(database, variant);

	if (::strchr(rowOrIdentity, '|'))
	{
		if (!scidb->setCurrentTreeRowFilter(cursor, view, mstl::string(rowOrIdentity)))
			return error(CmdSetTreeFilter, nullptr, nullptr, "unable to apply current tree identity '%s' to view %u", rowOrIdentity, view);
	}
	else
	{
		unsigned row = unsignedFromObj(objc, objv, 3 + n);

		if (!scidb->setCurrentTreeRowFilter(cursor, view, row))
			return error(CmdSetTreeFilter, nullptr, nullptr, "unable to apply current tree row %u to view %u", row, view);
	}

	setResult(true);
	return TCL_OK;
}


static int
cmdCopy(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 10)
	{
		Tcl_WrongNumArgs(
			ti, 1, objv,
			"<source> <view> <destination> <variant> <tag-set> "
			"<progress-cmd> <progress-arg> <log-cmd> <log-arg>");
		return TCL_ERROR;
	}


	View::TagBits	tagBits;
	mstl::string	source(stringFromObj(objc, objv, 1));
	unsigned			viewNo(unsignedFromObj(objc, objv, 2));
	mstl::string	destination(stringFromObj(objc, objv, 3));
	variant::Type	variant(tcl::game::variantFromObj(objc, objv, 4));
	bool				extraTags(tcl::view::buildTagSet(ti, CmdCopy, objv[5], tagBits));
	Tcl_Obj*			progressCmd(objectFromObj(objc, objv, 6));
	Tcl_Obj*			progressArg(objectFromObj(objc, objv, 7));
	Tcl_Obj*			logCmd(objectFromObj(objc, objv, 8));
	Tcl_Obj*			logArg(objectFromObj(objc, objv, 9));
	Progress			progress(progressCmd, progressArg);
	tcl::Log			log(logCmd, logArg);
	View&				view(scidb->cursor(source, variant).view(viewNo));
	unsigned			accepted[variant::NumberOfVariants];
	unsigned			rejected[variant::NumberOfVariants];
	unsigned			n;

	::memset(accepted, 0, sizeof(accepted));
	::memset(rejected, 0, sizeof(rejected));

	Cursor&		dst(scidb->cursor(destination, variant));
	unsigned		variantIndex(variant::toIndex(variant));
	unsigned		illegalRejected(0);
	unsigned		numGames(dst.count(table::Games));
	unsigned*	illegalPtr(::db::format::isScidFormat(dst.format()) ? &illegalRejected : nullptr);

	n = view.copyGames(dst, tagBits, extraTags, illegalPtr, log, progress);
	accepted[variantIndex] = n;
	rejected[variantIndex] = dst.count(table::Games) - numGames - n;

	if (progress.interrupted())
		n = -n - 1;

	tcl::PgnReader::setResult(n, illegalRejected, accepted, rejected);
	return TCL_OK;
}


static int
cmdExport(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 15)
	{
		Tcl_WrongNumArgs(
			ti, 1, objv,
			"<database> <variant> <view> <file> <flags> <mode> <encoding> <exclude-illegal-games-flag> "
			"<exported-tags> <languages> <progress-cmd> <progress-arg> <log-cmd> <log-arg>");
		return TCL_ERROR;
	}

	View::TagBits	tagBits;
	char const*		database			= stringFromObj(objc, objv, 1);
	variant::Type	variant			= tcl::game::variantFromObj(objc, objv, 2);
	unsigned			view				= unsignedFromObj(objc, objv, 3);
	char const*		filename			= stringFromObj(objc, objv, 4);
	unsigned			flags				= unsignedFromObj(objc, objv, 5);
	View::FileMode	mode				= boolFromObj(objc, objv, 6) ? View::Append : View::Create;
	mstl::string	encoding			= stringFromObj(objc, objv, 7);
	bool				excludeIllegal	= boolFromObj(objc, objv, 8);
	bool				extraTags		= tcl::view::buildTagSet(ti, CmdExport, objv[9], tagBits);
	Tcl_Obj*			languageList	= objectFromObj(objc, objv, 10);

	Progress				progress(objv[11], objv[12]);
	tcl::Log				log(objv[13], objv[14]);
	Cursor&				cursor(scidb->cursor(database, variant));
	Database const&	db(cursor.database());
	View&					v(cursor.view(view));
	type::ID				type(db.type());
	unsigned				illegalRejected(0);
	View::Languages	languages;
	int					significant;

	if (type == type::PGNFile)
		type = type::Unspecific;

	significant = view::makeLangList(ti, CmdExport, languageList, languages);

	if (significant == -1)
		return TCL_ERROR;

	int n = v.exportGames(	filename,
									encoding,
									db.description(),
									0,
									type,
									flags,
									tagBits,
									extraTags,
									significant == 0 ? nullptr : &languages,
									significant,
									excludeIllegal ? &illegalRejected : nullptr,
									log,
									progress,
									mode);

	if (progress.interrupted())
		n = -n - 1;

	Tcl_Obj* objs[2];
	objs[0] = Tcl_NewIntObj(n);
	objs[1] = Tcl_NewIntObj(illegalRejected);
	setResult(2, objs);

	return TCL_OK;
}


static int
cmdPrint(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	struct Log : public TeXt::Controller::Log
	{
		void error(mstl::string const& msg) { str = msg; }
		mstl::string str;
	};

	if (objc != 17)
	{
		Tcl_WrongNumArgs(
			ti, 1, objv,
			"<database> <variant> <view> <file> <search-path> <script-path> <preamble> <flags> "
			" <options> <nag-map> <languages> <trace> <progress-cmd> <progress-arg> "
			"<log-cmd> <log-arg>");
		return TCL_ERROR;
	}

	char const*		database			= stringFromObj(objc, objv, 1);
	variant::Type	variant			= tcl::game::variantFromObj(objc, objv, 2);
	unsigned			view				= unsignedFromObj(objc, objv, 3);
	char const*		filename			= stringFromObj(objc, objv, 4);
	char const* 	searchPath		= stringFromObj(objc, objv, 5);
	mstl::string 	scriptPath		= stringFromObj(objc, objv, 6);
	mstl::string 	preamble			= stringFromObj(objc, objv, 7);
	unsigned			flags				= unsignedFromObj(objc, objv, 8);
	unsigned			options			= unsignedFromObj(objc, objv, 9);
	Tcl_Obj*			mapObj			= objectFromObj(objc, objv, 10);
	Tcl_Obj*			languageList	= objectFromObj(objc, objv, 11);
	char const*		trace				= stringFromObj(objc, objv, 12);

	Progress				progress(objv[13], objv[14]);
	tcl::Log				log(objv[15], objv[16]);
	Cursor&				cursor(scidb->cursor(database, variant));
	View&					v(cursor.view(view));
	Tcl_Obj**			objs;
	View::NagMap		nagMap;
	View::Languages	languages;
	int					significant;

	::memset(nagMap, 0, sizeof(nagMap));

	if (Tcl_ListObjGetElements(ti, mapObj, &objc, &objs) != TCL_OK)
		return error(CmdPrint, 0, 0, "invalid nag map");

	for (int i = 0; i < objc; ++i)
	{
		Tcl_Obj** pair;
		int nelems;

		if (Tcl_ListObjGetElements(ti, objs[i], &nelems, &pair) != TCL_OK || nelems != 2)
			return error(CmdPrint, 0, 0, "invalid nag map");

		int lhs = intFromObj(2, pair, 0);
		int rhs = intFromObj(2, pair, 1);

		if (lhs >= nag::Scidb_Last || rhs >= nag::Scidb_Last)
			return error(CmdPrint, 0, 0, "invalid nag map values");

		nagMap[lhs] = rhs;
	}

	TeXt::Controller::LogP myLog(new Log);
	TeXt::Controller controller(searchPath, TeXt::Controller::AbortMode, myLog);
	mstl::istringstream src(preamble);
	mstl::ofstream dst(sys::file::internalName(filename));
	mstl::ostringstream out;

	if (controller.processInput(src, dst, &out, &out) >= 0)
	{
		int rc = controller.processInput(scriptPath, dst, &out, &out);

		if (rc == TeXt::Controller::OpenInputFileFailed)
			out.write(static_cast<Log*>(myLog.get())->str);
	}

	significant = view::makeLangList(ti, CmdPrint, languageList, languages);

	if (significant == -1)
		return TCL_ERROR;

	setResult(v.printGames(	controller.environment(),
									format::LaTeX,
									flags,
									options,
									nagMap,
									significant == 0 ? nullptr : &languages,
									significant,
									nullptr, // illegal game count not used here
									log,
									progress));

	{
		mstl::string log(out.str());

		if (!log.empty() && log.back() == '\n')
			log.set_size(log.size() - 1);

		Tcl_SetVar2Ex(ti, trace, 0, Tcl_NewStringObj(log, log.size()), TCL_GLOBAL_ONLY);
	}

	return TCL_OK;
}


static int
cmdMap(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 5 && objc != 6)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<player|event|site|game|position> <database> ?<variant>? <view> <index>");
		return TCL_ERROR;
	}

	char const*		attr		= stringFromObj(objc, objv, 1);
	char const*		database	= stringFromObj(objc, objv, 2);
	variant::Type	variant	= objc > 5 ? tcl::game::variantFromObj(objv[3]) : variant::Undetermined;
	Cursor const&	cursor	= Scidb->cursor(database, variant);
	View const&		view		= cursor.view(unsignedFromObj(objc, objv, objc > 5 ? 4 : 3));
	unsigned			index		= unsignedFromObj(objc, objv, objc > 5 ? 5 : 4);

	if (::strcmp(attr, "player") == 0)
		setResult(view.lookupPlayerIndex(index));
	else if (::strcmp(attr, "event") == 0)
		setResult(view.lookupEventIndex(index));
	else if (::strcmp(attr, "site") == 0)
		setResult(view.lookupSiteIndex(index));
	else if (::strcmp(attr, "game") == 0)
		setResult(view.lookupGameIndex(index));
	else if (::strcmp(attr, "position") == 0)
		setResult(view.lookupPositionIndex(index));
	else
		return error(CmdMap, 0, 0, "unexpected attribute '%s'", attr);

	return TCL_OK;
}


static int
cmdSubscribe(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 4 && objc != 5)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<proc> <database> <variant> ?<arg>?");
		return TCL_ERROR;
	}

	Tcl_Obj*			proc		= objectFromObj(objc, objv, 1);
	Tcl_Obj*			base		= objectFromObj(objc, objv, 2);
	variant::Type	variant	= game::variantFromObj(objc, objv, 3);
	Tcl_Obj*			arg		= objc > 4 ? objv[4] : 0;

	mstl::string basename(Tcl_GetString(base));
	mstl::string key(makeSubscriberKey(basename, variant));
	Cursor const& cursor = Scidb->cursor(basename, variant); // don't cancel tree search

	SubscriberP& subscriber = ::subscriberMap[key];

	if (!subscriber)
	{
		subscriber = new MySubscriber;
		const_cast<Cursor&>(cursor).setSubscriber(subscriber);
	}

	subscriber->addProc(base, variant, proc, arg);

	return TCL_OK;
}


static int
cmdUnsubscribe(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 4 && objc != 5)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<proc> <database> <variant> ?<arg>?");
		return TCL_ERROR;
	}

	Tcl_Obj*			proc		= objectFromObj(objc, objv, 1);
	Tcl_Obj*			base		= objectFromObj(objc, objv, 2);
	variant::Type	variant	= game::variantFromObj(objc, objv, 3);
	Tcl_Obj*			arg		= objc > 4 ? objv[4] : 0;

	mstl::string basename(Tcl_GetString(base));
	mstl::string key(makeSubscriberKey(basename, variant));
	SubscriberMap::iterator i = ::subscriberMap.find(key);

	if (i != subscriberMap.end())
	{
		i->second->removeProc(base, variant, proc, arg);

		if (i->second->m_list.empty())
			::subscriberMap.erase(i);
	}

	return TCL_OK;
}


static int
cmdStrip(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 8)
	{
		Tcl_WrongNumArgs(
			ti, 1, objv,
			"<what> <database> <variant> <view> <attributes> <progress-cmd> <progress-arg> ");
		return TCL_ERROR;
	}

	char const*		what		= stringFromObj(objc, objv, 1);
	char const*		database	= stringFromObj(objc, objv, 2);
	variant::Type	variant	= tcl::game::variantFromObj(objc, objv, 3);
	Cursor&			cursor	= scidb->cursor(database, variant);
	View&				view		= cursor.view(unsignedFromObj(objc, objv, 4));
	Tcl_Obj*			attrs		= objectFromObj(objc, objv, 5);
	Progress			progress(objv[6], objv[7]);

	if (::strcmp(what, "moveInfo") == 0)
	{
		Tcl_Obj** objs;

		if (Tcl_ListObjGetElements(ti, attrs, &objc, &objs) != TCL_OK)
			return error(CmdStrip, 0, 0, "list of attributes expected");

		unsigned types = 0;

		for (int i = 0; i < objc; ++i)
		{
			char const* attr = Tcl_GetString(objs[i]);

			if (::strcasecmp(attr, "evaluation") == 0)
				types |= 1 << MoveInfo::Evaluation;
			else if (::strcasecmp(attr, "playersClock") == 0)
				types |= 1 << MoveInfo::PlayersClock;
			else if (::strcasecmp(attr, "elapsedGameTime") == 0)
				types |= 1 << MoveInfo::ElapsedGameTime;
			else if (::strcasecmp(attr, "elapsedMoveTime") == 0)
				types |= 1 << MoveInfo::ElapsedMoveTime;
			else if (::strcasecmp(attr, "elapsedMilliSecs") == 0)
				types |= 1 << MoveInfo::ElapsedMilliSeconds;
			else if (::strcasecmp(attr, "clockTime") == 0)
				types |= 1 << MoveInfo::ClockTime;
			else if (::strcasecmp(attr, "corrChessSent") == 0)
				types |= 1 << MoveInfo::CorrespondenceChessSent;
			else if (::strcasecmp(attr, "videoTime") == 0)
				types |= 1 << MoveInfo::VideoTime;
			else
				return error(CmdStrip, 0, 0, "unknown attribute '%s'", attr);
		}

		setResult(scidb->stripMoveInformation(view, types, progress, Application::DontUpdateGameInfo));
	}
	else if (::strcmp(what, "tags") == 0)
	{
		typedef Application::TagMap TagMap;

		Tcl_Obj**	objs;
		TagMap		tags;

		if (Tcl_ListObjGetElements(ti, attrs, &objc, &objs) != TCL_OK)
			return error(CmdStrip, 0, 0, "list of attributes expected");

		for (int i = 0; i < objc; ++i)
			tags[Tcl_GetString(objs[i])] = 1;

		setResult(scidb->stripTags(view, tags, progress, Application::UpdateGameInfo));
	}
	else
	{
		return error(CmdStrip, 0, 0, "unexpected attribute '%s'", what);
	}

	return TCL_OK;
}


static int
cmdEnumTags(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	typedef View::TagMap TagMap;

	if (objc != 6)
	{
		Tcl_WrongNumArgs(
			ti, 1, objv,
			"<database> <variant> <view> <progress-cmd> <progress-arg> ");
		return TCL_ERROR;
	}

	char const*		database	= stringFromObj(objc, objv, 1);
	variant::Type	variant	= tcl::game::variantFromObj(objc, objv, 2);
	Cursor&			cursor	= scidb->cursor(database, variant);
	View&				view		= cursor.view(unsignedFromObj(objc, objv, 3));
	Progress			progress(objv[4], objv[5]);

	TagMap tags;
	view.findTags(tags, progress);

	if (progress.interrupted())
	{
		setResult("interrupted");
	}
	else
	{
		mstl::vector<Tcl_Obj*> objs(tags.size());
		unsigned n = 0;

		for (TagMap::const_iterator i = tags.begin(); i != tags.end(); ++i)
		{
			Tcl_Obj* v[2];

			v[0] = Tcl_NewStringObj(i->first, i->first.size());
			v[1] = Tcl_NewIntObj(i->second);

			M_ASSERT(n < tags.size());
			objs[n++] = Tcl_NewListObj(2, v);
		}

		M_ASSERT(n == tags.size());
		setResult(tags.size(), objs.data());
	}

	return TCL_OK;
}


namespace tcl {
namespace view {

void
init(Tcl_Interp* ti)
{
	createCommand(ti, CmdClose,			cmdClose);
	createCommand(ti, CmdCopy,				cmdCopy);
	createCommand(ti, CmdCount,			cmdCount);
	createCommand(ti, CmdEnumTags,		cmdEnumTags);
	createCommand(ti, CmdExport,			cmdExport);
	createCommand(ti, CmdFind,				cmdFind);
	createCommand(ti, CmdMap,				cmdMap);
	createCommand(ti, CmdNew,				cmdNew);
	createCommand(ti, CmdOpen,				cmdOpen);
	createCommand(ti, CmdPrint,			cmdPrint);
	createCommand(ti, CmdSearch,			cmdSearch);
	createCommand(ti, CmdSetTreeFilter,	cmdSetTreeFilter);
	createCommand(ti, CmdStrip,			cmdStrip);
	createCommand(ti, CmdSubscribe,		cmdSubscribe);
	createCommand(ti, CmdUnsubscribe,	cmdUnsubscribe);
}

} // namespace view
} // namespace tcl

// vi:set ts=3 sw=3:
