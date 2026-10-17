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
// Modified for Chesswiz, 2026; see docs/UPSTREAM.md
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#include "tcl_view.h"

#include <stdint.h>

#include "tcl_progress.h"
#include "tcl_application.h"
#include "tcl_pgn_reader.h"
#include "tcl_game.h"
#include "tcl_exception.h"
#include "tcl_log.h"
#include "tcl_obj.h"
#include "tcl_base.h"
#include "tcl_search.h"

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
static char const* CmdPrintHtml	= "::scidb::view::printHtml";
static char const* CmdPrintPdf	= "::scidb::view::printPdf";
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

static SubscriberMap subscriberMap;

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
	CHECK_ARGS_RANGE(ti, objc, objv, 8, 9, "<database> ?<variant>? <games> <players> <annotators> <positions> <events> <sites>");

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
	CHECK_ARGS_RANGE(ti, objc, objv, 3, 4, "<database> ?<variant>? <view>");

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

	CHECK_ARGS_RANGE(ti, objc, objv, 6, 7, "player|event|site|annotator <database> <variant> <view> <string> ?<start-index>?");

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
	CHECK_ARGS_RANGE(ti, objc, objv, 5, 7, "<database> ?<variant>? <view> <operator> <none|events|sites|players> ?<query>?");

	unsigned n = *Tcl_GetString(objv[2]) == '-' || isdigit(*Tcl_GetString(objv[2])) ? 0 : 1;

	// With an optional variant present (n == 1) the mandatory filter sits at
	// objv[5]; the objc >= 5 check above only covers n == 0, so guard the
	// variant case to avoid reading the NULL objv terminator below.
	if (objc < int(5 + n))
	{
		Tcl_WrongNumArgs(
			ti,
			1,
			objv,
			"<database> ?<variant>? <view> <operator> <none|events|sites|players> ?<query>?");
		return TCL_ERROR;
	}

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
		search = tcl::search::buildSearch(cursor.database(), ti, objv[5 + n]);

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
	// setTreeFilter <database> ?<variant>? <view> -row <n>
	// setTreeFilter <database> ?<variant>? <view> -identity <string>
	CHECK_ARGS_RANGE(ti, objc, objv, 6, 7,
		"<database> ?<variant>? <view> -row <n> | -identity <string>");

	unsigned n = objc == 7 ? 1 : 0;
	char const* database		= stringFromObj(objc, objv, 1);
	variant::Type variant		= n ? tcl::game::variantFromObj(objv[2]) : variant::Undetermined;
	unsigned view				= unsignedFromObj(objc, objv, 2 + n);
	char const* mode			= stringFromObj(objc, objv, 3 + n);
	char const* value			= stringFromObj(objc, objv, 4 + n);
	Cursor& cursor				= scidb->cursor(database, variant);

	if (::strcmp(mode, "-row") == 0)
	{
		unsigned row = unsignedFromObj(objc, objv, 4 + n);

		if (!scidb->setCurrentTreeRowFilter(cursor, view, row))
			return error(CmdSetTreeFilter, nullptr, nullptr,
			             "unable to apply tree row %u to view %u", row, view);
	}
	else if (::strcmp(mode, "-identity") == 0)
	{
		Tcl_Obj* listObj = Tcl_NewStringObj(value, -1);
		int listObjc = 0;
		Tcl_Obj** listObjv = 0;

		if (Tcl_ListObjGetElements(ti, listObj, &listObjc, &listObjv) != TCL_OK
			|| (listObjc != 5 && listObjc != 6))
		{
			Tcl_DecrRefCount(listObj);
			return error(CmdSetTreeFilter, nullptr, nullptr,
			             "invalid tree identity '%s'", value);
		}

		Tcl_WideInt hash = 0;
		int method = 0, treeMode = 0, ratingType = 0, moveIndex = 0;

		if (Tcl_GetWideIntFromObj(ti, listObjv[0], &hash) != TCL_OK
			|| Tcl_GetIntFromObj(ti, listObjv[1], &method) != TCL_OK
			|| Tcl_GetIntFromObj(ti, listObjv[2], &treeMode) != TCL_OK
			|| Tcl_GetIntFromObj(ti, listObjv[3], &ratingType) != TCL_OK
			|| Tcl_GetIntFromObj(ti, listObjv[4], &moveIndex) != TCL_OK)
		{
			Tcl_DecrRefCount(listObj);
			return error(CmdSetTreeFilter, nullptr, nullptr,
			             "invalid tree identity '%s'", value);
		}

		mstl::string eco;
		if (listObjc == 6)
			eco = Tcl_GetString(listObjv[5]);

		bool ok = scidb->setCurrentTreeRowFilter(
			cursor, view,
			static_cast<uint64_t>(hash),
			static_cast<unsigned>(method),
			static_cast<unsigned>(treeMode),
			static_cast<unsigned>(ratingType),
			static_cast<unsigned>(moveIndex),
			eco);

		Tcl_DecrRefCount(listObj);

		if (!ok)
			return error(CmdSetTreeFilter, nullptr, nullptr,
			             "unable to apply tree identity '%s' to view %u", value, view);
	}
	else
	{
		return error(CmdSetTreeFilter, nullptr, nullptr,
		             "unknown mode '%s', expected -row or -identity", mode);
	}

	setResult(true);
	return TCL_OK;
}

static int
cmdSetGames(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	// "-intersect": keep only those of <game-indices> already in the view
	CHECK_ARGS_RANGE(ti, objc, objv, 5, 6, "<database> <variant> <view> <game-indices> ?-intersect?");
	bool intersect = objc == 6 && ::strcmp(Tcl_GetString(objv[5]), "-intersect") == 0;
	if (objc == 6 && !intersect)
		return error("::scidb::view::setGames", 0, 0, "expected -intersect");
	char const* base = Tcl_GetString(objv[1]);
	variant::Type variant = tcl::game::variantFromObj(objv[2]);
	unsigned view = unsignedFromObj(objc, objv, 3);
	Cursor& cursor = scidb->cursor(base, variant);
	if (!cursor.isValidView(view) || !cursor.isViewOpen(view) || !cursor.view(view).isUsed(table::Games))
		return error("::scidb::view::setGames", 0, 0, "invalid game view");
	int count; Tcl_Obj** indices;
	if (Tcl_ListObjGetElements(ti, objv[4], &count, &indices) != TCL_OK) return TCL_ERROR;
	Filter filter(cursor.database().countGames());
	filter.reset();
	for (int i=0;i<count;++i)
	{
		int index;
		if (Tcl_GetIntFromObj(ti, indices[i], &index) != TCL_OK) return TCL_ERROR;
		if (index<0 || unsigned(index)>=filter.size())
			return error("::scidb::view::setGames", 0, 0, "game index out of range");
		if (!intersect || cursor.view(view).filter(table::Games).contains(unsigned(index)))
			filter.add(unsigned(index));
	}
	scidb->setGameFilter(cursor, view, filter);
	setResult(filter.count());
	return TCL_OK;
}


static int
cmdCopy(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	CHECK_ARGS(ti, objc, objv, 10,
		"<source> <view> <destination> <variant> <tag-set> "
		"<progress-cmd> <progress-arg> <log-cmd> <log-arg>");


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
	CHECK_ARGS(ti, objc, objv, 15,
		"<database> <variant> <view> <file> <flags> <mode> <encoding> <exclude-illegal-games-flag> "
		"<exported-tags> <languages> <progress-cmd> <progress-arg> <log-cmd> <log-arg>");

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
cmdPrintHtml(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	// Usage: ::scidb::view::printHtml <database> <variant> <view> <file>
	//                                   <flags> <progress-cmd> <progress-arg>
	//                                   <log-cmd> <log-arg>
	//
	// Publishes the games of the view as a standalone HTML file (UTF-8,
	// embedded CSS, inline-SVG diagrams). The write path of scidb's
	// native HTML support — independent of the TeXt print pipeline.
	// Returns the number of exported games.
	if (objc != 11)
	{
		Tcl_WrongNumArgs(ti, 1, objv,
			"<database> <variant> <view> <file> <flags> <languages> <progress-cmd> <progress-arg> <log-cmd> <log-arg>");
		return TCL_ERROR;
	}

	char const*			database	= stringFromObj(objc, objv, 1);
	variant::Type		variant		= tcl::game::variantFromObj(objc, objv, 2);
	unsigned				view			= unsignedFromObj(objc, objv, 3);
	char const*			filename	= stringFromObj(objc, objv, 4);
	unsigned				flags		= unsignedFromObj(objc, objv, 5);

	Tcl_Obj**				objs;
	View::Languages	languages;
	int					significant;

	significant = view::makeLangList(ti, CmdPrintHtml, objv[6], languages);

	if (significant == -1)
		return TCL_ERROR;

	Progress				progress(objv[7], objv[8]);
	tcl::Log				log(objv[9], objv[10]);
	Cursor&				cursor(scidb->cursor(database, variant));
	View&					v(cursor.view(view));

	setResult(v.printHtml(	filename,
									format::Html,
									flags,
									significant == 0 ? nullptr : &languages,
									unsigned(significant),
									nullptr, // illegal moves are not rejected on export
									log,
									progress));

	return TCL_OK;
}


static int
cmdPrintPdf(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	// Usage: ::scidb::view::printPdf <database> <variant> <view> <file>
	//                                  <flags> <progress-cmd> <progress-arg>
	//                                  <log-cmd> <log-arg>
	//
	// Publishes the games of the view as a native PDF file (PdfWriter -
	// embedded fonts, diagram images from the pdf/sets). Returns the
	// number of exported games.
	if (objc != 10)
	{
		Tcl_WrongNumArgs(ti, 1, objv,
			"<database> <variant> <view> <file> <flags> <progress-cmd> <progress-arg> <log-cmd> <log-arg>");
		return TCL_ERROR;
	}

	char const*			database	= stringFromObj(objc, objv, 1);
	variant::Type		variant		= tcl::game::variantFromObj(objc, objv, 2);
	unsigned				view			= unsignedFromObj(objc, objv, 3);
	char const*			filename	= stringFromObj(objc, objv, 4);
	unsigned				flags		= unsignedFromObj(objc, objv, 5);

	Progress				progress(objv[6], objv[7]);
	tcl::Log				log(objv[8], objv[9]);
	Cursor&				cursor(scidb->cursor(database, variant));
	View&					v(cursor.view(view));

	setResult(v.printPdf(	filename,
								format::Pdf,
								flags,
								nullptr,
								log,
								progress));

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

	CHECK_ARGS(ti, objc, objv, 17,
		"<database> <variant> <view> <file> <search-path> <script-path> <preamble> <flags> "
		"<options> <nag-map> <languages> <trace> <progress-cmd> <progress-arg> "
		"<log-cmd> <log-arg>");

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
	CHECK_ARGS_RANGE(ti, objc, objv, 5, 6, "<player|event|site|game|position> <database> ?<variant>? <view> <index>");

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
	CHECK_ARGS_RANGE(ti, objc, objv, 4, 5, "<proc> <database> <variant> ?<arg>?");

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
	CHECK_ARGS_RANGE(ti, objc, objv, 4, 5, "<proc> <database> <variant> ?<arg>?");

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
	CHECK_ARGS(ti, objc, objv, 8, "<what> <database> <variant> <view> <attributes> <progress-cmd> <progress-arg> ");

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

	CHECK_ARGS(ti, objc, objv, 6, "<database> <variant> <view> <progress-cmd> <progress-arg> ");

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
	createCommand(ti, CmdPrintHtml,	cmdPrintHtml);
	createCommand(ti, CmdPrintPdf,		cmdPrintPdf);
	createCommand(ti, CmdSearch,			cmdSearch);
	createCommand(ti, CmdSetTreeFilter,	cmdSetTreeFilter);
	createCommand(ti, "::scidb::view::setGames", cmdSetGames);
	createCommand(ti, CmdStrip,			cmdStrip);
	createCommand(ti, CmdSubscribe,		cmdSubscribe);
	createCommand(ti, CmdUnsubscribe,	cmdUnsubscribe);
}

} // namespace view
} // namespace tcl
// vi:set ts=3 sw=3:
