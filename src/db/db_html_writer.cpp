// ======================================================================
// db_html_writer — standalone HTML export (the "publish" path)
// ======================================================================
// See db_html_writer.h for the design and output structure.
// ======================================================================

#include "db_html_writer.h"

#include "db_annotation.h"
#include "db_comment.h"
#include "db_mark_set.h"
#include "db_move.h"
#include "db_move_info_set.h"

#include "m_assert.h"
#include "m_fstream.h"
#include "sys_file.h"

#include <string.h>
#include <stdio.h>

using namespace db;

namespace {
inline mstl::string
toStr(unsigned n)
{
	char buf[16];
	::snprintf(buf, sizeof(buf), "%u", n);
	return mstl::string(buf);
}


// CSS embedded in every exported file: self-contained, no external
// dependencies, readable in any browser.
char const* const Stylesheet =
	"body { font-family: sans-serif; margin: 2em auto; max-width: 50em; padding: 0 1em; color: #222; }\n"
	"h1 { font-size: 1.4em; }\n"
	"article.game { border-bottom: 1px solid #ddd; padding-bottom: 1em; margin-bottom: 2em; }\n"
	"div.tag { margin: 0.1em 0; }\n"
	"span.tname { display: inline-block; min-width: 7em; font-weight: bold; }\n"
	"div.moves { margin: 1em 0; line-height: 1.6; font-family: serif; font-size: 1.05em; }\n"
	"span.mnum { color: #888; font-family: sans-serif; font-size: 0.85em; }\n"
	"span.nag { color: #a00; }\n"
	"span.variation { color: #555; }\n"
	"p.comment, span.comment { color: #000090; }\n"
	"div.diagram { margin: 0.8em 0; }\n"
	"div.result { font-weight: bold; margin-top: 0.5em; }\n";

char const* const PieceGlyphs[2][6] =
{
	{ "\u265f", "\u265e", "\u265d", "\u265c", "\u265b", "\u265a" },	// black (fen letters k q r b n p)
	{ "\u2659", "\u2658", "\u2657", "\u2656", "\u2655", "\u2654" },	// white (fen letters K Q R B N P)
};


void
appendEscaped(mstl::string& out, char const* s, unsigned len)
{
	unsigned start = 0;

	for (unsigned i = 0; i < len; ++i)
	{
		char const* ent = 0;

		switch (s[i])
		{
			case '&':	ent = "&amp;";	break;
			case '<':	ent = "&lt;";		break;
			case '>':	ent = "&gt;";		break;
			case '"':	ent = "&quot;";	break;
		}

		if (ent)
		{
			if (i > start)
				out.append(s + start, i - start);
			out.append(ent);
			start = i + 1;
		}
	}

	if (start < len)
		out.append(s + start, len - start);
}


// Inline SVG diagram from the FEN placement field. Deterministic output
// (no dates/randomness) so exports are byte-comparable.
void
appendDiagram(mstl::string& out, mstl::string const& fen)
{
	unsigned const Cell = 45;
	unsigned const Size = 8 * Cell;

	out.append("<div class=\"diagram\"><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"");
	out.append(toStr(Size));
	out.append("\" height=\"");
	out.append(toStr(Size));
	out.append("\" viewBox=\"0 0 ");
	out.append(toStr(Size));
	out.append(" ");
	out.append(toStr(Size));
	out.append("\">");

	// board field of the FEN (up to the first space)
	mstl::string::size_type sp = fen.find(' ');
	mstl::string board(fen, 0, sp == mstl::string::npos ? fen.size() : sp);

	unsigned rank = 0;	// 0 = rank 8 (FEN order)
	unsigned file = 0;	// 0 = file a

	for (unsigned r = 0; r < 8; ++r)
	{
		for (unsigned f = 0; f < 8; ++f)
		{
			bool dark = (r + f) % 2 == 1;

			out.append("<rect x=\"");
			out.append(toStr(f * Cell));
			out.append("\" y=\"");
			out.append(toStr(r * Cell));
			out.append("\" width=\"");
			out.append(toStr(Cell));
			out.append("\" height=\"");
			out.append(toStr(Cell));
			out.append(dark ? "\" fill=\"#b58863\"/>" : "\" fill=\"#f0d9b5\"/>");
		}
	}

	char const* p = board.c_str();

	for ( ; *p && *p != ' '; ++p)
	{
		char c = *p;

		if (c == '/')
		{
			++rank;
			file = 0;
			continue;
		}

		if (c >= '1' && c <= '8')
		{
			file += c - '0';
			continue;
		}

		// piece glyph
		char const* glyph = 0;

		for (unsigned k = 0; k < 6 && !glyph; ++k)
		{
			if (c == "kqrbnp"[k])	glyph = PieceGlyphs[0][k];
			if (c == "KQRBNP"[k])	glyph = PieceGlyphs[1][k];
		}

		if (glyph)
		{
			unsigned x = file * Cell + Cell / 2;
			unsigned y = rank * Cell + Cell / 2;

			out.append("<text x=\"");
			out.append(toStr(x));
			out.append("\" y=\"");
			out.append(toStr(y));
			out.append("\" font-size=\"36\" text-anchor=\"middle\" dominant-baseline=\"central\">");
			out.append(glyph);
			out.append("</text>");
		}

		++file;
	}

	out.append("</svg></div>");
}



} // anonymous namespace


HtmlWriter::HtmlWriter(	format::Type srcFormat,
								mstl::string fname,
								mstl::string const& encoding,
								unsigned flags,
								LanguageList const* languages,
								unsigned significantLanguages)
	:Writer(srcFormat, flags, encoding, languages, significantLanguages)
	,m_fname(fname)
	,m_preambleWritten(false)
	,m_movesOpen(false)
	,m_tagsOpen(false)
	,m_inVariation(false)
	,m_diagramCount(0)
{
}


HtmlWriter::~HtmlWriter() throw()
{
	// the export framework never calls finish() (same as start()), so
	// the document tail is emitted here; guard everything: a destructor
	// must never throw
	try
	{
		if (m_preambleWritten && m_strm.is_open())
		{
			if (m_movesOpen)
				m_strm.write("</div>\n", 7);

			m_strm.write("</body>\n</html>\n", 16);
		}
	}
	catch (...)
	{
	}
}


format::Type
HtmlWriter::format() const
{
	return format::Html;
}


// The export framework does not call start()/finish() (PgnWriter gets
// its stream pre-opened by the caller), so the file is opened lazily on
// the first write; finish() (or the destructor) closes it.
void
HtmlWriter::ensureOpen()
{
	if (!m_strm.is_open())
	{
		m_strm.open(sys::file::internalName(m_fname),
						mstl::ios_base::out | mstl::ios_base::binary);

		if (!m_strm)
			M_RAISE("cannot create HTML file", m_fname.c_str());
	}

	if (!m_preambleWritten)
	{
		// the export framework never calls start() (PgnWriter gets its
		// stream pre-opened by the caller), so the document preamble is
		// emitted lazily with the first write
		m_preambleWritten = true;

		put("<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\"/>\n");
		put("<meta name=\"generator\" content=\"scidb\"/>\n");
		put("<title>Games</title>\n<style>\n");
		put(Stylesheet);
		put("</style>\n</head>\n<body>\n");
	}
}


void
HtmlWriter::put(char const* s, unsigned length)
{
	ensureOpen();
	m_strm.write(s, length);
}


void
HtmlWriter::put(mstl::string const& s)
{
	ensureOpen(); // "put(literal)" resolves HERE (string overload) — it
					// is usually the first write of the whole export
	m_strm.write(s, s.size());
}


void
HtmlWriter::putEscaped(mstl::string const& s)
{
	ensureOpen();
	unsigned start = 0;
	char const* d = s.c_str();

	for (unsigned i = 0; i < s.size(); ++i)
	{
		char const* ent = 0;

		switch (d[i])
		{
			case '&':	ent = "&amp;";	break;
			case '<':	ent = "&lt;";		break;
			case '>':	ent = "&gt;";		break;
			case '"':	ent = "&quot;";	break;
		}

		if (ent)
		{
			if (i > start)
				m_strm.write(d + start, i - start);
			m_strm.write(ent, ::strlen(ent));
			start = i + 1;
		}
	}

	if (start < s.size())
		m_strm.write(d + start, s.size() - start);
}


void
HtmlWriter::ensureTagsClosed()
{
	if (m_tagsOpen)
	{
		put("</div>\n");
		m_tagsOpen = false;
	}
}


void
HtmlWriter::ensureMovesOpen()
{
	ensureTagsClosed();

	if (!m_movesOpen)
	{
		put("<div class=\"moves\">\n");
		m_movesOpen = true;
	}
}


void
HtmlWriter::start()
{
	ensureOpen(); // emits the document preamble lazily
}


void
HtmlWriter::finish()
{
	if (!m_preambleWritten)
		return;

	ensureTagsClosed();

	if (m_movesOpen)
		put("</div>\n");

	put("</body>\n</html>\n");
	m_strm.close();
}


void
HtmlWriter::writeTag(mstl::string const& name, mstl::string const& value)
{
	if (!m_tagsOpen && !m_movesOpen)
	{
		put("<div class=\"tags\">\n");
		m_tagsOpen = true;
	}

	put("<div class=\"tag\"><span class=\"tname\">");
	putEscaped(name);
	put("</span> <span class=\"tvalue\">");
	putEscaped(value);
	put("</span></div>\n");
}


void
HtmlWriter::writeBeginGame(unsigned number)
{
	m_movesOpen = false;
	m_tagsOpen = false;
	m_inVariation = false;
	m_diagramCount = 0;

	put("<article class=\"game\" id=\"game-");
	put(toStr(number));
	put("\">\n");
}


void
HtmlWriter::writeEndGame()
{
	ensureTagsClosed();

	if (m_movesOpen)
	{
		put("</div>\n");
		m_movesOpen = false;
	}

	put("</article>\n\n");
}


void
HtmlWriter::writeBeginMoveSection()
{
	ensureTagsClosed();
	ensureMovesOpen();
}


void
HtmlWriter::writeEndMoveSection(result::ID result)
{
	ensureMovesOpen();

	put("<span class=\"result\">");
	putEscaped(mstl::string(result::toString(result)));
	put("</span>\n</div>\n");
	m_movesOpen = false;
}


void
HtmlWriter::writeMove(	Move const& move,
							mstl::string const& moveNumber,
							Annotation const& annotation,
							MarkSet const& /*marks*/,
							Comment const& preComment,
							Comment const& comment)
{
	ensureMovesOpen();

	if (!preComment.isEmpty())
		putComment(preComment);

	bool hasDiagram = annotation.contains(nag::Diagram)
						|| annotation.contains(nag::DiagramFromBlack);

	put("<span class=\"mnum\">");
	putEscaped(mstl::string(moveNumber));
	put("</span>\n");

	m_sBuf.clear();
	move.printSAN(m_sBuf, protocol::Standard, encoding::Latin1);
	put("<span class=\"san\">");
	putEscaped(m_sBuf);
	put("</span>");

	if (!annotation.isEmpty())
	{
		m_nBuf.clear();
		annotation.print(m_nBuf, Annotation::Flag_Symbolic_Annotation_Style);

		if (!m_nBuf.empty())
		{
			put("<span class=\"nag\">");
			putEscaped(m_nBuf);
			put("</span>");
		}
	}

	if (hasDiagram)
	{
		// the consumer's board is the position after the move
		m_diagramCount += 1;
		putDiagram();
	}

	put(" ");

	if (!comment.isEmpty())
		putComment(comment);
}


void
HtmlWriter::writeBeginVariation(unsigned)
{
	ensureMovesOpen();
	put("<span class=\"variation\">(");
	m_inVariation = true;
}


void
HtmlWriter::writeEndVariation(unsigned)
{
	put(")</span>");
	m_inVariation = false;
}


void
HtmlWriter::writePrecedingComment(	Annotation const& annotation,
											Comment const& comment,
											MarkSet const& marks)
{
	ensureMovesOpen();
	putComment(comment);
}


void
HtmlWriter::writeTrailingComment(Comment const& comment)
{
	ensureMovesOpen();
	putComment(comment);
}


void
HtmlWriter::writeMoveInfo(MoveInfoSet const&)
{
	// v1: clock/eval info is not rendered
}


void
HtmlWriter::writeBeginComment()
{
	// comments are emitted atomically by putComment (no delimiter state)
}


void
HtmlWriter::writeEndComment()
{
}


void
HtmlWriter::putComment(Comment const& comment)
{
	if (comment.isEmpty())
		return;

	// ChessBase diagram convention: a comment of exactly "#" is the
	// diagram marker of the PREVIOUS move's position (the producer has
	// already advanced the board) — render the diagram, not the text
	if (comment.size() == 1)
	{
		mstl::string probe;
		comment.flatten(probe, encoding::Utf8, langFlags());

		if (probe == "#")
		{
			putDiagram();
			return;
		}
	}

	mstl::string text;

	// v1 renders comments as PLAIN TEXT in the selected language:
	// flatten() strips the ChessBase XML markup (language sections,
	// rich-text tags) so no foreign markup leaks into the published
	// HTML. Rich-text round-tripping is a later phase (the sanitizer
	// in src/html is the intended gate).
	comment.flatten(text, encoding::Utf8, langFlags());

	if (text.empty())
		return;

	put("<span class=\"comment\">");
	putEscaped(text);
	put("</span> ");
	return;

	if (text.find('\n') != mstl::string::npos)
	{
		put("<p class=\"comment\">");
		m_strm.write(text, text.size());
		put("</p>\n");
	}
	else
	{
		put("<span class=\"comment\">");
		m_strm.write(text, text.size());
		put("</span> ");
	}
}


void
HtmlWriter::putDiagram()
{
		mstl::string fen(board().toFen(variant()));

		if (fen.empty())
			return;

		mstl::string svg;
		appendDiagram(svg, fen);
		put(svg);
}

// NOTE: appendDiagram builds the SVG into a string buffer so a unit
// test can verify it without a file.

// vi:set ts=3 sw=3: