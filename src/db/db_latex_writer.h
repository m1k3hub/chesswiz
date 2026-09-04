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

#ifndef _db_latex_writer_included
#define _db_latex_writer_included

#include "db_document_writer.h"

#include "T_TokenP.h"

namespace TeXt { class Environment; }

namespace db {

class LaTeXWriter : public DocumentWriter
{
public:

	LaTeXWriter(format::Type srcFormat,
					unsigned flags,
					unsigned options,
					NagMap const& nagMap,
					Languages const* languages,
					unsigned significantLanguages,
					TeXt::Environment& env);
	~LaTeXWriter() throw();

	void finish() override;

	format::Type format() const override;

private:

	void writeBeginMoveSection() override;
	void writeEndMoveSection(result::ID result) override;
	void writeMove(	Move const& move,
						mstl::string const& moveNumber,
						Annotation const& annotation,
						MarkSet const& marks,
						Comment const& preComment,
						Comment const& comment) override;
	void writeBeginVariation(unsigned level) override;
	void writeEndVariation(unsigned level) override;
	void writePrecedingComment(	Annotation const& annotation,
										Comment const& comment,
										MarkSet const& marks) override;
	void writeTrailingComment(Comment const& comment) override;

	void flushMoveBuffer();


	bool beginGame(TagSet const& tags) override;
	save::State endGame(TagSet const& tags) override;


	TeXt::Environment&	m_env;
	TeXt::TokenP			m_printHeader;
	TeXt::TokenP			m_printResult;
	TeXt::TokenP			m_printFooter;
	TeXt::TokenP			m_white;
	TeXt::TokenP			m_black;
	TeXt::TokenP			m_whiteCountry;
	TeXt::TokenP			m_blackCountry;
	TeXt::TokenP			m_whiteTitle;
	TeXt::TokenP			m_blackTitle;
	TeXt::TokenP			m_whiteElo;
	TeXt::TokenP			m_blackElo;
	TeXt::TokenP			m_whiteIPS;
	TeXt::TokenP			m_blackIPS;
	TeXt::TokenP			m_result;
	TeXt::TokenP			m_event;
	TeXt::TokenP			m_site;
	TeXt::TokenP			m_date;
	TeXt::TokenP			m_eventCountry;
	TeXt::TokenP			m_eco;
	TeXt::TokenP			m_idn;
	TeXt::TokenP			m_fen;
	TeXt::TokenP			m_annotator;
	mstl::string			m_buffer;		// movetext of the current line
	unsigned			m_variationLevel;
};

} // namespace db

#endif // _db_latex_writer_included

// vi:set ts=3 sw=3:
