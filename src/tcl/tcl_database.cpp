// ======================================================================
// Author : $Author$
// Version: $Revision: 1523 $
// Date   : $Date: 2018-09-17 08:11:58 -0400 (Mon, 17 Sep 2018) $
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

#include "tcl_database.h"
#include "tcl_tree.h"
#include "tcl_application.h"
#include "tcl_pgn_reader.h"
#include "tcl_player.h"
#include "tcl_progress.h"
#include "tcl_exception.h"
#include "tcl_game.h"
#include "tcl_view.h"
#include "tcl_file.h"
#include "tcl_tree.h"
#include "tcl_log.h"
#include "tcl_obj.h"
#include "tcl_base.h"

#include "app_application.h"
#include "app_subscriber.h"
#include "app_multi_cursor.h"
#include "app_cursor.h"
#include "app_view.h"

#include "db_database.h"
#include "db_database_codec.h"
#include "db_game.h"
#include "db_move_node.h"
#include "scm/scm_media.h"
#include "cbh/cbh_media.h"
#include "tcl_media_extract.h"
#include "html/html_cb_adapter.h"
#include "db_maintenance.h"
#include "db_multi_base.h"
#include "db_game_info.h"
#include "db_player.h"
#include "db_player_stats.h"
#include "db_site.h"
#include "db_statistic.h"
#include "db_pgn_reader.h"
#include "db_eco_table.h"
#include "db_exception.h"

#include "si3_decoder.h"
#include "si3_encoder.h"
#include "sci_codec.h"

#include "T_Controller.h"

#include "u_zstream.h"
#include "u_zlib_ostream.h"
#include "u_misc.h"
#include "u_crc.h"
#include "u_byte_stream.h"

#include "sys_utf8_codec.h"
#include "sys_file.h"

#include "m_utility.h"
#include "m_bitset.h"
#include "m_vector.h"
#include "m_map.h"
#include "m_algorithm.h"
#include "m_limits.h"
#include "m_tuple.h"
#include "m_sstream.h"
#include "m_auto_ptr.h"

#include <tcl.h>
#include <string.h>
#include <ctype.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>


using namespace db;
using namespace app;
using namespace tcl;
using namespace tcl::db;
using namespace tcl::app;
using namespace mstl;

static char const* CmdAttach			= "::scidb::db::attach";
static char const* CmdClear			= "::scidb::db::clear";
static char const* CmdClose			= "::scidb::db::close";
static char const* CmdCompact			= "::scidb::db::compact";
static char const* CmdCopy				= "::scidb::db::copy";
static char const* CmdCount			= "::scidb::db::count";
static char const* CmdFetch			= "::scidb::db::fetch";
static char const* CmdFind				= "::scidb::db::find";
static char const* CmdImport			= "::scidb::db::import";
static char const* CmdLoad				= "::scidb::db::load";
static char const* CmdNew				= "::scidb::db::new";
static char const* CmdSet				= "::scidb::db::set";
static char const* CmdGet				= "::scidb::db::get";
static char const* CmdMatch			= "::scidb::db::match";
static char const* CmdOpen				= "::scidb::db::open";
static char const* CmdPlayerCard		= "::scidb::db::playerCard";
static char const* CmdPlayerInfo		= "::scidb::db::playerInfo";
static char const* CmdRecode			= "::scidb::db::recode";
static char const* CmdReverse			= "::scidb::db::reverse";
static char const* CmdSave				= "::scidb::db::save";
static char const* CmdSavePGN			= "::scidb::db::savePGN";
static char const* CmdSort				= "::scidb::db::sort";
static char const* CmdSubscribe		= "::scidb::db::subscribe";
static char const* CmdSwitch			= "::scidb::db::switch";
static char const* CmdUnsubscribe	= "::scidb::db::unsubscribe";
static char const* CmdUpdate			= "::scidb::db::update";
static char const* CmdUpgrade			= "::scidb::db::upgrade";
static char const* CmdWrite			= "::scidb::db::write";
static char const* CmdFindDuplicates	= "::scidb::db::findDuplicates";
static char const* CmdEcoStats			= "::scidb::db::ecoStats";
static char const* CmdFindPlayers		= "::scidb::db::findPlayers";
static char const* CmdPlayerSpellings	= "::scidb::db::playerSpellings";
static char const* CmdOpeningScore	= "::scidb::db::openingScore";
static char const* CmdPlayerOpenings	= "::scidb::db::playerOpenings";
static char const* CmdPlayerGames		= "::scidb::db::playerGames";
static char const* CmdMediaFiles		= "::scidb::db::mediaFiles";
static char const* CmdMediaGallery	= "::scidb::db::mediaGallery";
static char const* CmdMediaLinkReady	= "::scidb::db::mediaLinkReady";
static char const* CmdFingerprints		= "::scidb::db::fingerprints";
static char const* CmdPlayerLinks		= "::scidb::db::playerLinks";
static char const* CmdLinkPlayers		= "::scidb::db::linkPlayers";
static char const* CmdSpellingCandidates	= "::scidb::db::spellingCandidates";
static char const* CmdLinkPlayer		= "::scidb::db::linkPlayer";
static char const* CmdGuidingText	= "::scidb::db::guidingText";
static char const* CmdGameAnchor	= "::scidb::db::gameAnchor";
static char const* CmdHtmlSanitize	= "::scidb::html::sanitize";
static char const* CmdMarkDeleted		= "::scidb::db::markDeleted";


static char const User1 = GameInfo::mapFlag(GameInfo::Flag_User1);
static char const User2 = GameInfo::mapFlag(GameInfo::Flag_User2);
static char const User3 = GameInfo::mapFlag(GameInfo::Flag_User3);
static char const User4 = GameInfo::mapFlag(GameInfo::Flag_User4);
static char const User5 = GameInfo::mapFlag(GameInfo::Flag_User5);
static char const User6 = GameInfo::mapFlag(GameInfo::Flag_User6);


enum
{
	PlayerKey_Name,
	PlayerKey_FideID,
	PlayerKey_Sex,
	PlayerKey_Country,
	PlayerKey_Title,
	PlayerKey_Type,
	PlayerKey_LAST,
};

enum
{
	EventKey_Name,
	EventKey_Type,
	EventKey_Date,
	EventKey_TimeMode,
	EventKey_EventMode,
	EventKey_Site,
	EventKey_SiteCountry,
	EventKey_LAST,
};

enum
{
	SiteKey_Site,
	SiteKey_Country,
	SiteKey_LAST,
};


__attribute__((unused))
static bool
checkNonZero(Tcl_Obj** objv, unsigned size)
{
	for (unsigned i = 0; i < size; ++i)
	{
		if (!objv[i])
			return false;
	}

	return true;
}


static bool
isOption(char const* s)
{
	return s[0] == '-' && !isdigit(s[1]);
}


static Ratings
convRatings(char const* s)
{
	M_ASSERT(s);

	char const* t = s;

	while (*t && !::isspace(*t))
		++t;

	while (::isspace(*t))
		++t;

	return Ratings(rating::fromString(s), rating::fromString(t));
}


static void
mapScid4Flags(mstl::string& flags)
{
	for (unsigned i = 0; i < flags.size(); ++i)
	{
		char c = flags[i];

		if (!isspace(c))
		{
			if      (c == User1) flags[i] = '1';
			else if (c == User2) flags[i] = '2';
			else if (c == User3) flags[i] = '3';
			else if (c == User4) flags[i] = '4';
			else if (c == User5) flags[i] = '5';
			else if (c == User6) flags[i] = '6';
		}
	}
}


static void
remapScid4Flags(mstl::string& flags)
{
	for (unsigned i = 0; i < flags.size(); ++i)
	{
		switch (flags[i])
		{
			case '1': flags[i] = User1; break;
			case '2': flags[i] = User2; break;
			case '3': flags[i] = User3; break;
			case '4': flags[i] = User4; break;
			case '5': flags[i] = User5; break;
			case '6': flags[i] = User6; break;
		}
	}
}


static Namebase::Type
getNamebaseType(Tcl_Obj* obj, char const* cmd)
{
	static char const* Keywords[] = { "player", "event", "site", "annotator", 0 };
	enum { Type_Player, Type_Event, Type_Site, Type_Annotator };

	switch (tcl::uniqueMatchObj(obj, Keywords))
	{
		case Type_Player:		return Namebase::Player;
		case Type_Event:		return Namebase::Event;
		case Type_Site:		return Namebase::Site;
		case Type_Annotator:	return Namebase::Annotator;
	}

	error(cmd, nullptr, nullptr, "unknown namebase type '%s'", Tcl_GetString(obj));
	return static_cast<Namebase::Type>(-1);
}


namespace {

struct MySubscriber : public ::app::Subscriber
{
	enum Type
	{
		GameList				= 1 << table::Games,
		PlayerList			= 1 << table::Players,
		EventList			= 1 << table::Events,
		SiteList				= 1 << table::Sites,
		AnnotatorList		= 1 << table::Annotators,
		PositionList		= 1 << table::Positions,
		DatabaseInfo		= 1 << table::LAST,
		GameInfo				= 1 << (table::LAST + 1),
		GameData				= 1 << (table::LAST + 2),
		GameHistory			= 1 << (table::LAST + 3),
		GameSwitched		= 1 << (table::LAST + 4),
		GameClosed			= 1 << (table::LAST + 5),
		DatabaseSwitched	= 1 << (table::LAST + 6),
		Tree					= 1 << (table::LAST + 7),
		None					= 1 << (table::LAST + 8),
	};

	typedef mstl::tuple<Obj, Obj> Tuple;

	struct Args
	{
		Args() :m_type(GameList), m_tuple(nullptr, nullptr), m_ref(0) {}

		Args(Type type, Tcl_Obj* updateCmd, Tcl_Obj* closeCmd)
			:m_type(type)
			,m_tuple(
				updateCmd && *Tcl_GetString(updateCmd) ? updateCmd : nullptr,
				closeCmd && *Tcl_GetString(closeCmd) ? closeCmd : nullptr)
			,m_ref(0)
		{
		}

		void ref()
		{
			if (m_ref++ == 0)
			{
				m_tuple.get<0>().ref();
				m_tuple.get<1>().ref();
			}
		}

		void deref()
		{
			M_ASSERT(m_ref > 0);

			if (--m_ref == 0)
			{
				m_tuple.get<0>().deref();
				m_tuple.get<1>().deref();

				m_type = None;
				m_tuple = Tuple(nullptr, nullptr);
			}
		}

		Type		m_type;
		Tuple		m_tuple;
		unsigned	m_ref;

		bool operator==(Args const& args) const
		{
			return m_type == args.m_type && m_tuple == args.m_tuple;
		}

		Tcl_Obj* getUpdate() const	{ return m_tuple.get<0>(); }
		Tcl_Obj* getClose() const	{ return m_tuple.get<1>(); }
	};

	typedef mstl::vector<Args> ArgsList;

	ArgsList			m_list;
	mstl::bitset	m_used;
	unsigned			m_last;

	void setCmd(Type type, Tcl_Obj* updateCmd, Tcl_Obj* closeCmd)
	{
		Args args(type, updateCmd, closeCmd);
		ArgsList::iterator i = mstl::find(m_list.begin(), m_list.end(), args);

		if (i == m_list.end())
		{
			unsigned index = m_used.find_first_not();

			if (index == m_used.npos)
			{
				index = m_list.size();
				m_list.push_back();
				m_used.resize(m_list.size());
			}

			m_list[index] = args;
			m_list[index].ref();
			m_used.set(index);
			m_last = m_used.find_last() + 1;
		}
		else
		{
			i->ref();
		}
	}

	void unsetCmd(Type type, Tcl_Obj* updateCmd, Tcl_Obj* closeCmd)
	{
		Args args(type, updateCmd, closeCmd);
		ArgsList::iterator i = mstl::find(m_list.begin(), m_list.end(), args);

		if (i == m_list.end())
		{
			fprintf(	stderr,
						"Warning: database::unsubscribe failed (%s, %s)\n",
						Tcl_GetString(updateCmd),
						closeCmd ? Tcl_GetString(closeCmd) : "");
		}
		else
		{
			i->deref();
			m_used.reset(i - m_list.begin());
			m_last = m_used.find_last() + 1;
		}
	}

	void setListCmd(table::Type type, Tcl_Obj* updateCmd, Tcl_Obj* closeCmd)
	{
		setCmd(Type(1 << type), updateCmd, closeCmd);
	}

	void setGameSwitchedCmd(Tcl_Obj* updateCmd)
	{
		setCmd(GameSwitched, updateCmd, nullptr);
	}

	void setGameClosedCmd(Tcl_Obj* updateCmd)
	{
		setCmd(GameClosed, updateCmd, nullptr);
	}

	void setDatabaseSwitchedCmd(Tcl_Obj* updateCmd)
	{
		setCmd(DatabaseSwitched, updateCmd, nullptr);
	}

	void unsetListCmd(table::Type type, Tcl_Obj* updateCmd, Tcl_Obj* closeCmd)
	{
		unsetCmd(Type(1 << type), updateCmd, closeCmd);
	}

	void unsetTreeCmd(Tcl_Obj* updateCmd, Tcl_Obj* closeCmd)
	{
		unsetCmd(Tree, updateCmd, closeCmd);
	}

	void unsetGameSwitchedCmd(Tcl_Obj* updateCmd)
	{
		unsetCmd(GameSwitched, updateCmd, nullptr);
	}

	void unsetGameClosedCmd(Tcl_Obj* updateCmd)
	{
		unsetCmd(GameClosed, updateCmd, nullptr);
	}

	void unsetDatabaseSwitchedCmd(Tcl_Obj* updateCmd)
	{
		unsetCmd(DatabaseSwitched, updateCmd, nullptr);
	}

	void closeDatabase(mstl::string const& name, variant::Type variant) override
	{
		Tcl_Obj* file = Tcl_NewStringObj(name, name.size());
		Tcl_Obj* t = tcl::tree::variantToString(variant);

		Tcl_IncrRefCount(file);

		for (unsigned k = 0; k < m_last; ++k)
		{
			Args const& i = m_list[k];

			if (i.getClose())
				invoke(__func__, i.getClose(), file, t, nullptr);
		}

		Tcl_DecrRefCount(file);
	}

	void updateDatabaseInfo(mstl::string const& name, variant::Type variant) override
	{
		Tcl_Obj* f = Tcl_NewStringObj(name, name.size());
		Tcl_Obj* t = tcl::tree::variantToString(variant);

		Tcl_IncrRefCount(f);

		for (unsigned k = 0; k < m_last; ++k)
		{
			Args const& i = m_list[k];

			if ((i.m_type & DatabaseInfo) && i.getUpdate())
				invoke(__func__, i.getUpdate(), f, t, nullptr);
		}

		Tcl_DecrRefCount(f);
	}

	void updateList(	unsigned id,
							string const& name,
							variant::Type variant,
							unsigned view,
							unsigned index,
							Type type)
	{
		Tcl_Obj* n = Tcl_NewIntObj(id);
		Tcl_Obj* f = Tcl_NewStringObj(name, name.size());
		Tcl_Obj* t = tcl::tree::variantToString(variant);
		Tcl_Obj* v = Tcl_NewIntObj(view);
		Tcl_Obj* w = Tcl_NewIntObj(index);

		Tcl_IncrRefCount(n);
		Tcl_IncrRefCount(f);
		Tcl_IncrRefCount(v);
		Tcl_IncrRefCount(w);

		for (unsigned k = 0; k < m_last; ++k)
		{
			Args const& i = m_list[k];

			if ((i.m_type & type) && i.getUpdate())
				invoke(__func__, i.getUpdate(), n, f, t, v, w, nullptr);
		}

		Tcl_DecrRefCount(n);
		Tcl_DecrRefCount(f);
		Tcl_DecrRefCount(v);
		Tcl_DecrRefCount(w);
	}

	void updateList(table::Type type, unsigned id, string const& name, variant::Type variant) override
	{
		updateList(id, name, variant, unsigned(-1), unsigned(-1), Type(1 << type));
	}

	void updateList(	table::Type type,
							unsigned id,
							string const& name,
							variant::Type variant,
							unsigned view) override
	{
		updateList(id, name, variant, view, unsigned(-1), Type(1 << type));
	}

	void updateList(	table::Type type,
							unsigned id,
							string const& name,
							variant::Type variant,
							unsigned view,
							unsigned index) override
	{
		updateList(id, name, variant, view, index, Type(1 << type));
	}

	void updateGameData(unsigned position, bool evenMainline) override
	{
		Tcl_Obj* pos = Tcl_NewIntObj(position);
		Tcl_Obj* mainline = Tcl_NewBooleanObj(evenMainline);

		Tcl_IncrRefCount(pos);
		Tcl_IncrRefCount(mainline);

		for (unsigned k = 0; k < m_last; ++k)
		{
			Args const& i = m_list[k];

			if ((i.m_type & GameData) && i.getUpdate())
				invoke(__func__, i.getUpdate(), pos, mainline, nullptr);
		}

		Tcl_DecrRefCount(pos);
		Tcl_DecrRefCount(mainline);
	}

	void updateGameInfo(unsigned position) override
	{
		Tcl_Obj* pos = Tcl_NewIntObj(position);
		Tcl_IncrRefCount(pos);

		for (unsigned k = 0; k < m_last; ++k)
		{
			Args const& i = m_list[k];

			if ((i.m_type & GameInfo) && i.getUpdate())
				invoke(__func__, i.getUpdate(), pos, nullptr);
		}

		Tcl_DecrRefCount(pos);
	}

	void updateGameInfo(mstl::string const& name, variant::Type variant, unsigned index) override
	{
		Tcl_Obj* f = Tcl_NewStringObj(name, name.size());
		Tcl_Obj* t = tcl::tree::variantToString(variant);
		Tcl_Obj* w = Tcl_NewIntObj(index);

		Tcl_IncrRefCount(f);
		Tcl_IncrRefCount(w);

		for (unsigned k = 0; k < m_last; ++k)
		{
			Args const& i = m_list[k];

			if ((i.m_type & GameHistory) && i.getUpdate())
				invoke(__func__, i.getUpdate(), f, t, w, nullptr);
		}

		Tcl_DecrRefCount(f);
		Tcl_DecrRefCount(w);
	}

	void gameSwitched(unsigned oldPosition, unsigned newPosition) override
	{
		Tcl_Obj* oldPos = Tcl_NewIntObj(oldPosition);
		Tcl_Obj* newPos = Tcl_NewIntObj(newPosition);

		Tcl_IncrRefCount(oldPos);
		Tcl_IncrRefCount(newPos);

		for (unsigned k = 0; k < m_last; ++k)
		{
			Args const& i = m_list[k];

			if ((i.m_type & GameSwitched) && i.getUpdate())
				invoke(__func__, i.getUpdate(), oldPos, newPos, nullptr);
		}

		Tcl_DecrRefCount(oldPos);
		Tcl_DecrRefCount(newPos);
	}

	void gameClosed(unsigned position) override
	{
		Tcl_Obj* pos = Tcl_NewIntObj(position);
		Tcl_IncrRefCount(pos);

		for (unsigned k = 0; k < m_last; ++k)
		{
			Args const& i = m_list[k];

			if ((i.m_type & GameClosed) && i.getUpdate())
				invoke(__func__, i.getUpdate(), pos, nullptr);
		}

		Tcl_DecrRefCount(pos);
	}

	void databaseSwitched(mstl::string const& name, variant::Type variant) override
	{
		Tcl_Obj* f = Tcl_NewStringObj(name, name.size());
		Tcl_Obj* t = tcl::tree::variantToString(variant);

		Tcl_IncrRefCount(f);

		for (unsigned k = 0; k < m_last; ++k)
		{
			Args const& i = m_list[k];

			if ((i.m_type & DatabaseSwitched) && i.getUpdate())
				invoke(__func__, i.getUpdate(), f, t, nullptr);
		}

		Tcl_DecrRefCount(f);
	}

	void updateTree(mstl::string const& name, variant::Type variant) override
	{
		static mstl::string prevFilename;

		if (name != prevFilename)
		{
			prevFilename = name;
			tcl::tree::referenceBaseChanged();
		}

		Tcl_Obj* file = Tcl_NewStringObj(name, name.size());
		Tcl_Obj* t = tcl::tree::variantToString(variant);

		Tcl_IncrRefCount(file);

		for (unsigned k = 0; k < m_last; ++k)
		{
			Args const& i = m_list[k];

			if ((i.m_type & Tree) && i.getUpdate())
				invoke(__func__, i.getUpdate(), file, t, nullptr);
		}

		Tcl_DecrRefCount(file);
	}

	void invalidateTreeCache() override
	{
		tcl::tree::invalidateCache();
	}
};

} // namespace


int
tcl::db::countNumGames(mstl::string const& filename)
{
	int						numGames;
	uint32_t					creationTime;
	::db::type::ID			type;
	::db::variant::Type	variant;

	if (!::db::DatabaseCodec::getAttributes(filename, numGames, type, variant, creationTime))
		return -1;
	return numGames;
}


char const*
tcl::db::lookupType(type::ID type)
{
	switch (type)
	{
		case type::Unspecific:					return "Unspecific";
		case type::Temporary:					return "Temporary";
		case type::Work:							return "Work";
		case type::Clipbase:						return "Clipbase";
		case type::My_Games:						return "MyGames";
		case type::Informant:					return "Informant";
		case type::Large_Database:				return "LargeDatabase";
		case type::Correspondence_Chess:		return "CorrespondenceChess";
		case type::Email_Chess:					return "EmailChess";
		case type::Internet_Chess:				return "InternetChess";
		case type::Computer_Chess:				return "ComputerChess";
		case type::Chess_960:					return "Chess960";
		case type::Player_Collection:			return "PlayerCollection";
		case type::Tournament:					return "Tournament";
		case type::Tournament_Swiss:			return "TournamentSwiss";
		case type::GM_Games:						return "GMGames";
		case type::IM_Games:						return "IMGames";
		case type::Blitz_Games:					return "BlitzGames";
		case type::Tactics:						return "Tactics";
		case type::Endgames:						return "Endgames";
		case type::Analysis:						return "Analysis";
		case type::Training:						return "Training";
		case type::Match:							return "Match";
		case type::Studies:						return "Studies";
		case type::Jewels:						return "Jewels";
		case type::Problems:						return "Problems";
		case type::Patzer:						return "Patzer";
		case type::Gambit:						return "Gambit";
		case type::Important:					return "Important";
		case type::Openings_White:				return "OpeningsWhite";
		case type::Openings_Black:				return "OpeningsBlack";
		case type::Openings:						return "Openings";
		case type::Bughouse:						return "Bughouse";
		case type::Antichess:					return "Antichess";
		case type::PlayerCollectionFemale:	return "PlayerCollectionFemale";
		case type::PGNFile:						return "PGNFile";
		case type::ThreeCheck:					return "ThreeCheck";
		case type::Crazyhouse:					return "Crazyhouse";
	}

	return 0;	// not reached
}


static attribute::game::ID
lookupGameInfo(Tcl_Obj* obj, Ratings& ratings, bool averageFlag)
{
	int column;

	if (	Tcl_GetIntFromObj(interp(), obj, &column) != TCL_OK
		|| column < 0
		|| column >= attribute::game::LastColumn)
	{
		appendResult(	"integer in range 0-%d expected", attribute::game::LastColumn - 1);
		return attribute::game::ID(-1);
	}

	switch (column)
	{
		case attribute::game::WhiteRating2:
			ratings.first = ratings.second;
			// fallthru

		case attribute::game::WhiteRating1:
			if (ratings.first == rating::Elo)
				column = averageFlag ? attribute::game::AverageElo : attribute::game::WhiteElo;
			else
				column = averageFlag ? attribute::game::AverageRating : attribute::game::WhiteRating;
			break;

		case attribute::game::BlackRating2:
			ratings.first = ratings.second;
			// fallthru

		case attribute::game::BlackRating1:
			if (ratings.first == rating::Elo)
				column = averageFlag ? attribute::game::AverageElo : attribute::game::BlackElo;
			else
				column = averageFlag ? attribute::game::AverageRating : attribute::game::BlackRating;
			break;

		default:
			if (averageFlag)
			{
				appendResult(	"'average' not allowed for column %d", column);
				return attribute::game::ID(-1);
			}
			break;
	}

	return attribute::game::ID(column);
}


static attribute::player::ID
lookupPlayerBase(Tcl_Obj* obj, Ratings& ratings, bool latest)
{
	int column;

	if (	Tcl_GetIntFromObj(interp(), obj, &column) != TCL_OK
		|| column < 0
		|| column >= attribute::player::LastColumn)
	{
		appendResult(	"integer in range 0-%d expected", attribute::player::LastColumn - 1);
		return attribute::player::ID(-1);
	}

	switch (column)
	{
		case attribute::player::Rating2:
			ratings.first = ratings.second;
			// fallthru

		case attribute::player::Rating1:
			if (latest)
			{
				column = ratings.first == rating::Elo
								? attribute::player::EloLatest
								: attribute::player::RatingLatest;
			}
			else
			{
				column = ratings.first == rating::Elo
								? attribute::player::EloHighest
								: attribute::player::RatingHighest;
			}
			break;
	}

	return attribute::player::ID(column);
}


static attribute::event::ID
lookupEventBase(Tcl_Obj* obj)
{
	int column;

	if (	Tcl_GetIntFromObj(interp(), obj, &column) != TCL_OK
		|| column < 0
		|| column >= attribute::event::LastColumn)
	{
		appendResult(	"integer in range 0-%d expected", attribute::event::LastColumn - 1);
		return attribute::event::ID(-1);
	}

	return attribute::event::ID(column);
}


static attribute::site::ID
lookupSiteBase(Tcl_Obj* obj)
{
	int column;

	if (	Tcl_GetIntFromObj(interp(), obj, &column) != TCL_OK
		|| column < 0
		|| column >= attribute::site::LastColumn)
	{
		appendResult(	"integer in range 0-%d expected", attribute::site::LastColumn - 1);
		return attribute::site::ID(-1);
	}

	return attribute::site::ID(column);
}


static attribute::annotator::ID
lookupAnnotatorBase(Tcl_Obj* obj)
{
	int column;

	if (	Tcl_GetIntFromObj(interp(), obj, &column) != TCL_OK
		|| column < 0
		|| column >= attribute::annotator::LastColumn)
	{
		appendResult(	"integer in range 0-%d expected", attribute::annotator::LastColumn - 1);
		return attribute::annotator::ID(-1);
	}

	return attribute::annotator::ID(column);
}


static attribute::position::ID
lookupPositionBase(Tcl_Obj* obj)
{
	int column;

	if (	Tcl_GetIntFromObj(interp(), obj, &column) != TCL_OK
		|| column < 0
		|| column >= attribute::position::LastColumn)
	{
		appendResult(	"integer in range 0-%d expected", attribute::position::LastColumn - 1);
		return attribute::position::ID(-1);
	}

	return attribute::position::ID(column);
}


static int
convToType(char const* cmd, Tcl_Obj* typeObj, int* type)
{
	if (Tcl_GetIntFromObj(interp(), typeObj, type) != TCL_OK)
	{
		return error(	cmd,
							nullptr,
							nullptr,
							"integer expected for type (given: %s)",
							Tcl_GetString(typeObj));
	}

	if (0 > *type || *type > ::db::type::LAST)
		return error(cmd, nullptr, nullptr, "given type exceeds range 0-%d", int(::db::type::LAST));

	return TCL_OK;
}


static void
flagsToString(unsigned flags, mstl::string& result)
{
	mstl::string buf;

	GameInfo::flagsToString(flags & ~GameInfo::Flag_Deleted, buf);

	for (unsigned i = 0; i < buf.size(); ++i)
	{
		result += buf[i];
		result += ' ';
	}

	result.trim();
}


static int
cmdAttach(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 3 && objc != 5)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <file> ?<progress-cmd> <progress-arg>?");
		return TCL_ERROR;
	}

	char const* database	= stringFromObj(objc, objv, 1);
	char const* filename = stringFromObj(objc, objv, 2);

	if (objc >= 5)
	{
		Progress progress(objv[3], objv[4]);
		scidb->cursor(database).getDatabase().attach(filename, progress);
	}
	else
	{
		util::Progress progress;
		scidb->cursor(database).getDatabase().attach(filename, progress);
	}

	return TCL_OK;
}


static int
cmdLoad(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc < 4 || (objc % 2) != 0)
	{
		Tcl_WrongNumArgs(
			ti,
			1, objv,
			"<file> <progress-cmd> <arg> ?-encoding <string>? ?-readonly <flag>?");
		return TCL_ERROR;
	}

	char const* encoding = sys::utf8::Codec::utf8();
	permission::ReadMode permission = permission::ReadWrite;

	for ( ; objc > 4; objc -= 2)
	{
		char const* arg = stringFromObj(objc, objv, objc - 2);

		if (::strcmp(arg, "-encoding") == 0)
			encoding = stringFromObj(objc, objv, objc - 1);
		else if (::strcmp(arg, "-readonly") == 0)
			permission = boolFromObj(objc, objv, objc - 1) ? permission::ReadOnly : permission::ReadWrite;
		else
			return error(CmdLoad, nullptr, nullptr, "unexpected option '%s'", arg);
	}

	mstl::string path(Tcl_GetString(objv[1]));

	if (util::misc::file::suffix(path) == "sci")
		encoding = sys::utf8::Codec::utf8();

	Progress	progress(objv[2], objv[3]);
	progress.checkInterruption();

	Cursor* cursor = scidb->open(path, encoding, permission, process::Synchronous, progress);

	if (cursor == 0)
		return TCL_ERROR;

	if (cursor->database().name() != path)
	{
		mstl::string msg;

		msg += "file ";
		msg += path;
		msg += " conflicts with open file ";
		msg += cursor->database().name();

		return ioError(cursor->database().name(), "HardLinkDetected", msg);
	}

	setResult(lookupType(cursor->type()));
	return TCL_OK;
}


static int
cmdImport(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	static char const* Usage =
		"<database> <file> <log> <log-arg> <progress-cmd> <progress-arg> "
		"?-encoding <string>? ?-illegal <boolean>?";

	if (objc < 7 || (objc % 2) == 0)
	{
		Tcl_WrongNumArgs(ti, 1, objv, Usage);
		return TCL_ERROR;
	}

	mstl::string	encoding		= sys::utf8::Codec::utf8();
	bool				includeIllegalGames = false;

	while (objc > 7)
	{
		char const* option = stringFromObj(objc, objv, objc - 2);

		if (::strcmp(option, "-encoding") == 0)
		{
			encoding = stringFromObj(objc, objv, objc - 1);
		}
		else if (::strcmp(option, "-illegal") == 0)
		{
			includeIllegalGames = boolFromObj(objc, objv, objc - 1);
		}
		else
		{
			appendResult("unexpected option '%s'", option);
			return TCL_ERROR;
		}

		objc -= 2;
	}

	mstl::string	dst(stringFromObj(objc, objv, 1));
	mstl::string	src(stringFromObj(objc, objv, 2));
	mstl::string	ext(::util::misc::file::suffix(src));
	Progress			progress(objv[5], objv[6]);
	unsigned			count = 0;

	if (ext == "sci" || ext == "si3" || ext == "si4")
	{
		unsigned accepted[variant::NumberOfVariants];
		unsigned rejected[variant::NumberOfVariants];

		::memset(accepted, 0, sizeof(accepted));
		::memset(rejected, 0, sizeof(accepted));

		tcl::Log log(objv[3], objv[4]);
		unsigned illegalRejected = 0;
		unsigned* illegalPtr = includeIllegalGames ? nullptr : &illegalRejected;

		if (scidb->contains(src))
		{
			::app::Application::Variants srcVariants = Scidb->getAllVariants(src);
			::app::Application::Variants dstVariants = Scidb->getAllVariants(dst);

			for (unsigned v = 0; v < variant::NumberOfVariants; ++v)
			{
				if (srcVariants.test(v) && dstVariants.test(v))
				{
					variant::Type variant = variant::fromIndex(v);
					Cursor const& source(Scidb->cursor(src, variant));
					Cursor& destination(const_cast<Cursor&>(Scidb->cursor(dst, variant)));
					unsigned k = destination.database().countGames();
					unsigned n = destination.importGames(source.database(), illegalPtr, log, progress);

					count += n;
					accepted[v] = n;

					if (!format::isScidFormat(source.sourceFormat()) || variant != variant::ThreeCheck)
						rejected[v] = source.database().countGames() - n - k;
				}
				else if (srcVariants.test(v))
				{
					variant::Type variant = variant::fromIndex(v);
					Cursor const& source(scidb->cursor(src, variant));

					if (!format::isScidFormat(source.sourceFormat()) || variant != variant::Normal)
						rejected[v] = source.database().countGames();
				}
			}
		}
		else
		{
			mstl::auto_ptr< ::db::Database> db;

			try
			{
				db = new ::db::Database(src, encoding);
			}
			catch (...)
			{
				appendResult("cannot open file '%s'", src.c_str());
				return TCL_ERROR;
			}

			variant::Type variant = db->variant();
			MultiCursor const& destination = Scidb->multiCursor(dst);
			unsigned numGames = tcl::db::countNumGames(src);

			if (	format::isScidFormat(db->format())
				&& destination.multiBase().sourceFormat() == format::Scidb
				&& destination.multiBase().variant() == variant::ThreeCheck)
			{
				M_ASSERT(variant == variant::Normal);
				variant = variant::ThreeCheck;
			}

			unsigned variantIndex = variant::toIndex(variant);

			if (Scidb->contains(dst, variant))
			{
				M_ASSERT(destination[variantIndex]);
				Cursor& cursor(*destination[variantIndex]);
				unsigned n = cursor.importGames(*db, illegalPtr, log, progress);

				count += n;
				accepted[variantIndex] = n;
				rejected[variantIndex] = numGames - n;
			}
			else
			{
				rejected[variantIndex] = tcl::db::countNumGames(src);
			}
		}

		if (progress.interrupted())
			count = -count - 1;

		tcl::PgnReader::setResult(count, illegalRejected, accepted, rejected);
	}
	else if (ext == "pgn" || ext == "gz" || ext == "zip" || ext == "PGN" || ext == "ZIP")
	{
		util::ZStream stream(sys::file::internalName(src), ios_base::in);

		if (!stream)
		{
			appendResult("cannot open file '%s'", src.c_str());
			return TCL_ERROR;
		}

		::db::MultiBase& destination = scidb->multiBase(dst);

		tcl::PgnReader	reader(	stream,
										variant::Undetermined,
										encoding,
										objv[3],
										objv[4],
										tcl::PgnReader::Normalize,
										tcl::PgnReader::File);

		::db::MultiBase::GameCount gameNumbers;
		destination.countGames(gameNumbers);
		reader.setupGameNumbers(gameNumbers);

		count = destination.importGames(reader, progress);
		stream.close();

		if (progress.interrupted())
			count = -count - 1;

		reader.setResult(count, 0);
	}
	else
	{
		appendResult("unsupported extension '%s'", ext.c_str());
		return TCL_ERROR;
	}

	return TCL_OK;
}


static int
cmdOpen(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	static char const* Usage =
		"<file> <log> <log-arg> <progress-cmd> <progress-arg> "
		"?-encoding <string>? ?-description <flag>?";

	if (objc < 6 || (objc % 2) == 1)
	{
		Tcl_WrongNumArgs(ti, 1, objv, Usage);
		return TCL_ERROR;
	}

	mstl::string	encoding		= sys::utf8::Codec::automatic();
	char const*		option		= stringFromObj(objc, objv, objc - 2);
	bool				description	= false;

	while (objc >= 6 && *option == '-')
	{
		if (::strcmp(option, "-encoding") == 0)
		{
			encoding = stringFromObj(objc, objv, objc - 1);
		}
		else if (::strcmp(option, "-description") == 0)
		{
			description = boolFromObj(objc, objv, objc - 1);
		}
		else
		{
			appendResult("unexpected option '%s'", option);
			return TCL_ERROR;
		}

		objc -= 2;
		option = stringFromObj(objc, objv, objc - 2);
	}

	mstl::string	dst(stringFromObj(objc, objv, 1));
	mstl::string	ext(::util::misc::file::suffix(dst));
	Progress			progress(objv[4], objv[5]);

	ext.tolower();

	if (ext != "pgn" && ext != "gz" && ext != "zip" && ext != "PGN" && ext != "ZIP")
	{
		appendResult("unsupported extension '%s'", ext.c_str());
		return TCL_ERROR;
	}

	util::ZStream stream(sys::file::internalName(dst), ios_base::in);

	if (!stream)
	{
		appendResult("cannot open file '%s'", dst.c_str());
		return TCL_ERROR;
	}

	mstl::auto_ptr< ::db::FileOffsets> fileOffsets;

	if (ext == "pgn" || ext == "PGN" || ext == "gz" || ext == "ZIP" || ext == "zip")
		fileOffsets.reset(new ::db::FileOffsets);

	tcl::PgnReader	reader(	stream,
									variant::Undetermined,
									encoding,
									objv[2],
									objv[3],
									tcl::PgnReader::Normalize,
									tcl::PgnReader::File,
									fileOffsets.get());

	int n = scidb->create(dst, type::PGNFile, reader, progress);

	if (description)
	{
		for (unsigned v = 0; v < variant::NumberOfVariants; ++v)
		{
			variant::Type variant = variant::fromIndex(v);

			if (Scidb->contains(dst, variant))
				scidb->cursor(dst, variant).setupDescription(reader.description());
		}
	}

	stream.close();

	if (progress.interrupted())
	{
		scidb->multiCursor(dst).multiBase().setup(0);
		n = -n - 1;
	}
	else
	{
		scidb->multiCursor(dst).multiBase().setup(fileOffsets.release());
	}

	reader.setResult(n, 0);
	return TCL_OK;
}


static int
cmdNew(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 4 && objc != 5)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<file> <variant> <type> ?<encoding>?");
		return TCL_ERROR;
	}

	char const* name = stringFromObj(objc, objv, 1);
	variant::Type variant = tcl::game::variantFromObj(objc, objv, 2);
	int type;

	if (convToType(::CmdSet, objv[3], &type) != TCL_OK)
		return TCL_ERROR;

	mstl::string encoding;

	if (objc == 5)
		encoding = stringFromObj(objc, objv, 4);

	mstl::string suffix(util::misc::file::suffix(name));

	if (suffix == "pgn" || suffix == "gz" || suffix == "zip" || suffix == "PGN" || suffix == "ZIP")
	{
		// currently we do not support charset detection for PGN files
		if (encoding.empty() || encoding == sys::utf8::Codec::automatic())
			encoding = sys::utf8::Codec::latin1();
		if (type == ::db::type::Unspecific)
			type = ::db::type::PGNFile;
	}
	else if (encoding.empty() || encoding == sys::utf8::Codec::automatic())
	{
		encoding = sys::utf8::Codec::utf8();
	}

	if (scidb->create(name, variant, encoding, type::ID(type)) == 0)
		return error(::CmdNew, nullptr, nullptr, "database '%s' already exists", name);

	return TCL_OK;
}


static int
cmdSetCreationVersion(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	// docs/SCI_CORRESPONDENCE_FORMAT.md §3: creation version for newly
	// created SCI databases (96 = native correspondence clock storage,
	// 95 = legacy comment mode). Affects databases created after this call.
	if (objc != 2)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<version>");
		return TCL_ERROR;
	}

	int version = intFromObj(objc, objv, 1);

	if (version < 95 || version > 96)
		return error(::CmdNew, nullptr, nullptr, "unsupported SCI version '%d' (expected 95 or 96)", version);

	::db::sci::Codec::setCreationVersion(unsigned(version));

	return TCL_OK;
}


static int
cmdGetCreationVersion(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 1)
	{
		Tcl_WrongNumArgs(ti, 1, objv, nullptr);
		return TCL_ERROR;
	}

	Tcl_SetObjResult(ti, Tcl_NewIntObj(int(::db::sci::Codec::creationVersion())));

	return TCL_OK;
}


static int
cmdSet(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	static char const* subcommands[] =
	{
		"type", "description", "readonly", "delete", "flag", "variant", 0,
	};
	static char const* args[] =
	{
		"<database> <number>",
		"<database> <string>",
		"?<database>? <bool>",
		"<index> <view> <database> <variant> <value>",
		"<index> <view> ?<database> <flag> <value>",
		"<database> <variant>",
	};
	enum { Cmd_Type, Cmd_Description, Cmd_Readonly, Cmd_Delete, Cmd_Flag, Cmd_Variant };

	if (objc < 2)
		return usage(::CmdSet, nullptr, nullptr, subcommands, args);

	int cmd = tcl::uniqueMatchObj(objv[1], subcommands);

	switch (cmd)
	{
		case Cmd_Delete:
			scidb->deleteGame(
				scidb->cursor(stringFromObj(objc, objv, 4), tcl::game::variantFromObj(objc, objv, 5)),
				intFromObj(objc, objv, 2),
				intFromObj(objc, objv, 3),
				intFromObj(objc, objv, 6));
			break;

		case Cmd_Flag:
		{
			int index	= intFromObj(objc, objv, 2);
			int view		= intFromObj(objc, objv, 3);

			char const*		base		= stringFromObj(objc, objv, 4);
			variant::Type	variant	= tcl::game::variantFromObj(objc, objv, 5);

			Cursor& cursor = scidb->cursor(base, variant);
			mstl::string flags(stringFromObj(objc, objv, 6));

			if (cursor.database().format() == format::Scid4)
				::remapScid4Flags(flags);

			unsigned oldFlags = cursor.database().gameInfo(cursor.index(table::Games, index, view)).flags();
			unsigned newFlags = GameInfo::stringToFlags(flags);
			bool		value		= boolFromObj(objc, objv, 7);

			if (value)
				oldFlags |= newFlags;
			else
				oldFlags &= ~newFlags;

			scidb->setGameFlags(cursor, index, view, oldFlags);
			break;
		}

		case Cmd_Type:
		{
			int type;
			if (convToType(::CmdSet, objv[3], &type) != TCL_OK)
				return TCL_ERROR;
			scidb->cursor(stringFromObj(objc, objv, 2)).databaseObject().setType(type::ID(type));
			break;
		}

		case Cmd_Description:
		{
			Database& db = scidb->cursor(stringFromObj(objc, objv, 2)).databaseObject();
			char const* descr = stringFromObj(objc, objv, 3);

			if (strlen(descr) <= db.maxDescriptionLength())
			{
				db.updateDescription(descr);
				setResult(unsigned(0));
			}
			else
			{
				setResult(db.maxDescriptionLength());
			}
			break;
		}

		case Cmd_Readonly:
			if (objc == 4)
			{
				setResult(scidb->setReadonly(	scidb->multiCursor(stringFromObj(objc, objv, 2)),
														boolFromObj(objc, objv, 3)));
			}
			else
			{
				setResult(scidb->setReadonly(scidb->multiCursor(), boolFromObj(objc, objv, 2)));
			}
			break;

		case Cmd_Variant:
		{
			char const*		base		= stringFromObj(objc, objv, 2);
			variant::Type	variant	= tcl::game::variantFromObj(objc, objv, 3);

			scidb->changeVariant(base, variant);
			break;
		}

		default:
			return usage(::CmdSet, nullptr, nullptr, subcommands, args);
	}

	return TCL_OK;
}


static int
countGames(char const* database)
{
	mstl::string base;
	if (database)
		base.assign(database);
	else
		base.assign(Scidb->cursor().name());
	::tcl::setResult(Scidb->countGames(base));
	return TCL_OK;
}


static int
count(table::Type type, char const* database, variant::Type variant)
{
	M_ASSERT(Scidb->contains(database, variant));
	Cursor const& cursor = database ? Scidb->cursor(database, variant) : Scidb->cursor();
	::tcl::setResult(cursor.count(type));
	return TCL_OK;
}


static int
cmdCount(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	static char const* subcommands[] =
	{
		"games", "players", "annotators", "positions", "events", "sites", "total", 0
	};
	static char const* args[] =
	{
		"?\?<database>? <variant>?",
		"?\?<database>? <variant>?",
		"?\?<database>? <variant>?",
		"?\?<database>? <variant>?",
		"?\?<database>? <variant>?",
		"?\?<database>? <variant>?",
		"?<database>?",
	};
	enum { Cmd_Games, Cmd_Players, Cmd_Annotators, Cmd_Positions, Cmd_Events, Cmd_Sites, Cmd_Total };

	if (objc < 2 || objc > 4)
		return usage(::CmdCount, nullptr, nullptr, subcommands, args);

	char const*		base		= 0;
	variant::Type	variant	= variant::Undetermined;

	int index = tcl::uniqueMatchObj(objv[1], subcommands);

	if (index == Cmd_Total)
	{
		if (objc > 2)
			base = Tcl_GetString(objv[2]);
	}
	else
	{
		if (objc < 3)
		{
			variant = Scidb->currentVariant();
		}
		else if (objc == 3)
		{
			variant = tcl::game::variantFromObj(objc, objv, 2);
		}
		else
		{
			base = Tcl_GetString(objv[2]);
			variant = tcl::game::variantFromObj(objc, objv, 3);
		}
	}

	switch (index)
	{
		case Cmd_Players:		return count(table::Players, base, variant);
		case Cmd_Annotators:	return count(table::Annotators, base, variant);
		case Cmd_Positions:	return count(table::Positions, base, variant);
		case Cmd_Games:		return count(table::Games, base, variant);
		case Cmd_Events:		return count(table::Events, base, variant);
		case Cmd_Sites:		return count(table::Sites, base, variant);
		case Cmd_Total:		return countGames(base);
	}

	return usage(::CmdCount, nullptr, nullptr, subcommands, args);
}


static int
getClipbaseAttr(Tcl_Interp*, char const* attr)
{
	if (strcmp(attr, "name") == 0)
		setResult(Scidb->clipbaseName());
	else if (strcmp(attr, "type") == 0)
		setResult(lookupType(type::Clipbase));
	else
		return error(::CmdGet, "clipbase", nullptr, "invalid subcommand '%s'", attr);

	return TCL_OK;
}


static int
getScratchbaseAttr(Tcl_Interp*, char const* attr)
{
	if (strcmp(attr, "name") == 0)
		setResult(Scidb->scratchbaseName());
	else
		return error(::CmdGet, "scratchbase", nullptr, "invalid subcommand '%s'", attr);

	return TCL_OK;
}


static int
getTypes(Tcl_Interp* ti, char const* suffix)
{
	Tcl_Obj* list = Tcl_NewListObj(0, 0);

	if (::strcmp(suffix, "sci") == 0)
	{
		for (int i = 0; i <= type::LAST; ++i)
			Tcl_ListObjAppendElement(ti, list, Tcl_NewStringObj(lookupType(type::ID(i)), -1));
	}
	else	// si3, si4
	{
		for (int i = 0; i <= type::LAST; ++i)
		{
			type::ID type = type::ID(i);

			if (si3::Decoder::decodeType(si3::Encoder::encodeType(type)) == type)
				Tcl_ListObjAppendElement(ti, list, Tcl_NewStringObj(lookupType(type), -1));
		}
	}

	setResult(list);
	return TCL_OK;
}


static int
getName()
{
	::tcl::setResult(Scidb->cursor().name());
	return TCL_OK;
}


static int
getCodec()
{
	::tcl::setResult(Scidb->cursor().database().extension());
	return TCL_OK;
}


static int
getCodec(char const* database, variant::Type variant)
{
	M_ASSERT(database);

	if (variant != variant::Undetermined)
		variant = variant::toMainVariant(variant);

	M_ASSERT(Scidb->contains(database, variant));
	::tcl::setResult(Scidb->cursor(database, variant).database().extension());
	return TCL_OK;
}


static int
getEncoding(char const* database, variant::Type variant)
{
	M_ASSERT(database == 0 || Scidb->contains(database, variant));
	Cursor const& cursor = database ? Scidb->cursor(database, variant) : Scidb->cursor();
	::tcl::setResult(cursor.database().encoding());
	return TCL_OK;
}


static int
getUsedEncoding(char const* database, variant::Type variant)
{
	M_ASSERT(database == 0 || Scidb->contains(database, variant));
	Cursor const& cursor = database ? Scidb->cursor(database, variant) : Scidb->cursor();
	::tcl::setResult(cursor.database().usedEncoding());
	return TCL_OK;
}


static int
getCreated(char const* database = 0)
{
	M_ASSERT(database == 0 || Scidb->contains(database));
	::tcl::setResult(Scidb->cursor(database).database().created().asString());
	return TCL_OK;
}


static int
getModified(char const* database = 0)
{
	M_ASSERT(database == 0 || Scidb->contains(database));
	::tcl::setResult(Scidb->cursor(database).database().modified().asString());
	return TCL_OK;
}


static int
getReadonly(char const* database, variant::Type variant __attribute__((unused)))
{
	M_ASSERT(database == 0 || Scidb->contains(database, variant));
	MultiCursor const& cursor = database ? Scidb->multiCursor(database) : Scidb->multiCursor();
	::tcl::setResult(cursor.isReadonly());
	return TCL_OK;
}


static int
getWritable(char const* database = 0)
{
	M_ASSERT(database == 0 || Scidb->contains(database));
	::tcl::setResult(Scidb->isWritable(database));
	return TCL_OK;
}


static int
getDescription(char const* database = 0)
{
	M_ASSERT(database == 0 || Scidb->contains(database));
	::tcl::setResult(Scidb->cursor(database).database().description());
	return TCL_OK;
}


static int
getVariant(char const* database = 0)
{
	M_ASSERT(database == 0 || Scidb->contains(database));
	::tcl::setResult(tcl::tree::variantToString(Scidb->cursor(database).database().variant()));
	return TCL_OK;
}


static int
getVariant(char const* database, unsigned number)
{
	M_ASSERT(database == 0 || Scidb->contains(database));
	::tcl::setResult(tcl::tree::variantToString(Scidb->cursor(database).database().variant(number)));
	return TCL_OK;
}


static int
getVariants(char const* database)
{
	M_ASSERT(database);

	Application::Variants variants = Scidb->getAllVariants(database);

	Tcl_Obj* objs[::db::variant::NumberOfVariants];
	int objc = 0;

	for (	unsigned i = variants.find_first();
			i != Application::Variants::npos;
			i = variants.find_next(i))
	{
		M_ASSERT(objc < variant::NumberOfVariants);
		objs[objc++] = tcl::tree::variantToString(::db::variant::fromIndex(i));
	}

	setResult(objc, objs);
	return TCL_OK;
}


static int
isUnsaved(char const* database)
{
	M_ASSERT(database);
	setResult(Scidb->multiBase(database).isUnsaved());
	return TCL_OK;
}


static int
getChanges(char const* database)
{
	M_ASSERT(database);

	MultiBase const& base = Scidb->multiBase(database);
	Tcl_Obj* result[4];
	result[0] = Tcl_NewIntObj(base.countGames(MultiBase::Added));
	result[1] = Tcl_NewIntObj(base.countGames(MultiBase::Changed));
	result[2] = Tcl_NewIntObj(base.countGames(MultiBase::Deleted));
	result[3] = Tcl_NewBooleanObj(base.descriptionHasChanged());
	setResult(U_NUMBER_OF(result), result);
	return TCL_OK;
}


static int
getType(char const* database = 0)
{
	M_ASSERT(database == 0 || Scidb->contains(database));
	::tcl::setResult(lookupType(Scidb->cursor(database).type()));
	return TCL_OK;
}


static int
getGameIndex(int number, int view, char const* database, variant::Type variant)
{
	M_ASSERT(database == 0 || Scidb->contains(database, variant));

	Cursor const& cursor = database ? Scidb->cursor(database, variant) : Scidb->cursor();
	View const& v = cursor.view(view);

	if (number < int(v.total(table::Games)))
		::tcl::setResult(v.lookupGameIndex(number));
	else
		::tcl::setResult(-1);

	return TCL_OK;
}


static int
getIndex(table::Type type, unsigned index, int view, char const* database, variant::Type variant)
{
	M_ASSERT(database == 0 || Scidb->contains(database, variant));

	if (database)
		::tcl::setResult(Scidb->cursor(database, variant).view(view).index(type, index));
	else
		::tcl::setResult(Scidb->cursor().view(view).index(type, index));

	return TCL_OK;
}


static int
getLookupPlayer(unsigned index, int view, char const* database, variant::Type variant)
{
	M_ASSERT(database);
	M_ASSERT(Scidb->contains(database, variant));
	::tcl::setResult(Scidb->cursor(database, variant).view(view).lookupPlayerIndex(index));
	return TCL_OK;
}


static int
getLookupEvent(unsigned index, int view, char const* database, variant::Type variant)
{
	M_ASSERT(database);
	M_ASSERT(Scidb->contains(database, variant));
	::tcl::setResult(Scidb->cursor(database, variant).view(view).lookupEventIndex(index));
	return TCL_OK;
}


static int
getLookupSite(unsigned index, int view, char const* database, variant::Type variant)
{
	M_ASSERT(database);
	M_ASSERT(Scidb->contains(database, variant));
	::tcl::setResult(Scidb->cursor(database, variant).view(view).lookupSiteIndex(index));
	return TCL_OK;
}


static int
getLookupPosition(unsigned index, int view, char const* database, variant::Type variant)
{
	M_ASSERT(database);
	M_ASSERT(Scidb->contains(database, variant));
	::tcl::setResult(Scidb->cursor(database, variant).view(view).lookupPositionIndex(index));
	return TCL_OK;
}


static int
getAnnotatorIndex(char const* name, int view, char const* database, variant::Type variant)
{
	M_ASSERT(database);
	M_ASSERT(Scidb->contains(database, variant));
	::tcl::setResult(Scidb->cursor(database, variant).view(view).lookupAnnotator(name));
	return TCL_OK;
}


static int
getStats(char const* database)
{
	Statistic const& statistic = Scidb->cursor(database).database().statistic();
	Tcl_Obj*	objv[14];

	objv[ 0] = Tcl_NewIntObj(statistic.counter.deleted);
	objv[ 1] = Tcl_NewIntObj(statistic.counter.changed);
	objv[ 2] = Tcl_NewIntObj(statistic.counter.added);
	objv[ 3] = Tcl_NewIntObj(statistic.content.minYear);
	objv[ 4] = Tcl_NewIntObj(statistic.content.maxYear);
	objv[ 5] = Tcl_NewIntObj(statistic.content.avgYear);
	objv[ 6] = Tcl_NewIntObj(statistic.content.minElo);
	objv[ 7] = Tcl_NewIntObj(statistic.content.maxElo);
	objv[ 8] = Tcl_NewIntObj(statistic.content.avgElo);
	objv[ 9] = Tcl_NewIntObj(statistic.content.result[0]);
	objv[10] = Tcl_NewIntObj(statistic.content.result[1]);
	objv[11] = Tcl_NewIntObj(statistic.content.result[2]);
	objv[12] = Tcl_NewIntObj(statistic.content.result[3]);
	objv[13] = Tcl_NewIntObj(statistic.content.result[4]);

	setResult(U_NUMBER_OF(objv), objv);

	return TCL_OK;
}


static int
findRating(GameInfo const& info, color::ID color, rating::Type type)
{
	int value = info.findRating(color, type);

	if (!info.isGameRating(color, type))
		value = -value;

	return value;
}


static int
getPlayerKey(NamebasePlayer const& player)
{
	Tcl_Obj* objv[PlayerKey_LAST];

	objv[PlayerKey_Name]		= Tcl_NewStringObj(player.name(), player.name().size());
	objv[PlayerKey_FideID]	= player.haveFideId() ? Tcl_NewIntObj(player.fideID()) : Tcl_NewListObj(0, 0);
	objv[PlayerKey_Sex]		= Tcl_NewStringObj(sex::toString(player.sex()), -1);
	objv[PlayerKey_Country]	= Tcl_NewStringObj(country::toString(player.federation()), -1);
	objv[PlayerKey_Title]	= Tcl_NewStringObj(title::toString(player.title()), -1);
	objv[PlayerKey_Type]		= Tcl_NewStringObj(species::toString(player.type()), -1);

	setResult(U_NUMBER_OF(objv), objv);
	return TCL_OK;
}


static int
getPlayerStats(char const* database, variant::Type variant, unsigned index)
{
	M_ASSERT(database);
	M_ASSERT(Scidb->contains(database, variant));

	Database const& base = Scidb->cursor(database, variant).database();
	return tcl::db::getPlayerStats(base, base.player(index));
}


static int
getEventKey(NamebaseEvent const& event)
{
	Tcl_Obj* objv[EventKey_LAST];

	objv[EventKey_Name]			= Tcl_NewStringObj(event.name(), event.name().size());
	objv[EventKey_Type]			= Tcl_NewStringObj(event::toString(event.type()), -1);
	objv[EventKey_Date]			= Tcl_NewStringObj(event.date().asString(), -1);
	objv[EventKey_TimeMode]		= Tcl_NewStringObj(::db::time::toString(event.timeMode()), -1);
	objv[EventKey_EventMode]	= Tcl_NewStringObj(event::toString(event.eventMode()), -1);
	objv[EventKey_Site]			= Tcl_NewStringObj(event.site()->name(), event.site()->name().size());
	objv[EventKey_SiteCountry]	= Tcl_NewStringObj(country::toString(event.site()->country()), -1);

	setResult(U_NUMBER_OF(objv), objv);
	return TCL_OK;
}


static int
getSiteKey(NamebaseSite const& site)
{
	Tcl_Obj* objv[SiteKey_LAST];

	objv[SiteKey_Site]		= Tcl_NewStringObj(site.name(), site.name().size());
	objv[SiteKey_Country]	= Tcl_NewStringObj(country::toString(site.country()), -1);

	setResult(U_NUMBER_OF(objv), objv);
	return TCL_OK;
}


static int
getGameInfo(int index, int view, char const* database, variant::Type variant, unsigned which)
{
	Cursor const& cursor = Scidb->cursor(database, variant);

	if (view >= 0)
		index = cursor.index(table::Games, index, view);

	GameInfo const& info = cursor.database().gameInfo(index);
	Tcl_Obj* obj;

	switch (which)
	{
		case attribute::game::WhiteCountry:
			obj = Tcl_NewStringObj(country::toString(info.findFederation(color::White)), -1);
			break;

		case attribute::game::WhiteTitle:
			obj = Tcl_NewStringObj(title::toString(info.findTitle(color::White)), -1);
			break;

		case attribute::game::WhiteSex:
			obj = Tcl_NewStringObj(sex::toString(info.findSex(color::White)), 1);
			break;

		case attribute::game::WhiteType:
			obj = Tcl_NewStringObj(species::toString(info.findPlayerType(color::White)), -1);
			break;

		case attribute::game::BlackCountry:
			obj = Tcl_NewStringObj(country::toString(info.findFederation(color::Black)), -1);
			break;

		case attribute::game::BlackTitle:
			obj = Tcl_NewStringObj(title::toString(info.findTitle(color::Black)), -1);
			break;

		case attribute::game::BlackSex:
			obj = Tcl_NewStringObj(sex::toString(info.findSex(color::Black)), 1);
			break;

		case attribute::game::BlackType:
			obj = Tcl_NewStringObj(species::toString(info.findPlayerType(color::Black)), -1);
			break;

		case attribute::game::WhiteRatingType:
			obj = Tcl_NewStringObj(rating::toString(info.findRatingType(color::White)), -1);
			break;

		case attribute::game::BlackRatingType:
			obj = Tcl_NewStringObj(rating::toString(info.findRatingType(color::Black)), -1);
			break;

		case attribute::game::Idn:
			{
				mstl::string position;

				if (variant::isShuffleChess(info.idn()))
					shuffle::utf8::position(info.idn(), position);
				else if (info.idn())
					position = variant::ficsIdentifier(info.idn());

				obj = Tcl_NewStringObj(position, position.size());
			}
			break;

		case attribute::game::Eco:
		case attribute::game::Opening:
		case attribute::game::InternalEco:
			{
				mstl::string openingLong, openingShort, variation, subvar, position;
				Eco eco;

				if (which == attribute::game::Eco || which == attribute::game::Opening)
					eco = info.userEco(variant);
				else if (info.idn() == variant::Standard)
					eco = info.ecoKey();

				EcoTable const& ecoTable = EcoTable::specimen(variant);
				EcoTable::Opening const* opening = &ecoTable.getOpening(Eco());

				if (eco)
				{
					if (info.eco(variant).basic() == info.ecoKey().basic())
						opening = &ecoTable.getOpening(info.ecoKey());
					else
						opening = &ecoTable.getOpening(eco);
				}

				if (variant::isShuffleChess(info.idn()))
					shuffle::utf8::position(info.idn(), position);
				else if (info.idn())
					position = variant::ficsIdentifier(info.idn());

				Tcl_Obj* objv[3 + EcoTable::Num_Name_Parts];

				objv[0] = Tcl_NewIntObj(info.idn());
				objv[1] = Tcl_NewStringObj(position, position.size());
				objv[2] = Tcl_NewStringObj(eco.asShortString(), -1);

				for (unsigned i = 0; i < EcoTable::Num_Name_Parts; ++i)
					objv[i + 3] = Tcl_NewStringObj(opening->part[i], opening->part[i].size());

				obj = Tcl_NewListObj(U_NUMBER_OF(objv), objv);
			}
			break;

		case attribute::game::Acv:
			{
				char acv[100];

				int acvSize = snprintf(acv, sizeof(acv),
									
												"%u %u %u",
												info.countAnnotations(),
												info.countComments(),
												info.countVariations());
				obj = Tcl_NewStringObj(acv, acvSize);
			}
			break;

		case attribute::game::Flags:
			{
				mstl::string flags;

				flagsToString(info.flags(), flags);
				if (cursor.database().format() == format::Scid4)
					::mapScid4Flags(flags);
				obj = Tcl_NewStringObj(flags, flags.size());
			}
			break;

		case attribute::game::Mode:
			obj = Tcl_NewStringObj(event::toString(info.eventMode()), -1);
			break;

		case attribute::game::Termination:
			obj = Tcl_NewStringObj(termination::toString(info.terminationReason()), -1);
			break;

		case attribute::game::TimeMode:
			obj = Tcl_NewStringObj(::db::time::toString(info.timeMode()), -1);
			break;

		case attribute::game::EventCountry:
			obj = Tcl_NewStringObj(country::toString(info.findEventCountry()), -1);
			break;

		case attribute::game::EventType:
			obj = Tcl_NewStringObj(event::toString(info.eventType()), -1);
			break;

		case attribute::game::Deleted:
			obj = Tcl_NewBooleanObj(info.isDeleted());
			break;

		case attribute::game::Changed:
			obj = Tcl_NewBooleanObj(info.isChanged());
			break;

		case attribute::game::Added:
			obj = Tcl_NewBooleanObj(cursor.database().isAdded(index));
			break;

		case attribute::game::HasAudio:
			obj = Tcl_NewBooleanObj(info.hasAudio());
			break;

		case attribute::game::HasPicture:
			obj = Tcl_NewBooleanObj(info.hasPicture());
			break;

		case attribute::game::HasVideo:
			obj = Tcl_NewBooleanObj(info.hasVideo());
			break;

		case attribute::game::HasMedia:
			obj = Tcl_NewBooleanObj(info.hasMedia());
			break;

		default:
			return error(::CmdGet, "gameInfo", nullptr, "cannot access number %u", which);
	}

	setResult(obj);
	return TCL_OK;
}


// TODO: notation is unused
int
tcl::db::getGameInfo(Database const& db, unsigned index, Ratings const& ratings, move::Notation notation)
{
	GameInfo const& info = db.gameInfo(index);

	char		acv[100];
	Tcl_Obj*	objv[attribute::game::LastColumn];

	M_ASSERT(::memset(objv, 0, sizeof(objv)));

	int acvSize = snprintf(acv, sizeof(acv),
									"%u %u %u",
									info.countAnnotations(),
									info.countComments(),
									info.countVariations());

	mstl::string startPosition, round;

	if (variant::isShuffleChess(info.idn()))
		shuffle::utf8::position(info.idn(), startPosition);
	else if (info.idn())
		startPosition = variant::ficsIdentifier(info.idn());

	EcoTable const& ecoTable = EcoTable::specimen(db.variant());

	Eco eco = info.eco(db.variant());
	Eco eop = info.idn() == variant::Standard ? info.ecoKey() : Eco();

	if (db.format() == format::Scidb)
	{
		if (!eco)
			eco = eop;

		round.assign(info.roundAsString());
	}
	else
	{
		TagSet tags;
		db.getInfoTags(index, tags);
		round.assign(tags.value(tag::Round));
	}

	EcoTable::Opening const* opening = &ecoTable.getOpening(Eco());

	if (info.idn() == variant::Standard && eco)
	{
		if (info.eco(db.variant()).basic() == info.ecoKey().basic())
			opening = &ecoTable.getOpening(info.ecoKey());
		else
			opening = &ecoTable.getOpening(eco);
	}

	mstl::string flags;
	flagsToString(info.flags(), flags);

	if (db.format() == format::Scid4)
		::mapScid4Flags(flags);

	Tcl_Obj* openingVar[4] =
	{
		Tcl_NewStringObj(opening->part[0], opening->part[0].size()),
		Tcl_NewStringObj(opening->part[1], opening->part[1].size()),
		Tcl_NewStringObj(opening->part[2], opening->part[2].size()),
		Tcl_NewStringObj(opening->part[3], opening->part[3].size())
	};

	mstl::string material;
	material::si3::utf8::print(info.material(), material);

	mstl::string const& whitePlayer = info.playerName(color::White);
	mstl::string const& blackPlayer = info.playerName(color::Black);

	mstl::string const& whiteRatingType = rating::toString(info.findRatingType(color::White));
	mstl::string const& blackRatingType = rating::toString(info.findRatingType(color::Black));

	int32_t whiteFideID = info.findFideID(color::White);
	int32_t blackFideID = info.findFideID(color::Black);

	uint16_t idn = variant::isShuffleChess(info.idn()) ? info.idn() : 0;

#define SET(attr, value) objv[::attribute::game::attr] = value

	SET(Number,               Tcl_NewIntObj(index + 1));
	SET(WhitePlayer,          Tcl_NewStringObj(whitePlayer, whitePlayer.size()));
	SET(WhiteFideID,          whiteFideID ? Tcl_NewIntObj(whiteFideID) : Tcl_NewListObj(0, 0));
	SET(WhiteRating1,         Tcl_NewIntObj(::findRating(info, color::White, ratings.first)));
	SET(WhiteRating2,         Tcl_NewIntObj(::findRating(info, color::White, ratings.second)));
	SET(WhiteRatingType,      Tcl_NewStringObj(whiteRatingType, whiteRatingType.size()));
	SET(WhiteCountry,         Tcl_NewStringObj(country::toString(info.findFederation(color::White)), -1));
	SET(WhiteTitle,           Tcl_NewStringObj(title::toString(info.findTitle(color::White)), -1));
	SET(WhiteType,            Tcl_NewStringObj(species::toString(info.findPlayerType(color::White)), -1));
	SET(WhiteSex,             Tcl_NewStringObj(sex::toString(info.findSex(color::White)), -1));
	SET(BlackPlayer,          Tcl_NewStringObj(blackPlayer, blackPlayer.size()));
	SET(BlackFideID,          blackFideID ? Tcl_NewIntObj(blackFideID) : Tcl_NewListObj(0, 0));
	SET(BlackRating1,         Tcl_NewIntObj(::findRating(info, color::Black, ratings.first)));
	SET(BlackRating2,         Tcl_NewIntObj(::findRating(info, color::Black, ratings.second)));
	SET(BlackRatingType,      Tcl_NewStringObj(blackRatingType, blackRatingType.size()));
	SET(BlackCountry,         Tcl_NewStringObj(country::toString(info.findFederation(color::Black)), -1));
	SET(BlackTitle,           Tcl_NewStringObj(title::toString(info.findTitle(color::Black)), -1));
	SET(BlackType,            Tcl_NewStringObj(species::toString(info.findPlayerType(color::Black)), -1));
	SET(BlackSex,             Tcl_NewStringObj(sex::toString(info.findSex(color::Black)), -1));
	SET(Event,                Tcl_NewStringObj(info.event(), info.event().size()));
	SET(EventType,            Tcl_NewStringObj(event::toString(info.eventType()), -1));
	SET(EventDate,            Tcl_NewStringObj(info.eventDate().asShortString(), -1));
	SET(Result,               Tcl_NewStringObj(result::toString(info.result()), -1));
	SET(Site,                 Tcl_NewStringObj(info.site(), info.site().size()));
	SET(EventCountry,         Tcl_NewStringObj(country::toString(info.findEventCountry()), -1));
	SET(Date,                 Tcl_NewStringObj(info.date().asShortString(), -1));
	SET(Round,                Tcl_NewStringObj(round, round.size()));
	SET(Annotator,            Tcl_NewStringObj(info.annotator(), info.annotator().size()));
	SET(Idn,                  Tcl_NewIntObj(idn));
	SET(Position,             Tcl_NewStringObj(startPosition, -1));
	SET(MoveList,             Tcl_NewStringObj(mstl::string::empty_string, 0)),
	SET(Length,               Tcl_NewIntObj(mstl::div2(info.plyCount() + 1)));
	SET(Eco,                  Tcl_NewStringObj(eco.asShortString(), -1));
	SET(Flags,                Tcl_NewStringObj(flags, flags.size()));
	SET(Material,             Tcl_NewStringObj(material, material.size()));
	SET(Deleted,              Tcl_NewBooleanObj(info.isDeleted()));
	SET(Changed,              Tcl_NewIntObj(info.isChanged()));
	SET(Added,                Tcl_NewIntObj(db.isAdded(index)));
	SET(Acv,                  Tcl_NewStringObj(acv, acvSize));
	SET(CommentEngFlag,       Tcl_NewBooleanObj(info.containsEnglishLanguage()));
	SET(CommentOthFlag,       Tcl_NewBooleanObj(info.containsOtherLanguage()));
	SET(Promotion,            Tcl_NewBooleanObj(info.hasPromotion()));
	SET(UnderPromotion,       Tcl_NewBooleanObj(info.hasUnderPromotion()));
	SET(StandardPosition,     Tcl_NewBooleanObj(variant::isStandardChess(info.idn(), db.variant())));
	SET(Chess960Position,     Tcl_NewBooleanObj(variant::isChess960(info.idn())));
	SET(Termination,          Tcl_NewStringObj(termination::toString(info.terminationReason()), -1));
	SET(Mode,                 Tcl_NewStringObj(event::toString(info.eventMode()), -1));
	SET(TimeMode,             Tcl_NewStringObj(::db::time::toString(info.timeMode()), -1));
	SET(Opening,              Tcl_NewListObj(U_NUMBER_OF(openingVar), openingVar));
	SET(Variation,            Tcl_NewStringObj(opening->part[2], opening->part[2].size()));
	SET(SubVariation,         Tcl_NewStringObj(opening->part[3], opening->part[3].size()));
	SET(InternalEco,          Tcl_NewStringObj(eop.asString(), -1));
	SET(HasAudio,             Tcl_NewBooleanObj(info.hasAudio()));
	SET(HasPicture,           Tcl_NewBooleanObj(info.hasPicture()));
	SET(HasVideo,             Tcl_NewBooleanObj(info.hasVideo()));
	SET(HasMedia,             Tcl_NewBooleanObj(info.hasMedia()));

#undef SET

	M_ASSERT(::checkNonZero(objv, U_NUMBER_OF(objv)));

	setResult(U_NUMBER_OF(objv), objv);
	return TCL_OK;
}


static int
getGameInfo(int index, int view, char const* database, variant::Type variant, move::Notation notation)
{
	Cursor const& cursor = Scidb->cursor(database, variant);

	if (view >= 0)
		index = cursor.index(table::Games, index, view);

	return getGameInfo(cursor.database(), index, Ratings(rating::Elo, rating::DWZ), notation);
}


static int
getGameInfo(int index,
				int view,
				char const* database,
				variant::Type variant,
				Ratings const& ratings,
				move::Notation notation)
{
	Cursor const& cursor = Scidb->cursor(database, variant);

	if (view >= 0)
		index = cursor.index(table::Games, index, view);

	return getGameInfo(cursor.database(), index, ratings, notation);
}


static int
getPlayerInfo(int index, int view, char const* database, variant::Type variant, unsigned which)
{
	M_ASSERT(database);

	Cursor const& cursor = Scidb->cursor(database, variant);

	if (view >= 0)
		index = cursor.index(table::Players, index, view);

	NamebasePlayer const& player = cursor.database().player(index);
	Tcl_Obj* obj;

	switch (which)
	{
		case attribute::player::Country:
			obj = Tcl_NewStringObj(country::toString(player.findFederation()), -1);
			break;

		case attribute::player::Title:
			obj = Tcl_NewStringObj(title::toString(player.findTitle()), -1);
			break;

		case attribute::player::Type:
			obj = Tcl_NewStringObj(species::toString(player.findType()), -1);
			break;

		case attribute::player::Sex:
			obj = Tcl_NewStringObj(sex::toString(player.findSex()), -1);
			break;

		default:
			return error(::CmdGet, "playerInfo", nullptr, "cannot access number %u", which);
	}

	setResult(obj);
	return TCL_OK;
}


static int
getPlayerInfo(	int index,
					int view,
					char const* database,
					variant::Type variant,
					Ratings& ratings,
					organization::ID federation,
					bool info,
					bool idCard,
					bool usePlayerBase)
{
	M_ASSERT(database);

	Cursor const& cursor = Scidb->cursor(database, variant);

	if (view >= 0)
		index = cursor.index(table::Players, index, view);

	NamebasePlayer const& player = cursor.database().player(index);
	return tcl::player::getInfo(player, ratings, federation, info, idCard, usePlayerBase);
}


static int
getEventInfo(int index, int view, char const* database, variant::Type variant, unsigned which)
{
	M_ASSERT(database);

	Cursor const& cursor = Scidb->cursor(database, variant);

	if (view >= 0)
		index = cursor.index(table::Events, index, view);

	NamebaseEvent const& event = cursor.database().event(index);
	Tcl_Obj* obj;

	switch (which)
	{
		case attribute::event::Country:
			obj = Tcl_NewStringObj(country::toString(event.site()->country()), -1);
			break;

		case attribute::event::Type:
			obj = Tcl_NewStringObj(event::toString(event.type()), -1);
			break;

		case attribute::event::Mode:
			obj = Tcl_NewStringObj(event::toString(event.eventMode()), -1);
			break;

		case attribute::event::TimeMode:
			obj = Tcl_NewStringObj(::db::time::toString(event.timeMode()), -1);
			break;

		default:
			return error(::CmdGet, "eventInfo", nullptr, "cannot access number %u", which);
	}

	setResult(obj);
	return TCL_OK;
}


static int
getSiteInfo(int index, int view, char const* database, variant::Type variant, unsigned which)
{
	M_ASSERT(database);

	Cursor const& cursor = Scidb->cursor(database, variant);

	if (view >= 0)
		index = cursor.index(table::Sites, index, view);

	NamebaseSite const& site = cursor.database().site(index);
	Tcl_Obj* obj;

	switch (which)
	{
		case attribute::site::Site:
			obj = Tcl_NewStringObj(site.name(), -1);
			break;

		case attribute::site::Country:
			obj = Tcl_NewStringObj(country::toString(site.country()), -1);
			break;

		default:
			return error(::CmdGet, "eventInfo", nullptr, "cannot access number %u", which);
	}

	setResult(obj);
	return TCL_OK;
}


static int
getEventInfo(NamebaseEvent const& event, Database const* database = nullptr)
{
	Tcl_Obj* objv[attribute::event::LastColumn + (database ? 3 : 0)];

	mstl::string const& country = country::toString(event.site()->country());
	mstl::string siteName;

#if 0
	if (database)
	{
		if (Site const* site = Site::findSite(event.site()->name()))
			siteName = site->name();
	}

	if (siteName.empty())
#endif
	siteName = event.site()->name();

	objv[attribute::event::Country  ] = Tcl_NewStringObj(country, country.size());
	objv[attribute::event::Site     ] = Tcl_NewStringObj(siteName, siteName.size());
	objv[attribute::event::Title    ] = Tcl_NewStringObj(event.name(), -1);
	objv[attribute::event::Type     ] = Tcl_NewStringObj(event::toString(event.type()), -1);
	objv[attribute::event::Date     ] = Tcl_NewStringObj(event.date().asShortString(), -1);
	objv[attribute::event::Mode     ] = Tcl_NewStringObj(event::toString(event.eventMode()), -1);
	objv[attribute::event::TimeMode ] = Tcl_NewStringObj(::db::time::toString(event.timeMode()), -1);
	objv[attribute::event::Frequency] = Tcl_NewIntObj(event.frequency());

	if (database)
	{
		unsigned averageElo;
		unsigned category;
		unsigned attendants = database->countPlayers(event, averageElo, category);

		objv[attribute::event::Frequency + 1] = Tcl_NewIntObj(attendants);
		objv[attribute::event::Frequency + 2] = Tcl_NewIntObj(averageElo);
		objv[attribute::event::Frequency + 3] = Tcl_NewIntObj(category);
	}

	M_ASSERT(::checkNonZero(objv, attribute::event::LastColumn + (database ? 3 : 0)));

	setResult(U_NUMBER_OF(objv), objv);
	return TCL_OK;
}


static int
getEventInfo(int index, int view, char const* database, variant::Type variant, bool idCard)
{
	M_ASSERT(variant);

	Cursor const& cursor = Scidb->cursor(database, variant);

	if (view >= 0)
		index = cursor.index(table::Events, index, view);

	return getEventInfo(cursor.database().event(index), idCard ? &cursor.database() : nullptr);
}


static int
getSiteInfo(int index, int view, char const* database, variant::Type variant)
{
	M_ASSERT(database);

	Cursor const& cursor = Scidb->cursor(database, variant);

	if (view >= 0)
		index = cursor.index(table::Sites, index, view);

	NamebaseSite const& site = cursor.database().site(index);

	Tcl_Obj* objv[attribute::site::LastColumn];

	mstl::string const& country	= country::toString(site.country());
	mstl::string const& siteName	= site.name();

	objv[attribute::site::Site     ] = Tcl_NewStringObj(siteName, siteName.size());
	objv[attribute::site::Country  ] = Tcl_NewStringObj(country, country.size());
	objv[attribute::site::Frequency] = Tcl_NewIntObj(site.frequency());

	M_ASSERT(::checkNonZero(objv, attribute::site::LastColumn));

	setResult(U_NUMBER_OF(objv), objv);
	return TCL_OK;
}


static int
getAnnotator(int index, int view, char const* database = nullptr, variant::Type variant = variant::Normal)
{
	Tcl_Obj* objv[::attribute::annotator::LastColumn];

	M_ASSERT(::memset(objv, 0, sizeof(objv)));

	Cursor const& cursor = database ? Scidb->cursor(database, variant) : Scidb->cursor();

	if (view >= 0)
		index = cursor.index(table::Annotators, index, view);

	NamebaseEntry const& annotator = cursor.database().annotator(index);

	objv[::attribute::annotator::Name] = Tcl_NewStringObj(annotator.name(), annotator.name().size());
	objv[::attribute::annotator::Frequency] = Tcl_NewIntObj(annotator.frequency());

	M_ASSERT(::checkNonZero(objv, U_NUMBER_OF(objv)));

	setResult(U_NUMBER_OF(objv), objv);
	return TCL_OK;
}


static int
getPosition(unsigned index, int view, char const* database = nullptr, variant::Type variant = variant::Normal)
{
	Tcl_Obj* objv[::attribute::position::LastColumn];

	M_ASSERT(memset(objv, 0, sizeof(objv)));

	Cursor const& cursor = database ? Scidb->cursor(database, variant) : Scidb->cursor();

	if (view >= 0)
		index = cursor.index(table::Positions, index, view);

	uint16_t idn	= cursor.database().statistic().idnAt(index);
	unsigned freq	= cursor.database().statistic().positionCount(idn);

	objv[attribute::position::Frequency] = Tcl_NewIntObj(freq);

	if (variant::isShuffleChess(idn))
	{
		mstl::string buf;

		objv[attribute::position::Idn] = Tcl_NewIntObj(idn);
		objv[attribute::position::BackRank] = Tcl_NewStringObj(shuffle::utf8::position(idn, buf), -1);
	}
	else if (idn == 0)
	{
		objv[attribute::position::Idn] = Tcl_NewIntObj(0);
		objv[attribute::position::BackRank] = Tcl_NewStringObj(0, 0);
	}
	else
	{
		objv[attribute::position::Idn] = Tcl_NewStringObj(variant::fics::identifier(idn), -1);
		objv[attribute::position::BackRank] = Tcl_NewStringObj(0, 0);
	}

	M_ASSERT(checkNonZero(objv, U_NUMBER_OF(objv)));

	setResult(U_NUMBER_OF(objv), objv);
	return TCL_OK;
}


static int
getEncodingState(char const* database)
{
	Database const& base = Scidb->cursor(database).database();

	if (base.encodingFailed())
		setResult("failed");
	else if (base.encodingIsBroken())
		setResult("broken");
	else
		setResult("ok");

	return TCL_OK;
}


static int
getDeleted(int index, int view, char const* database, variant::Type variant)
{
	Cursor const& cursor = database ? Scidb->cursor(database, variant) : Scidb->cursor();

	if (view >= 0)
		index = cursor.index(table::Games, index, view);

	setResult(cursor.database().gameInfo(index).isDeleted());
	return TCL_OK;
}


static int
getChanged(int index, int view, char const* database, variant::Type variant)
{
	Cursor const& cursor = database ? Scidb->cursor(database, variant) : Scidb->cursor();

	if (view >= 0)
		index = cursor.index(table::Games, index, view);

	setResult(cursor.database().gameInfo(index).isChanged());
	return TCL_OK;
}


int
tcl::db::getTags(TagSet const& tags, bool userSuppliedOnly)
{
	Tcl_Obj* result = Tcl_NewListObj(0, 0);

	for (tag::ID tag = tag::ID(0); tag < tag::ExtraTag; tag = tag::ID(tag + 1))
	{
		if (tag::isMandatory(tag) || (tags.contains(tag) && tags.isUserSupplied(tag)))
		{
			Tcl_Obj* objs[2];

			mstl::string const name		= tag::toName(tag);
			mstl::string const value	= tags.value(tag);

			objs[0] = Tcl_NewStringObj(name, name.size());
			objs[1] = Tcl_NewStringObj(value, value.size());

			Tcl_ListObjAppendElement(0, result, Tcl_NewListObj(2, objs));
		}
	}

	for (unsigned i = 0; i < tags.countExtra(); ++i)
	{
		Tcl_Obj* objs[2];

		TagSet::Tag const& pair = tags.extra(i);
		objs[0] = Tcl_NewStringObj(pair.name, pair.name.size());
		objs[1] = Tcl_NewStringObj(pair.value, pair.value.size());

		Tcl_ListObjAppendElement(0, result, Tcl_NewListObj(2, objs));
	}

	setResult(result);
	return TCL_OK;
}


static int
getTags(int index, char const* database, variant::Type variant)
{
	TagSet tags;
	Cursor const& cursor = database ? Scidb->cursor(database, variant) : Scidb->cursor();
	cursor.database().getInfoTags(index, tags);
	return getTags(tags, false);
}


static int
getChecksum(int index, char const* database, variant::Type variant)
{
	Cursor const& cursor = database ? Scidb->cursor(database, variant) : Scidb->cursor();
	setResult(cursor.database().computeChecksum(index));
	return TCL_OK;
}


static int
getIdn(int index, char const* database, variant::Type variant)
{
	Cursor const& cursor = database ? Scidb->cursor(database, variant) : Scidb->cursor();
	setResult(cursor.database().gameInfo(index).idn());
	return TCL_OK;
}


static int
getEco(int index, char const* database, variant::Type variant)
{
	Cursor const& cursor = database ? Scidb->cursor(database, variant) : Scidb->cursor();
	setResult(cursor.database().gameInfo(index).eco(variant).asShortString());
	return TCL_OK;
}


static int
getRatingTypes(int index, char const* database, variant::Type variant)
{
	Cursor const& cursor = database ? Scidb->cursor(database, variant) : Scidb->cursor();
	GameInfo const& info = cursor.database().gameInfo(index);

	mstl::string const& wr = rating::toString(info.ratingType(color::White));
	mstl::string const& br = rating::toString(info.ratingType(color::Black));

	Tcl_Obj* objs[2] = { Tcl_NewStringObj(wr, wr.size()), Tcl_NewStringObj(br, br.size())};
	setResult(2, objs);

	return TCL_OK;
}


static int
cmdPlayerInfo(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 4 && objc != 5)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant> (<player-index> | <game-index> <side>)");
		return TCL_ERROR;
	}

	char const*					database(stringFromObj(objc, objv, 1));
	variant::Type				variant(tcl::game::variantFromObj(objc, objv, 2));
	unsigned                index(unsignedFromObj(objc, objv, 3));
	Database const&         base(Scidb->cursor(database, variant).database());
	NamebasePlayer const*   player;

	if (objc == 4)
		player = &base.player(index);
	else
		player = &base.player(index, color::fromSide(stringFromObj(objc, objv, 4)));

	Ratings ratings(rating::Any, rating::Any);
	return tcl::player::getInfo(*player, ratings, organization::Fide, true, true, true);
}


static int
cmdPlayerCard(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	struct Log : public TeXt::Controller::Log
	{
		void error(mstl::string const& msg) { str = msg; }
		mstl::string str;
	};

	if (objc != 7 && objc != 8)
	{
		Tcl_WrongNumArgs(
			ti,
			1,
			objv,
			"<search-dir> <script> <preamble> <database> <variant> (<player-index> | <game-index> <side>)");
		return TCL_ERROR;
	}

	mstl::string				searchDir(stringFromObj(objc, objv, 1));
	mstl::string				script(stringFromObj(objc, objv, 2));
	mstl::string				preamble(stringFromObj(objc, objv, 3));
	char const*					database(stringFromObj(objc, objv, 4));
	variant::Type				variant(tcl::game::variantFromObj(objc, objv, 5));
	unsigned						index(unsignedFromObj(objc, objv, 6));
	Database const&			base(Scidb->cursor(database, variant).database());
	TeXt::Controller::LogP	myLog(new Log);
	TeXt::Controller			controller(searchDir, TeXt::Controller::AbortMode, myLog);
	mstl::istringstream		src(preamble);
	mstl::ostringstream		dst;
	mstl::ostringstream		out;
	NamebasePlayer const*	player;

	if (objc == 7)
		player = &base.player(index);
	else
		player = &base.player(index, color::fromSide(stringFromObj(objc, objv, 7)));

	base.emitPlayerCard(controller.receptacle(), *player);

	if (controller.processInput(src, dst, &out, &out) >= 0)
	{
		int rc = controller.processInput(script, dst, &out, &out);

		if (rc == TeXt::Controller::OpenInputFileFailed)
			out.write(static_cast<Log*>(myLog.get())->str);
	}

	mstl::string htm(dst.str());
	mstl::string log(out.str());

	if (!htm.empty() && htm.back() == '\n')
		htm.set_size(htm.size() - 1);
	if (!log.empty() && log.back() == '\n')
		log.set_size(log.size() - 1);

	Tcl_Obj* args[2];
	args[0] = Tcl_NewStringObj(htm, htm.size());
	args[1] = Tcl_NewStringObj(log, log.size());

	setResult(2, args);

	return TCL_OK;
}


static int
cmdFetch(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	static char const* subcommands[] =
	{
		"eventName", "whitePlayerName", "blackPlayerName",
		"eventInfo", "whitePlayerInfo", "blackPlayerInfo",
		"whitePlayerStats", "blackPlayerStats", 0
	};
	static char const* args[] =
	{
		"<game-index> <database> ?<variant>?",
		"<game-index> <database> ?<variant>?",
		"<game-index> <database> ?<variant>?",
		"<game-index> <database> ?<variant>?",
		"<game-index> <database> ?<variant>?",
		"<game-index> <database> ?<variant>?",
		"<game-index> <database> ?<variant>?",
		"<game-index> <database> ?<variant>?",
		0,
	};
	enum
	{
		Cmd_EventName, Cmd_WhitePlayerName, Cmd_BlackPlayerName, Cmd_EventInfo,
		Cmd_WhitePlayerInfo, Cmd_BlackPlayerInfo, Cmd_WhitePlayerStats, Cmd_BlackPlayerStats,
	};

	if (objc < 4)
		return usage(::CmdFetch, nullptr, nullptr, subcommands, args);

	int index = intFromObj(objc, objv, 2);
	char const* database = stringFromObj(objc, objv, 3);
	variant::Type variant = tcl::game::variantFromObj(objc, objv, 4);
	Cursor const& cursor = Scidb->cursor(database, variant);
	GameInfo const& info = cursor.database().gameInfo(index);

	switch (int idx = tcl::uniqueMatchObj(objv[1], subcommands))
	{
		case Cmd_EventName:
			setResult(info.eventEntry()->name());
			return TCL_OK;

		case Cmd_WhitePlayerName:
			setResult(info.playerEntry(color::White)->name());
			return TCL_OK;

		case Cmd_BlackPlayerName:
			setResult(info.playerEntry(color::Black)->name());
			return TCL_OK;

		case Cmd_EventInfo:
			{
				bool idCard = false;

				if (objc > 4)
				{
					char const*	lastArg	= Tcl_GetString(objv[objc - 1]);

					if (lastArg[0] == '-' && !::isdigit(lastArg[1]))
					{
						if (::strcmp(lastArg, "-card") != 0)
							return error(::CmdFetch, nullptr, nullptr, "invalid argument %s", lastArg);

						idCard = true;
					}
				}

				return getEventInfo(*info.eventEntry(), idCard ? &cursor.database() : nullptr);
			}
			break;

		case Cmd_WhitePlayerInfo:
		case Cmd_BlackPlayerInfo:
			{
				Ratings ratings(rating::Any, rating::Any);
				organization::ID federation = organization::Fide;

				bool parseOptions = true;
				bool idCard			= false;
				bool infoWanted	= false;

				while (parseOptions && objc > 4)
				{
					char const*	lastArg	= Tcl_GetString(objv[objc - 1]);

					if (*lastArg != '-')
						lastArg = Tcl_GetString(objv[objc - 2]);

					if (lastArg[0] == '-' && !::isdigit(lastArg[1]))
					{
						if (::strcmp(lastArg, "-card") == 0)
						{
							idCard = infoWanted = true;
						}
						else if (::strcmp(lastArg, "-info") == 0)
						{
							infoWanted = true;
						}
						else if (::strcmp(lastArg, "-ratings") == 0)
						{
							ratings = ::convRatings(stringFromObj(objc, objv, objc - 1));
							--objc;
						}
						else if (::strcmp(lastArg, "-federation") == 0)
						{
							federation = organization::fromString(stringFromObj(objc, objv, objc - 1));
						}
						else
						{
							return error(::CmdFetch, nullptr, nullptr, "invalid argument %s", lastArg);
						}

						--objc;
					}
					else
					{
						parseOptions = false;
					}
				}

				color::ID side = idx == Cmd_WhitePlayerInfo ? color::White : color::Black;
				NamebasePlayer const& player = *info.playerEntry(side);

				return tcl::player::getInfo(player, ratings, federation, infoWanted, idCard, true);
			}
			break;

		case Cmd_WhitePlayerStats:
		case Cmd_BlackPlayerStats:
			{
				color::ID side = idx == Cmd_WhitePlayerStats ? color::White : color::Black;
				return getPlayerStats(cursor.database(), *info.playerEntry(side));
			}
			break;
	}

	return usage(::CmdFetch, nullptr, nullptr, subcommands, args);
}


static int
cmdGet(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	static char const* subcommands[] =
	{
		"clipbase", "scratchbase", "types", "type", "name", "codec", "encoding", "created?",
		"modified?", "gameInfo", "playerInfo", "eventInfo", "siteInfo", "annotator", "position",
		"gameIndex", "playerIndex", "eventIndex", "siteIndex", "annotatorIndex", "description",
		"variant?", "stats", "readonly?", "encodingState", "deleted?", "open?", "lastChange",
		"customFlags", "gameFlags", "gameNumber", "minYear", "maxYear", "maxUsage", "tags",
		"checksum", "idn", "eco", "ratingTypes", "lookupPlayer", "lookupEvent", "lookupSite",
		"lookupPosition", "writable?", "upgrade?", "memoryOnly?", "compact?", "playerKey",
		"playerStats",
		"eventKey", "siteKey", "variants", "changed?", "unsaved?", "changes", "usedencoding",
		nullptr
	};
	static char const* args[] =
	{
		/* clipbase			*/ "<name>|<type>",
		/* scratchbase		*/ "<name>|<type>",
		/* types				*/ "sci|si3|si4",
		/* type				*/ "?<database>?",
		/* name				*/ "",
		/* codec				*/ "?<database>? ?<variant>?",
		/* encoding			*/ "?<database>?",
		/* created?			*/ "?<database>?",
		/* modified?		*/ "?<database>?",
		/* gameInfo			*/ "<index> <view> <database> ?<variant>? ?-ratings <ratings>? ?-notation <notation>?",
		/* playerInfo		*/ "<index> <view> <database> <variant> ?<which>?",
		/* eventInfo		*/ "<index> <view> <database> <variant> ?<which>?",
		/* siteInfo			*/ "<index> <view> <database> <variant> ?<which>?",
		/* annotator		*/ "<index> ?<view>? ?<database>? ?<variant>?",
		/* position			*/ "<index> ?<view>? ?<database>? ?<variant>?",
		/* gameIndex		*/ "<number> <view> ?<database>? ?<variant>?",
		/* playerIndex		*/ "<number> ?<view>? ?<database>? ?<variant>?",
		/* eventIndex		*/ "<number> <view> ?<database>? ?<variant>?",
		/* siteIndex		*/ "<number> ?<view>? ?<database>? ?<variant>?",
		/* annotatorIndex	*/ "<number> ?<view>? ?<database>? ?<variant>?",
		/* description		*/ "?<database>?",
		/* variant?			*/ "?<database> ?<number>??",
		/* stats				*/ "<database>",
		/* readonly?		*/ "?<database>?",
		/* encodingState	*/ "?<database>?",
		/* deleted?			*/ "<index> ?<view>? ?<database>? ?<variant>?",
		/* open?				*/ "<database> ?<variant>?",
		/* lastChange		*/ "?<database>? ?<variant>?",
		/* customFlags		*/ "?<database>? ?<variant>?",
		/* gameFlags		*/ "?<database>? ?<variant>?",
		/* gameNumber		*/ "<database> ?<variant>? <index> <view>",
		/* minYear			*/ "<database> ?<variant>?",
		/* maxYear			*/ "<database> ?<variant>?",
		/* maxUsage			*/ "<database> <variant> <namebase-type>",
		/* tags				*/ "<number> ?<database>? ?<variant>",
		/* checksum			*/ "<number> ?<database>? ?<variant>?",
		/* idn				*/ "<number> ?<database>? ?<variant>?",
		/* eco				*/ "<number> ?<database>? ?<variant>?",
		/* ratingTypes		*/ "<number> ?<database>? ?<variant>?",
		/* lookupPlayer	*/ "<index> ?<view>? ?<database>? ?<variant>?",
		/* lookupEvent		*/ "<index> ?<view>? ?<database>? ?<variant>?",
		/* lookupSite		*/ "<index> ?<view>? ?<database>? ?<variant>?",
		/* lookupPosition		*/ "<index> ?<view>? ?<database>? ?<variant>?",
		/* writable?		*/ "?<database>?",
		/* upgrade?			*/ "<database>",
		/* memoryOnly?		*/ "?<database>?",
		/* compact?			*/ "<database>",
		/* playerKey		*/ "<database> <variant> (<player-index> | <game-index> <side>)",
		/* playerStats		*/ "<database> <variant> <player-index>",
		/* eventKey			*/ "<database> <variant> game|event <event>",
		/* siteKey			*/ "<database> <variant> game|site <site>",
		/* variants			*/ "<database>",
		/* changed?			*/ "<index> ?<view>? ?<database>? ?<variant>?",
		/* unsaved?			*/ "<database>",
		/* changes			*/ "<database>",
		/* usedencoding	*/ "?<database>?",
		0
	};
	enum
	{
		Cmd_Clipbase, Cmd_Scratchbase, Cmd_Types, Cmd_Type, Cmd_Name, Cmd_Codec, Cmd_Encoding,
		Cmd_Created, Cmd_Modified, Cmd_GameInfo, Cmd_PlayerInfo, Cmd_EventInfo, Cmd_SiteInfo,
		Cmd_Annotator, Cmd_Position, Cmd_GameIndex, Cmd_PlayerIndex, Cmd_EventIndex, Cmd_SiteIndex,
		Cmd_AnnotatorIndex, Cmd_Description, Cmd_Variant, Cmd_Stats, Cmd_ReadOnly, Cmd_EncodingState,
		Cmd_Deleted, Cmd_Open, Cmd_LastChange, Cmd_CustomFlags, Cmd_GameFlags, Cmd_GameNumber,
		Cmd_MinYear, Cmd_MaxYear, Cmd_MaxUsage, Cmd_Tags, Cmd_Checksum, Cmd_Idn, Cmd_Eco, Cmd_RatingTypes,
		Cmd_LookupPlayer, Cmd_LookupEvent, Cmd_LookupSite, Cmd_LookupPosition, Cmd_Writable, Cmd_Upgrade,
		Cmd_MemoryOnly, Cmd_Compact, Cmd_PlayerKey, Cmd_PlayerStats, Cmd_EventKey, Cmd_SiteKey,
		Cmd_Variants, Cmd_Changed, Cmd_Unsaved, Cmd_Changes, Cmd_UsedEncoding
	};

	if (objc < 2)
		return usage(::CmdGet, nullptr, nullptr, subcommands, args);

	int index	= tcl::uniqueMatchObj(objv[1], subcommands);
	int view		= View::DefaultView;

	switch (index)
	{
		case Cmd_Clipbase:
			if (objc != 3)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);
			return getClipbaseAttr(ti, Tcl_GetString(objv[2]));

		case Cmd_Scratchbase:
			if (objc != 3)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);
			return getScratchbaseAttr(ti, Tcl_GetString(objv[2]));

		case Cmd_Types:
			if (objc != 3)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);
			return getTypes(ti, Tcl_GetString(objv[2]));

		case Cmd_Type:
			if (objc < 3)
				return getType();
			return getType(Tcl_GetString(objv[2]));

		case Cmd_Name:
			return getName();

		case Cmd_Codec:
			if (objc < 3)
				return getCodec();
			return getCodec(Tcl_GetString(objv[2]), tcl::game::variantFromObj(objc, objv, 3));

		case Cmd_Encoding:
			return getEncoding(	objc > 2 ? stringFromObj(objc, objv, 2) : 0,
										tcl::game::variantFromObj(objc, objv, 3));

		case Cmd_UsedEncoding:
			return getUsedEncoding(	objc > 2 ? stringFromObj(objc, objv, 2) : 0,
											tcl::game::variantFromObj(objc, objv, 3));

		case Cmd_Created:
			if (objc < 3)
				return getCreated();
			return getCreated(Tcl_GetString(objv[2]));

		case Cmd_Modified:
			if (objc < 3)
				return getModified();
			return getModified(Tcl_GetString(objv[2]));

		case Cmd_GameInfo:
		{
			if (objc < 5)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);

			Ratings ratings(rating::Any, rating::Any);
			move::Notation notation = move::SAN;
			bool haveRatings = false;

			for ( ; objc > 7; objc -= 2)
			{
				char const* option = stringFromObj(objc, objv, objc - 2);

				if (strcmp(option, "-ratings") == 0)
				{
					ratings = ::convRatings(stringFromObj(objc, objv, objc - 1));
					haveRatings = true;
				}
				else if (strcmp(option, "-notation") == 0)
				{
					notation = tcl::game::notationFromObj(objv[objc - 1]);
				}
				else
				{
					return error(CmdGet, "gameInfo", nullptr, "unknown option %s", option);
				}
			}

			index = unsignedFromObj(objc, objv, 2);
			view = intFromObj(objc, objv, 3);
			char const* database = stringFromObj(objc, objv, 4);
			variant::Type variant = tcl::game::variantFromObj(objc, objv, 5);

			if (haveRatings)
				return getGameInfo(index, view, database, variant, ratings, notation);

			if (objc <= 6)
				return getGameInfo(index, view, database, variant, notation);

			return getGameInfo(index, view, database, variant, unsignedFromObj(objc, objv, 6));
		}

		case Cmd_PlayerInfo:
		{
			if (objc < 6)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);

			Ratings ratings(rating::Any, rating::Any);
			organization::ID federation = organization::Fide;

			bool parseOptions 	= true;
			bool idCard				= false;
			bool info				= false;
			bool usePlayerBase	= true;

			while (parseOptions && objc >= 3)
			{
				char const*	lastArg	= Tcl_GetString(objv[objc - 1]);

				if (*lastArg != '-')
					lastArg = Tcl_GetString(objv[objc - 2]);

				if (lastArg[0] == '-' && !::isdigit(lastArg[1]))
				{
					if (::strcmp(lastArg, "-card") == 0)
					{
						idCard = info = true;
					}
					else if (::strcmp(lastArg, "-info") == 0)
					{
						info = true;
					}
					else if (::strcmp(lastArg, "-ratings") == 0)
					{
						ratings = ::convRatings(stringFromObj(objc, objv, objc - 1));
						--objc;
					}
					else if (::strcmp(lastArg, "-federation") == 0)
					{
						federation = organization::fromString(stringFromObj(objc, objv, objc - 1));
						--objc;
					}
					else if (::strcmp(lastArg, "-usebase") == 0)
					{
						usePlayerBase = boolFromObj(objc, objv, objc - 1);
						--objc;
					}
					else
					{
						return error(::CmdGet, nullptr, nullptr, "invalid argument %s", lastArg);
					}

					--objc;
				}
				else
				{
					parseOptions = false;
				}
			}

			index = unsignedFromObj(objc, objv, 2);

			if (objc > 3)
				view = intFromObj(objc, objv, 3);

			char const*		database	= stringFromObj(objc, objv, 4);
			variant::Type	variant	= tcl::game::variantFromObj(objc, objv, 5);

			if (objc < 7)
			{
				return getPlayerInfo(index,
											view,
											database,
											variant,
											ratings,
											federation,
											info,
											idCard,
											usePlayerBase);
			}

			unsigned which = unsignedFromObj(objc, objv, 6);

			return getPlayerInfo(index, view, database, variant, which);
		}
		// not reached

		case Cmd_EventInfo:
		{
			if (objc < 6)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);

			bool idCard = false;

			if (objc >= 3)
			{
				char const*	lastArg	= Tcl_GetString(objv[objc - 1]);

				if (lastArg[0] == '-' && !::isdigit(lastArg[1]))
				{
					if (::strcmp(lastArg, "-card") != 0)
						return error(::CmdGet, nullptr, nullptr, "invalid argument %s", lastArg);

					idCard = true;
					--objc;
				}
			}

			index = unsignedFromObj(objc, objv, 2);

			if (objc > 3)
				view = intFromObj(objc, objv, 3);

			char const*		database	= stringFromObj(objc, objv, 4);
			variant::Type	variant	= tcl::game::variantFromObj(objc, objv, 5);

			if (objc < 7)
				return getEventInfo(index, view, database, variant, idCard);

			unsigned which = unsignedFromObj(objc, objv, 6);

			return getEventInfo(index, view, database, variant, which);
		}

		case Cmd_SiteInfo:
		{
			if (objc < 6)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);

			index = unsignedFromObj(objc, objv, 2);

			if (objc > 3)
				view = intFromObj(objc, objv, 3);

			char const*		database	= stringFromObj(objc, objv, 4);
			variant::Type	variant	= tcl::game::variantFromObj(objc, objv, 5);

			if (objc < 7)
				return getSiteInfo(index, view, database, variant);

			unsigned which = unsignedFromObj(objc, objv, 6);

			return getSiteInfo(index, view, database, variant, which);
		}

		case Cmd_Annotator:
			return getAnnotator(	unsignedFromObj(objc, objv, 2),
										objc > 3 ? intFromObj(objc, objv, 3) : -1,
										objc > 4 ? stringFromObj(objc, objv, 4) : nullptr,
										objc > 5 ? tcl::game::variantFromObj(objc, objv, 5) : variant::Normal);

		case Cmd_Position:
			return getPosition(	unsignedFromObj(objc, objv, 2),
										objc > 3 ? intFromObj(objc, objv, 3) : -1,
										objc > 4 ? stringFromObj(objc, objv, 4) : nullptr,
										objc > 5 ? tcl::game::variantFromObj(objc, objv, 5) : variant::Normal);

		case Cmd_GameIndex:
			return getGameIndex(	unsignedFromObj(objc, objv, 2),
										objc > 3 ? intFromObj(objc, objv, 3) : -1,
										objc > 4 ? stringFromObj(objc, objv, 4) : 0,
										tcl::game::variantFromObj(objc, objv, 5));

		case Cmd_PlayerIndex:
			return getIndex(	table::Players,
									unsignedFromObj(objc, objv, 2),
									objc > 3 ? intFromObj(objc, objv, 3) : -1,
									objc > 4 ? stringFromObj(objc, objv, 4) : 0,
									tcl::game::variantFromObj(objc, objv, 5));

		case Cmd_LookupPlayer:
			return getLookupPlayer(	unsignedFromObj(objc, objv, 2),
											objc > 3 ? intFromObj(objc, objv, 3) : -1,
											objc > 4 ? stringFromObj(objc, objv, 4) : 0,
											tcl::game::variantFromObj(objc, objv, 5));

		case Cmd_EventIndex:
			return getIndex(	table::Events,
									unsignedFromObj(objc, objv, 2),
									objc > 3 ? intFromObj(objc, objv, 3) : -1,
									objc > 4 ? stringFromObj(objc, objv, 4) : 0,
									tcl::game::variantFromObj(objc, objv, 5));

		case Cmd_SiteIndex:
			return getIndex(	table::Sites,
									unsignedFromObj(objc, objv, 2),
									objc > 3 ? intFromObj(objc, objv, 3) : -1,
									objc > 4 ? stringFromObj(objc, objv, 4) : 0,
									tcl::game::variantFromObj(objc, objv, 5));

		case Cmd_LookupEvent:
			return getLookupEvent(	unsignedFromObj(objc, objv, 2),
											objc > 3 ? intFromObj(objc, objv, 3) : -1,
											objc > 4 ? stringFromObj(objc, objv, 4) : 0,
											tcl::game::variantFromObj(objc, objv, 5));

		case Cmd_LookupSite:
			return getLookupSite(unsignedFromObj(objc, objv, 2),
											objc > 3 ? intFromObj(objc, objv, 3) : -1,
											objc > 4 ? stringFromObj(objc, objv, 4) : 0,
											tcl::game::variantFromObj(objc, objv, 5));

		case Cmd_LookupPosition:
			return getLookupPosition(unsignedFromObj(objc, objv, 2),
											objc > 3 ? intFromObj(objc, objv, 3) : -1,
											objc > 4 ? stringFromObj(objc, objv, 4) : 0,
											tcl::game::variantFromObj(objc, objv, 5));

		case Cmd_AnnotatorIndex:
			return getAnnotatorIndex(	stringFromObj(objc, objv, 2),
												objc > 3 ? intFromObj(objc, objv, 3) : -1,
												objc > 4 ? stringFromObj(objc, objv, 4) : 0,
												tcl::game::variantFromObj(objc, objv, 5));

		case Cmd_Description:
			if (objc < 3)
				return getDescription();
			return getDescription(Tcl_GetString(objv[2]));

		case Cmd_Variant:
			if (objc < 3)
				return getVariant();
			if (objc < 4)
				return getVariant(Tcl_GetString(objv[2]));
			return getVariant(Tcl_GetString(objv[2]), unsignedFromObj(objc, objv, 3));

		case Cmd_Stats:
			return getStats(stringFromObj(objc, objv, 2));

		case Cmd_ReadOnly:
		{
			::db::variant::Type variant = ::db::variant::Undetermined;
			if (objc > 3)
				variant = tcl::game::variantFromObj(objc, objv, 3);
			return getReadonly(objc > 2 ? stringFromObj(objc, objv, 2) : 0, variant);
		}

		case Cmd_Writable:
			if (objc < 3)
				return getWritable();
			return getWritable(stringFromObj(objc, objv, 2));

		case Cmd_Upgrade:
			if (objc != 3)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);
			::tcl::setResult(Scidb->cursor(stringFromObj(objc, objv, 2)).database().shouldUpgrade());
			return TCL_OK;

		case Cmd_Open:
			if (objc != 3 && objc != 4)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);
			if (objc > 3)
			{
				setResult(	Scidb->contains(stringFromObj(objc, objv, 2),
								tcl::game::variantFromObj(objc, objv, 3)));
			}
			else
			{
				setResult(Scidb->contains(stringFromObj(objc, objv, 2)));
			}
			return TCL_OK;

		case Cmd_EncodingState:
			if (objc < 3)
				return getEncodingState(0);
			return getEncodingState(Tcl_GetString(objv[2]));

		case Cmd_Deleted:
			return getDeleted(intFromObj(objc, objv, 2),
									objc < 4 ? -1 : intFromObj(objc, objv, 3),
									objc < 5 ? 0 : stringFromObj(objc, objv, 4),
									tcl::game::variantFromObj(objc, objv, 5));

		case Cmd_Changed:
			return getChanged(intFromObj(objc, objv, 2),
									objc < 4 ? -1 : intFromObj(objc, objv, 3),
									objc < 5 ? 0 : stringFromObj(objc, objv, 4),
									tcl::game::variantFromObj(objc, objv, 5));

		case Cmd_LastChange:
		{
			char const* base = objc < 3 ? "" : stringFromObj(objc, objv, 2);
			variant::Type variant = tcl::game::variantFromObj(objc, objv, 3);
			Cursor const& cursor = objc < 3 ? Scidb->cursor() : Scidb->cursor(base, variant);
			setResult(Tcl_NewWideIntObj(cursor.database().lastChange()));
			return TCL_OK;
		}

		case Cmd_CustomFlags:
		{
			char const* base = objc < 3 ? "" : stringFromObj(objc, objv, 2);
			variant::Type variant = tcl::game::variantFromObj(objc, objv, 3);
			Cursor const& cursor = objc < 3 ? Scidb->cursor() : Scidb->cursor(base, variant);
			Database const& database = cursor.database();

			if (database.format() == format::Scid4)
			{
				Tcl_Obj* objv[6];

				DatabaseCodec::CustomFlags const& flags = database.codec().customFlags();

				for (unsigned i = 0; i < 6; ++i)
					objv[i] = Tcl_NewStringObj(flags.get(i), -1);

				setResult(6, objv);
			}
			else
			{
				setResult("");
			}

			return TCL_OK;
		}

		case Cmd_GameFlags:
		{
			char const* base = objc < 3 ? "" : stringFromObj(objc, objv, 2);
			variant::Type variant = tcl::game::variantFromObj(objc, objv, 3);
			Cursor const& cursor = objc < 3 ? Scidb->cursor() : Scidb->cursor(base, variant);
			Database const& database = cursor.database();
			mstl::string flags;

			flagsToString(database.codec().gameFlags(), flags);

			if (database.format() == format::Scid4)
				::mapScid4Flags(flags);

			setResult(flags);
			return TCL_OK;
		}

		case Cmd_GameNumber:
			if (objc != 5 && objc != 6)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);
			if ((view = intFromObj(objc, objv, objc > 5 ? 5 : 4)) >= 0)
			{
				char const*		base		= stringFromObj(objc, objv, 2);
				unsigned			idx		= unsignedFromObj(objc, objv, objc > 5 ? 4 : 3);
				variant::Type	variant	= variant::Undetermined;

				if (objc > 5)
					variant = tcl::game::variantFromObj(objv[3]);

				index = Scidb->cursor(base, variant).index(table::Games, idx, view);
			}
			else
			{
				index = unsignedFromObj(objc, objv, objc > 5 ? 4 : 3);
			}
			setResult(index);
			return TCL_OK;

		case Cmd_MinYear:
		{
			if (objc != 3 && objc != 4)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);

			char const* base = stringFromObj(objc, objv, 2);
			variant::Type variant = tcl::game::variantFromObj(objc, objv, 3);
			setResult(Scidb->cursor(base, variant).database().codec().minYear());
			return TCL_OK;
		}

		case Cmd_MaxYear:
		{
			if (objc != 3 && objc != 4)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);

			char const* base = stringFromObj(objc, objv, 2);
			variant::Type variant = tcl::game::variantFromObj(objc, objv, 3);
			setResult(Scidb->cursor(base, variant).database().codec().maxYear());
			return TCL_OK;
		}

		case Cmd_MaxUsage:
		{
			if (objc != 5)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);

			char const* base = stringFromObj(objc, objv, 2);
			variant::Type variant = tcl::game::variantFromObj(objc, objv, 3);
			Tcl_Obj* namebase = objectFromObj(objc, objv, 4);

			Namebase::Type	type = getNamebaseType(namebase, ::CmdGet);
			if (int(type) < 0)
				return TCL_ERROR;
			setResult(Scidb->cursor(base, variant).database().namebase(type).maxUsage());
			return TCL_OK;
		}

		case Cmd_Tags:
			if (objc < 3)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);
			return getTags(unsignedFromObj(objc, objv, 2),
								objc > 3 ? stringFromObj(objc, objv, 3) : 0,
								tcl::game::variantFromObj(objc, objv, 4));

		case Cmd_Checksum:
			if (objc < 3)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);
			return getChecksum(unsignedFromObj(objc, objv, 2),
									objc > 3 ? stringFromObj(objc, objv, 3) : 0,
									tcl::game::variantFromObj(objc, objv, 4));

		case Cmd_Idn:
			if (objc < 3 || Tcl_GetIntFromObj(ti, objv[2], &index) != TCL_OK)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);
			return getIdn(	unsignedFromObj(objc, objv, 2),
								objc > 3 ? stringFromObj(objc, objv, 3) : 0,
								tcl::game::variantFromObj(objc, objv, 4));

		case Cmd_Eco:
			if (objc < 3 || Tcl_GetIntFromObj(ti, objv[2], &index) != TCL_OK)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);
			return getEco(index,
								objc > 3 ? stringFromObj(objc, objv, 3) : 0,
								tcl::game::variantFromObj(objc, objv, 4));

		case Cmd_RatingTypes:
			if (objc < 3 || Tcl_GetIntFromObj(ti, objv[2], &index) != TCL_OK)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);
			return getRatingTypes(	unsignedFromObj(objc, objv, 2),
											objc > 3 ? stringFromObj(objc, objv, 3) : 0,
											tcl::game::variantFromObj(objc, objv, 4));

		case Cmd_MemoryOnly:
		{
			char const* base = objc < 3 ? "" : stringFromObj(objc, objv, 2);
			setResult(Scidb->cursor(base).database().isMemoryOnly());
			return TCL_OK;
		}

		case Cmd_Compact:
		{
			if (objc != 3 && objc != 4)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);

			char const*		database(stringFromObj(objc, objv, 2));
			variant::Type	variant(tcl::game::variantFromObj(objc, objv, 3));

			setResult(Scidb->cursor(database, variant).database().shouldCompact());
			return TCL_OK;
		}

		case Cmd_PlayerKey:
		{
			if (objc != 5 && objc != 6)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);

			char const*			database(stringFromObj(objc, objv, 2));
			variant::Type		variant(tcl::game::variantFromObj(objc, objv, 3));
			unsigned				index(unsignedFromObj(objc, objv, 4));
			Database const&	base(Scidb->cursor(database, variant).database());

			if (objc == 5)
				getPlayerKey(base.player(index));
			else
				getPlayerKey(base.player(index, color::fromSide(stringFromObj(objc, objv, 5))));

			return TCL_OK;
		}

		case Cmd_PlayerStats:
		{
			if (objc != 5)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);

			return getPlayerStats(
				stringFromObj(objc, objv, 2),
				tcl::game::variantFromObj(objc, objv, 3),
				unsignedFromObj(objc, objv, 4));
		}

		case Cmd_EventKey:
		{
			if (objc != 6)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);

			char const*			database(stringFromObj(objc, objv, 2));
			variant::Type		variant(tcl::game::variantFromObj(objc, objv, 3));
			char const*			what(stringFromObj(objc, objv, 4));
			unsigned				index(unsignedFromObj(objc, objv, 5));
			Database const&	base(Scidb->cursor(database, variant).database());

			getEventKey(base.event(index, *what == 'e' ? Database::MyIndex : Database::GameIndex));
			return TCL_OK;
		}

		case Cmd_SiteKey:
		{
			if (objc != 6)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);

			char const*			database(stringFromObj(objc, objv, 2));
			variant::Type		variant(tcl::game::variantFromObj(objc, objv, 3));
			char const*			what(stringFromObj(objc, objv, 4));
			unsigned				index(unsignedFromObj(objc, objv, 5));
			Database const&	base(Scidb->cursor(database, variant).database());

			getSiteKey(base.site(index, *what == 'e' ? Database::MyIndex : Database::GameIndex));
			return TCL_OK;
		}

		case Cmd_Variants:
			if (objc != 3)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);
			return getVariants(stringFromObj(objc, objv, 2));

		case Cmd_Unsaved:
			if (objc != 3)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);
			return isUnsaved(stringFromObj(objc, objv, 2));

		case Cmd_Changes:
			if (objc != 3)
				return usage(::CmdGet, nullptr, nullptr, subcommands, args);
			return getChanges(stringFromObj(objc, objv, 2));
	}

	return usage(::CmdGet, nullptr, nullptr, subcommands, args);
}


static int
cmdSubscribe(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc < 3 || objc > 4)
	{
		Tcl_WrongNumArgs(
			ti, 1, objv,
			"dbInfo|gameList|playerList|annotatorList|positionList|eventList|siteList|gameInfo|"
			"gameData|gameHistory|gameSwitch|gameClose|databaseSwitch|tree <update-cmd> "
			"?<close-cmd>?");
		return TCL_ERROR;
	}

	static char const* subcommands[] =
	{
		"dbInfo", "gameList", "playerList", "annotatorList", "positionList", "eventList",
		"siteList", "gameInfo", "gameData", "gameHistory", "gameSwitch", "gameClose",
		"databaseSwitch",
		"tree", 0
	};
	enum
	{
		Cmd_DbInfo, Cmd_GameList, Cmd_PlayerList, Cmd_AnnotatorList, Cmd_PositionList, Cmd_EventList,
		Cmd_SiteList, Cmd_GameInfo, Cmd_GameData, Cmd_GameHistory, Cmd_GameSwitch, Cmd_GameClose,
		Cmd_DatabaseSwitched, Cmd_Tree,
	};

	MySubscriber* subscriber = static_cast<MySubscriber*>(scidb->subscriber());

	if (subscriber == 0)
	{
		subscriber = new MySubscriber;
		scidb->setSubscriber(Application::SubscriberP(subscriber));
	}

	int index = tcl::uniqueMatchObj(objv[1], subcommands);

	Tcl_Obj* updateCmd	= objv[2];
	Tcl_Obj* closeCmd		= objc == 4 ? objv[3] : nullptr;

	MySubscriber::Type type = MySubscriber::None;

	switch (index)
	{
		case Cmd_DbInfo:				type = MySubscriber::DatabaseInfo; break;
		case Cmd_GameList:			type = MySubscriber::GameList; break;
		case Cmd_PlayerList:			type = MySubscriber::PlayerList; break;
		case Cmd_AnnotatorList:		type = MySubscriber::AnnotatorList; break;
		case Cmd_PositionList:		type = MySubscriber::PositionList; break;
		case Cmd_EventList:			type = MySubscriber::EventList; break;
		case Cmd_SiteList:			type = MySubscriber::SiteList; break;
		case Cmd_GameInfo:			type = MySubscriber::GameInfo; break;
		case Cmd_GameData:			type = MySubscriber::GameData; break;
		case Cmd_GameHistory:		type = MySubscriber::GameHistory; break;
		case Cmd_Tree:					type = MySubscriber::Tree; break;

		case Cmd_GameSwitch:			subscriber->setGameSwitchedCmd(updateCmd); break;
		case Cmd_GameClose:			subscriber->setGameClosedCmd(updateCmd); break;
		case Cmd_DatabaseSwitched:	subscriber->setDatabaseSwitchedCmd(updateCmd); break;

		default:
			return error(	::CmdSubscribe,
								nullptr, nullptr,
								"invalid argument %s",
								static_cast<char const*>(Tcl_GetString(objv[1])));
	}

	if (type != ::MySubscriber::None)
		subscriber->setCmd(type, updateCmd, closeCmd);

	return TCL_OK;
}


static int
cmdUnsubscribe(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc < 3 || objc > 4)
	{
		Tcl_WrongNumArgs(
			ti, 1, objv,
			"dbInfo|gameList|playerList|annotatorList|eventList|"
			"siteList|gameInfo|gameData|gameHistory|gameSwitch|tree "
			"<update-cmd> ?<close-cmd>?");
		return TCL_ERROR;
	}

	static char const* subcommands[] =
	{
		"dbInfo", "gameList", "playerList", "eventList", "siteList",
		"annotatorList", "gameInfo", "gameData", "gameHistory", "gameSwitch",
		"gameClose", "databaseSwitch", "tree", 0
	};
	enum
	{
		Cmd_DbInfo, Cmd_GameList, Cmd_PlayerList, Cmd_EventList, Cmd_SiteList,
		Cmd_AnnotatorList, Cmd_GameInfo, Cmd_GameData, Cmd_GameHistory, Cmd_GameSwitch,
		Cmd_GameClose, Cmd_DatabaseSwitched, Cmd_Tree,
	};

	MySubscriber* subscriber = static_cast<MySubscriber*>(scidb->subscriber());

	if (subscriber == 0)
		return TCL_OK;

	int index = tcl::uniqueMatchObj(objv[1], subcommands);

	Tcl_Obj* updateCmd	= objv[2];
	Tcl_Obj* closeCmd		= objc == 4 ? objv[3] : nullptr;

	switch (index)
	{
		case Cmd_DbInfo:
			subscriber->unsetCmd(MySubscriber::DatabaseInfo, updateCmd, closeCmd);
			break;

		case Cmd_GameList:
			subscriber->unsetListCmd(table::Games, updateCmd, closeCmd);
			break;

		case Cmd_PlayerList:
			subscriber->unsetListCmd(table::Players, updateCmd, closeCmd);
			break;

		case Cmd_EventList:
			subscriber->unsetListCmd(table::Events, updateCmd, closeCmd);
			break;

		case Cmd_SiteList:
			subscriber->unsetListCmd(table::Sites, updateCmd, closeCmd);
			break;

		case Cmd_AnnotatorList:
			subscriber->unsetListCmd(table::Annotators, updateCmd, closeCmd);
			break;

		case Cmd_GameInfo:
			subscriber->unsetCmd(MySubscriber::GameInfo, updateCmd, closeCmd);
			break;

		case Cmd_GameData:
			subscriber->unsetCmd(MySubscriber::GameData, updateCmd, closeCmd);
			break;

		case Cmd_GameHistory:
			subscriber->unsetCmd(MySubscriber::GameHistory, updateCmd, closeCmd);
			break;

		case Cmd_GameSwitch:
			subscriber->unsetGameSwitchedCmd(updateCmd);
			break;

		case Cmd_GameClose:
			subscriber->unsetGameClosedCmd(updateCmd);
			break;

		case Cmd_DatabaseSwitched:
			subscriber->unsetDatabaseSwitchedCmd(updateCmd);
			break;

		case Cmd_Tree:
			subscriber->unsetTreeCmd(updateCmd, closeCmd);
			break;

		default:
			return error(::CmdUnsubscribe, nullptr, nullptr, "invalid argument %s", Tcl_GetString(objv[1]));
	}

	return TCL_OK;
}


static int
cmdSwitch(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 3)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant>");
		return TCL_ERROR;
	}

	char const*		database	= Tcl_GetString(objv[1]);
	variant::Type	variant	= tcl::game::variantFromObj(objv[2]);

	scidb->switchBase(scidb->cursor(database, variant));

	return TCL_OK;
}


static int
cmdClose(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 2)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database>");
		return TCL_ERROR;
	}

	scidb->close(Tcl_GetString(objv[1]));
	return TCL_OK;
}


static int
cmdClear(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 2 && objc != 3)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> ?<variant>?");
		return TCL_ERROR;
	}

	char const*		database	= stringFromObj(objc, objv, 1);
	variant::Type	variant	= tcl::game::variantFromObj(objc, objv, 2);

	if (variant == variant::Undetermined)
		scidb->clearBase(scidb->multiCursor(database));
	else
		scidb->clearBase(scidb->cursor(database, variant));

	return TCL_OK;
}


static int
cmdSort(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	static char const* subcommands[] =
	{
		"gameInfo", "player", "event", "site", "annotator", "position", nullptr
	};
	static char const* args[] =
	{
		"<database> <variant> <column> ?<view>? ?-reset? ?-descending? ?-ascending? ?-average?"
			" -ratings {<rating type> <rating type>}",
		"<database> <variant> <column> ?<view>? ?-reset? ?-descending? ?-ascending? ?-latest?",
		"<database> <variant> <column> ?<view>? ?-reset? ?-descending? ?-ascending?",
		"<database> <variant> <column> ?<view>? ?-reset? ?-descending? ?-ascending?",
		"<database> <variant> <column> ?<view>? ?-reset? ?-descending? ?-ascending?",
		"<database> <variant> <column> ?<view>? ?-reset? ?-descending? ?-ascending?",
	};
	enum { Cmd_GameInfo, Cmd_Player, Cmd_Event, Cmd_Site, Cmd_Annotator, Cmd_Position };

	if (objc < 5)
		return usage(::CmdSort, nullptr, nullptr, subcommands, args);

	int				view		= View::DefaultView;
	int				index		= tcl::uniqueMatchObj(objv[1], subcommands);
	char const*		database	= stringFromObj(objc, objv, 2);
	variant::Type	variant	= tcl::game::variantFromObj(objv[3]);
	bool				average	= false;
	bool				latest	= false;
	bool				reset		= false;
	order::ID		order		= order::Ascending;
	int				optCount	= 0;

	Ratings ratings(rating::Elo, rating::Elo);

	while (	objc > 5
			&& (	::isOption(stringFromObj(objc, objv, objc - 1))
				|| ::isOption(stringFromObj(objc, objv, objc - 2))))
	{
		++optCount;
		--objc;
	}

	if (objc < 4 || 6 < objc)
		return usage(::CmdSort, nullptr, nullptr, subcommands, args);

	if (objc == 6)
		view = intFromObj(objc, objv, 5);

	for (int i = 0; i < optCount; ++i)
	{
		char const* opt = stringFromObj(optCount, objv + objc, i);

		if (*opt == '-')
		{
			if (::strcmp(opt, "-average") == 0)
				average = true;
			else if (::strcmp(opt, "-latest") == 0)
				latest = true;
			else if (::strcmp(opt, "-ascending") == 0)
				order = order::Ascending;
			else if (::strcmp(opt, "-descending") == 0)
				order = order::Descending;
			else if (::strcmp(opt, "-reset") == 0)
				reset = true;
			else if (::strcmp(opt, "-ratings") != 0)
				return error(::CmdSort, nullptr, nullptr, "illegal option %s", opt);
			else if (i == optCount - 1)
				return error(::CmdSort, nullptr, nullptr, "missing rating types");
			else
				ratings = convRatings(stringFromObj(optCount, objv + objc, ++i));
		}
		else
		{
			return usage(::CmdSort, nullptr, nullptr, subcommands, args);
		}
	}

	switch (index)
	{
		case Cmd_GameInfo:
			{
				attribute::game::ID column = lookupGameInfo(objv[4], ratings, average);
				if (column < 0)
					return TCL_ERROR;
				if (reset)
					scidb->resetOrder(scidb->cursor(database, variant), view, table::Games);
				scidb->sort(scidb->cursor(database, variant), view, column, order, ratings.first);
			}
			break;

		case Cmd_Player:
			{
				attribute::player::ID column = lookupPlayerBase(objv[4], ratings, latest);
				if (column < 0)
					return TCL_ERROR;
				if (reset)
					scidb->resetOrder(scidb->cursor(database, variant), view, table::Players);
				scidb->sort(scidb->cursor(database, variant), view, column, order, ratings.first);
			}
			break;

		case Cmd_Event:
			{
				attribute::event::ID column = lookupEventBase(objv[4]);
				if (column < 0)
					return TCL_ERROR;
				if (reset)
					scidb->resetOrder(scidb->cursor(database, variant), view, table::Events);
				scidb->sort(scidb->cursor(database, variant), view, column, order);
			}
			break;

		case Cmd_Site:
			{
				attribute::site::ID column = lookupSiteBase(objv[4]);
				if (column < 0)
					return TCL_ERROR;
				if (reset)
					scidb->resetOrder(scidb->cursor(database, variant), view, table::Sites);
				scidb->sort(scidb->cursor(database, variant), view, column, order);
			}
			break;

		case Cmd_Annotator:
			{
				attribute::annotator::ID column = lookupAnnotatorBase(objv[4]);
				if (column < 0)
					return TCL_ERROR;
				if (reset)
					scidb->resetOrder(scidb->cursor(database, variant), view, table::Annotators);
				scidb->sort(scidb->cursor(database, variant), view, column, order);
			}
			break;

		case Cmd_Position:
			{
				attribute::position::ID column = lookupPositionBase(objv[4]);
				if (column < 0)
					return TCL_ERROR;
				if (reset)
					scidb->resetOrder(scidb->cursor(database, variant), view, table::Positions);
				scidb->sort(scidb->cursor(database, variant), view, column, order);
			}
			break;

		default:
			return usage(::CmdSort, nullptr, nullptr, subcommands, args);
	}

	return TCL_OK;
}


static int
cmdRecode(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 5)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <encoding> <progress-cmd> <progress-arg>");
		return TCL_ERROR;
	}

	char const* database	= stringFromObj(objc, objv, 1);
	char const* encoding	= stringFromObj(objc, objv, 2);

	Progress progress(objv[3], objv[4]);
	scidb->recode(scidb->cursor(database), encoding, progress);

	return TCL_OK;
}


static int
cmdReverse(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	static char const* subcommands[] = { "gameInfo", "player", "event", "site", "annotator", 0 };
	static char const* args[] =
	{
		"<database> <variant> ?<view>?",
		"<database> <variant> ?<view>?",
		"<database> <variant> ?<view>?",
		"<database> <variant> ?<view>?",
		"<database> <variant> ?<view>?",
	};
	enum { Cmd_GameInfo, Cmd_Player, Cmd_Event, Cmd_Site, Cmd_Annotator };

	if (objc < 4 || 5 < objc)
		return usage(::CmdReverse, nullptr, nullptr, subcommands, args);

	int				view		= View::DefaultView;
	int				index		= tcl::uniqueMatchObj(objv[1], subcommands);
	char const*		database	= Tcl_GetString(objv[2]);
	variant::Type	variant	= tcl::game::variantFromObj(objv[3]);

	if (objc >= 5 && Tcl_GetIntFromObj(ti, objv[4], &view) != TCL_OK)
		return error(CmdReverse, nullptr, nullptr, "integer expected for view argument");

	table::Type type;

	switch (index)
	{
		case Cmd_GameInfo:	type = table::Games; break;
		case Cmd_Player:		type = table::Players; break;
		case Cmd_Event:		type = table::Events; break;
		case Cmd_Site:			type = table::Sites; break;
		case Cmd_Annotator:	type = table::Annotators; break;
		default:					return usage(::CmdReverse, nullptr, nullptr, subcommands, args);
	}

	scidb->reverseOrder(scidb->cursor(database, variant), view, type);
	return TCL_OK;
}


static int
cmdMatch(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 6 && objc != 8)
	{
		Tcl_WrongNumArgs(
			ti,
			1,
			objv,
			"player|event|site|annotator <database> <variant> <maximal> <string> "
			"?<rating-type> <two-ratings-flag>?");
		return TCL_ERROR;
	}

	Namebase::Type		type			= getNamebaseType(objv[1], ::CmdMatch);
	if (int(type) < 0)
		return TCL_ERROR;
	char const*			database		= stringFromObj(objc, objv, 2);
	variant::Type		variant		= tcl::game::variantFromObj(objc, objv, 3);
	unsigned				maximal		= unsignedFromObj(objc, objv, 4);
	mstl::string		suffix		= stringFromObj(objc, objv, 5);
	rating::Type		ratingType	= rating::Any;
	bool					twoRatings	= true;
	Player::Matches	playerMatches;
	Site::Matches		siteMatches;

	if (objc > 6)
		ratingType = rating::fromString(stringFromObj(objc, objv, 6));
	if (objc > 7)
		twoRatings	= boolFromObj(objc, objv, 7);

	if (twoRatings && ratingType == rating::Elo)
		ratingType = rating::Any;

	Namebase::Matches matches;
	Scidb->cursor(database, variant).database().namebase(type).findMatches(suffix, matches, maximal);
	M_ASSERT(matches.size() <= maximal);

	unsigned resultSize = matches.size();

	switch (unsigned(type))
	{
		case Namebase::Player:
			Player::findMatches(suffix, playerMatches, maximal - matches.size());
			M_ASSERT(playerMatches.size() <= maximal - matches.size());
			resultSize += playerMatches.size();
			break;

		case Namebase::Site:
			Site::findMatches(suffix, siteMatches, maximal - matches.size());
			M_ASSERT(siteMatches.size() <= maximal - matches.size());
			resultSize += siteMatches.size();
			break;
	}

	mstl::vector<Tcl_Obj*> result(resultSize);

	for (unsigned i = 0; i < matches.size(); ++i)
	{
		NamebaseEntry const* entry = matches[i];

		Tcl_Obj* objs[11];
		unsigned n = 0;

		objs[n++] = Tcl_NewIntObj(entry->frequency());
		objs[n++] = Tcl_NewStringObj(entry->name(), -1);

		switch (unsigned(type))
		{
			case Namebase::Player:
				{
					NamebasePlayer const* player = static_cast<NamebasePlayer const*>(entry);

					uint32_t fideID = player->fideID();

					objs[n++] = Tcl_NewStringObj(player->name(), -1);
					objs[n++] = fideID ? Tcl_NewIntObj(player->fideID()) : Tcl_NewListObj(0, 0);
					objs[n++] = Tcl_NewStringObj(species::toString(player->type()), -1);
					objs[n++] = Tcl_NewStringObj(sex::toString(player->sex()), -1);
					objs[n++] = Tcl_NewStringObj(country::toString(player->federation()), -1);
					objs[n++] = Tcl_NewStringObj(title::toString(player->title()), -1);
					objs[n++] = Tcl_NewIntObj(player->elo());

					if (ratingType != rating::Any && player->rating(ratingType) != 0)
					{
						objs[n++] = Tcl_NewStringObj(rating::toString(ratingType), -1);
						objs[n++] = Tcl_NewIntObj(player->rating(ratingType));
					}
					else if (twoRatings || player->elo() == 0)
					{
						objs[n++] = Tcl_NewStringObj(rating::toString(player->ratingType()), -1);
						objs[n++] = Tcl_NewIntObj(player->rating());
					}
					else
					{
						objs[n++] = Tcl_NewStringObj(rating::toString(rating::Elo), -1);
						objs[n++] = Tcl_NewIntObj(player->elo());
					}
				}
				break;

			case Namebase::Event:
				{
					NamebaseEvent const* event = static_cast<NamebaseEvent const*>(entry);

					objs[n++] = Tcl_NewStringObj(event->site()->name(), -1);
					objs[n++] = Tcl_NewStringObj(country::toString(event->site()->country()), -1);
					objs[n++] = Tcl_NewStringObj(event->date().asShortString(), -1);
					objs[n++] = Tcl_NewStringObj(event::toString(event->eventMode()), -1);
					objs[n++] = Tcl_NewStringObj(event::toString(event->type()), -1);
					objs[n++] = Tcl_NewStringObj(::db::time::toString(event->timeMode()), -1);
				}
				break;

			case Namebase::Site:
				{
					NamebaseSite const* site = static_cast<NamebaseSite const*>(entry);
					objs[n++] = Tcl_NewStringObj(entry->name(), -1);
					objs[n++] = Tcl_NewStringObj(country::toString(site->country()), -1);
				}
				break;
		}

		M_ASSERT(n <= U_NUMBER_OF(objs));
		result[i] = Tcl_NewListObj(n, objs);
	}

	switch (unsigned(type))
	{
		case Namebase::Player:
			for (unsigned i = 0; i < playerMatches.size(); ++i)
			{
				Tcl_Obj* objs[11];
				unsigned n = 0;

				Player const* player = playerMatches[i];
				mstl::string const& ascii = player->asciiName();
				uint32_t fideID = player->fideID();

				objs[n++] = Tcl_NewIntObj(0);
				objs[n++] = Tcl_NewStringObj(player->name(), player->name().size());
				objs[n++] = Tcl_NewStringObj(ascii.empty() ? player->name() : ascii, -1);
				objs[n++] = fideID ? Tcl_NewIntObj(player->fideID()) : Tcl_NewListObj(0, 0);
				objs[n++] = Tcl_NewStringObj(species::toString(player->type()), -1);
				objs[n++] = Tcl_NewStringObj(sex::toString(player->sex()), -1);
				objs[n++] = Tcl_NewStringObj(country::toString(player->federation()), -1);
				objs[n++] = Tcl_NewStringObj(title::toString(title::best(player->titles())), -1);
				objs[n++] = Tcl_NewIntObj(player->latestElo());

				if (ratingType != rating::Any && player->latestRating(ratingType) != 0)
				{
					objs[n++] = Tcl_NewStringObj(rating::toString(ratingType), -1);
					objs[n++] = Tcl_NewIntObj(player->latestRating(ratingType));
				}
				else if (twoRatings || player->latestElo() == 0)
				{
					rating::Type rt = player->ratingType();

					if (rt == rating::Elo)
						rt = rating::Any;

					unsigned score = rt == rating::Any ? 0 : player->latestRating(rt);

					objs[n++] = Tcl_NewStringObj(rating::toString(rt), -1);
					objs[n++] = Tcl_NewIntObj(score);
				}
				else
				{
					objs[n++] = Tcl_NewStringObj(rating::toString(rating::Elo), -1);
					objs[n++] = Tcl_NewIntObj(player->latestElo());
				}

				result[matches.size() + i] = Tcl_NewListObj(n, objs);
				M_ASSERT(n <= U_NUMBER_OF(objs));
			}
			break;

		case Namebase::Site:
			for (unsigned i = 0; i < siteMatches.size(); ++i)
			{
				Tcl_Obj* objs[4];
				unsigned n = 0;

				Site const* site = siteMatches[i].second;
				country::Code country = siteMatches[i].first;
				mstl::string const& ascii = site->nonDiacriticName(country);

				objs[n++] = Tcl_NewIntObj(0);
				objs[n++] = Tcl_NewStringObj(site->name(), site->name().size());
				objs[n++] = Tcl_NewStringObj(ascii, ascii.size());
				objs[n++] = Tcl_NewStringObj(country::toString(country), -1);

				result[matches.size() + i] = Tcl_NewListObj(n, objs);
			}
			break;
	}

	setResult(resultSize, result.data());
	return TCL_OK;
}


static int
cmdFind(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 4 && objc != 5)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "player|event|site|annotator|position <database> ?<variant>? <key>");
		return TCL_ERROR;
	}

	char const*		what		= stringFromObj(objc, objv, 1);
	char const*		database	= stringFromObj(objc, objv, 2);
	variant::Type	variant	= objc == 4 ? variant::Undetermined : tcl::game::variantFromObj(objv[3]);
	Tcl_Obj*			keyObj	= objv[objc == 4 ? 3 : 4];
	unsigned			numObjs	= 0;

	if (strcmp(what, "player") == 0)
	{
		numObjs = PlayerKey_LAST;
	}
	else if (strcmp(what, "event") == 0)
	{
		numObjs = EventKey_LAST;
	}
	else if (strcmp(what, "site") == 0)
	{
		numObjs = SiteKey_LAST;
	}
	else if (strcmp(what, "annotator") == 0)
	{
		numObjs = 1;
	}
	else if (strcmp(what, "position") == 0)
	{
		numObjs = 1;
	}
	else
	{
		return error(	CmdFind,
							nullptr,
							nullptr,
							"only 'player', 'event', 'site', 'annotator', or 'position' is allowed");
	}

	Tcl_Obj* objs[numObjs];
	memset(objs, 0, sizeof(objs));

	for (unsigned i = 0; i < numObjs; ++i)
	{
		Tcl_ListObjIndex(ti, keyObj, i, &objs[i]);

		if (objs[i] == 0)
			return error(CmdFind, nullptr, nullptr, "invalid info list");
	}

	Database const& db = Scidb->cursor(database, variant).database();
	int index = -1;

	if (strcmp(what, "player") == 0)
	{
		int fideId = 0;
		Tcl_GetIntFromObj(ti, objs[PlayerKey_FideID], &fideId);

		index = db.namebase(Namebase::Player).findPlayerIndex(
						Tcl_GetString(objs[PlayerKey_Name]),
						fideId,
						country::fromString(Tcl_GetString(objs[PlayerKey_Country])),
						title::fromString(Tcl_GetString(objs[PlayerKey_Title])),
						species::fromString(Tcl_GetString(objs[PlayerKey_Type])),
						sex::fromString(Tcl_GetString(objs[PlayerKey_Sex])));
	}
	else if (strcmp(what, "event") == 0)
	{
		NamebaseSite const* site = db.namebase(Namebase::Site).findSite(
												Tcl_GetString(objs[EventKey_Site]),
												country::fromString(Tcl_GetString(objs[EventKey_SiteCountry])));

		if (site)
		{
			index = db.namebase(Namebase::Event).findEventIndex(
				Tcl_GetString(objs[EventKey_Name]),
				Date(Tcl_GetString(objs[EventKey_Date])),
				event::typeFromString(Tcl_GetString(objs[EventKey_Type])),
				::db::time::fromString(Tcl_GetString(objs[EventKey_TimeMode])),
				event::modeFromString(Tcl_GetString(objs[EventKey_EventMode])),
				site
			);
		}
	}
	else if (strcmp(what, "site") == 0)
	{
		index = db.namebase(Namebase::Site).findSiteIndex(
			Tcl_GetString(objs[SiteKey_Site]),
			country::fromString(Tcl_GetString(objs[SiteKey_Country]))
		);
	}
	else if (strcmp(what, "annotator") == 0)
	{
		index = db.namebase(Namebase::Annotator).findAnnotatorIndex(Tcl_GetString(objs[0]));
	}
	else if (strcmp(what, "position") == 0)
	{
		unsigned position = unsignedFromObj(objc, objs, 0);

		if (db.statistic().positions.test(position))
			index = position;
	}

	setResult(index);
	return TCL_OK;
}


static int
cmdSave(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 4)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <progress-cmd> <progress-arg>");
		return TCL_ERROR;
	}

	char const*	db(stringFromObj(objc, objv, 1));
	Progress		progress(objv[2], objv[3]);

	scidb->save(db, progress);
	return TCL_OK;
}


static int
cmdSavePGN(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 6)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <encoding> <flags> <progress-cmd> <progress-arg>");
		return TCL_ERROR;
	}

	char const*	db(stringFromObj(objc, objv, 1));
	char const*	encoding(stringFromObj(objc, objv, 2));
	unsigned		flags(unsignedFromObj(objc, objv, 3));
	Progress		progress(objv[4], objv[5]);

	switch (scidb->save(db, encoding, flags, progress))
	{
		case file::IsUpTodate:	setResult("IsUpTodate"); break;
		case file::Updated:		setResult("Updated"); break;
		case file::IsRemoved:	setResult("IsRemoved"); break;
		case file::IsReadonly:	setResult("IsReadonly"); break;
		case file::HasChanged:	setResult("HasChanged"); break;
	}

	return TCL_OK;
}


static int
cmdUpdate(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 5)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant> <index> <tag-list>");
		return TCL_ERROR;
	}

	char const*		database	= stringFromObj(objc, objv, 1);
	variant::Type	variant	= tcl::game::variantFromObj(objc, objv, 2);
	unsigned			index		= unsignedFromObj(objc, objv, 3);

	int rc = TCL_OK;
	TagSet tags;

	if ((rc = game::convertTags(tags, objectFromObj(objc, objv, 4))) == TCL_OK)
		scidb->cursor(database, variant).updateCharacteristics(index, tags);

	return rc;
}


static int
cmdUpgrade(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 4)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <progress-cmd> <progress-arg>");
		return TCL_ERROR;
	}

	struct Log : public ::db::Log
	{
		bool error(save::State, unsigned) override	{ return true; }
		void warning(Warning, unsigned) override		{}
	};

	mstl::string database(stringFromObj(objc, objv, 1));
	mstl::string filename(::util::misc::file::rootname(database));

	filename += ".partial-293t83873xx878.sci";

	Progress				progress(objv[2], objv[3]);
	Cursor&				cursor(scidb->cursor(database));
	Database const&	db(cursor.database());
	View&					v(cursor.view());
	Log					log;
	type::ID				type(db.type());
	View::FileMode		fmode(DatabaseCodec::upgradeIndexOnly() ? View::Create : View::Upgrade);

	try
	{
		::db::sci::Codec::remove(filename); // to be sure

		setResult(v.exportGames(filename,
										sys::utf8::Codec::utf8(),
										db.description(),
										db.creationTime(),
										type,
										0,
										View::TagBits(true),
										true,
										nullptr, // all languages
										0,			// significance of languages has no meaning here
										nullptr, // illegal game counter not needed
										log,
										progress,
										fmode));

		::db::sci::Codec::rename(filename, database);
	}
	catch (...)
	{
		::db::sci::Codec::remove(filename);
		throw;
	}

	return TCL_OK;
}


static int
cmdCompact(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 4)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <progress-cmd> <progress-arg>");
		return TCL_ERROR;
	}

	Progress progress(objv[2], objv[3]);
	scidb->compactBase(scidb->cursor(stringFromObj(objc, objv, 1)), progress);

	return TCL_OK;
}


static int
cmdCopy(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 8)
	{
		Tcl_WrongNumArgs(
			ti, 1, objv,
			"<source> <destination> <tag-set> "
			"<progress-cmd> <progress-arg> <log-cmd> <log-arg>");
		return TCL_ERROR;
	}

	::db::tag::TagSet	tagBits;
	mstl::string		source(stringFromObj(objc, objv, 1));
	mstl::string		destination(stringFromObj(objc, objv, 2));
	bool					extraTags(tcl::view::buildTagSet(ti, CmdCopy, objv[3], tagBits));
	Tcl_Obj*				progressCmd(objectFromObj(objc, objv, 4));
	Tcl_Obj*				progressArg(objectFromObj(objc, objv, 5));
	Tcl_Obj*				logCmd(objectFromObj(objc, objv, 6));
	Tcl_Obj*				logArg(objectFromObj(objc, objv, 7));
	Progress				progress(progressCmd, progressArg);
	tcl::Log				log(logCmd, logArg);
	unsigned				accepted[variant::NumberOfVariants];
	unsigned				rejected[variant::NumberOfVariants];
	unsigned				illegalRejected(0);
	unsigned*			illegalPtr(nullptr);
	int					n;

	::memset(accepted, 0, sizeof(accepted));
	::memset(rejected, 0, sizeof(rejected));

	::app::MultiCursor& dst = scidb->multiCursor(destination);

	if (::db::format::isScidFormat(dst.multiBase().format()))
		illegalPtr = &illegalRejected;

	n = scidb->copyGames(
			Scidb->multiCursor(source),
			scidb->multiCursor(destination),
			accepted,
			rejected,
			tagBits,
			extraTags,
			illegalPtr,
			log,
			progress);

	if (progress.interrupted())
		n = -n - 1;

	tcl::PgnReader::setResult(n, illegalRejected, accepted, rejected);
	return TCL_OK;
}


static int
cmdWrite(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 6)
	{
		Tcl_WrongNumArgs(
			ti, 1, objv, "<database> <file-extension> <channel> <progress-cmd> <progress-arg>");
		return TCL_ERROR;
	}

	char const*	baseName		= stringFromObj(objc, objv, 1);
	char const* extension	= stringFromObj(objc, objv, 2);
	char const* channelName	= stringFromObj(objc, objv, 3);

	tcl::Progress		progress(objv[4], objv[5]);
	Tcl_Channel			chan(Tcl_GetChannel(ti, channelName, 0));
	tcl::File			file(chan);
	util::ZlibOStream	os(file.handle());

	if (strcmp(extension, "sci") == 0)
		scidb->cursor(baseName).databaseObject().writeIndex(os, progress);
	else if (strcmp(extension, "scn") == 0)
		scidb->cursor(baseName).databaseObject().writeNamebases(os, progress);
	else if (strcmp(extension, "scg") == 0)
		scidb->cursor(baseName).databaseObject().writeGames(os, progress);
	else
		return error(CmdWrite, 0, 0, "unexpected extension '%s'", extension);

	os.flush();
	file.flush();
	os.close();
	file.close();

	Tcl_Obj* objs[3];
	objs[0] = Tcl_NewIntObj(os.size());
	objs[1] = Tcl_NewIntObj(os.compressedSize());
	objs[2] = Tcl_NewIntObj(os.crc());
	setResult(3, objs);

	return TCL_OK;
}


int
tcl::db::getPlayerStats(Database const& database, NamebasePlayer const& player)
{
	PlayerStats stats;
	database.playerStatistic(player, stats);

	Tcl_Obj* objv[7];
	Tcl_Obj* objs[4];

	objs[0] = Tcl_NewStringObj(stats.firstDate().asString(), -1);
	objs[1] = Tcl_NewStringObj(stats.lastDate().asString(), -1);
	objv[0] = Tcl_NewListObj(2, objs);

	objs[0] = Tcl_NewIntObj(stats.minRating(rating::Elo));
	objs[1] = Tcl_NewIntObj(stats.maxRating(rating::Elo));
	objv[1] = Tcl_NewListObj(2, objs);

	objv[2] = Tcl_NewIntObj(stats.countGames());

	objs[0] = Tcl_NewIntObj(stats.score(color::White, result::White));
	objs[1] = Tcl_NewIntObj(stats.score(color::White, result::Black));
	objs[2] = Tcl_NewIntObj(stats.score(color::White, result::Draw));
	objs[3] = Tcl_NewIntObj(int(stats.percentage(color::White)*100.0));
	objv[3] = Tcl_NewListObj(4, objs);

	objs[0] = Tcl_NewIntObj(stats.score(color::Black, result::Black));
	objs[1] = Tcl_NewIntObj(stats.score(color::Black, result::White));
	objs[2] = Tcl_NewIntObj(stats.score(color::Black, result::Draw));
	objs[3] = Tcl_NewIntObj(int(stats.percentage(color::Black)*100.0));
	objv[4] = Tcl_NewListObj(4, objs);

	objs[0] = Tcl_NewIntObj(stats.score(result::White));
	objs[1] = Tcl_NewIntObj(stats.score(result::Black));
	objs[2] = Tcl_NewIntObj(stats.score(result::Draw));
	objs[3] = Tcl_NewIntObj(int(stats.percentage()*100.0));
	objv[5] = Tcl_NewListObj(4, objs);

	EcoTable const& ecoTable = EcoTable::specimen(database.variant());

	objs[0] = Tcl_NewListObj(0, 0);
	for (unsigned i = 0, n = mstl::min(5u, stats.countEcoLines(color::White)); i < n; ++i)
	{
		Tcl_Obj* argv[3];
		mstl::string line;
		mstl::string eco(stats.ecoLine(color::White, i).asShortString());

		ecoTable.getLine(stats.ecoLine(color::White, i)).
			print(line, variant::Normal, move::SAN, protocol::Scidb, encoding::Utf8);
		argv[0] = Tcl_NewIntObj(stats.ecoCount(color::White, i));
		argv[1] = Tcl_NewStringObj(eco, eco.size());
		argv[2] = Tcl_NewStringObj(line, line.size());
		Tcl_ListObjAppendElement(0, objs[0], Tcl_NewListObj(3, argv));
	}
	objs[1] = Tcl_NewListObj(0, 0);
	for (unsigned i = 0, n = mstl::min(5u, stats.countEcoLines(color::Black)); i < n; ++i)
	{
		Tcl_Obj* argv[3];
		mstl::string line;
		mstl::string eco(stats.ecoLine(color::Black, i).asShortString());

		ecoTable.getLine(stats.ecoLine(color::Black, i)).
			print(line, variant::Normal, move::SAN, protocol::Scidb, encoding::Utf8);
		argv[0] = Tcl_NewIntObj(stats.ecoCount(color::Black, i));
		argv[1] = Tcl_NewStringObj(eco, eco.size());
		argv[2] = Tcl_NewStringObj(line, line.size());
		Tcl_ListObjAppendElement(0, objs[1], Tcl_NewListObj(3, argv));
	}
	objv[6] = Tcl_NewListObj(2, objs);

	setResult(U_NUMBER_OF(objv), objv);
	return TCL_OK;
}


static int
cmdFindDuplicates(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 3 && objc != 5)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant> ?-normalize 0|1?");
		return TCL_ERROR;
	}

	int normalize = 1;
	if (objc == 5)
	{
		if (strcmp(Tcl_GetString(objv[3]), "-normalize") != 0)
		{
			Tcl_SetObjResult(ti, Tcl_NewStringObj("expected -normalize", -1));
			return TCL_ERROR;
		}
		if (Tcl_GetBooleanFromObj(ti, objv[4], &normalize) != TCL_OK) return TCL_ERROR;
	}

	char const* database = stringFromObj(objc, objv, 1);
	variant::Type variant = tcl::game::variantFromObj(objc, objv, 2);

	Cursor& cursor = scidb->cursor(database, variant);
	Database& db = cursor.getDatabase();
	::db::maintenance::DuplicateGroups groups = ::db::maintenance::findDuplicates(db, normalize ? ::db::maintenance::Normalized : ::db::maintenance::Exact);
	Tcl_Obj* result = Tcl_NewListObj(0, nullptr);

	for (unsigned i = 0; i < groups.size(); ++i)
	{
		Tcl_Obj* group = Tcl_NewListObj(0, nullptr);
		for (unsigned k = 0; k < groups[i].size(); ++k)
			Tcl_ListObjAppendElement(ti, group, Tcl_NewIntObj(groups[i][k]));
		Tcl_ListObjAppendElement(ti, result, group);
	}

	Tcl_SetObjResult(ti, result);
	return TCL_OK;
}


struct SimilarMatch
{
	unsigned number;
	unsigned shared;

	bool operator<(SimilarMatch const& other) const
	{
		return shared != other.shared ? shared > other.shared : number < other.number;
	}
};


// One pass: O(D + G*L + G*log(N+1)) time, O(R + M + N) space, where
// D is decoded data, G scanned games, L reference plies, R reference size,
// M largest decoded game and N result limit. Only the reference first-ply
// bucket is retained; real positions and moves verify every candidate.
// Local Games never touch the editor or write database records. Time is
// checked between decodes; a single codec read cannot be interrupted.
static int
cmdSimilar(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc < 4 || (objc - 4) % 2)
	{
		Tcl_WrongNumArgs(ti, 1, objv,
			"<database> <variant> <number> ?-limit N? ?-max G? ?-seconds S?");
		return TCL_ERROR;
	}

	int number, limit = 10, maximum = 10000;
	double seconds = 5;
	if (Tcl_GetIntFromObj(ti, objv[3], &number) != TCL_OK)
		return TCL_ERROR;
	for (int i = 4; i < objc; i += 2)
	{
		char const* option = Tcl_GetString(objv[i]);
		if (::strcmp(option, "-seconds") == 0)
		{
			if (Tcl_GetDoubleFromObj(ti, objv[i + 1], &seconds) != TCL_OK)
				return TCL_ERROR;
		}
		else if (::strcmp(option, "-limit") == 0 || ::strcmp(option, "-max") == 0)
		{
			int& value = ::strcmp(option, "-limit") == 0 ? limit : maximum;
			if (Tcl_GetIntFromObj(ti, objv[i + 1], &value) != TCL_OK)
				return TCL_ERROR;
		}
		else
		{
			Tcl_SetObjResult(ti, Tcl_NewStringObj("unknown similar option", -1));
			return TCL_ERROR;
		}
	}
	if (number < 0 || limit < 0 || maximum < 0 || !(seconds >= 0 && seconds <= 3600))
	{
		Tcl_SetObjResult(ti, Tcl_NewStringObj("expected nonnegative integers and seconds between 0 and 3600", -1));
		return TCL_ERROR;
	}

	variant::Type variant = tcl::game::variantFromObj(objc, objv, 2);
	Database& db = scidb->cursor(stringFromObj(objc, objv, 1), variant).getDatabase();
	if (unsigned(number) >= db.countGames())
	{
		Tcl_SetObjResult(ti, Tcl_NewStringObj("game number out of range", -1));
		return TCL_ERROR;
	}
	Tcl_ResetResult(ti);
	if (!limit || !maximum || !seconds || db.gameInfo(number).isDeleted())
		return TCL_OK;

	typedef std::chrono::steady_clock Clock;
	auto deadline = Clock::now() + std::chrono::duration<double>(seconds);
	Game reference;
	if (db.loadGame(number, reference) != load::Ok)
	{
		Tcl_SetObjResult(ti, Tcl_NewStringObj("cannot read reference game", -1));
		return TCL_ERROR;
	}
	MoveNode const* first = reference.data().m_startNode->next();
	if (!first || first->atLineEnd())
		return TCL_OK;

	std::vector<SimilarMatch> best;
	unsigned stop = mstl::min(unsigned(maximum), db.countGames());
	for (unsigned n = 0; n < stop && Clock::now() < deadline; ++n)
	{
		if (n == unsigned(number) || db.gameInfo(n).isDeleted() || db.gameInfo(n).isGuidingText())
			continue;
		Game game;
		if (db.loadGame(n, game) != load::Ok)
		{
			Tcl_SetObjResult(ti, Tcl_NewStringObj("cannot read candidate game", -1));
			return TCL_ERROR;
		}
		MoveNode const* b = game.data().m_startNode->next();
		if (!b || b->atLineEnd() || b->move().index() != first->move().index())
			continue;
		if (game.variant() != reference.variant()
			|| !game.startBoard().isEqualZHPosition(reference.startBoard()))
			continue;
		unsigned shared = 0;
		for (MoveNode const* a = first; a && b && !a->atLineEnd() && !b->atLineEnd();
				a = a->next(), b = b->next())
		{
			if (a->move() != b->move())
				break;
			++shared;
		}
		if (!shared)
			continue;
		SimilarMatch match = { n, shared };
		if (best.size() == unsigned(limit))
		{
			if (!(match < best.front()))
				continue;
			std::pop_heap(best.begin(), best.end());
			best.pop_back();
		}
		best.push_back(match);
		std::push_heap(best.begin(), best.end());
	}
	std::sort_heap(best.begin(), best.end());
	Tcl_Obj* rows = Tcl_NewListObj(0, nullptr);
	for (auto const& match : best)
	{
		GameInfo const& info = db.gameInfo(match.number);
		Tcl_Obj* row = Tcl_NewDictObj();
		Tcl_DictObjPut(ti, row, Tcl_NewStringObj("number", -1), Tcl_NewWideIntObj(match.number));
		Tcl_DictObjPut(ti, row, Tcl_NewStringObj("white", -1), Tcl_NewStringObj(info.playerName(color::White), -1));
		Tcl_DictObjPut(ti, row, Tcl_NewStringObj("black", -1), Tcl_NewStringObj(info.playerName(color::Black), -1));
		Tcl_DictObjPut(ti, row, Tcl_NewStringObj("result", -1), Tcl_NewStringObj(result::toString(info.result()), -1));
		Tcl_DictObjPut(ti, row, Tcl_NewStringObj("year", -1), Tcl_NewIntObj(info.date().year()));
		Tcl_DictObjPut(ti, row, Tcl_NewStringObj("shared", -1), Tcl_NewIntObj(match.shared));
		Tcl_ListObjAppendElement(ti, rows, row);
	}
	Tcl_SetObjResult(ti, rows);
	return TCL_OK;
}


static int
cmdMarkDeleted(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 4)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant> <index>");
		return TCL_ERROR;
	}

	char const* database = stringFromObj(objc, objv, 1);
	variant::Type variant = tcl::game::variantFromObj(objc, objv, 2);
	unsigned index = unsigned(intFromObj(objc, objv, 3));

	Cursor& cursor = scidb->cursor(database, variant);

	if (index >= cursor.database().countGames())
	{
		Tcl_SetResult(ti, const_cast<char*>("game index out of range"), TCL_STATIC);
		return TCL_ERROR;
	}

	scidb->deleteGame(cursor, index, Cursor::BaseView, true);
	return TCL_OK;
}


// ======================================================================
// Per-game media for ChessBase (.cbh) databases.
//
// Guiding-text records (tournament reports) carry their media in HTML
// bodies stored in .cbg. Regular games are linked to the reports that
// carry their media via CBLink(tag_game,White,Black,Event,Site,Year,Round)
// anchors in the report body (CBM_FORMAT_DESIGN.md §7.7). The anchors give
// a direct game->report linkage: player lastnames + event + year + round
// match the game headers. (The guiding-text CBH index records themselves
// carry unusable tournament references — getEvent() yields "?" — so the
// event field of the CBH tournament table cannot be used to link them.)
// ======================================================================

namespace
{

struct GuidingTextMediaRow
{
	unsigned		gameIndex;
	int				type;
	mstl::string	path;
	mstl::string	title;
};


// Game -> report media mapping, rebuilt when the database (path, variant,
// game count) changes. The builder loads every guiding-text report once,
// parses its CBLink(tag_game,...) anchors into per-game blocks and matches
// the blocks against the game headers. Owned by the Tcl command layer,
// which runs on the app thread (like Scidb's cursor registry).
struct GuidingTextLinkCache
{
	mstl::string				database;
	unsigned						countGames;
	mstl::vector<unsigned>	gtIndices;		// guiding-text record indices
	unsigned						blockCount;		// parsed tag_game anchors
	mstl::vector<GuidingTextMediaRow> rows;	// sorted by gameIndex

	GuidingTextLinkCache():countGames(0),blockCount(0){}

	bool validFor(char const* db, variant::Type v, unsigned count) const
	{
		return database == db && thisVariant == v && countGames == count;
	}

	void clear()
	{
		database.clear();
		countGames = 0;
		blockCount = 0;
		gtIndices.clear();
		rows.clear();
	}

	variant::Type	thisVariant;
};

GuidingTextLinkCache mediaLinkCache;


// Manifest key: lowercase, alphanumerics only.
void
mediaLinkKey(mstl::string const& s, mstl::string& out)
{
	out.clear();
	for (unsigned i = 0; i < s.size(); ++i)
	{
		unsigned char c = static_cast<unsigned char>(s[i]);
		if (::isalnum(c))
			out += static_cast<char>(::tolower(c));
	}
}


// Surname key of a game header name: "Lastname, Firstname" -> lastname key;
// names without a comma are keyed in full.
void
mediaLinkLastName(mstl::string const& name, mstl::string& out)
{
	mstl::string::size_type comma = name.find(',');
	mediaLinkKey(comma == mstl::string::npos ? name : name.substr(0, comma), out);
}


// mediaLinkKey and mediaLinkLastName for std::string, keying the
// characters in place.
void
mediaLinkKey(char const* s, unsigned n, std::string& out)
{
	out.clear();
	for (unsigned i = 0; i < n; ++i)
	{
		unsigned char c = static_cast<unsigned char>(s[i]);
		if (::isalnum(c))
			out += static_cast<char>(::tolower(c));
	}
}


void
mediaLinkKey(mstl::string const& s, std::string& out)
{
	mediaLinkKey(s.c_str(), s.size(), out);
}


void
mediaLinkLastName(mstl::string const& name, std::string& out)
{
	mstl::string::size_type comma = name.find(',');
	mediaLinkKey(name.c_str(), comma == mstl::string::npos ? name.size() : comma, out);
}


// The cache is built in three steps. prepareMediaLinks runs on the app
// thread: it decodes the guiding-text reports (Database::loadGame mutates
// the shared codec) and snapshots the per-game header keys; it can stop at
// a deadline and resume, so a background build runs in short slices of the
// event loop. matchMediaLinks reads only that owned snapshot (std
// containers: deep copies, never borrowed mstl buffers) and may run on a
// worker. installMediaLinks runs on the app thread again: path resolution
// probes the media folders.
//
// Namebase entries appear as opaque keys only: the matcher compares the
// pointers and never dereferences them.
typedef void const* MediaLinkEntry;

struct MediaLinkGame
{
	MediaLinkEntry white, black, event;	// white == 0: skip (guiding text)
	uint16_t year, round;
};

typedef std::vector<std::pair<MediaLinkEntry, std::string> > MediaLinkKeys;

enum MediaLinkPhase { Scan, Parse, BlockKeys, Players, Events, Games, Prepared };

struct MediaLinkJob
{
	mstl::string		database;
	variant::Type		variant;
	unsigned				countGames;
	Database const*	identity;

	// App thread only: preparation state, and the blocks for install.
	MediaLinkPhase		phase;
	unsigned				next;
	mstl::vector<unsigned> gtIndices;
	std::unordered_map<std::string, bool> blockPlayers;
	Tcl_TimerToken		timer;
	mstl::vector<tcl_media::GuidingTextGameBlock> blocks;

	// Matcher input.
	std::vector<std::string>	blockWhite, blockBlack, blockEvent;
	std::vector<unsigned>		blockYear, blockRound;
	MediaLinkKeys					playerKeys, eventKeys;
	std::vector<MediaLinkGame>	games;

	// Matcher output: (game index, block), in game order.
	std::vector<std::pair<unsigned, unsigned> > matches;
	std::atomic<bool> cancelled;

	MediaLinkJob(mstl::string const& db, variant::Type v, Database const& base)
		:database(db)
		,variant(v)
		,countGames(base.countGames())
		,identity(&base)
		,phase(Scan)
		,next(0)
		,timer(0)
		,cancelled(false)
	{
	}
};


uint64_t const NoDeadline = uint64_t(-1);


// Advances the preparation until it is done (returns true) or the deadline
// (sys::time::timestamp) has passed (returns false; call again to resume).
bool
prepareMediaLinks(MediaLinkJob& job, Database& db, uint64_t deadline)
{
	unsigned count = 0;
	auto expired = [&count, deadline]()
	{
		return (++count & 1023) == 0 && sys::time::timestamp() >= deadline;
	};
	std::string key;

	// 1. Locate the guiding-text records (cheap index scan, no game bodies).
	if (job.phase == Scan)
	{
		while (job.next < job.countGames)
		{
			if (db.gameInfo(job.next++).isGuidingText())
				job.gtIndices.push_back(job.next - 1);
			if (expired())
				return false;
		}
		job.phase = job.gtIndices.empty() ? Prepared : Parse;
		job.next = 0;
	}

	// 2. Parse every report body into per-game blocks (the extraction helper
	// clears its output, so parse into a per-report vector and append).
	if (job.phase == Parse)
	{
		while (job.next < job.gtIndices.size())
		{
			Game game;
			if (db.loadGame(job.gtIndices[job.next++], game) == load::Ok)
			{
				mstl::string const& html = game.data().m_guidingText;
				if (!html.empty())
				{
					mstl::vector<tcl_media::GuidingTextGameBlock> report;
					tcl_media::extractGuidingTextGameBlocks(html, report);
					for (unsigned q = 0; q < report.size(); ++q)
						job.blocks.push_back(report[q]);
				}
			}
			if (sys::time::timestamp() >= deadline)	// a report decodes slowly
				return false;
		}
		job.phase = job.blocks.empty() ? Prepared : BlockKeys;
		job.next = 0;
	}

	// 3. Snapshot the manifest keys: per block, per namebase entry, and the
	// per-game entries. The worker builds its lookup tables from these.
	if (job.phase == BlockKeys)
	{
		for (unsigned b = 0; b < job.blocks.size(); ++b)
		{
			tcl_media::GuidingTextGameBlock const& block = job.blocks[b];
			mediaLinkKey(block.white, key);
			job.blockWhite.push_back(key);
			mediaLinkKey(block.black, key);
			job.blockBlack.push_back(key);
			mediaLinkKey(block.event, key);
			job.blockEvent.push_back(key);
			job.blockYear.push_back(block.year);
			job.blockRound.push_back(block.round);
			if (!job.blockWhite[b].empty() && !job.blockBlack[b].empty())
			{
				job.blockPlayers[job.blockWhite[b]] = true;
				job.blockPlayers[job.blockBlack[b]] = true;
			}
		}
		job.phase = Players;
		job.next = 0;
	}

	if (job.phase == Players)
	{
		// Only players named by some block can match.
		Namebase const& players = db.namebase(Namebase::Player);
		while (job.next < players.size())
		{
			NamebasePlayer const* entry = players.player(job.next++);
			mediaLinkLastName(entry->name(), key);
			if (!key.empty() && job.blockPlayers.count(key))
				job.playerKeys.push_back(std::make_pair(MediaLinkEntry(entry), key));
			if (expired())
				return false;
		}
		job.phase = Events;
		job.next = 0;
	}

	if (job.phase == Events)
	{
		Namebase const& events = db.namebase(Namebase::Event);
		while (job.next < events.size())
		{
			NamebaseEvent const* entry = events.event(job.next++);
			mediaLinkKey(entry->name(), key);
			job.eventKeys.push_back(std::make_pair(MediaLinkEntry(entry), key));
			if (expired())
				return false;
		}
		job.phase = Games;
		job.next = 0;
		job.games.reserve(job.countGames);
	}

	// Pointers only, no dereference: a sequential pass over the game infos.
	if (job.phase == Games)
	{
		while (job.next < job.countGames)
		{
			GameInfo const& info = db.gameInfo(job.next++);
			MediaLinkGame game;

			if (info.isGuidingText())
			{
				game.white = game.black = game.event = 0;
				game.year = game.round = 0;
			}
			else
			{
				game.white	= info.playerEntry(color::White);
				game.black	= info.playerEntry(color::Black);
				game.event	= info.eventEntry();
				game.year	= info.date().year();
				game.round	= info.round();
			}

			job.games.push_back(game);
			if (expired())
				return false;
		}
		job.phase = Prepared;
	}

	return true;
}


void
matchMediaLinks(MediaLinkJob& job)
{
	if (job.blocks.empty())
		return;

	// Blocks by "white|black" key (keys are alphanumeric, so '|' cannot
	// collide), each list in block order so the first match still wins.
	std::unordered_map<std::string, std::vector<unsigned> > byPair;
	for (unsigned b = 0; b < job.blockWhite.size(); ++b)
	{
		if (!job.blockWhite[b].empty() && !job.blockBlack[b].empty())
			byPair[job.blockWhite[b] + '|' + job.blockBlack[b]].push_back(b);
	}

	std::unordered_map<MediaLinkEntry, std::string const*> playerKey;
	for (auto const& entry : job.playerKeys)
		playerKey[entry.first] = &entry.second;
	std::unordered_map<MediaLinkEntry, std::string const*> eventKey;
	for (auto const& entry : job.eventKeys)
		eventKey[entry.first] = &entry.second;

	std::string pairKey;
	static std::string const NoEvent;

	for (unsigned i = 0; i < job.games.size(); ++i)
	{
		if ((i & 0xffff) == 0 && job.cancelled.load(std::memory_order_relaxed))
			return;

		MediaLinkGame const& game = job.games[i];
		if (game.white == 0)
			continue;

		auto white = playerKey.find(game.white);
		if (white == playerKey.end())
			continue;
		auto black = playerKey.find(game.black);
		if (black == playerKey.end())
			continue;

		pairKey = *white->second;
		pairKey += '|';
		pairKey += *black->second;
		auto candidates = byPair.find(pairKey);
		if (candidates == byPair.end())
			continue;

		auto event = eventKey.find(game.event);
		std::string const& eventName = event == eventKey.end() ? NoEvent : *event->second;

		for (unsigned b : candidates->second)
		{
			if (job.blockYear[b] != 0 && job.blockYear[b] != game.year)
				continue;
			if (job.blockRound[b] != 0 && job.blockRound[b] != game.round)
				continue;
			if (!job.blockEvent[b].empty() && eventName.find(job.blockEvent[b]) == std::string::npos)
				continue;

			// First matching block wins (a game linked by two reports keeps
			// the media of the earliest report).
			job.matches.push_back(std::make_pair(i, b));
			break;
		}
	}

	// The install step needs the matches and blocks only.
	std::vector<MediaLinkGame>().swap(job.games);
	MediaLinkKeys().swap(job.playerKeys);
	MediaLinkKeys().swap(job.eventKeys);
}


void
installMediaLinks(MediaLinkJob const& job, GuidingTextLinkCache& cache)
{
	cache.clear();
	cache.database		= job.database;
	cache.thisVariant	= job.variant;
	cache.countGames	= job.countGames;
	cache.blockCount	= job.blocks.size();

	for (auto const& match : job.matches)
	{
		tcl_media::GuidingTextGameBlock const& block = job.blocks[match.second];

		for (unsigned f = 0; f < block.files.size(); ++f)
		{
			GuidingTextMediaRow row;
			row.gameIndex	= match.first;
			row.type			= block.types[f];
			row.path			= tcl_media::resolveGuidingTextPath(job.database, block.files[f]);
			row.title		= block.event;
			cache.rows.push_back(row);
		}
	}
}


void
buildMediaLinkCache(mstl::string const& database, variant::Type vtype, Database& db,
						GuidingTextLinkCache& cache)
{
	MediaLinkJob job(database, vtype, db);
	prepareMediaLinks(job, db, NoDeadline);
	matchMediaLinks(job);
	installMediaLinks(job, cache);
}


// Background build, driven by ::scidb::db::mediaLinkReady. One build at a
// time: a request for another database cancels the pending one. The app
// thread prepares in slices of SliceTime; then a worker matches, owning
// the job, and hands it back through the Tcl event queue. The app thread
// installs it if the database is still the one it snapshotted.
uint64_t const SliceTime = 10000;	// usec

struct MediaLinkBuild
{
	std::shared_ptr<MediaLinkJob>	job;
	Tcl_Interp*							interp;
	mstl::vector<Tcl_Obj*>			callbacks;

	MediaLinkBuild() :interp(0) {}
};

MediaLinkBuild mediaLinkBuild;	// app thread only

// Workers may outlive the interpreter (process exit); they queue nothing
// once it is gone. Leaked on purpose: no destructor can race a worker.
struct MediaLinkOwner
{
	std::mutex		mutex;
	bool				alive;
	Tcl_ThreadId	thread;

	MediaLinkOwner() :alive(false), thread(0) {}
};

MediaLinkOwner& mediaLinkOwner = *new MediaLinkOwner;

struct MediaLinkEvent
{
	Tcl_Event header;
	std::shared_ptr<MediaLinkJob>* job;
};


bool
mediaLinkBaseAlive(MediaLinkJob const& job)
{
	return	Scidb->contains(job.database, job.variant)
			&& &Scidb->cursor(job.database, job.variant).database() == job.identity
			&& job.identity->countGames() == job.countGames;
}


void
cancelMediaLinkBuild()
{
	if (MediaLinkJob* job = mediaLinkBuild.job.get())
	{
		job->cancelled = true;
		if (job->timer)
			Tcl_DeleteTimerHandler(job->timer);
		job->timer = 0;
	}
	mediaLinkBuild.job.reset();
	for (unsigned i = 0; i < mediaLinkBuild.callbacks.size(); ++i)
		Tcl_DecrRefCount(mediaLinkBuild.callbacks[i]);
	mediaLinkBuild.callbacks.clear();
}


// Ends the pending build: installs it if ok, then calls back.
void
finishMediaLinkBuild(bool ok)
{
	std::shared_ptr<MediaLinkJob> job;
	mstl::vector<Tcl_Obj*> callbacks;
	Tcl_Interp* ti = mediaLinkBuild.interp;

	job.swap(mediaLinkBuild.job);
	callbacks.swap(mediaLinkBuild.callbacks);

	if (ok)
		installMediaLinks(*job, mediaLinkCache);

	for (unsigned i = 0; i < callbacks.size(); ++i)
	{
		Tcl_Obj* cmd = Tcl_DuplicateObj(callbacks[i]);
		Tcl_IncrRefCount(cmd);
		Tcl_ListObjAppendElement(ti, cmd, Tcl_NewBooleanObj(ok));
		if (Tcl_EvalObjEx(ti, cmd, TCL_EVAL_GLOBAL) != TCL_OK)
			Tcl_BackgroundException(ti, TCL_ERROR);
		Tcl_DecrRefCount(cmd);
		Tcl_DecrRefCount(callbacks[i]);
	}
}


int
mediaLinkEventProc(Tcl_Event* event, int)
{
	std::shared_ptr<MediaLinkJob> job(*reinterpret_cast<MediaLinkEvent*>(event)->job);
	delete reinterpret_cast<MediaLinkEvent*>(event)->job;

	if (job == mediaLinkBuild.job)	// else superseded
		finishMediaLinkBuild(mediaLinkBaseAlive(*job));

	return 1;
}


void
runMediaLinkJob(std::shared_ptr<MediaLinkJob> job)
{
	matchMediaLinks(*job);

	std::lock_guard<std::mutex> lock(mediaLinkOwner.mutex);
	if (!mediaLinkOwner.alive || job->cancelled)
		return;

	MediaLinkEvent* e = reinterpret_cast<MediaLinkEvent*>(Tcl_Alloc(sizeof(MediaLinkEvent)));
	e->header.proc = mediaLinkEventProc;
	e->job = new std::shared_ptr<MediaLinkJob>(job);
	Tcl_ThreadQueueEvent(mediaLinkOwner.thread, &e->header, TCL_QUEUE_TAIL);
	Tcl_ThreadAlert(mediaLinkOwner.thread);
}


// Runs one slice of the pending build's preparation; once prepared, hands
// the match to a worker (or does it here when no thread can be started).
void
mediaLinkSlice(ClientData)
{
	std::shared_ptr<MediaLinkJob> job = mediaLinkBuild.job;
	if (!job)
		return;
	job->timer = 0;

	if (!mediaLinkBaseAlive(*job))
	{
		finishMediaLinkBuild(false);
		return;
	}

	Database& db = const_cast<Cursor&>(Scidb->cursor(job->database, job->variant)).getDatabase();

	if (!prepareMediaLinks(*job, db, sys::time::timestamp() + SliceTime))
	{
		job->timer = Tcl_CreateTimerHandler(0, mediaLinkSlice, nullptr);
		return;
	}

	if (!job->blocks.empty())
	{
		try
		{
			std::thread(runMediaLinkJob, job).detach();
			return;
		}
		catch (std::exception const&)
		{
			matchMediaLinks(*job);
		}
	}

	finishMediaLinkBuild(true);
}


void
stopMediaLinkBuilds(ClientData)
{
	std::lock_guard<std::mutex> lock(mediaLinkOwner.mutex);
	mediaLinkOwner.alive = false;
	if (mediaLinkBuild.job)
		mediaLinkBuild.job->cancelled = true;
}


} // anonymous namespace


static int
cmdMediaFiles(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	// Usage: ::scidb::db::mediaFiles <database> <variant> <gameIndex>
	// Returns a list of {path type title mediaId inline} rows for the media
	// associated with the game at <gameIndex>. Order of resolution:
	//   1. .scm companion manifest fingerprint lookup (scidb-native DBs).
	//   2. .cbh guiding-text HTML bodies (<IMG src>, CBLink(tag_stream,...)):
	//      when the game IS a guiding-text record its own body is used.
	//   3. .cbh regular games: mapped onto the tournament reports that link
	//      them via CBLink(tag_game,...) anchors; rows carry the anchor's
	//      event string in the title column (CBM_FORMAT_DESIGN §7.7).
	// Empty list if nothing matches. type: 0=none 1=picture 2=audio
	// 3=video 4=stream. inline: 1 if path is a base64 payload rather than
	// a filesystem path.
	if (objc != 4)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant> <gameIndex>");
		return TCL_ERROR;
	}

	char const*		database	= stringFromObj(objc, objv, 1);
	variant::Type	variant		= tcl::game::variantFromObj(objc, objv, 2);
	int				gameIndex	= 0;
	if (Tcl_GetIntFromObj(ti, objv[3], &gameIndex) != TCL_OK || gameIndex < 0)
	{
		Tcl_SetResult(ti, "expected a non-negative game index", TCL_STATIC);
		return TCL_ERROR;
	}

	Cursor const&		cursor	= Scidb->cursor(database, variant);
	Database const&	db		= cursor.database();

	scm::MediaTable const* table = db.scmMediaTable();
	Tcl_Obj* result = Tcl_NewListObj(0, nullptr);

	if (table != nullptr && table->isOpen())
	{
		GameInfo const& info = db.gameInfo(unsigned(gameIndex));

		uint64_t fp = scm::MediaTable::fingerprint(	info.playerName(color::White),
											info.playerName(color::Black),
											info.event(),
											info.date().asString(),
											info.round(),
											unsigned(info.result()));

		mstl::vector<scm::MediaTable::Entry> entries;
		table->mediaFor(fp, entries);

		for (unsigned i = 0; i < entries.size(); ++i)
		{
			mstl::string resolved = table->resolvePath(entries[i]);

				// Resolve relative paths against the database directory so
				// the caller (xdg-open etc.) can find the file.
				if (!entries[i].inlineData && !resolved.empty()
					&& resolved[0] != '/' && resolved[0] != '\\')
				{
					mstl::string dir = ::util::misc::file::dirname(database);
					if (!dir.empty())
					{
						if (dir[dir.size() - 1] != '/')
							dir += '/';
						resolved = dir + resolved;
					}
				}

				Tcl_Obj* row[5];
			row[0] = Tcl_NewStringObj(resolved.c_str(), int(resolved.size()));
			row[1] = Tcl_NewIntObj(int(entries[i].type));
			row[2] = Tcl_NewStringObj(entries[i].title.c_str(), int(entries[i].title.size()));
			row[3] = Tcl_NewStringObj(entries[i].mediaId.c_str(), int(entries[i].mediaId.size()));
			row[4] = Tcl_NewBooleanObj(int(entries[i].inlineData));
			Tcl_ListObjAppendElement(ti, result, Tcl_NewListObj(5, row));
		}
	}

	// Fallback for ChessBase databases: a guiding-text entry carries its
	// media references in its HTML body (<IMG src="..."> and
	// CBLink(tag_stream,...)); a regular game is mapped onto the reports
	// that link it via CBLink(tag_game,...) anchors. Paths resolve to the
	// database's sibling "<DBName>.html" folder.
	{
		int len = 0;
		Tcl_ListObjLength(ti, result, &len);
		if (len == 0 && unsigned(gameIndex) < db.countGames())
		{
			GameInfo const& info = db.gameInfo(unsigned(gameIndex));
			Database& mdb = const_cast<Cursor&>(Scidb->cursor(database, variant)).getDatabase();

			if (info.isGuidingText())
			{
				// The record itself carries the media in its HTML body.
				Game game;
				if (mdb.loadGame(unsigned(gameIndex), game) == load::Ok)
				{
					mstl::string const& html = game.data().m_guidingText;
					if (!html.empty())
					{
						mstl::vector<mstl::string> files;
						mstl::vector<int> types;
						tcl_media::extractGuidingTextMedia(html, files, types);
						for (unsigned i = 0; i < files.size(); ++i)
						{
							mstl::string path(tcl_media::resolveGuidingTextPath(database, files[i]));
							Tcl_Obj* row[5];
							row[0] = Tcl_NewStringObj(path.c_str(), int(path.size()));
							row[1] = Tcl_NewIntObj(types[i]);
							row[2] = Tcl_NewStringObj("", 0);
							row[3] = Tcl_NewStringObj("", 0);
							row[4] = Tcl_NewBooleanObj(0);
							Tcl_ListObjAppendElement(ti, result, Tcl_NewListObj(5, row));
						}
					}
				}
			}
			else
			{
				// Regular game: use the tag_game anchor mapping.
				if (!mediaLinkCache.validFor(database, variant, db.countGames()))
					buildMediaLinkCache(mstl::string(database), variant, mdb, mediaLinkCache);

				for (unsigned i = 0; i < mediaLinkCache.rows.size(); ++i)
				{
					if (mediaLinkCache.rows[i].gameIndex != unsigned(gameIndex))
						continue;

					GuidingTextMediaRow const& row = mediaLinkCache.rows[i];
					Tcl_Obj* cells[5];
					cells[0] = Tcl_NewStringObj(row.path.c_str(), int(row.path.size()));
					cells[1] = Tcl_NewIntObj(row.type);
					cells[2] = Tcl_NewStringObj(row.title.c_str(), int(row.title.size()));
					cells[3] = Tcl_NewStringObj("", 0);
					cells[4] = Tcl_NewBooleanObj(0);
					Tcl_ListObjAppendElement(ti, result, Tcl_NewListObj(5, cells));
				}
			}
		}
	}

	Tcl_SetObjResult(ti, result);
	return TCL_OK;
}


// ----------------------------------------------------------------------
// PathResolver over the ChessBase release media folders (the database's
// own "<DB>.html" folder first, then the release's shared media folders;
// see tcl_media_resolve.h). Backslash separators are normalized here so
// the core stays filesystem-shaped.
// ----------------------------------------------------------------------
namespace {

struct ReleaseMediaResolver : public html::PathResolver
{
	explicit ReleaseMediaResolver(mstl::string const& database) :m_database(database) {}

	bool resolve(mstl::string const& file, mstl::string& out) override
	{
		mstl::string normalized(file);

		for (unsigned i = 0; i < normalized.size(); ++i)
		{
			if (normalized[i] == '\\')
				normalized[i] = '/';
		}

		// ChessBase writes IMG src values relative to the DATABASE's
		// directory ("168Strategy.html/cblogo.gif"), which already
		// contains the media folder prefix. Resolve such references
		// against the base directory first, then fall back to the
		// multi-folder release lookup (bare filenames).
		mstl::string::size_type htmlSlash = normalized.find(".html/");

		if (htmlSlash != mstl::string::npos)
		{
			mstl::string::size_type slash = m_database.rfind('/');
			mstl::string dir = (slash == mstl::string::npos)
			? mstl::string() : mstl::string(m_database, 0, slash + 1);
			mstl::string candidate(dir + normalized);

			if (tcl_media::mediaFileExists(candidate))
			{
				out = candidate;
				return true;
			}
		}

		mstl::string candidate(tcl_media::resolveGuidingTextPath(m_database, normalized));

		// resolveMediaFilename returns the primary candidate even when the
		// file is absent; an absent candidate means "unresolved"
		if (candidate.empty() || !tcl_media::mediaFileExists(candidate))
			return false;

		out = candidate;
		return true;
	}

private:

	mstl::string	m_database;
};


char const*
refStatusName(html::RefStatus status)
{
	switch (status)
	{
		case html::Ref_Kept:			return "kept";
		case html::Ref_Rewritten:	return "resolved";
		case html::Ref_Dropped:		return "dropped";
		case html::Ref_Unresolved:	return "unresolved";
		case html::Ref_External:	return "external";
		case html::Ref_ScidbGame:	return "game";
		case html::Ref_ScidbMedia:	return "media";
	}

	return "kept";
}

} // anonymous namespace


static void
appendEmptyGuidingResult(Tcl_Interp* ti, Tcl_Obj* result, int isGuiding)
{
	Tcl_Obj* empty = Tcl_NewListObj(0, nullptr);
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("html", -1));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("", 0));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("title", -1));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("", 0));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("isGuiding", -1));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewIntObj(isGuiding));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("media", -1));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewListObj(0, nullptr));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("anchors", -1));
	Tcl_ListObjAppendElement(ti, result, empty);
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("warnings", -1));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewListObj(0, nullptr));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("unresolved", -1));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewIntObj(0));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("converted", -1));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewIntObj(0));
}


// ----------------------------------------------------------------------
// ::scidb::html::sanitize <text> <basedir>
//
// Runs arbitrary HTML through the scidb HTML profile (the intake gate of
// scidb's native HTML support): encoding normalization, active-content
// removal, structural repair, URI scheme checks. Relative references
// (img src) resolve against <basedir> — the semantics of a saved web
// page and its asset folder. Returns a dict (flat key/value list):
//   html, title, media {{path type status} ...}, anchors, warnings,
//   unresolved, converted.
// ----------------------------------------------------------------------
namespace {

struct DirResolver : public html::PathResolver
{
	explicit DirResolver(mstl::string const& dir) :m_dir(dir) {}

	bool resolve(mstl::string const& file, mstl::string& out) override
	{
		mstl::string normalized(file);

		for (unsigned i = 0; i < normalized.size(); ++i)
		{
			if (normalized[i] == '\\')
				normalized[i] = '/';
		}

		// absolute references pass through if they exist
		if (normalized.size() > 1 && normalized[0] == '/')
		{
			if (tcl_media::mediaFileExists(normalized))
			{
				out = normalized;
				return true;
			}
			return false;
		}

		// relative to the document's directory (../ climbs handled by the OS)
		mstl::string candidate(m_dir + '/' + normalized);

		if (tcl_media::mediaFileExists(candidate))
		{
			out = candidate;
			return true;
		}

		return false;
	}

private:

	mstl::string	m_dir;
};

} // anonymous namespace


static int
cmdHtmlSanitize(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 3)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<html-text> <basedir>");
		return TCL_ERROR;
	}

	char const*		html		= stringFromObj(objc, objv, 1);
	char const*		basedir	= stringFromObj(objc, objv, 2);

	DirResolver resolver(basedir);
	mstl::string preprocessed;
	unsigned rewritten = 0;
	unsigned unresolved = 0;

	// the general profile has no ChessBase constructs; cbPreprocess is
	// harmless on clean HTML (no CBLink occurrences) and keeps one entry
	// point for all intake
	html::cbPreprocess(mstl::string(html), resolver, preprocessed, rewritten, unresolved);

	html::ChessBaseRewriter rewriter(resolver);
	html::Report report;
	html::sanitize(preprocessed, rewriter, report);

	Tcl_Obj* result = Tcl_NewListObj(0, nullptr);
	Tcl_Obj* mediaRows = Tcl_NewListObj(0, nullptr);

	for (unsigned i = 0; i < report.media.size(); ++i)
	{
		Tcl_Obj* row[3];
		row[0] = Tcl_NewStringObj(report.media[i].resolved.c_str(), int(report.media[i].resolved.size()));
		row[1] = Tcl_NewIntObj(report.media[i].type);
		row[2] = Tcl_NewStringObj(refStatusName(report.media[i].status), -1);
		Tcl_ListObjAppendElement(ti, mediaRows, Tcl_NewListObj(3, row));
	}

	Tcl_Obj* anchorRows = Tcl_NewListObj(0, nullptr);
	Tcl_Obj* warningRows = Tcl_NewListObj(0, nullptr);

	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("html", -1));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj(report.html.c_str(), int(report.html.size())));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("title", -1));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj(report.title.c_str(), int(report.title.size())));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("media", -1));
	Tcl_ListObjAppendElement(ti, result, mediaRows);
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("anchors", -1));
	Tcl_ListObjAppendElement(ti, result, anchorRows);
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("warnings", -1));
	Tcl_ListObjAppendElement(ti, result, warningRows);
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("unresolved", -1));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewIntObj(int(unresolved)));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("converted", -1));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewIntObj(report.wasConverted ? 1 : 0));

	Tcl_SetObjResult(ti, result);
	return TCL_OK;
}


// ----------------------------------------------------------------------
// ::scidb::db::gameAnchor <database> <variant> <anchor-args>
//
// Resolves a scidb-game: URI payload (the CBLink(tag_game,...) argument
// list: "WhiteLast,WhiteFirst,BlackLast,BlackFirst,Event,Site,Year,
// Round,[Extra...]") to the index of the first game (record order)
// linked by that anchor in the database's guiding-text reports.
// Returns -1 when nothing matches.
//
// The matching mirrors buildMediaLinkCache's rules: case/alnum-folded
// lastname keys for both players, event substring, year/round equality
// (0 = don't care). Commas inside event/site names shift the parsed
// fields — the identical shift happens on both sides (blocks are parsed
// from the same syntax), so the match still holds.
// ----------------------------------------------------------------------
static int
cmdGameAnchor(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 4)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant> <anchor-args>");
		return TCL_ERROR;
	}

	char const*		database	= stringFromObj(objc, objv, 1);
	variant::Type	variant		= tcl::game::variantFromObj(objc, objv, 2);
	int				len			= 0;
	Tcl_Obj* const*	fields		= nullptr;

	if (Tcl_ListObjGetElements(ti, objv[3], &len, const_cast<Tcl_Obj***>(&fields)) != TCL_OK)
	{
		Tcl_SetResult(ti, "expected the anchor arguments as a list", TCL_STATIC);
		return TCL_ERROR;
	}

	// minimum: 4 name fields (white last/first, black last/first)
	if (len < 4)
	{
		Tcl_SetObjResult(ti, Tcl_NewIntObj(-1));
		return TCL_OK;
	}

	// fold the anchor's name fields
	mstl::string anchorWhite, anchorBlack;

	mediaLinkLastName(mstl::string(Tcl_GetString(fields[0])), anchorWhite);
	mediaLinkLastName(mstl::string(Tcl_GetString(fields[2])), anchorBlack);

	// optional year/round at the documented positions (6, 7)
	unsigned anchorYear	= 0;
	unsigned anchorRound	= 0;

	if (len >= 8)
	{
		char const* y = Tcl_GetString(fields[6]);
		char const* r = Tcl_GetString(fields[7]);
		anchorYear	= tcl_media::parseDigits(y, y + ::strlen(y));
		anchorRound	= tcl_media::parseDigits(r, r + ::strlen(r));
	}

	Cursor const&	cursor	= Scidb->cursor(database, variant);
	Database const&	db		= cursor.database();

	// 1. parse every guiding-text report into per-game blocks
	mstl::vector<tcl_media::GuidingTextGameBlock> blocks;

	for (unsigned i = 0; i < db.countGames(); ++i)
	{
		if (!db.gameInfo(i).isGuidingText())
			continue;

		Database& mdb = const_cast<Cursor&>(cursor).getDatabase();
		Game game;

		if (mdb.loadGame(i, game) != load::Ok)
			continue;

		mstl::string const& html = game.data().m_guidingText;

		if (html.empty())
			continue;

		tcl_media::extractGuidingTextGameBlocks(html, blocks);
	}

	if (blocks.empty())
	{
		Tcl_SetObjResult(ti, Tcl_NewIntObj(-1));
		return TCL_OK;
	}

	// 2. find the block matching the anchor
	int matchedBlock = -1;

	for (unsigned b = 0; b < blocks.size(); ++b)
	{
		mstl::string blockWhite, blockBlack;

		mediaLinkKey(blocks[b].white, blockWhite);
		mediaLinkKey(blocks[b].black, blockBlack);

		if (blockWhite != anchorWhite || blockBlack != anchorBlack)
			continue;

		if (anchorYear && blocks[b].year != 0 && blocks[b].year != anchorYear)
			continue;

		if (anchorRound && blocks[b].round != 0 && blocks[b].round != anchorRound)
			continue;

		matchedBlock = int(b);
		break;
	}

	if (matchedBlock < 0)
	{
		Tcl_SetObjResult(ti, Tcl_NewIntObj(-1));
		return TCL_OK;
	}

	tcl_media::GuidingTextGameBlock const& block = blocks[matchedBlock];

	// 3. first game (record order) matching the block's headers
	mstl::string blockWhite, blockBlack, blockEvent, whiteKey, blackKey, eventKey;

	mediaLinkKey(block.white, blockWhite);
	mediaLinkKey(block.black, blockBlack);
	mediaLinkKey(block.event, blockEvent);

	for (unsigned i = 0; i < db.countGames(); ++i)
	{
		GameInfo const& info = db.gameInfo(i);

		if (info.isGuidingText())
			continue;

		mediaLinkLastName(info.playerName(color::White), whiteKey);
		mediaLinkLastName(info.playerName(color::Black), blackKey);

		if (whiteKey.empty() || blackKey.empty())
			continue;

		if (blockWhite != whiteKey || blockBlack != blackKey)
			continue;

		if (block.year != 0 && block.year != info.date().year())
			continue;

		if (block.round != 0 && block.round != info.round())
			continue;

		if (!blockEvent.empty())
		{
			mediaLinkKey(info.event(), eventKey);

			if (eventKey.find(blockEvent) == mstl::string::npos)
				continue;
		}

		Tcl_SetObjResult(ti, Tcl_NewIntObj(int(i)));
		return TCL_OK;
	}

	Tcl_SetObjResult(ti, Tcl_NewIntObj(-1));
	return TCL_OK;
}


static int
cmdGuidingText(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	// Usage: ::scidb::db::guidingText <database> <variant> <gameIndex>
	//
	// Returns the guiding-text body of the record at <gameIndex> as a
	// dict (flat key/value list):
	//   html       — sanitized UTF-8 fragment (the scidb HTML profile;
	//                ChessBase constructs rewritten: CBLink(tag_game,..) ->
	//                scidb-game: anchors, CBLink(tag_stream|audio,..) ->
	//                scidb-media: links, <IMG src> resolved to filesystem
	//                paths). Empty for non-guiding-text records.
	//   title      — <title> content (may be empty)
	//   isGuiding  — 1 if the record is a guiding-text entry
	//   media      — list of {path type status} rows (status: kept /
	//                resolved / dropped / unresolved / external / media)
	//   anchors    — list of CBLink argument strings (game anchors, in
	//                document order)
	//   warnings   — non-fatal diagnostics from the sanitizer
	//   unresolved — count of unresolved media references
	//   converted  — 1 if the body needed transcoding to UTF-8
	if (objc != 4)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant> <gameIndex>");
		return TCL_ERROR;
	}

	char const*		database	= stringFromObj(objc, objv, 1);
	variant::Type	variant		= tcl::game::variantFromObj(objc, objv, 2);
	int				gameIndex	= 0;

	if (Tcl_GetIntFromObj(ti, objv[3], &gameIndex) != TCL_OK || gameIndex < 0)
	{
		Tcl_SetResult(ti, "expected a non-negative game index", TCL_STATIC);
		return TCL_ERROR;
	}

	Cursor const&	cursor	= Scidb->cursor(database, variant);
	Database const&	db		= cursor.database();

	Tcl_Obj* result = Tcl_NewListObj(0, nullptr);

	if (unsigned(gameIndex) >= db.countGames() || !db.gameInfo(unsigned(gameIndex)).isGuidingText())
	{
		appendEmptyGuidingResult(ti, result, 0);
		Tcl_SetObjResult(ti, result);
		return TCL_OK;
	}

	Database& mdb = const_cast<Cursor&>(cursor).getDatabase();
	Game game;

	if (mdb.loadGame(unsigned(gameIndex), game) != load::Ok)
	{
		Tcl_SetResult(ti, "cannot load the guiding-text record", TCL_STATIC);
		return TCL_ERROR;
	}

	mstl::string const& raw = game.data().m_guidingText;

	if (raw.empty())
	{
		appendEmptyGuidingResult(ti, result, 1);
		Tcl_SetObjResult(ti, result);
		return TCL_OK;
	}

	// 1. ChessBase pre-pass: CBLink(...) -> scidb-game:/scidb-media: URIs
	ReleaseMediaResolver resolver(database);
	mstl::string preprocessed;
	unsigned rewritten = 0;
	unsigned unresolved = 0;

	html::cbPreprocess(raw, resolver, preprocessed, rewritten, unresolved);

	// 2. sanitize into the scidb HTML profile
	html::ChessBaseRewriter rewriter(resolver);
	html::Report report;
	html::sanitize(preprocessed, rewriter, report);

	// 3. report rows
	Tcl_Obj* mediaRows = Tcl_NewListObj(0, nullptr);

	for (unsigned i = 0; i < report.media.size(); ++i)
	{
		Tcl_Obj* row[3];
		row[0] = Tcl_NewStringObj(report.media[i].resolved.c_str(), int(report.media[i].resolved.size()));
		row[1] = Tcl_NewIntObj(report.media[i].type);
		row[2] = Tcl_NewStringObj(refStatusName(report.media[i].status), -1);
		Tcl_ListObjAppendElement(ti, mediaRows, Tcl_NewListObj(3, row));
	}

	Tcl_Obj* anchorRows = Tcl_NewListObj(0, nullptr);

	for (unsigned i = 0; i < report.anchors.size(); ++i)
	{
		Tcl_Obj* row[1];
		row[0] = Tcl_NewStringObj(report.anchors[i].args.c_str(), int(report.anchors[i].args.size()));
		Tcl_ListObjAppendElement(ti, anchorRows, Tcl_NewListObj(1, row));
	}

	Tcl_Obj* warningRows = Tcl_NewListObj(0, nullptr);

	for (unsigned i = 0; i < report.warnings.size(); ++i)
	{
		Tcl_ListObjAppendElement(ti, warningRows,
			Tcl_NewStringObj(report.warnings[i].c_str(), int(report.warnings[i].size())));
	}

	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("html", -1));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj(report.html.c_str(), int(report.html.size())));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("title", -1));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj(report.title.c_str(), int(report.title.size())));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("isGuiding", -1));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewIntObj(1));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("media", -1));
	Tcl_ListObjAppendElement(ti, result, mediaRows);
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("anchors", -1));
	Tcl_ListObjAppendElement(ti, result, anchorRows);
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("warnings", -1));
	Tcl_ListObjAppendElement(ti, result, warningRows);
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("unresolved", -1));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewIntObj(int(unresolved)));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewStringObj("converted", -1));
	Tcl_ListObjAppendElement(ti, result, Tcl_NewIntObj(report.wasConverted ? 1 : 0));

	Tcl_SetObjResult(ti, result);
	return TCL_OK;
}


static int
cmdLinkPlayers(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	// Usage: ::scidb::db::linkPlayers <database> <variant>
	// Link the players the exact lookup left without a rating-list entry
	// (other spellings, homonyms told apart by the games' Elo); nothing is
	// written into the database. Returns {linked N ambiguous {name ...}}.
	if (objc != 3)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant>");
		return TCL_ERROR;
	}
	char const*		database	= stringFromObj(objc, objv, 1);
	variant::Type	variant	= tcl::game::variantFromObj(objc, objv, 2);
	Database&		db			= const_cast<Cursor&>(Scidb->cursor(database, variant)).getDatabase();

	mstl::vector<unsigned> unclear;
	unsigned linked = db.namebases()(Namebase::Player).linkPlayerVariants(&unclear);

	Tcl_Obj* names = Tcl_NewListObj(0, nullptr);
	for (unsigned i = 0; i < unclear.size(); ++i)
	{
		mstl::string const& name = db.player(unclear[i]).name();
		Tcl_ListObjAppendElement(ti, names, Tcl_NewStringObj(name, name.size()));
	}
	Tcl_Obj* objs[4] = { Tcl_NewStringObj("linked", -1), Tcl_NewIntObj(linked),
								Tcl_NewStringObj("ambiguous", -1), names };
	setResult(Tcl_NewListObj(4, objs));
	return TCL_OK;
}


static int
cmdSpellingCandidates(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	// Usage: ::scidb::db::spellingCandidates <database> <variant>
	// For each player left unlinked, the rating-list entries that may be
	// another spelling of the name (Player::spellingCandidates), as
	// {index name elo {{fideID name federation rating} ...}}; players
	// without candidates are left out. Nothing is linked.
	if (objc != 3)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant>");
		return TCL_ERROR;
	}
	char const*		database	= stringFromObj(objc, objv, 1);
	variant::Type	variant	= tcl::game::variantFromObj(objc, objv, 2);
	Database const&	db		= Scidb->cursor(database, variant).database();

	Tcl_Obj* list = Tcl_NewListObj(0, nullptr);
	mstl::vector<Player*> candidates;
	for (unsigned i = 0, n = db.countPlayers(); i < n; ++i)
	{
		NamebasePlayer const& p = db.player(i);
		if (p.player() || p.type() == species::Program)
			continue;
		Player::spellingCandidates(p.name(), p.federation(), p.sex(), p.elo(), candidates);
		if (candidates.empty())
			continue;
		Tcl_Obj* cands = Tcl_NewListObj(0, nullptr);
		for (unsigned k = 0; k < candidates.size(); ++k)
		{
			Player const* c = candidates[k];
			Tcl_Obj* row[4] =
			{
				Tcl_NewWideIntObj(c->fideID()),
				Tcl_NewStringObj(c->name(), c->name().size()),
				Tcl_NewStringObj(country::toString(c->federation()), -1),
				Tcl_NewIntObj(mstl::abs(int(c->highestElo()))),
			};
			Tcl_ListObjAppendElement(ti, cands, Tcl_NewListObj(4, row));
		}
		Tcl_Obj* row[4] =
		{
			Tcl_NewIntObj(i),
			Tcl_NewStringObj(p.name(), p.name().size()),
			Tcl_NewIntObj(p.elo()),
			cands,
		};
		Tcl_ListObjAppendElement(ti, list, Tcl_NewListObj(4, row));
	}
	setResult(list);
	return TCL_OK;
}


static int
cmdLinkPlayer(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	// Usage: ::scidb::db::linkPlayer <database> <variant> <index> <fideID>
	// Link the player at <index> to the rating-list entry of <fideID> (a
	// link the user confirmed); nothing is written into the database.
	// Returns 1 when linked, 0 when the player was linked already.
	if (objc != 5)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant> <index> <fideID>");
		return TCL_ERROR;
	}
	char const*		database	= stringFromObj(objc, objv, 1);
	variant::Type	variant	= tcl::game::variantFromObj(objc, objv, 2);
	unsigned			index		= unsignedFromObj(objc, objv, 3);
	Tcl_WideInt		fideID;
	if (Tcl_GetWideIntFromObj(ti, objv[4], &fideID) != TCL_OK)
		return TCL_ERROR;
	Database&		db			= const_cast<Cursor&>(Scidb->cursor(database, variant)).getDatabase();

	if (index >= db.countPlayers())
		return error(CmdLinkPlayer, nullptr, nullptr, "invalid player index %u", index);
	Player* entry = Player::findFidePlayer(uint32_t(fideID));
	if (!entry)
		return error(CmdLinkPlayer, nullptr, nullptr, "no rating-list entry with FIDE ID %lld", (long long)fideID);

	setResult(db.namebases()(Namebase::Player).linkPlayer(index, entry));
	return TCL_OK;
}


static int
cmdPlayerLinks(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	// Usage: ::scidb::db::playerLinks <database> <variant>
	// Each player of the database as {name games linked fideID elo federation entry}:
	// whether the name is linked to a rating-list entry, that entry's FIDE ID
	// (0: none, e.g. a player of the past), the Elo and federation as the
	// games give them, and the entry's name ("" when not linked).
	if (objc != 3)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant>");
		return TCL_ERROR;
	}
	char const*		database	= stringFromObj(objc, objv, 1);
	variant::Type	variant	= tcl::game::variantFromObj(objc, objv, 2);
	Database const&	db		= Scidb->cursor(database, variant).database();

	Tcl_Obj* list = Tcl_NewListObj(0, nullptr);
	for (unsigned i = 0, n = db.countPlayers(); i < n; ++i)
	{
		NamebasePlayer const& p = db.player(i);
		Player const* entry = p.player();
		Tcl_Obj* row[7] =
		{
			Tcl_NewStringObj(p.name(), p.name().size()),
			Tcl_NewIntObj(p.frequency()),
			Tcl_NewBooleanObj(entry != nullptr),
			Tcl_NewWideIntObj(entry ? entry->fideID() : 0),
			Tcl_NewIntObj(p.elo()),
			Tcl_NewStringObj(country::toString(p.federation()), -1),
			entry ? Tcl_NewStringObj(entry->name(), entry->name().size()) : Tcl_NewStringObj("", 0),
		};
		Tcl_ListObjAppendElement(ti, list, Tcl_NewListObj(7, row));
	}
	setResult(list);
	return TCL_OK;
}


static int
cmdFingerprints(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	// Usage: ::scidb::db::fingerprints <database> <variant> ?<old>?
	// A CRC-32 of every game's stored record (start position, moves,
	// comments), as a byte array of 32-bit little-endian words, one per game.
	// Edits that leave the record where it was still change the CRC. With
	// <old> (an earlier result) returns {<fingerprints> <changed>}: <changed>
	// the games below both counts whose record differs. Scidb and Scid
	// formats only (an error otherwise): their codecs read raw records.
	if (objc != 3 && objc != 4)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant> ?<old>?");
		return TCL_ERROR;
	}

	char const*		database	= stringFromObj(objc, objv, 1);
	variant::Type	variant		= tcl::game::variantFromObj(objc, objv, 2);
	Database&		db			= const_cast<Cursor&>(Scidb->cursor(database, variant)).getDatabase();

	if (db.isMemoryOnly() || !(db.format() == format::Scidb || isScidFormat(db.format())))
		return error(CmdFingerprints, nullptr, nullptr, "game records cannot be read from this format");

	unsigned count = db.countGames();
	mstl::vector<unsigned char> bytes(count*4);

	for (unsigned i = 0; i < count; ++i)
	{
		util::ByteStream record = db.codec().getGame(db.gameInfo(i));
		uint32_t crc = util::crc::compute(0, record.data(), record.size());
		bytes[4*i + 0] = crc & 0xff;
		bytes[4*i + 1] = (crc >> 8) & 0xff;
		bytes[4*i + 2] = (crc >> 16) & 0xff;
		bytes[4*i + 3] = (crc >> 24) & 0xff;
	}

	Tcl_Obj* fingerprints = Tcl_NewByteArrayObj(bytes.data(), int(bytes.size()));

	if (objc == 3)
	{
		setResult(fingerprints);
		return TCL_OK;
	}

	int oldLength;
	unsigned char const* old = Tcl_GetByteArrayFromObj(objv[3], &oldLength);
	unsigned common = mstl::min(count, unsigned(oldLength)/4);
	Tcl_Obj* changed = Tcl_NewListObj(0, nullptr);

	for (unsigned i = 0; i < common; ++i)
	{
		if (::memcmp(old + 4*i, bytes.data() + 4*i, 4) != 0)
			Tcl_ListObjAppendElement(ti, changed, Tcl_NewIntObj(i));
	}

	Tcl_Obj* objs[2] = { fingerprints, changed };
	setResult(Tcl_NewListObj(2, objs));
	return TCL_OK;
}


static int
cmdMediaLinkReady(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	// Usage: ::scidb::db::mediaLinkReady <database> <variant> <command>
	// Returns 1 if the game -> report media mapping that mediaFiles and
	// mediaGallery use is built. Otherwise returns 0, builds it in the
	// background, and calls <command> with one more argument: 1 when the
	// mapping is installed, 0 when the database went away meanwhile. A
	// request for another database cancels a pending build; the commands
	// of a cancelled build are never called.
	if (objc != 4)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant> <command>");
		return TCL_ERROR;
	}

	char const*		database	= stringFromObj(objc, objv, 1);
	variant::Type	variant		= tcl::game::variantFromObj(objc, objv, 2);
	Database&		db			= const_cast<Cursor&>(Scidb->cursor(database, variant)).getDatabase();
	MediaLinkJob*	pending		= mediaLinkBuild.job.get();

	bool samePending =	pending
							&& pending->database == database
							&& pending->variant == variant
							&& pending->countGames == db.countGames()
							&& pending->identity == &db;

	if (!samePending)
		cancelMediaLinkBuild();

	if (mediaLinkCache.validFor(database, variant, db.countGames()))
	{
		setResult(true);
		return TCL_OK;
	}

	if (!samePending)
	{
		std::shared_ptr<MediaLinkJob> job =
			std::make_shared<MediaLinkJob>(mstl::string(database), variant, db);

		if (prepareMediaLinks(*job, db, sys::time::timestamp() + SliceTime))
		{
			// A small base: done within one slice, no background build.
			matchMediaLinks(*job);
			installMediaLinks(*job, mediaLinkCache);
			setResult(true);
			return TCL_OK;
		}

		mediaLinkBuild.job = job;
		mediaLinkBuild.interp = ti;
		job->timer = Tcl_CreateTimerHandler(0, mediaLinkSlice, nullptr);
	}

	Tcl_IncrRefCount(objv[3]);
	mediaLinkBuild.callbacks.push_back(objv[3]);
	setResult(false);
	return TCL_OK;
}


static int
cmdMediaGallery(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	// Usage: ::scidb::db::mediaGallery <database> <variant>
	// Returns ALL media entries for the database (not per-game) — the
	// “gallery”. For .scm databases this calls scm::MediaTable::collectAll();
	// for .cbh databases with a .cbm it calls cbh::MediaTable::collectMediaFiles().
	// Returns a list of {path type title mediaId gameIndex} rows. Only media
	// with a resolvable owning game is returned.
	if (objc != 3)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant>");
		return TCL_ERROR;
	}

	char const*		database	= stringFromObj(objc, objv, 1);
	variant::Type	variant		= tcl::game::variantFromObj(objc, objv, 2);

	Cursor const&		cursor	= Scidb->cursor(database, variant);
	Database const&	db		= cursor.database();

	Tcl_Obj* result = Tcl_NewListObj(0, nullptr);

	// Try .scm companion first (scidb-native databases)
	scm::MediaTable const* scmTable = db.scmMediaTable();
	if (scmTable != nullptr && scmTable->isOpen())
	{
		mstl::string dir = ::util::misc::file::dirname(database);
		if (!dir.empty())
		{
			if (dir[dir.size() - 1] != '/')
				dir += '/';
		}

		for (unsigned gameIndex = 0; gameIndex < db.countGames(); ++gameIndex)
		{
			GameInfo const& info = db.gameInfo(gameIndex);
			uint64_t fp = scm::MediaTable::fingerprint(info.playerName(color::White),
				info.playerName(color::Black), info.event(), info.date().asString(),
				info.round(), unsigned(info.result()));
			mstl::vector<scm::MediaTable::Entry> entries;
			scmTable->mediaFor(fp, entries);
			for (unsigned i = 0; i < entries.size(); ++i)
			{
				mstl::string resolved = scmTable->resolvePath(entries[i]);
				if (!entries[i].inlineData && !resolved.empty()
					&& resolved[0] != '/' && resolved[0] != '\\')
					resolved = dir + resolved;

				Tcl_Obj* row[5];
				row[0] = Tcl_NewStringObj(resolved.c_str(), int(resolved.size()));
				row[1] = Tcl_NewIntObj(int(entries[i].type));
				row[2] = Tcl_NewStringObj(entries[i].title.c_str(), int(entries[i].title.size()));
				row[3] = Tcl_NewStringObj(entries[i].mediaId.c_str(), int(entries[i].mediaId.size()));
				row[4] = Tcl_NewIntObj(int(gameIndex));
				Tcl_ListObjAppendElement(ti, result, Tcl_NewListObj(5, row));
			}
		}
	}
	else
	{
		// Try .cbm companion (ChessBase databases)
		// Fallback: read .cbm directly to get the gallery
		mstl::string cbmPath(database);
		// Strip the suffix and add .cbm
		mstl::string base(cbmPath);
		mstl::string::size_type dot = base.rfind('.');
		if (dot != mstl::string::npos)
			base.resize(dot);
		mstl::string mediaPath(base + ".cbm");

		if (sys::file::access(mediaPath, sys::file::Readable))
		{
			mstl::string htmlDir(base + ".html");
			mstl::string dir = ::util::misc::file::dirname(database);
			if (!dir.empty())
			{
				if (dir[dir.size() - 1] != '/')
				dir += '/';
			}

			// Use cbh::MediaTable to parse the .cbm
			cbh::MediaTable cbm;
			util::Progress& progress = util::Progress::null();
			if (cbm.read(base, progress) && cbm.isOpen())
			{
				// The CBM bag index is not a game index. Use the existing
				// guiding-text tag_game cache, which resolves each media file
				// to its owning CBH game.
				if (!mediaLinkCache.validFor(database, variant, db.countGames()))
					buildMediaLinkCache(mstl::string(database), variant,
						const_cast<Database&>(db), mediaLinkCache);
				for (unsigned i = 0; i < mediaLinkCache.rows.size(); ++i)
				{
					GuidingTextMediaRow const& entry = mediaLinkCache.rows[i];
					Tcl_Obj* row[5];
					row[0] = Tcl_NewStringObj(entry.path.c_str(), int(entry.path.size()));
					row[1] = Tcl_NewIntObj(entry.type);
					row[2] = Tcl_NewStringObj(entry.title.c_str(), int(entry.title.size()));
					row[3] = Tcl_NewStringObj("", 0);
					row[4] = Tcl_NewIntObj(int(entry.gameIndex));
					Tcl_ListObjAppendElement(ti, result, Tcl_NewListObj(5, row));
				}
			}
		}
	}

	Tcl_SetObjResult(ti, result);
	return TCL_OK;
}


static int
cmdEcoStats(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 3)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant>");
		return TCL_ERROR;
	}

	char const* database = stringFromObj(objc, objv, 1);
	variant::Type variant = tcl::game::variantFromObj(objc, objv, 2);

	Cursor const& cursor = Scidb->cursor(database, variant);
	Database const& db = cursor.database();
	::db::maintenance::EcoStatsList stats = ::db::maintenance::computeEcoStats(db, variant);

	Tcl_Obj* result = Tcl_NewListObj(0, nullptr);

	for (unsigned i = 0; i < stats.size(); ++i)
	{
		Tcl_Obj* row[5];
		row[0] = Tcl_NewStringObj(stats[i].eco, stats[i].eco.size());
		row[1] = Tcl_NewIntObj(stats[i].total);
		row[2] = Tcl_NewIntObj(stats[i].white);
		row[3] = Tcl_NewIntObj(stats[i].draws);
		row[4] = Tcl_NewIntObj(stats[i].black);
		Tcl_ListObjAppendElement(ti, result, Tcl_NewListObj(5, row));
	}

	Tcl_SetObjResult(ti, result);
	return TCL_OK;
}


static mstl::string
asciiLower(mstl::string const& s)
{
	mstl::string result(s);

	for (unsigned i = 0; i < result.size(); ++i)
		result[i] = ::tolower(static_cast<unsigned char>(result[i]));

	return result;
}


// Players whose name contains <text> (ASCII case-insensitive), most games first:
// {{<player-index> <name> <games> <elo>} ...}
// Who a database player is, by the rating-list entry the name is linked to:
// "fide:<id>", "entry:<name>" for an entry without a FIDE ID, "" when not
// linked. Spellings of one player share it.
static Tcl_Obj*
identityObj(NamebasePlayer const& player)
{
	Player const* entry = player.player();
	if (!entry)
		return Tcl_NewStringObj("", 0);
	if (entry->fideID())
		return Tcl_ObjPrintf("fide:%u", unsigned(entry->fideID()));
	mstl::string id("entry:");
	id += entry->name();
	return Tcl_NewStringObj(id, id.size());
}


static int
cmdFindPlayers(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 4 && objc != 5)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant> <text> ?<maximal>?");
		return TCL_ERROR;
	}

	char const*		database	= stringFromObj(objc, objv, 1);
	variant::Type	variant	= tcl::game::variantFromObj(objc, objv, 2);
	mstl::string	text		= asciiLower(stringFromObj(objc, objv, 3));
	unsigned			maximal	= objc == 5 ? unsignedFromObj(objc, objv, 4) : 10;
	Database const&	db		= Scidb->cursor(database, variant).database();

	mstl::vector<unsigned> found;

	for (unsigned i = 0, n = db.countPlayers(); i < n; ++i)
	{
		NamebasePlayer const& player = db.player(i);

		if (player.frequency() && ::strstr(asciiLower(player.name()), text))
			found.push_back(i);
	}

	// partial selection sort: only the first <maximal> are needed
	unsigned count = mstl::min(maximal, unsigned(found.size()));

	for (unsigned i = 0; i < count; ++i)
	{
		unsigned best = i;

		for (unsigned k = i + 1; k < found.size(); ++k)
		{
			if (db.player(found[k]).frequency() > db.player(found[best]).frequency())
				best = k;
		}

		mstl::swap(found[i], found[best]);
	}

	Tcl_Obj* result = Tcl_NewListObj(0, nullptr);

	for (unsigned i = 0; i < count; ++i)
	{
		NamebasePlayer const& player = db.player(found[i]);
		Tcl_Obj* row[5];

		row[0] = Tcl_NewIntObj(found[i]);
		row[1] = Tcl_NewStringObj(player.name(), player.name().size());
		row[2] = Tcl_NewIntObj(player.frequency());
		row[3] = Tcl_NewIntObj(player.elo());
		row[4] = identityObj(player);
		Tcl_ListObjAppendElement(ti, result, Tcl_NewListObj(5, row));
	}

	Tcl_SetObjResult(ti, result);
	return TCL_OK;
}


static int
cmdPlayerSpellings(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	// Usage: ::scidb::db::playerSpellings <database> <variant> <index>
	// The names of the database's players linked to the same rating-list
	// entry as player <index> (all spellings of one player), most games first;
	// just its own name when it is not linked.
	if (objc != 4)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant> <index>");
		return TCL_ERROR;
	}
	char const*		database	= stringFromObj(objc, objv, 1);
	variant::Type	variant	= tcl::game::variantFromObj(objc, objv, 2);
	unsigned			index		= unsignedFromObj(objc, objv, 3);
	Database const&	db		= Scidb->cursor(database, variant).database();

	if (index >= db.countPlayers())
		return error(CmdPlayerSpellings, nullptr, nullptr, "invalid player index %u", index);

	Player const* entry = db.player(index).player();
	mstl::vector<unsigned> found;
	if (!entry)
	{
		found.push_back(index);
	}
	else
	{
		for (unsigned i = 0, n = db.countPlayers(); i < n; ++i)
		{
			NamebasePlayer const& p = db.player(i);
			if (p.player() == entry && (p.frequency() || i == index))
				found.push_back(i);
		}
	}
	for (unsigned i = 0; i < found.size(); ++i)
	{
		for (unsigned k = i + 1; k < found.size(); ++k)
		{
			if (db.player(found[k]).frequency() > db.player(found[i]).frequency())
				mstl::swap(found[i], found[k]);
		}
	}
	Tcl_Obj* names = Tcl_NewListObj(0, nullptr);
	for (unsigned i = 0; i < found.size(); ++i)
	{
		mstl::string const& name = db.player(found[i]).name();
		Tcl_ListObjAppendElement(ti, names, Tcl_NewStringObj(name, name.size()));
	}
	setResult(names);
	return TCL_OK;
}


// Results of the standard-chess games whose ECO code lies in <from>..<to>:
//   {<games> <white-wins> <draws> <black-wins>}
// With <player-index>, only that player's games, from the player's side:
//   {<games> {<white: win draw loss>} {<black: win draw loss>}}
static int
cmdOpeningScore(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 5 && objc != 6)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant> <eco-from> <eco-to> ?<player-index>?");
		return TCL_ERROR;
	}

	char const*		database	= stringFromObj(objc, objv, 1);
	variant::Type	variant	= tcl::game::variantFromObj(objc, objv, 2);
	uint16_t			from		= Eco::toShort(stringFromObj(objc, objv, 3));
	uint16_t			to			= Eco::toShort(stringFromObj(objc, objv, 4));
	Database const&	db		= Scidb->cursor(database, variant).database();

	if (!from || !to || to < from)
		return error(CmdOpeningScore, nullptr, nullptr, "invalid ECO range");

	NamebasePlayer const* player = nullptr;

	if (objc == 6)
	{
		unsigned index = unsignedFromObj(objc, objv, 5);

		if (index >= db.countPlayers())
			return error(CmdOpeningScore, nullptr, nullptr, "invalid player index");

		player = &db.player(index);
	}

	unsigned games = 0;
	unsigned score[2][4];	// [color][result::ID]: side-to-colour results
	memset(score, 0, sizeof(score));

	if (db.variant() == variant::Normal)
	{
		for (unsigned i = 0, n = db.countGames(); i < n; ++i)
		{
			GameInfo const& info = db.gameInfo(i);

			// NOTE: in .si4 databases the ECO code may be undefined.
			if (info.idn() != variant::Standard)
				continue;

			uint16_t eco = info.eco(variant::Normal).toShort();

			if (eco < from || to < eco)
				continue;

			result::ID result = info.result();
			unsigned side = color::White;

			if (player)
			{
				if (info.playerEntry(color::Black) == player)
					side = color::Black;
				else if (info.playerEntry(color::White) != player)
					continue;
			}

			++games;

			if (result <= result::Draw)
				++score[side][result];
		}
	}

	Tcl_Obj* objs[3];

	if (player)
	{
		for (unsigned side = 0; side < 2; ++side)
		{
			result::ID win  = side == color::White ? result::White : result::Black;
			result::ID loss = side == color::White ? result::Black : result::White;
			Tcl_Obj* wdl[3];

			wdl[0] = Tcl_NewIntObj(score[side][win]);
			wdl[1] = Tcl_NewIntObj(score[side][result::Draw]);
			wdl[2] = Tcl_NewIntObj(score[side][loss]);
			objs[side + 1] = Tcl_NewListObj(3, wdl);
		}

		objs[0] = Tcl_NewIntObj(games);
		setResult(3, objs);
	}
	else
	{
		Tcl_Obj* row[4];

		row[0] = Tcl_NewIntObj(games);
		row[1] = Tcl_NewIntObj(score[color::White][result::White]);
		row[2] = Tcl_NewIntObj(score[color::White][result::Draw]);
		row[3] = Tcl_NewIntObj(score[color::White][result::Black]);
		setResult(4, row);
	}

	return TCL_OK;
}


static NamebasePlayer const*
playerFromObj(Database const& db, int objc, Tcl_Obj* const objv[], unsigned index)
{
	unsigned player = unsignedFromObj(objc, objv, index);
	return player < db.countPlayers() ? &db.player(player) : nullptr;
}


// A player's standard-chess openings by ECO code, from the player's side,
// most played first: {<as-white> <as-black>}, each {{<eco> <games> <win> <draw> <loss>} ...}
static int
cmdPlayerOpenings(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 4)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant> <player-index>");
		return TCL_ERROR;
	}

	char const*		database	= stringFromObj(objc, objv, 1);
	variant::Type	variant	= tcl::game::variantFromObj(objc, objv, 2);
	Database const&	db		= Scidb->cursor(database, variant).database();
	NamebasePlayer const* player = playerFromObj(db, objc, objv, 3);

	if (!player)
		return error(CmdPlayerOpenings, nullptr, nullptr, "invalid player index");

	enum { NumCodes = 5*10*10 + 1, Games = 0, Win, Draw, Loss };
	mstl::vector<unsigned> counts[2];
	counts[0].resize(NumCodes*4, 0);
	counts[1].resize(NumCodes*4, 0);

	if (db.variant() == variant::Normal)
	{
		for (unsigned i = 0, n = db.countGames(); i < n; ++i)
		{
			GameInfo const& info = db.gameInfo(i);
			unsigned side;

			if (info.playerEntry(color::White) == player)
				side = color::White;
			else if (info.playerEntry(color::Black) == player)
				side = color::Black;
			else
				continue;

			// NOTE: in .si4 databases the ECO code may be undefined.
			if (info.idn() != variant::Standard)
				continue;

			uint16_t eco = info.eco(variant::Normal).toShort();

			if (eco == 0 || eco >= NumCodes)
				continue;

			unsigned* c = &counts[side][eco*4];
			result::ID won = side == color::White ? result::White : result::Black;

			++c[Games];

			if (info.result() == won)
				++c[Win];
			else if (info.result() == result::Draw)
				++c[Draw];
			else if (info.result() == result::White || info.result() == result::Black)
				++c[Loss];
		}
	}

	Tcl_Obj* sides[2];

	for (unsigned side = 0; side < 2; ++side)
	{
		mstl::vector<unsigned> codes;

		for (unsigned eco = 1; eco < NumCodes; ++eco)
		{
			if (counts[side][eco*4 + Games])
				codes.push_back(eco);
		}

		// insertion sort by games, descending; at most 500 codes
		for (unsigned i = 1; i < codes.size(); ++i)
		{
			for (unsigned k = i; k > 0 && counts[side][codes[k]*4] > counts[side][codes[k - 1]*4]; --k)
				mstl::swap(codes[k], codes[k - 1]);
		}

		sides[side] = Tcl_NewListObj(0, nullptr);

		for (unsigned i = 0; i < codes.size(); ++i)
		{
			unsigned const* c = &counts[side][codes[i]*4];
			mstl::string eco(Eco::fromShort(codes[i]).asShortString());
			Tcl_Obj* row[5];

			row[0] = Tcl_NewStringObj(eco, eco.size());
			row[1] = Tcl_NewIntObj(c[Games]);
			row[2] = Tcl_NewIntObj(c[Win]);
			row[3] = Tcl_NewIntObj(c[Draw]);
			row[4] = Tcl_NewIntObj(c[Loss]);
			Tcl_ListObjAppendElement(ti, sides[side], Tcl_NewListObj(5, row));
		}
	}

	setResult(2, sides);
	return TCL_OK;
}


// A player's latest games, newest first:
// {{<game-index> <date> <colour> <opponent> <opponent-elo> <result> <eco> <event>} ...}
static int
cmdPlayerGames(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 4 && objc != 5)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant> <player-index> ?<maximal>?");
		return TCL_ERROR;
	}

	char const*		database	= stringFromObj(objc, objv, 1);
	variant::Type	variant	= tcl::game::variantFromObj(objc, objv, 2);
	unsigned			maximal	= objc == 5 ? unsignedFromObj(objc, objv, 4) : 10;
	Database const&	db		= Scidb->cursor(database, variant).database();
	NamebasePlayer const* player = playerFromObj(db, objc, objv, 3);

	if (!player)
		return error(CmdPlayerGames, nullptr, nullptr, "invalid player index");

	mstl::vector<unsigned> found;

	for (unsigned i = 0, n = db.countGames(); i < n; ++i)
	{
		GameInfo const& info = db.gameInfo(i);

		if (info.playerEntry(color::White) == player || info.playerEntry(color::Black) == player)
			found.push_back(i);
	}

	// partial selection sort: only the newest <maximal> are needed
	unsigned count = mstl::min(maximal, unsigned(found.size()));

	for (unsigned i = 0; i < count; ++i)
	{
		unsigned best = i;

		for (unsigned k = i + 1; k < found.size(); ++k)
		{
			if (db.gameInfo(found[best]).date() < db.gameInfo(found[k]).date())
				best = k;
		}

		mstl::swap(found[i], found[best]);
	}

	Tcl_Obj* result = Tcl_NewListObj(0, nullptr);

	for (unsigned i = 0; i < count; ++i)
	{
		GameInfo const& info = db.gameInfo(found[i]);
		color::ID side = info.playerEntry(color::White) == player ? color::White : color::Black;
		color::ID other = color::opposite(side);
		mstl::string date(info.date().asString());
		mstl::string eco(info.eco(variant::Normal).asShortString());
		mstl::string const& opponent = info.playerName(other);
		mstl::string const& res = result::toString(info.result());
		Tcl_Obj* row[8];

		row[0] = Tcl_NewIntObj(found[i]);
		row[1] = Tcl_NewStringObj(date, date.size());
		row[2] = Tcl_NewStringObj(side == color::White ? "white" : "black", -1);
		row[3] = Tcl_NewStringObj(opponent, opponent.size());
		row[4] = Tcl_NewIntObj(info.elo(other));
		row[5] = Tcl_NewStringObj(res, res.size());
		row[6] = Tcl_NewStringObj(eco, eco.size());
		row[7] = Tcl_NewStringObj(info.event(), info.event().size());
		Tcl_ListObjAppendElement(ti, result, Tcl_NewListObj(8, row));
	}

	Tcl_SetObjResult(ti, result);
	return TCL_OK;
}


namespace tcl {
namespace db {

void
init(Tcl_Interp* ti)
{
	createCommand(ti, CmdAttach,			cmdAttach);
	createCommand(ti, CmdClear,			cmdClear);
	createCommand(ti, CmdClose,			cmdClose);
	createCommand(ti, CmdCompact,			cmdCompact);
	createCommand(ti, CmdCopy,				cmdCopy);
	createCommand(ti, CmdCount,			cmdCount);
	createCommand(ti, CmdFetch,			cmdFetch);
	createCommand(ti, CmdFind,				cmdFind);
	createCommand(ti, CmdImport,			cmdImport);
	createCommand(ti, CmdLoad,				cmdLoad);
	createCommand(ti, CmdNew,				cmdNew);
	createCommand(ti, "::scidb::db::setcreationversion",	cmdSetCreationVersion);
	createCommand(ti, "::scidb::db::creationversion",		cmdGetCreationVersion);
	createCommand(ti, CmdSet,				cmdSet);
	createCommand(ti, CmdGet,				cmdGet);
	createCommand(ti, CmdMatch,			cmdMatch);
	createCommand(ti, CmdOpen,				cmdOpen);
	createCommand(ti, CmdPlayerCard,		cmdPlayerCard);
	createCommand(ti, CmdPlayerInfo,		cmdPlayerInfo);
	createCommand(ti, CmdRecode,			cmdRecode);
	createCommand(ti, CmdReverse,			cmdReverse);
	createCommand(ti, CmdSave,				cmdSave);
	createCommand(ti, CmdSavePGN,			cmdSavePGN);
	createCommand(ti, CmdSort,				cmdSort);
	createCommand(ti, CmdSubscribe,		cmdSubscribe);
	createCommand(ti, CmdSwitch,			cmdSwitch);
	createCommand(ti, CmdUnsubscribe,	cmdUnsubscribe);
	createCommand(ti, CmdUpdate,			cmdUpdate);
	createCommand(ti, CmdUpgrade,			cmdUpgrade);
	createCommand(ti, CmdWrite,				cmdWrite);
	createCommand(ti, "::scidb::db::similar", cmdSimilar);
	createCommand(ti, CmdFindDuplicates,	cmdFindDuplicates);
	createCommand(ti, CmdEcoStats,			cmdEcoStats);
	createCommand(ti, CmdFindPlayers,		cmdFindPlayers);
	createCommand(ti, CmdPlayerSpellings,	cmdPlayerSpellings);
	createCommand(ti, CmdOpeningScore,		cmdOpeningScore);
	createCommand(ti, CmdPlayerOpenings,	cmdPlayerOpenings);
	createCommand(ti, CmdPlayerGames,		cmdPlayerGames);
	createCommand(ti, CmdMediaFiles,		cmdMediaFiles);
	createCommand(ti, CmdMediaGallery,	cmdMediaGallery);
	createCommand(ti, CmdMediaLinkReady,	cmdMediaLinkReady);
	createCommand(ti, CmdFingerprints,		cmdFingerprints);
	createCommand(ti, CmdPlayerLinks,		cmdPlayerLinks);
	createCommand(ti, CmdSpellingCandidates,	cmdSpellingCandidates);
	createCommand(ti, CmdLinkPlayer,		cmdLinkPlayer);
	createCommand(ti, CmdLinkPlayers,		cmdLinkPlayers);

	{
		std::lock_guard<std::mutex> lock(mediaLinkOwner.mutex);
		mediaLinkOwner.alive = true;
		mediaLinkOwner.thread = Tcl_GetCurrentThread();
	}
	Tcl_CreateExitHandler(stopMediaLinkBuilds, nullptr);
	createCommand(ti, CmdGuidingText,	cmdGuidingText);
	createCommand(ti, CmdGameAnchor,		cmdGameAnchor);
	createCommand(ti, CmdHtmlSanitize,	cmdHtmlSanitize);
	createCommand(ti, CmdMarkDeleted,		cmdMarkDeleted);
}

} // namespace db
} // namespace tcl

// vi:set ts=3 sw=3:
