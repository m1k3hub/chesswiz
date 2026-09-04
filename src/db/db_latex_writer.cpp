// ======================================================================
// Author : $Author$
// Version: $Revision: 1085 $
// Date   : $Date: 2016-02-29 12:11:08 -0500 (Mon, 29 Feb 2016) $
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
// Copyright: (C) 2011-2013 Gregor Cramer
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#include "db_latex_writer.h"
#include "db_tag_set.h"

#include "T_ListToken.h"
#include "T_MacroToken.h"

#include "T_Environment.h"

using namespace db;
using namespace TeXt;


namespace {

// The print script defines the game header/result macros with \def; such
// bindings live in the environment's domain lists, while the token handles
// created by Environment::newUndefinedToken() refer to the (still undefined)
// root slots. Moreover macro expansion is producer-driven: it happens while
// the interpreter pumps getFinalToken()/execute() over the producer stack,
// which is not running outside Controller::processInput(). So the macro is
// resolved through the domain chain, its producer is pushed, and the parser
// loop is pumped until the producer stack is drained again (the consumer
// set up by the last processInput() call persists).
void
expandGameMacro(Environment& env, TokenP const& handle)
{
	TokenP macro = env.lookupMacro(handle->refID());

	if (!macro || !macro->isBound())
		return;

	env.pushProducer(Environment::ProducerP(new MacroToken::TokenProducer(macro)));

	try
	{
		while (TokenP token = env.getFinalToken(Environment::AllowNull))
			env.execute(token);
	}
	catch (Token::AbortException const&)
	{
	}
	catch (Token::EmergencyStopException const&)
	{
	}
	catch (Token::UnexpectedEndOfInputException const&)
	{
	}
	catch (Token::BreakExecutionException const&)
	{
	}
}

}

LaTeXWriter::LaTeXWriter(	format::Type srcFormat,
									unsigned flags,
									unsigned options,
									NagMap const& nagMap,
									Languages const* languages,
									unsigned significantLanguages,
									Environment& env)
	:DocumentWriter(srcFormat, flags, options, nagMap, languages, significantLanguages)
	,m_env(env)
	,m_printHeader(env.newUndefinedToken("\\print-game-header"))
	,m_printResult(env.newUndefinedToken("\\print-game-result"))
	,m_printFooter(env.newUndefinedToken("\\print-footer"))
	,m_white(env.newUndefinedToken("\\White"))
	,m_black(env.newUndefinedToken("\\Black"))
	,m_whiteCountry(env.newUndefinedToken("\\WhiteCountry"))
	,m_blackCountry(env.newUndefinedToken("\\BlackCountry"))
	,m_whiteTitle(env.newUndefinedToken("\\WhiteTitle"))
	,m_blackTitle(env.newUndefinedToken("\\BlackTitle"))
	,m_whiteElo(env.newUndefinedToken("\\WhiteElo"))
	,m_blackElo(env.newUndefinedToken("\\BlackElo"))
	,m_whiteIPS(env.newUndefinedToken("\\WhiteIPS"))
	,m_blackIPS(env.newUndefinedToken("\\BlackIPS"))
	,m_result(env.newUndefinedToken("\\Result"))
	,m_event(env.newUndefinedToken("\\Event"))
	,m_site(env.newUndefinedToken("\\Site"))
	,m_date(env.newUndefinedToken("\\Date"))
	,m_eventCountry(env.newUndefinedToken("\\EventCountry"))
	,m_eco(env.newUndefinedToken("\\Eco"))
	,m_idn(env.newUndefinedToken("\\Idn"))
	,m_fen(env.newUndefinedToken("\\Fen"))
	,m_annotator(env.newUndefinedToken("\\Annotator"))
{
}


LaTeXWriter::~LaTeXWriter() throw()
{
	// gcc is complaining w/o this destructor
}


format::Type
LaTeXWriter::format() const
{
	return format::LaTeX;
}


bool
LaTeXWriter::beginGame(TagSet const& tags)
{
	m_env.bindMacro(m_white, 			tags.value(tag::White));
	m_env.bindMacro(m_black, 			tags.value(tag::Black));
	m_env.bindMacro(m_whiteCountry,	tags.value(tag::WhiteCountry));
	m_env.bindMacro(m_blackCountry,	tags.value(tag::BlackCountry));
	m_env.bindMacro(m_whiteTitle,		tags.value(tag::WhiteTitle));
	m_env.bindMacro(m_blackTitle,		tags.value(tag::BlackTitle));
	m_env.bindMacro(m_whiteElo,		tags.value(tag::WhiteElo));
	m_env.bindMacro(m_blackElo,		tags.value(tag::BlackElo));
	m_env.bindMacro(m_whiteIPS,		tags.value(tag::WhiteIPS));
	m_env.bindMacro(m_blackIPS,		tags.value(tag::BlackIPS));
	m_env.bindMacro(m_result,			tags.value(tag::Result));
	m_env.bindMacro(m_event,			tags.value(tag::Event));
	m_env.bindMacro(m_eventCountry,	tags.value(tag::EventCountry));
	m_env.bindMacro(m_site,				tags.value(tag::Site));
	m_env.bindMacro(m_date,				tags.value(tag::Date));
	m_env.bindMacro(m_eco,				tags.value(tag::Eco));
	m_env.bindMacro(m_idn,				tags.value(tag::Idn));
	m_env.bindMacro(m_fen,				tags.value(tag::Fen));
	m_env.bindMacro(m_annotator,		tags.value(tag::Annotator));

	expandGameMacro(m_env, m_printHeader);

	return true;
}


save::State
LaTeXWriter::endGame(TagSet const& tags)
{
	expandGameMacro(m_env, m_printResult);
	expandGameMacro(m_env, m_printFooter);
	return save::Ok;
}

// vi:set ts=3 sw=3:
