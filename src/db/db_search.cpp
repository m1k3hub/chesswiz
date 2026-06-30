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
// Copyright: (C) 2009-2013 Gregor Cramer
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#include "db_search.h"
#include "db_game_info.h"
#include "db_namebase_entry.h"

#include "m_utility.h"
#include "m_assert.h"

using namespace db;


Search::~Search() throw() {}
SearchOpNot::~SearchOpNot() throw() {}

void
SearchOpAnd::append(Search* search)
{
	M_REQUIRE(search);
	m_searches.push_back(SearchP(search));
}


void
SearchOpOr::append(Search* search)
{
	M_REQUIRE(search);
	m_searches.push_back(SearchP(search));
}


bool
SearchOpAnd::match(GameInfo const& info) const
{
	for (unsigned i = 0; i < m_searches.size(); ++i)
	{
		if (!m_searches[i]->match(info))
			return false;
	}

	return !m_searches.empty();
}


bool
SearchOpOr::match(GameInfo const& info) const
{
	for (unsigned i = 0; i < m_searches.size(); ++i)
	{
		if (m_searches[i]->match(info))
			return true;
	}

	return false;
}

SearchPlayer::SearchPlayer(NamebasePlayer const* entry) :m_entry(entry) {}
SearchEvent::SearchEvent(NamebaseEvent const* entry) :m_entry(entry) {}
SearchSite::SearchSite(NamebaseSite const* entry) :m_entry(entry) {}
SearchOpNot::SearchOpNot(SearchP const& search) :m_search(search) { M_REQUIRE(search); }
SearchAnnotator::SearchAnnotator(mstl::string const& name) :m_name(name) {}
SearchPosition::SearchPosition(uint16_t idn) :m_idn(idn) {}
SearchPlayerName::SearchPlayerName(Mode mode, mstl::string const& name, bool exact)
	:m_mode(mode)
	,m_exact(exact)
	,m_name(name)
{
}
SearchEventName::SearchEventName(mstl::string const& name, bool exact)
	:m_exact(exact)
	,m_name(name)
{
}
SearchSiteName::SearchSiteName(mstl::string const& name, bool exact)
	:m_exact(exact)
	,m_name(name)
{
}
SearchAnnotatorName::SearchAnnotatorName(mstl::string const& name, bool exact)
	:m_exact(exact)
	,m_name(name)
{
}
SearchEco::SearchEco(mstl::string const& eco, variant::Type variant)
	:m_eco(eco)
	,m_variant(variant)
{
}
SearchMaterial::SearchMaterial(material::si3::Signature signature) :m_signature(signature) {}
SearchMaterialClass::SearchMaterialClass(material::si3::Signature signature)
	:m_whiteMajor(signature.wq + signature.wr)
	,m_whiteMinor(signature.wb + signature.wn)
	,m_blackMajor(signature.bq + signature.br)
	,m_blackMinor(signature.bb + signature.bn)
{
}
SearchMaterialPawns::SearchMaterialPawns(unsigned whiteMin, unsigned whiteMax, unsigned blackMin, unsigned blackMax)
	:m_whiteMin(whiteMin)
	,m_whiteMax(whiteMax)
	,m_blackMin(blackMin)
	,m_blackMax(blackMax)
{
}
SearchRating::SearchRating(rating::Type type,
									Mode mode,
									unsigned minRatingW,
									unsigned maxRatingW,
									unsigned minRatingB,
									unsigned maxRatingB)
	:m_type(type)
	,m_mode(mode)
	,m_minW(minRatingW)
	,m_maxW(maxRatingW)
	,m_minB(minRatingB)
	,m_maxB(maxRatingB)
{
}


#if HAVE_C11_MOVE_CONSTRCUTOR_AND_ASSIGMENT_OPERATOR

# include "m_utility.h"

SearchOpNot::SearchOpNot(SearchOpNot&& search)
	:m_search(mstl::move(search.m_search))
{
}


SearchOpNot&
SearchOpNot::operator=(SearchOpNot&& search)
{
	m_search = mstl::move(search.m_search);
	return *this;
}

#endif


bool
SearchOpNot::match(GameInfo const& info) const
{
	return !m_search->match(info);
}


bool
SearchPlayer::match(GameInfo const& info) const
{
	return info.playerEntry(color::White) == m_entry || info.playerEntry(color::Black) == m_entry;
}


bool
SearchEvent::match(GameInfo const& info) const
{
	return info.eventEntry() == m_entry;
}


SearchGameEvent::SearchGameEvent(NamebaseEvent const* entry, Date const& date)
	:m_entry(entry)
	,m_firstDate(date)
	,m_lastDate(date)
{
	if (date.month())
	{
		int y1 = date.year();
		int y2 = y1;
		int m1 = int(date.month()) - 3;
		int m2 = int(date.month()) + 3;

		if (m1 <= 0)
		{
			m1 += 12;
			--y1;
		}

		if (m2 > 12)
		{
			m2 -= 12;
			++y2;
		}

		int d1 = mstl::min(date.day(), Date::lastDayInMonth(y1, m1));
		int d2 = mstl::min(date.day(), Date::lastDayInMonth(y2, m2));

		m_firstDate.setYMD(mstl::max(y1, int(Date::MinYear)), m1, d1);
		m_lastDate .setYMD(mstl::min(y2, int(Date::MaxYear)), m2, d2);
	}
}


bool
SearchGameEvent::match(GameInfo const& info) const
{
	if (info.eventEntry() != m_entry)
		return false;

	if (m_entry->date())
		return true;

	if (!info.date())
		return !m_firstDate;

	return m_firstDate <= info.date() && info.date() <= m_lastDate;
}


bool
SearchSite::match(GameInfo const& info) const
{
	return info.eventEntry()->site() == m_entry;
}


bool
SearchAnnotator::match(GameInfo const& info) const
{
	return info.annotator() == m_name;
}


bool
SearchPosition::match(GameInfo const& info) const
{
	return info.idn() == m_idn;
}


bool
SearchPlayerName::match(GameInfo const& info) const
{
	char const* white = info.playerName(color::White);
	char const* black = info.playerName(color::Black);

	if (m_exact)
	{
		switch (m_mode)
		{
			case White: return ::strcasecmp(white, m_name.content()) == 0;
			case Black: return ::strcasecmp(black, m_name.content()) == 0;
			case Any:   return ::strcasecmp(white, m_name.content()) == 0
							 || ::strcasecmp(black, m_name.content()) == 0;
		}
	}

	switch (m_mode)
	{
		case White: return m_name.match(white);
		case Black: return m_name.match(black);
		case Any:
			return	m_name.match(white)
				||	m_name.match(black);
	}

	return false;
}


bool
SearchEventName::match(GameInfo const& info) const
{
	if (m_exact)
		return ::strcasecmp(info.event(), m_name.content()) == 0;
	return m_name.match(info.event());
}


bool
SearchSiteName::match(GameInfo const& info) const
{
	if (m_exact)
		return ::strcasecmp(info.site(), m_name.content()) == 0;
	return m_name.match(info.site());
}


bool
SearchAnnotatorName::match(GameInfo const& info) const
{
	if (m_exact)
		return ::strcasecmp(info.annotator(), m_name.content()) == 0;
	return m_name.match(info.annotator());
}


bool
SearchEco::match(GameInfo const& info) const
{
	return ::strcasecmp(info.eco(m_variant).asShortString(), m_eco) == 0;
}


bool
SearchMaterial::match(GameInfo const& info) const
{
	return info.material().u32 == m_signature.u32;
}


bool
SearchMaterialClass::match(GameInfo const& info) const
{
	material::si3::Signature sig = info.material();
	unsigned whiteMajor = unsigned(sig.wq + sig.wr);
	unsigned whiteMinor = unsigned(sig.wb + sig.wn);
	unsigned blackMajor = unsigned(sig.bq + sig.br);
	unsigned blackMinor = unsigned(sig.bb + sig.bn);

	return whiteMajor == m_whiteMajor
		&& whiteMinor == m_whiteMinor
		&& blackMajor == m_blackMajor
		&& blackMinor == m_blackMinor;
}


bool
SearchMaterialPawns::match(GameInfo const& info) const
{
	material::si3::Signature sig = info.material();

	return m_whiteMin <= sig.wp && sig.wp <= m_whiteMax
		&& m_blackMin <= sig.bp && sig.bp <= m_blackMax;
}


bool
SearchRating::match(GameInfo const& info) const
{
	unsigned white = info.findRating(color::White, m_type);
	unsigned black = info.findRating(color::Black, m_type);

	switch (m_mode)
	{
		case White:
			return m_minW <= white && white <= m_maxW;

		case Black:
			return m_minB <= black && black <= m_maxB;

		case Average:
		{
			if (white == 0 || black == 0)
				return false;

			// Round half up: (white + black + 1)/2 rounds up for odd sums.
			// This matches the UI's display rounding behavior.
			unsigned average = (white + black + 1)/2;
			return m_minW <= average && average <= m_maxW;
		}

		case Both:
			return m_minW <= white && white <= m_maxW
				&& m_minB <= black && black <= m_maxB;
	}

	return false;
}

// vi:set ts=3 sw=3:
