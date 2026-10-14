// ======================================================================
// Author : $Author$
// Version: $Revision: 1339 $
// Date   : $Date: 2017-07-31 15:09:29 -0400 (Mon, 31 Jul 2017) $
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

#include "db_pdf_writer.h"
#include "db_move_info_set.h"
#include "db_comment.h"
#include "db_annotation.h"
#include "db_mark_set.h"
#include "db_move.h"

#include "u_misc.h"

#include "sys_utf8.h"
#include "sys_utf8_codec.h"
#include "sys_file.h"
#include <stdlib.h>

#include "hpdf.h"

#include "m_stdio.h"
#include "m_assert.h"

#include <string.h>

using namespace db;


static double pixelsToPoints(double pixels)
{
	// NOTE: We assume a resolution of 600dpi.
	// size in points = size in pixels * (points per inch / dots per inch)
	return pixels*(72.0/600.0);
}


static void
errorHandler(HPDF_STATUS errorNo, HPDF_STATUS detailNo, void* user_data)
{

	static_cast<PdfWriter*>(user_data)->errorHandler(errorNo, PdfWriter::errorMessage(errorNo));
}


PdfWriter::PdfWriter(format::Type srcFormat,
							mstl::string fname,
							mstl::string const& encoding,
							unsigned flags)
	:Writer(srcFormat, flags, encoding)
	,m_fname(fname)
	,m_doc(HPDF_New(::errorHandler, this))
	,m_page(nullptr)
	,m_currentStyle(LAST)
	,m_saved(false)
	,m_variationLevel(0)
	,m_cursorX(0.0)
	,m_cursorY(0.0)
	,m_pageWidth(0.0)
	,m_pageHeight(0.0)
	,m_lineHeight(14.0)
	,m_margin(48.0)
	,m_imagePath(SHAREDIR "/pdf/sets")
	,m_boardStyle("Default")
	,m_pieceSet("Merida")
{
	M_REQUIRE(isUsable());

	// the share directory of a relocatable install (Windows, macOS) is known
	// at run time only; start.tcl exports it
	mstl::string fontPath(SHAREDIR "/fonts/ScidbChessMerida.ttf");

	if (char const* share = ::getenv("SCIDB_SHAREDIR"))
	{
		m_imagePath = share;
		m_imagePath += "/pdf/sets";
		fontPath = share;
		fontPath += "/fonts/ScidbChessMerida.ttf";
	}

	::memset(m_font, 0, sizeof(m_font));
	::memset(m_fontSize, 0, sizeof(m_fontSize));
	::memset(m_image, 0, sizeof(m_image));

	HPDF_SetCompressionMode(m_doc, HPDF_COMP_ALL);

	if (encoding == ::sys::utf8::Codec::utf8())
		HPDF_UseUTFEncodings(m_doc);

	char const* fontName = HPDF_LoadFont(	m_doc,
														"Scidb Chess Merida",
														HPDF_FALSE,
														HPDF_FALSE,
														HPDF_TRUE);

	// macOS has neither GDI nor fontconfig to find the font by its name;
	// the program ships it, so load the file itself
	if (fontName == nullptr)
		fontName = HPDF_LoadTTFontFromFile(m_doc, fontPath.c_str(), HPDF_TRUE);

	m_font[Move_Figurine_MainLine] =
	m_font[Move_Figurine_Variation] =
	m_font[Move_Figurine_SubVariation] = HPDF_GetFont(m_doc, fontName, "UTF-8");

	m_font[GameInfo] = HPDF_GetFont(m_doc, "Helvetica", NULL);
	m_font[Move_Text_MainLine] =
		m_font[Move_Text_Variation] =
		m_font[Move_Text_SubVariation] =
		m_font[Move_Symbol_MainLine] =
		m_font[Move_Symbol_Variation] =
		m_font[Move_Symbol_SubVariation] =
		m_font[Comment_MainLine] =
		m_font[Comment_Variation] =
		m_font[Comment_SubVariation] =
		m_font[Result] =
		m_font[GameInfo];

	for (unsigned i = 0; i < LAST; ++i)
		m_fontSize[i] = 12;
}


PdfWriter::~PdfWriter() throw()
{
	// the export framework never calls finish() (same as start()), so
	// the document is saved here; a destructor must never throw
	try { finish(); } catch (...) {}

	if (m_doc)
		HPDF_Free(m_doc);
}


bool
PdfWriter::isUsable()
{
	// without a system font lookup the figurine font is loaded from its file
	return true;
}


void
PdfWriter::setFont(Style style)
{
	M_ASSERT(m_page);

	if (m_font[style] == 0)
	{
		// font resolution failed for this style: fall back to the first
		// available font so text rendering cannot enter an error state
		for (unsigned i = 0; i < LAST; ++i)
		{
			if (m_font[i] != 0)
			{
				style = Style(i);
				break;
			}
		}
	}

	if (style != m_currentStyle)
	{
		HPDF_Page_SetFontAndSize(m_page, m_font[style], m_fontSize[style]);
		m_currentStyle = style;
	}
}


void
PdfWriter::writeTag(mstl::string const& name, mstl::string const& value)
{
	mstl::string line(name);
	line += ":  ";
	line += value;
	showText(line, GameInfo);
	newLine();	// one tag per line (game header block)
}


void
PdfWriter::writeComment(Comment const& comment, MarkSet const& marks)
{
	if (!comment.isEmpty())
	{
		mstl::string text;
		comment.flatten(text, encoding::Utf8, langFlags());
		showWrapped(text, commentStyle());
	}
}


void
PdfWriter::writeMove(	Move const& move,
						mstl::string const& moveNumber,
						Annotation const& annotation,
						MarkSet const& marks,
						Comment const& preComment,
						Comment const& comment)
{
	if (!preComment.isEmpty())
		writeComment(preComment, marks);

	Style style		= moveStyle();
	Style figurine	= figurineStyle();

	mstl::string num(moveNumber);
	showText(num, style);

	mstl::string str;

	if (m_font[figurine])
	{
		move.printSAN(str, protocol::Standard, encoding::Utf8);
		char const* s = str;

		while (*s)
		{
			unsigned len = ::sys::utf8::charLength(s);

			if (len > 1)
			{
				showText(mstl::string(s, len), figurine);
				s += len;
			}
			else
			{
				char const* t = s + 1;

				while (t < str.c_str() + str.size() && ::sys::utf8::charLength(t) == 1)
				++t;

				showText(mstl::string(s, unsigned(t - s)), style);
				s = t;
			}
		}
	}
	else
	{
		move.printSAN(str, protocol::Standard, encoding::Latin1);
		showText(str, style);
	}

	if (!annotation.isEmpty())
	{
		// the diagram NAGs are layout markers, not annotation symbols
		Annotation symbols(annotation);
		symbols.removeDiagramNags();

		if (!symbols.isEmpty())
		{
			mstl::string sym;
			symbols.print(sym, Annotation::Flag_Symbolic_Annotation_Style);

			if (!sym.empty())
				showText(sym, symbolStyle());
		}
	}

	putSpace();

	if (annotation.contains(nag::Diagram) || annotation.contains(nag::DiagramFromBlack))
	{
		newLine();
		writeDiagram(board());
	}

	if (!comment.isEmpty())
		writeComment(comment, MarkSet());
}


void
PdfWriter::writePrecedingComment(	Annotation const& annotation,
											Comment const& comment,
											MarkSet const& marks)
{
	writeComment(comment, marks);
}


void
PdfWriter::writeTrailingComment(Comment const& comment)
{
	writeComment(comment, MarkSet());
}


void
PdfWriter::writeMoveInfo(MoveInfoSet const&)
{
	// clock/eval info is not rendered (v1)
}


// ----------------------------------------------------------------------
// Page flow: draw one text run at the cursor and advance; wrap at the
// right margin. PDF coordinates are bottom-up: the cursor tracks a
// top-down Y that is mirrored at draw time.
// ----------------------------------------------------------------------
void
PdfWriter::showText(mstl::string const& text, Style style)
{
	M_ASSERT(m_page);

	setFont(style);

	if (m_font[m_currentStyle] == 0)
		return;	// no usable font: skip (the font error was already reported)

	double width = HPDF_Page_TextWidth(m_page, text.c_str(), HPDF_INT(text.size()));

	if (m_cursorX + width > m_pageWidth - m_margin)
		newLine();	// may add a fresh page (which resets the current style)

	setFont(style);	// re-apply: a page break inside newLine() cleared the page font

	HPDF_Page_BeginText(m_page);
	HPDF_Page_MoveTextPos(m_page, m_cursorX, m_cursorY);
	HPDF_Page_ShowText(m_page, text.c_str(), HPDF_INT(text.size()));
	HPDF_Page_EndText(m_page);

	m_cursorX += width + 4.0;
}


// Word-wrapped placement for long runs (comments): the text is split
// at whitespace and the words are placed one by one, so a comment that
// exceeds the line width continues on the next line.
void
PdfWriter::showWrapped(mstl::string const& text, Style style)
{
	char const* s	= text.c_str();
	char const* end	= s + text.size();

	while (s < end)
	{
		while (s < end && (*s == ' ' || *s == '\t'))
			++s;

		char const* t = s;

		while (t < end && *t != ' ' && *t != '\t')
			++t;

		if (t > s)
			showText(mstl::string(s, unsigned(t - s)), style);

		s = t;
	}
}


void
PdfWriter::putSpace()
{
	m_cursorX += 4.0;
}


void
PdfWriter::newLine()
{
	m_cursorX = m_margin;

	if (m_cursorY - 2*m_lineHeight < m_margin)
		addPage();	// bottom margin reached: continue on a fresh page
	else
		m_cursorY -= m_lineHeight;
}


// Begin a new page (A4 portrait) and reset the cursor to the top-left
// margin. Used both per game and for bottom-margin page breaks.
void
PdfWriter::addPage()
{
	m_page = HPDF_AddPage(m_doc);
	HPDF_Page_SetSize(m_page, HPDF_PAGE_SIZE_A4, HPDF_PAGE_PORTRAIT);
	m_pageWidth	= HPDF_Page_GetWidth(m_page);
	m_pageHeight	= HPDF_Page_GetHeight(m_page);
	m_cursorX		= m_margin;
	m_cursorY		= m_pageHeight - m_margin;
	m_currentStyle	= LAST;
}


void
PdfWriter::writeBeginGame(unsigned number)
{
	// one game per page
	addPage();
	m_variationLevel = 0;
	m_lineHeight = 14.0;
}


void
PdfWriter::writeEndGame()
{
	// the finished page is kept; the next game starts a new page
}


void
PdfWriter::writeBeginMoveSection()
{
	newLine();
}


void
PdfWriter::writeEndMoveSection(result::ID result)
{
	mstl::string res(result::toString(result));
	newLine();
	showText(res, Result);
}


void
PdfWriter::writeBeginVariation(unsigned level)
{
	m_variationLevel = level;
	showText(mstl::string("("), moveStyle());
}


void
PdfWriter::writeEndVariation(unsigned level)
{
	m_variationLevel = level > 1 ? level - 1 : 0;
	showText(mstl::string(")"), moveStyle());
	putSpace();
}


void
PdfWriter::writeBeginComment()
{
}


void
PdfWriter::writeEndComment()
{
}


// Style mapping for the current variation depth (0 = main line,
// 1 = variation, >1 = subvariation).
PdfWriter::Style
PdfWriter::moveStyle() const
{
	switch (m_variationLevel)
	{
		case 0:	return Move_Text_MainLine;
		case 1:	return Move_Text_Variation;
		default:	return Move_Text_SubVariation;
	}
}


PdfWriter::Style
PdfWriter::figurineStyle() const
{
	switch (m_variationLevel)
	{
		case 0:	return Move_Figurine_MainLine;
		case 1:	return Move_Figurine_Variation;
		default:	return Move_Figurine_SubVariation;
	}
}


PdfWriter::Style
PdfWriter::commentStyle() const
{
	switch (m_variationLevel)
	{
		case 0:	return Comment_MainLine;
		case 1:	return Comment_Variation;
		default:	return Comment_SubVariation;
	}
}


PdfWriter::Style
PdfWriter::symbolStyle() const
{
	switch (m_variationLevel)
	{
		case 0:	return Move_Symbol_MainLine;
		case 1:	return Move_Symbol_Variation;
		default:	return Move_Symbol_SubVariation;
	}
}


void
PdfWriter::writeDiagram(Board const& board)
{
	M_ASSERT(m_page);

	loadImages();

	if (m_image[Square_Lite] == 0 || m_image[Border_Top] == 0)
		return;	// image set unavailable: skip diagrams

	double wd	= ::pixelsToPoints(HPDF_Image_GetWidth(m_image[Square_Lite]));
	double ht	= ::pixelsToPoints(HPDF_Image_GetHeight(m_image[Square_Lite]));
	double bht	= ::pixelsToPoints(HPDF_Image_GetHeight(m_image[Border_Top]));
	double bwd	= ::pixelsToPoints(HPDF_Image_GetWidth(m_image[Border_Left]));

	double height = 8.0*ht + 2.0*bht;

	if (m_cursorY - height < m_margin)
		addPage();	// does not fit on this page: continue on a fresh one

	// top-left outer corner of the border ring; PDF coordinates are
	// bottom-up, so yTop is the highest y of the diagram block
	double x		= m_margin;
	double yTop	= m_cursorY;

	// border ring
	for (unsigned f = 0; f < 8; ++f)
	{
		double xb = x + bwd + f*wd;
		HPDF_Page_DrawImage(m_page, m_image[Border_Top],		xb, yTop - bht,				wd, bht);
		HPDF_Page_DrawImage(m_page, m_image[Border_Bottom],	xb, yTop - 2*bht - 8*ht,	wd, bht);
	}

	for (unsigned r = 0; r < 8; ++r)
	{
		double yb = yTop - bht - (r + 1)*ht;
		HPDF_Page_DrawImage(m_page, m_image[Border_Left],	x,				yb, bwd, ht);
		HPDF_Page_DrawImage(m_page, m_image[Border_Right],	x + bwd + 8*wd,	yb, bwd, ht);
	}

	HPDF_Page_DrawImage(m_page, m_image[Border_TopLeft],		x,				yTop - bht,			bwd, bht);
	HPDF_Page_DrawImage(m_page, m_image[Border_TopRight],	x + bwd + 8*wd,	yTop - bht,			bwd, bht);
	HPDF_Page_DrawImage(m_page, m_image[Border_BottomLeft],	x,				yTop - 2*bht - 8*ht,	bwd, bht);
	HPDF_Page_DrawImage(m_page, m_image[Border_BottomRight],x + bwd + 8*wd,	yTop - 2*bht - 8*ht,	bwd, bht);

	// squares, file-major (a1 = 0; a1 is a light square)
	for (unsigned i = 0; i < 64; ++i)
	{
		unsigned file	= i % 8;
		unsigned rank	= i / 8;	// 0 = rank 1

		piece::ID piece = board.pieceAt(sq::ID(i));
		bool lite = (file + rank) % 2 == 0;

		Part part;

		if (piece == piece::Empty)
			part = lite ? Square_Lite : Square_Dark;
		else
			part = lite ? Part(piece) : Part(piece << 4);

		HPDF_Page_DrawImage(	m_page,
									m_image[part],
									x + bwd + file*wd,
									yTop - bht - (rank + 1)*ht,
									wd,
									ht);
	}

	// reserve the diagram's vertical space
	m_cursorY -= height + 0.5*m_lineHeight;
	m_cursorX = m_margin;
}


void PdfWriter::start()
{
	M_REQUIRE(isUsable());
}


// Saves the document. The export framework never calls finish() (nor
// start()), so the destructor performs the save; finish() stays
// idempotent for explicit callers.
void
PdfWriter::finish()
{
	if (m_saved || m_doc == 0)
		return;

	m_saved = true;

	if (m_page == 0)
		return;	// nothing was written (empty export): no output file

	HPDF_SaveToFile(m_doc, m_fname);
}


void
PdfWriter::loadImages()
{
	if (m_image[Piece_LiteWK])
		return;

	loadPiece(Piece_LiteWK, "lwk");
	loadPiece(Piece_LiteWQ, "lwq");
	loadPiece(Piece_LiteWR, "lwr");
	loadPiece(Piece_LiteWB, "lwb");
	loadPiece(Piece_LiteWN, "lwn");
	loadPiece(Piece_LiteWP, "lwp");
	loadPiece(Piece_LiteBK, "lbk");
	loadPiece(Piece_LiteBQ, "lbq");
	loadPiece(Piece_LiteBR, "lbr");
	loadPiece(Piece_LiteBB, "lbb");
	loadPiece(Piece_LiteBN, "lbn");
	loadPiece(Piece_LiteBP, "lbp");
	loadPiece(Piece_DarkWK, "dwk");
	loadPiece(Piece_DarkWQ, "dwq");
	loadPiece(Piece_DarkWR, "dwr");
	loadPiece(Piece_DarkWB, "dwb");
	loadPiece(Piece_DarkWN, "dwn");
	loadPiece(Piece_DarkWP, "dwp");
	loadPiece(Piece_DarkBK, "dbk");
	loadPiece(Piece_DarkBQ, "dbq");
	loadPiece(Piece_DarkBR, "dbr");
	loadPiece(Piece_DarkBB, "dbb");
	loadPiece(Piece_DarkBN, "dbn");
	loadPiece(Piece_DarkBP, "dbp");

	loadSquare(Square_Lite,  			"empty-l");
	loadSquare(Square_Dark,  			"empty-d");

	loadBorder(Border_Top,				"border-t");
	loadBorder(Border_Bottom, 			"border-b");
	loadBorder(Border_Left, 			"border-l");
	loadBorder(Border_Right, 			"border-r");

	loadBorder(Border_TopLeft, 		"edge-tl");
	loadBorder(Border_TopRight, 		"edge-tr");
	loadBorder(Border_BottomLeft,		"edge-bl");
	loadBorder(Border_BottomRight,	"edge-br");
}


void
PdfWriter::loadImage(Part part,
							mstl::string const& style,
							mstl::string const& pieceSet,
							mstl::string const& id)
{
	mstl::string filename(m_imagePath);

	filename += ::util::misc::file::pathSeparator();
	filename += style;
	filename += ::util::misc::file::pathSeparator();
	filename += "200";	// square size (pixels) of the bundled sets

	if (!pieceSet.empty())
	{
		filename += ::util::misc::file::pathSeparator();
		filename += "pieces";
		filename += ::util::misc::file::pathSeparator();
		filename += pieceSet;
	}

	filename += ::util::misc::file::pathSeparator();
	filename += id;
	filename += ".jpg";

	// a missing image must not put the document into the error state
	// (libharu errors are sticky), so the file is probed first
	if (!::sys::file::access(filename.c_str(), ::sys::file::Existence))
		return;

	m_image[part] = HPDF_LoadJpegImageFromFile(m_doc, filename);
}


void
PdfWriter::errorHandler(unsigned code, mstl::string const& message)
{
	::fprintf(stderr, "[%s] error %04X: %s\n", __func__, code, message.c_str());
}


mstl::string
PdfWriter::errorMessage(unsigned detailNo)
{
	switch (detailNo)
	{
		case HPDF_BINARY_LENGTH_ERR:					return "The length of the data exceeds HPDF_LIMIT_MAX_STRING_LEN.";
		case HPDF_CANNOT_GET_PALLET:					return "Cannot get a pallet data from PNG image.";
		case HPDF_DICT_COUNT_ERR:						return "The count of elements of a dictionary exceeds HPDF_LIMIT_MAX_DICT_ELEMENT";
		case HPDF_DOC_ENCRYPTDICT_NOT_FOUND:		return "HPDF_SetPermission() or HPDF_SetEncryptMode() was called before a password is set.";
		case HPDF_DUPLICATE_REGISTRATION:			return "Tried to register a font that has been registered.";
		case HPDF_EXCEED_JWW_CODE_NUM_LIMIT:		return "Cannot register a character to the japanese word wrap characters list.";
		case HPDF_ENCRYPT_INVALID_PASSWORD:			return	"1. Tried to set the owner password to NULL.\n"
																			"2. The owner password and user password is the same.";
		case HPDF_EXCEED_GSTATE_LIMIT:				return "The depth of the stack exceeded HPDF_LIMIT_MAX_GSTATE.";
		case HPDF_FAILD_TO_ALLOC_MEM:					return "Memory allocation failed.";
		case HPDF_FILE_IO_ERROR:						return "File processing failed. (A detailed code is set.)";
		case HPDF_FILE_OPEN_ERROR:						return "Cannot open a file. (A detailed code is set.)";
		case HPDF_FONT_EXISTS:							return "Tried to load a font that has been registered.";
		case HPDF_FONT_INVALID_WIDTHS_TABLE:		return	"1. The format of a font-file is invalid.\n"
																			"2. Internal error. The consistency of the data was lost.";
		case HPDF_INVALID_AFM_HEADER:					return "Cannot recognize a header of an afm file.";
		case HPDF_INVALID_ANNOTATION:					return "The specified annotation handle is invalid.";
		case HPDF_INVALID_BIT_PER_COMPONENT:		return "Bit-per-component of a image which was set as mask-image is invalid.";
		case HPDF_INVALID_CHAR_MATRICS_DATA:		return "Cannot recognize char-matrics-data  of an afm file.";
		case HPDF_INVALID_COLOR_SPACE:				return	"1. The color_space parameter of HPDF_LoadRawImage is invalid.\n"
																			"2. Color-space of a image which was set as mask-image is invalid.\n"
																			"3. The function which is invalid in the present color-space was invoked.";
		case HPDF_INVALID_COMPRESSION_MODE:			return "Invalid value was set when invoking HPDF_SetCommpressionMode().";
		case HPDF_INVALID_DATE_TIME:					return "An invalid date-time value was set.";
		case HPDF_INVALID_DESTINATION:				return "An invalid destination handle was set.";
		case HPDF_INVALID_DOCUMENT:					return "An invalid document handle was set.";
		case HPDF_INVALID_DOCUMENT_STATE:			return "The function which is invalid in the present state was invoked.";
		case HPDF_INVALID_ENCODER:						return "An invalid encoder handle was set.";
		case HPDF_INVALID_ENCODER_TYPE:				return "A combination between font and encoder is wrong.";
		case HPDF_INVALID_ENCODING_NAME:				return "An Invalid encoding name is specified.";
		case HPDF_INVALID_ENCRYPT_KEY_LEN:			return "The lengh of the key of encryption is invalid.";
		case HPDF_INVALID_FONTDEF_DATA:				return	"1. An invalid font handle was set.\n"
																			"2. Unsupported font format.";
		case HPDF_INVALID_FONT_NAME:					return "A font which has the specified name is not found.";
		case HPDF_INVALID_IMAGE:						return "Unsupported image format.";
		case HPDF_INVALID_JPEG_DATA:					return "Unsupported JPEG image format.";
		case HPDF_INVALID_N_DATA:						return "Cannot read a postscript-name from an afm file.";
		case HPDF_INVALID_OBJECT:						return	"1. An invalid object is set.\n"
																			"2. Internal error. The consistency of the data was lost.";
		case HPDF_INVALID_OPERATION:					return "Invoked HPDF_Image_SetColorMask() against the image-object which was set a mask-image.";
		case HPDF_INVALID_OUTLINE:						return "An invalid outline-handle was specified.";
		case HPDF_INVALID_PAGE:							return "An invalid page-handle was specified.";
		case HPDF_INVALID_PAGES:						return "An invalid pages-handle was specified. (internel error)";
		case HPDF_INVALID_PARAMETER:					return "An invalid value is set.";
		case HPDF_INVALID_PNG_IMAGE:					return "Invalid PNG image format.";
		case HPDF_MISSING_FILE_NAME_ENTRY:			return "Internal error. The \"_FILE_NAME\" entry for delayed loading is missing.";
		case HPDF_INVALID_TTC_FILE:					return "Invalid .TTC file format.";
		case HPDF_INVALID_TTC_INDEX:					return "The index parameter was exceed the number of included fonts.";
		case HPDF_INVALID_WX_DATA:						return "Cannot read a width-data from an afm file.";
		case HPDF_LIBPNG_ERROR:							return "An error has returned from PNGLIB while loading an image.";
		case HPDF_PAGE_CANNOT_RESTORE_GSTATE:		return "There are no graphics-states to be restored.";
		case HPDF_PAGE_FONT_NOT_FOUND:				return "The current font is not set.";
		case HPDF_PAGE_INVALID_FONT:					return "An invalid font-handle was spacified.";
		case HPDF_PAGE_INVALID_FONT_SIZE:			return "An invalid font-size was set.";
		case HPDF_PAGE_INVALID_GMODE:					return "See Graphics mode.";
		case HPDF_PAGE_INVALID_ROTATE_VALUE:		return "The specified value is not a multiple of 90.";
		case HPDF_PAGE_INVALID_SIZE:					return "An invalid page-size was set.";
		case HPDF_PAGE_INVALID_XOBJECT:				return "An invalid image-handle was set.";
		case HPDF_PAGE_OUT_OF_RANGE:					return "The specified value is out of range.";
		case HPDF_REAL_OUT_OF_RANGE:					return "The specified value is out of range.";
		case HPDF_STREAM_EOF:							return "Unexpected EOF marker was detected.";
		case HPDF_STRING_OUT_OF_RANGE:				return "The length of the specified text is too long.";
		case HPDF_THIS_FUNC_WAS_SKIPPED:				return "The execution of a function was skipped because of other errors.";
		case HPDF_TTF_CANNOT_EMBEDDING_FONT:		return "This font cannot be embedded (restricted by license).";
		case HPDF_TTF_INVALID_CMAP:					return "Unsupported ttf format (cannot find unicode cmap).";
		case HPDF_TTF_INVALID_FOMAT:					return "Unsupported ttf format.";
		case HPDF_TTF_MISSING_TABLE:					return "Unsupported ttf format (cannot find a necessary table).";
		case HPDF_UNSUPPORTED_FUNC:					return	"1. The library is not configured to use PNGLIB.\n"
																			"2. Internal error. The consistency of the data was lost.";
		case HPDF_UNSUPPORTED_JPEG_FORMAT:			return "Unsupported JPEG format.";
		case HPDF_UNSUPPORTED_TYPE1_FONT:			return "Failed to parse .PFB file.";
		case HPDF_ZLIB_ERROR:							return "An error has occurred while executing a function of Zlib.";
		case HPDF_INVALID_PAGE_INDEX:					return "An invalid page index was passed.";
		case HPDF_INVALID_URI:							return "An invalid URI was set.";
		case HPDF_PAGE_LAYOUT_OUT_OF_RANGE:			return "An invalid page-layout was set.";
		case HPDF_PAGE_MODE_OUT_OF_RANGE:			return "An invalid page-mode was set.";
		case HPDF_PAGE_NUM_STYLE_OUT_OF_RANGE:		return "An invalid page-num-style was set.";
		case HPDF_ANNOT_INVALID_ICON:					return "An invalid icon was set.";
		case HPDF_ANNOT_INVALID_BORDER_STYLE:		return "An invalid border-style was set.";
		case HPDF_PAGE_INVALID_DIRECTION:			return "An invalid page-direction was set.";
		case HPDF_INVALID_FONT:							return "An invalid font-handle was specified.";
		case HPDF_UNKOWN_FONT:							return "Font creation failed (unknown font)";
		case HPDF_FAMILY_NAME_TOO_LONG:				return "HPDF_GetTTFontDef() failed because family name is too long.";

		case HPDF_PAGE_INVALID_PARAM_COUNT:			return "HPDF_PAGE_INVALID_PARAM_COUNT: unspecified error.";
		case HPDF_PAGE_INSUFFICIENT_SPACE:			return "HPDF_PAGE_INSUFFICIENT_SPACE: unspecified error.";
		case HPDF_PAGE_INVALID_DISPLAY_TIME:		return "HPDF_PAGE_INVALID_DISPLAY_TIME: unspecified error.";
		case HPDF_PAGE_INVALID_TRANSITION_TIME:	return "HPDF_PAGE_INVALID_TRANSITION_TIME: unspecified error.";
		case HPDF_INVALID_PAGE_SLIDESHOW_TYPE:		return "HPDF_INVALID_PAGE_SLIDESHOW_TYPE: unspecified error.";
		case HPDF_EXT_GSTATE_OUT_OF_RANGE:			return "HPDF_EXT_GSTATE_OUT_OF_RANGE: unspecified error.";
		case HPDF_INVALID_EXT_GSTATE:					return "HPDF_INVALID_EXT_GSTATE: unspecified error.";
		case HPDF_EXT_GSTATE_READ_ONLY:				return "HPDF_EXT_GSTATE_READ_ONLY: unspecified error.";
		case HPDF_INVALID_U3D_DATA:					return "HPDF_INVALID_U3D_DATA: unspecified error.";
		case HPDF_NAME_CANNOT_GET_NAMES:				return "HPDF_NAME_CANNOT_GET_NAMES: unspecified error.";
		case HPDF_INVALID_ICC_COMPONENT_NUM:		return "HPDF_INVALID_ICC_COMPONENT_NUM: unspecified error.";

		case HPDF_ARRAY_COUNT_ERR:						// fallthru
		case HPDF_ARRAY_ITEM_NOT_FOUND:				// fallthru
		case HPDF_ARRAY_ITEM_UNEXPECTED_TYPE:		// fallthru
		case HPDF_DICT_ITEM_NOT_FOUND:				// fallthru
		case HPDF_DICT_ITEM_UNEXPECTED_TYPE:		// fallthru
		case HPDF_DICT_STREAM_LENGTH_NOT_FOUND:	// fallthru
		case HPDF_NAME_INVALID_VALUE:					// fallthru
		case HPDF_NAME_OUT_OF_RANGE:					// fallthru
		case HPDF_PAGES_MISSING_KIDS_ENTRY:			// fallthru
		case HPDF_PAGE_CANNOT_FIND_OBJECT:			// fallthru
		case HPDF_PAGE_CANNOT_GET_ROOT_PAGES:		// fallthru
		case HPDF_UNSUPPORTED_FONT_TYPE:				// fallthru
		case HPDF_DOC_INVALID_OBJECT:					// fallthru
		case HPDF_ERR_UNKNOWN_CLASS:					// fallthru
		case HPDF_INVALID_FONTDEF_TYPE:				// fallthru
		case HPDF_INVALID_OBJ_ID:						// fallthru
		case HPDF_INVALID_STREAM:						// fallthru
		case HPDF_ITEM_NOT_FOUND:						// fallthru
		case HPDF_PAGE_CANNOT_SET_PARENT:			// fallthru
		case HPDF_PAGE_INVALID_INDEX:					// fallthru
		case HPDF_STREAM_READLN_CONTINUE:			// fallthru
		case HPDF_XREF_COUNT_ERR:						return "Internal error. The consistency of the data was lost.";
	}

	char buf[200];
	::snprintf(buf, sizeof(buf), "<unknown error code %04X>", detailNo);
	return buf;
}

format::Type
PdfWriter::format() const
{
	return format::Pdf;
}

// vi:set ts=3 sw=3:

