// ======================================================================
// Author : $Author$
// Version: $Revision$
// Date   : $Date$
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

#include "cbh_annotation_encoder.h"

#include "db_comment.h"
#include "db_annotation.h"
#include "db_mark_set.h"
#include "db_mark.h"

#include "u_byte_stream.h"

#include "sys_utf8_codec.h"

#include "m_string.h"

using namespace util;
using namespace db;
using namespace db::cbh;


inline
static Byte
unmapSquare(Byte sq)
{
	// Inverse of mapSquare: converts standard square encoding to CBH square byte.
	// mapSquare(x) = sq::make(x >> 3, x & 7) = ((x & 7) << 3) | (x >> 3)
	// unmapSquare is self-inverse: unmapSquare = mapSquare
	return sq::make(sq >> 3, sq & 7);
}


static Byte
mapColor(mark::Color c)
{
	switch (c)
	{
		case mark::Green:		return 2;
		case mark::Yellow:	return 3;
		case mark::Red:		return 4;
		default:					return 4;	// default to red
	}
}


// Map NAG to first-byte symbol code (move quality)
static Byte
nagToMoveSymbol(nag::ID nag)
{
	switch (nag)
	{
		case nag::GoodMove:				return 0x01;
		case nag::PoorMove:				return 0x02;
		case nag::VeryGoodMove:			return 0x03;
		case nag::VeryPoorMove:			return 0x04;
		case nag::SpeculativeMove:		return 0x05;
		case nag::QuestionableMove:	return 0x06;
		case nag::SingularMove:			return 0x08;
		default:								return 0;
	}
}


// Map NAG to second-byte symbol code (position evaluation)
static Byte
nagToPositionSymbol(nag::ID nag)
{
	switch (nag)
	{
		case nag::DrawishPosition:									return 0x0b;
		case nag::UnclearPosition:									return 0x0d;
		case nag::WhiteHasASlightAdvantage:						return 0x0e;
		case nag::BlackHasASlightAdvantage:						return 0x0f;
		case nag::WhiteHasAModerateAdvantage:					return 0x10;
		case nag::BlackHasAModerateAdvantage:					return 0x11;
		case nag::WhiteHasADecisiveAdvantage:					return 0x12;
		case nag::BlackHasADecisiveAdvantage:					return 0x13;
		case nag::Novelty:												return 0x92;
		case nag::TimeLimit:												return 0x8a;
		default:																return 0;
	}
}


// Map NAG to second-byte symbol code (color-dependent position evaluation)
static Byte
nagToColorPositionSymbol(nag::ID nag, bool whiteToMove)
{
	// The decoder maps these symbols back via the color of the annotated
	// move (NAG(code) = wtm ? White##code : Black##code), so a symbol may
	// only be emitted when the NAG's color matches the moving side.
	switch (nag)
	{
		case nag::WhiteHasAModerateTimeAdvantage:	return whiteToMove ? 0x20 : 0;
		case nag::BlackHasAModerateTimeAdvantage:	return whiteToMove ? 0 : 0x20;
		case nag::WhiteHasTheInitiative:					return whiteToMove ? 0x24 : 0;
		case nag::BlackHasTheInitiative:					return whiteToMove ? 0 : 0x24;
		case nag::WhiteHasTheAttack:						return whiteToMove ? 0x28 : 0;
		case nag::BlackHasTheAttack:						return whiteToMove ? 0 : 0x28;
		case nag::WhiteHasSufficientCompensationForMaterialDeficit:
			return whiteToMove ? 0x2c : 0;
		case nag::BlackHasSufficientCompensationForMaterialDeficit:
			return whiteToMove ? 0 : 0x2c;
		case nag::WhiteHasModerateCounterplay:			return whiteToMove ? 0x84 : 0;
		case nag::BlackHasModerateCounterplay:			return whiteToMove ? 0 : 0x84;
		default:													return 0;
	}
}


// Map NAG to third-byte symbol code (editorial)
static Byte
nagToEditorialSymbol(nag::ID nag)
{
	switch (nag)
	{
		case nag::WithTheIdea:			return 0x8C;
		case nag::AimedAgainst:			return 0x8D;
		case nag::BetterMove:			return 0x8E;
		case nag::WorseMove:				return 0x8F;
		case nag::EquivalentMove:		return 0x90;
		case nag::EditorsRemark:		return 0x91;
		default:								return 0;
	}
}


AnnotationEncoder::AnnotationEncoder(ByteStream& aStrm, sys::utf8::Codec& codec)
	:m_aStrm(aStrm)
	,m_codec(codec)
{
}


void
AnnotationEncoder::writeRecordHeader(unsigned moveNo, Byte type, unsigned dataLength)
{
	// Record format: 3-byte move number, 1-byte type, 2-byte total length
	// Total length includes the 6-byte header itself.
	unsigned totalLength = dataLength + 6;

	m_aStrm.put(Byte((moveNo >> 16) & 0xff));
	m_aStrm.put(Byte((moveNo >> 8) & 0xff));
	m_aStrm.put(Byte(moveNo & 0xff));
	m_aStrm.put(type);
	m_aStrm.put(Byte((totalLength >> 8) & 0xff));
	m_aStrm.put(Byte(totalLength & 0xff));
}


void
AnnotationEncoder::encodeComment(unsigned moveNo, Comment const& comment, move::Position position)
{
	if (comment.isEmpty())
		return;

	// Flatten comment to plain text for CP1252 encoding.
	// This is a simplification: complex XML comments with embedded NAGs
	// are reduced to their text content.
	mstl::string text;
	comment.flatten(text, encoding::Latin1, i18n::English);

	if (text.empty())
		return;

	// Convert from UTF-8 to CP1252
	m_codec.fromUtf8(text);

	// Language code: default to 0x0000 (no specific language).
	// English = 0x002a, but 0 works as a universal code.
	uint16_t langCode = 0;

	if (comment.langFlags() & i18n::English)
		langCode = 0x2a;

	unsigned dataLength = 2 + text.size();

	// Type: 0x02 = text after move, 0x82 = text before move
	Byte type = (position == move::Ante) ? 0x82 : 0x02;

	writeRecordHeader(moveNo, type, dataLength);
	m_aStrm.put(Byte((langCode >> 8) & 0xff));
	m_aStrm.put(Byte(langCode & 0xff));
	m_aStrm.put(reinterpret_cast<Byte const*>(text.c_str()), text.size());
}


void
AnnotationEncoder::encodeAnnotation(unsigned moveNo, Annotation const& annotation, bool whiteToMove)
{
	if (annotation.isEmpty())
		return;

	// Collect up to 3 symbol bytes
	Byte symbols[3] = { 0, 0, 0 };
	unsigned symbolCount = 0;

	for (unsigned i = 0; i < annotation.count(); ++i)
	{
		nag::ID nag = annotation[i];

		// Try move quality (byte 1)
		Byte b = nagToMoveSymbol(nag);
		if (b && symbols[0] == 0)
		{
			symbols[0] = b;
			continue;
		}

		// Zugzwang is encoded as move symbol 0x16; the decoder restores the
		// color from the moving side, so only emit it when the colors match.
		if ((nag == nag::WhiteIsInZugzwang && whiteToMove)
			|| (nag == nag::BlackIsInZugzwang && !whiteToMove))
		{
			if (symbols[0] == 0)
			{
				symbols[0] = 0x16;
				continue;
			}
		}

		// Try position evaluation (byte 2)
		b = nagToPositionSymbol(nag);
		if (b && symbols[1] == 0)
		{
			symbols[1] = b;
			continue;
		}

		// Try color-dependent position evaluation (byte 2)
		b = nagToColorPositionSymbol(nag, whiteToMove);
		if (b && symbols[1] == 0)
		{
			symbols[1] = b;
			continue;
		}

		// Try editorial (byte 3)
		b = nagToEditorialSymbol(nag);
		if (b && symbols[2] == 0)
		{
			symbols[2] = b;
			continue;
		}
	}

	// Determine how many bytes to write (1-3, trailing zeros omitted)
	if (symbols[2]) symbolCount = 3;
	else if (symbols[1]) symbolCount = 2;
	else if (symbols[0]) symbolCount = 1;
	else return;	// no encodable symbols

	writeRecordHeader(moveNo, 0x03, symbolCount);
	m_aStrm.put(symbols, symbolCount);
}


void
AnnotationEncoder::encodeMarks(unsigned moveNo, MarkSet const& marks)
{
	if (marks.count() == 0)
		return;

	// Separate marks into square marks and arrows
	unsigned squareCount = 0;
	unsigned arrowCount  = 0;

	for (unsigned i = 0; i < marks.count(); ++i)
	{
		Mark const& m = marks[i];

		if (m.type() == mark::Full)
			++squareCount;
		else if (m.type() == mark::Arrow)
			++arrowCount;
	}

	// Write square marks (type 0x04): pairs of (color, square+1)
	if (squareCount > 0)
	{
		writeRecordHeader(moveNo, 0x04, squareCount * 2);

		for (unsigned i = 0; i < marks.count(); ++i)
		{
			Mark const& m = marks[i];

			if (m.type() == mark::Full)
			{
				m_aStrm.put(::mapColor(m.color()));
				m_aStrm.put(Byte(::unmapSquare(m.square(0)) + 1));
			}
		}
	}

	// Write arrows (type 0x05): triples of (color, from+1, to+1)
	if (arrowCount > 0)
	{
		writeRecordHeader(moveNo, 0x05, arrowCount * 3);

		for (unsigned i = 0; i < marks.count(); ++i)
		{
			Mark const& m = marks[i];

			if (m.type() == mark::Arrow)
			{
				m_aStrm.put(::mapColor(m.color()));
				m_aStrm.put(Byte(::unmapSquare(m.square(0)) + 1));
				m_aStrm.put(Byte(::unmapSquare(m.square(1)) + 1));
			}
		}
	}
}

// vi:set ts=3 sw=3:
