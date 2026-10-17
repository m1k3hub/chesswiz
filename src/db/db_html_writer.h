/* Modified for Chesswiz, 2026; see docs/UPSTREAM.md */
// ======================================================================
// db_html_writer — standalone HTML export (the "publish" path)
// ======================================================================
// Part of scidb's native HTML support (see src/html/). Implements the
// Writer interface over the scidb HTML profile: one HTML file with one
// <article> per game, UTF-8 throughout, self-contained (embedded CSS,
// inline-SVG diagrams) — publishable as-is.
//
// Structure:
//   start()        <!doctype html><head><meta charset> + <style>
//   writeTag       <div class="tag"><span class="tname">…</span> …
//   writeBeginMoveSection   <div class="moves">
//   writeMove      <span class="mnum">1.</span> <span class="san">e4</span>
//                  + NAG symbols (nag::toSymbol), inline comments,
//                  diagrams (nag::Diagram → inline SVG from the board)
//   variations     <span class="variation">( … )</span>
//   comments       Comment::toHtml for XML comments (ChessBase-style
//                  markup), escaped text otherwise — never raw, never
//                  silently dropped
//   writeEndMoveSection     result + close moves
//   finish()       </body></html>
//
// v1 notes: MarkSet (board arrows) and MoveInfo (clocks) are not
// rendered; the output encoding is always UTF-8 (the encoding argument
// is accepted for interface compatibility and ignored).
// ======================================================================

#ifndef _db_html_writer_included
#define _db_html_writer_included

#include "db_writer.h"

#include "m_fstream.h"
#include "m_string.h"

namespace db {

class HtmlWriter : public Writer
{
public:

	static unsigned const Default_Flags =	Flag_Include_Variations
													 | Flag_Include_Comments
													 | Flag_Include_Annotation
													 | Flag_Indent_Variations
													 | Flag_Comment_To_Html;

	HtmlWriter(	format::Type srcFormat,
					mstl::string fname,
					mstl::string const& encoding,
					unsigned flags = Default_Flags,
					LanguageList const* languages = nullptr,
					unsigned significantLanguages = 0);
	~HtmlWriter() throw();

	void writeTag(mstl::string const& name, mstl::string const& value) override;
	void writeMove(	Move const& move,
							mstl::string const& moveNumber,
							Annotation const& annotation,
							MarkSet const& marks,
							Comment const& preComment,
							Comment const& comment) override;

	void writeBeginGame(unsigned number) override;
	void writeEndGame() override;
	void writeBeginMoveSection() override;
	void writeEndMoveSection(result::ID result) override;
	void writeBeginVariation(unsigned level) override;
	void writeEndVariation(unsigned level) override;
	void writePrecedingComment(	Annotation const& annotation,
											Comment const& comment,
											MarkSet const& marks) override;
	void writeTrailingComment(Comment const& comment) override;
	void writeMoveInfo(MoveInfoSet const& moveInfo) override;
	void writeBeginComment() override;
	void writeEndComment() override;

	void start() override;
	void finish() override;

private:

	format::Type format() const override;

	void put(char const* s, unsigned length);
	void put(mstl::string const& s);
	void ensureOpen();
	bool	m_preambleWritten;
	void putEscaped(mstl::string const& s);
	void putComment(Comment const& comment);
	void putDiagram();
	void ensureTagsClosed();
	void ensureMovesOpen();

	mstl::ofstream	m_strm;
	mstl::string		m_fname;
	mstl::string		m_sBuf;			///< SAN buffer (Writer keeps its own private)
	mstl::string		m_nBuf;			///< NAG buffer

	bool				m_movesOpen;
	bool				m_tagsOpen;
	bool				m_inVariation;
	unsigned			m_diagramCount;
};

} // namespace db

#endif // _db_html_writer_included

// vi:set ts=3 sw=3: