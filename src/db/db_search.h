// ======================================================================
// Author : $Author$
// Version: $Revision: 1453 $
// Date   : $Date: 2017-12-11 09:27:52 -0500 (Mon, 11 Dec 2017) $
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
// Copyright: (C) 2009-2017 Gregor Cramer
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#ifndef _db_search_included
#define _db_search_included

#include "db_common.h"
#include "db_date.h"

#include "u_match.h"

#include "m_string.h"
#include "m_ref_counter.h"
#include "m_ref_counted_ptr.h"
#include "m_vector.h"

namespace db {

class GameInfo;
class NamebasePlayer;
class NamebaseEvent;
class NamebaseSite;
class NamebaseAnnotator;

class Search : public mstl::ref_counter
{
public:

	virtual ~Search() throw() = 0;
	virtual bool match(GameInfo const& info) const = 0;
};

class SearchOpAnd : public Search
{
public:

	typedef mstl::ref_counted_ptr<Search> SearchP;

	bool match(GameInfo const& info) const override;
	void append(Search* search);

private:

	mstl::vector<SearchP> m_searches;
};

class SearchOpOr : public Search
{
public:

	typedef mstl::ref_counted_ptr<Search> SearchP;

	bool match(GameInfo const& info) const override;
	void append(Search* search);

private:

	mstl::vector<SearchP> m_searches;
};

class SearchOpNot : public Search
{
public:

	typedef mstl::ref_counted_ptr<Search> SearchP;

	SearchOpNot(SearchP const& search);
	~SearchOpNot() throw();

#if HAVE_C11_MOVE_CONSTRCUTOR_AND_ASSIGMENT_OPERATOR
	SearchOpNot(SearchOpNot&& search);
	SearchOpNot& operator=(SearchOpNot&& search);
#endif

	bool match(GameInfo const& info) const override;

private:

	SearchP m_search;
};

class SearchPlayer : public Search
{
public:

	SearchPlayer(NamebasePlayer const* entry);

	bool match(GameInfo const& info) const override;

private:

	NamebasePlayer const* m_entry;
};

class SearchEvent : public Search
{
public:

	SearchEvent(NamebaseEvent const* entry);

	bool match(GameInfo const& info) const override;

private:

	NamebaseEvent const* m_entry;
};

class SearchGameEvent : public Search
{
public:

	SearchGameEvent(NamebaseEvent const* entry, Date const& gameDate);

	bool match(GameInfo const& info) const override;

private:

	NamebaseEvent const* m_entry;
	Date m_firstDate;
	Date m_lastDate;
};

class SearchSite : public Search
{
public:

	SearchSite(NamebaseSite const* entry);

	bool match(GameInfo const& info) const override;

private:

	NamebaseSite const* m_entry;
};

class SearchAnnotator : public Search
{
public:

	SearchAnnotator(mstl::string const& name);

	bool match(GameInfo const& info) const override;

private:

	mstl::string m_name;
};

class SearchPosition : public Search
{
public:

	SearchPosition(uint16_t idn);

	bool match(GameInfo const& info) const override;

private:

	uint16_t m_idn;
};

class SearchPlayerName : public Search
{
public:

	enum Mode
	{
		White,
		Black,
		Any,
	};

	SearchPlayerName(Mode mode, mstl::string const& name, bool exact = false);

	bool match(GameInfo const& info) const override;

private:

	Mode m_mode;
	bool m_exact;
	util::Pattern m_name;
};

class SearchEventName : public Search
{
public:

	SearchEventName(mstl::string const& name, bool exact = false);

	bool match(GameInfo const& info) const override;

private:

	bool m_exact;
	util::Pattern m_name;
};

class SearchSiteName : public Search
{
public:

	SearchSiteName(mstl::string const& name, bool exact = false);

	bool match(GameInfo const& info) const override;

private:

	bool m_exact;
	util::Pattern m_name;
};

class SearchAnnotatorName : public Search
{
public:

	SearchAnnotatorName(mstl::string const& name, bool exact = false);

	bool match(GameInfo const& info) const override;

private:

	bool m_exact;
	util::Pattern m_name;
};

class SearchEco : public Search
{
public:

	SearchEco(mstl::string const& eco, variant::Type variant);

	bool match(GameInfo const& info) const override;

private:

	mstl::string m_eco;
	variant::Type m_variant;
};

/// ECO codes from..to, by their basic three-character code.
class SearchEcoRange : public Search
{
public:

	SearchEcoRange(uint16_t from, uint16_t to, variant::Type variant);

	bool match(GameInfo const& info) const override;

private:

	uint16_t m_from;
	uint16_t m_to;
	variant::Type m_variant;
};

/// Dates as keys year*10000 + month*100 + day; a game without a year never matches.
class SearchDate : public Search
{
public:

	SearchDate(unsigned from, unsigned to);

	bool match(GameInfo const& info) const override;

private:

	unsigned m_from;
	unsigned m_to;
};

class SearchResult : public Search
{
public:

	SearchResult(result::ID result);

	bool match(GameInfo const& info) const override;

private:

	result::ID m_result;
};

class SearchMaterial : public Search
{
public:

	SearchMaterial(material::si3::Signature signature);

	bool match(GameInfo const& info) const override;

private:

	material::si3::Signature m_signature;
};

class SearchMaterialClass : public Search
{
public:

	SearchMaterialClass(material::si3::Signature signature);

	bool match(GameInfo const& info) const override;

private:

	unsigned m_whiteMajor;
	unsigned m_whiteMinor;
	unsigned m_blackMajor;
	unsigned m_blackMinor;
};

class SearchMaterialPawns : public Search
{
public:

	SearchMaterialPawns(unsigned whiteMin, unsigned whiteMax, unsigned blackMin, unsigned blackMax);

	bool match(GameInfo const& info) const override;

private:

	unsigned m_whiteMin;
	unsigned m_whiteMax;
	unsigned m_blackMin;
	unsigned m_blackMax;
};

class SearchRating : public Search
{
public:

	enum Mode
	{
		White,
		Black,
		Average,
		Both,
	};

	SearchRating(rating::Type type,
					Mode mode,
					unsigned minRatingW,
					unsigned maxRatingW,
					unsigned minRatingB = 0,
					unsigned maxRatingB = 0);

	bool match(GameInfo const& info) const override;

private:

	rating::Type m_type;
	Mode m_mode;
	unsigned m_minW;
	unsigned m_maxW;
	unsigned m_minB;
	unsigned m_maxB;
};

} // namespace db

#endif // _db_search_included

// vi:set ts=3 sw=3:
