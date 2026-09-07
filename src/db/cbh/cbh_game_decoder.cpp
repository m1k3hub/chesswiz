// ======================================================================
// Author : $Author: gcramer $
// Version: $Revision: 1339 $
// Date   : $Date: 2017-07-31 15:09:29 -0400 (Mon, 31 Jul 2017) $
// Url    : $URL: https://svn.code.sf.net/p/scidb/code/trunk/src/db/cbh/cbh_game_decoder.cpp $
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

// ChessBase format description:
// http://talkchess.com/forum/viewtopic.php?t=29468&highlight=cbh
// http://talkchess.com/forum/viewtopic.php?topic_view=threads&p=287896&t=29468&sid=a535ba2e9a17395e2582bdddf57c2425

#include "cbh_game_decoder.h"
#include "cbh_quotation.h"
#include "db_eco.h"

#include "db_consumer.h"
#include "db_game_data.h"
#include "db_game_info.h"
#include "db_database_codec.h"
#include "db_move_node.h"
#include "db_move_info.h"
#include "db_mark_set.h"
#include "db_annotation.h"
#include "db_exception.h"

#include "u_byte_stream.h"
#include "u_bit_stream.h"

#include "sys_utf8.h"
#include "sys_utf8_codec.h"

#include "m_vector.h"
#include "m_limits.h"
#include "m_stdio.h"

#include <ctype.h>

using namespace util;
using namespace db;
using namespace db::cbh;


static int const MaxMoveNo = mstl::numeric_limits<int>::max();


# define ____ 0
static char const* LangMap[] =
{
	____, ____, ____, ____, ____, ____, ____, ____, // x00 - x07
	____, ____, ____, ____, ____, ____, ____, ____, // x08 - x0f
	____, ____, ____, ____, ____, ____, ____, ____, // x10 - x17
	____, ____, ____, ____, ____, ____, ____, ____, // x18 - x1f
	____, ____, ____, ____, ____, ____, ____, ____, // x20 - x27
	____, ____, "en", "es", ____, ____, ____, ____, // x28 - x2f
	____, "fr", ____, ____, ____, "de", ____, ____, // x30 - x37
	____, ____, ____, ____, ____, ____, ____, ____, // x38 - x3f
	____, ____, ____, ____, ____, ____, "it", ____, // x40 - x47
	____, ____, ____, ____, ____, ____, ____, ____, // x48 - x4f
	____, ____, ____, ____, ____, ____, ____, ____, // x50 - x57
	____, ____, ____, ____, ____, ____, ____, ____, // x58 - x5f
	____, ____, ____, ____, ____, ____, ____, "nl", // x60 - x67
	____, ____, ____, ____, ____, ____, ____, ____, // x68 - x6f
	____, ____, ____, ____, "pl", "pt", ____, ____, // x70 - x77
	____, ____, ____, ____, ____, ____, ____, ____, // x78 - x7f
};
#undef ____


inline
static Byte
mapSquare(Byte sq)
{
	return sq::make(sq >> 3, sq & 7);
}


static mark::Color
mapColor(Byte c)
{
	switch (c)
	{
		case 2: return mark::Green;
		case 3: return mark::Yellow;
		case 4: return mark::Red;
	}

	return Mark::DefaultColor;
}


GameDecoder::GameDecoder(ByteStream& gStrm, ByteStream& aStrm, sys::utf8::Codec& codec, bool isChess960)
	:Decoder(gStrm, isChess960)
	,m_aStrm(aStrm)
	,m_codec(codec)
	,m_moveNo(MaxMoveNo)
{
	if (!m_aStrm.isEmpty())
	{
		if ((m_moveNo = m_aStrm.uint24()) == 0xffffff)
			m_moveNo = -1;
	}
}


void
GameDecoder::traverse(Consumer& consumer, MoveNode const* node)
{
	M_ASSERT(node);

	if (node->hasNote())
		consumer.putPrecedingComment(node->comment(move::Post), node->annotation(), node->marks());

	for (node = node->next(); node->isBeforeLineEnd(); node = node->next())
	{
		if (node->hasNote())
		{
			consumer.putMove(	node->move(),
									node->annotation(),
									node->comment(move::Ante),
									node->comment(move::Post),
									node->marks());
		}
		else
		{
			consumer.putMove(node->move());
		}

		if (node->hasMoveInfo())
			consumer.putMoveInfo(node->moveInfo());

		for (unsigned i = 0; i < node->variationCount(); ++i)
		{
			consumer.startVariation();
			traverse(consumer, node->variation(i));
			consumer.finishVariation();
		}
	}
}


void
GameDecoder::decodeComment(MoveNode* node, unsigned length, move::Position position)
{
	M_ASSERT(node);

	if (length < 2)
	{
		m_aStrm.skip(length);
		return;
	}

	uint16_t country = m_aStrm.uint16();
	length -= 2;

	unsigned char const* p = m_aStrm.data();

	mstl::string str;

	char const* lang = 0;

	if (country < U_NUMBER_OF(::LangMap))
		lang = ::LangMap[country];

	bool useXml = lang != 0 || node->comment(position).isXml();

	// BUG: ChessBase uses country code 0 for ALL and for Pol.
	//      How should we distinguish between these countries?

	str.reserve(length + 200);

	unsigned i = 0;
	while (i < length && ::isspace(p[i]))
		++i;

	for ( ; i < length; ++i)
	{
		Byte c = p[i];

		if (::isprint(c))
		{
			str += c;
		}
		else
		{
			nag::ID nag = nag::Null;

			switch (c)
			{
				case 0x0d:
					str.append(0x0a);
					if (i + 1 < length && p[i + 1] == 0x0a)
						++i;
					break;

				case 0xa2: str.append(char(0x01)); useXml = true; break;		// King
				case 0xa3: str.append(char(0x02)); useXml = true; break;		// Queen
				case 0xa4: str.append(char(0x05)); useXml = true; break;		// Knight
				case 0xa5: str.append(char(0x04)); useXml = true; break;		// Bishop
				case 0xa6: str.append(char(0x03)); useXml = true; break;		// Rook
				case 0xa7: str.append(char(0x06)); useXml = true; break;		// Pawn

				case 0x82: nag = nag::Attack; break; 								// "->"
				case 0x83: nag = nag::Initiative; break;							// "|^"
				case 0x84: nag = nag::Counterplay; break;							// "<=>"
				case 0x85: nag = nag::WithTheIdea; break;							// "/\"
				case 0x86: nag = nag::Space; break; 								// "()"
				case 0x87: nag = nag::Zugzwang; break;								// "(.)"
				case 0x90: nag = nag::Development; break;							// "@"
				case 0x91: nag = nag::Line; break; 									// "<->"
				case 0x92: nag = nag::Diagonal; break; 							// "/^"
				case 0x93: nag = nag::Zeitnot; break;								// "(+)"
				case 0x94: nag = nag::Center; break;								// "[+]"
				case 0x99: nag = nag::SingularMove; break;						// "[]"
				case 0xa9: nag = nag::WithCompensationForMaterial; break;	// "~/="
				case 0xaa: nag = nag::With; break; 									// "|_"
				case 0xab: nag = nag::Queenside; break; 							// "<<"
				case 0xac: nag = nag::Endgame; break; 								// "_|_"
				case 0xad: nag = nag::PairOfBishops; break; 						// "^^"
				case 0xae: nag = nag::BishopsOfOppositeColor; break; 			// "^_"
				case 0xaf: nag = nag::BishopsOfSameColor; break;				// "^="
				case 0xb0: nag = nag::WithCompensationForMaterial; break;	// "~/="
				case 0xb1: nag = nag::WhiteHasAModerateAdvantage; break; 	// "+/-"
				case 0xb2: nag = nag::WhiteHasASlightAdvantage; break; 		// "+/="
				case 0xb3: nag = nag::BlackHasASlightAdvantage; break; 		// "=/+"
				case 0xb5: nag = nag::BlackHasAModerateAdvantage; break; 	// "-/+"
				case 0xb9: nag = nag::BetterMove; break; 							// ">="
				case 0xba: nag = nag::Without; break; 								// "_|"
				case 0xbb: nag = nag::Kingside; break; 							// ">>"
				case 0xd7: nag = nag::WeakPoint; break; 							// "><"
				case 0xf7: nag = nag::UnclearPosition; break; 					// "~~"
				case 0xfe: nag = nag::PassedPawn; break; 							// "o^"

				case 0x9e:
					node->addAnnotation(nag::Diagram);								// "#"
					break;

				default:
					if (length == 1)
					{
						m_aStrm.skip(1);
						return; // seems to be a special instruction
					}
					if (Byte(c) > 0x07)
						str += c;
					break;
			}

			if (nag != nag::Null)
			{
				str.append(char(0x07));
				str.append(char(nag));
				useXml = true;
			}
		}
	}

	while (!str.empty() && ::isspace(str.back()) && (str.size() == 1 || *(str.end() - 2) != 0x07))
		str.resize(str.size() - 1);

	if (!str.empty())
	{
		if (useXml)
		{
			mstl::string tmp;
			tmp.swap(str);
			str.reserve(2*tmp.size() + 20);
			str.append("<xml><:", 7);
			if (lang)
				str.append(lang);
			str.append('>');

			for (char const* s = tmp; *s; ++s)
			{
				switch (*s)
				{
					case 0x01:	str.append("<sym>K</sym>", 12); break;
					case 0x02:	str.append("<sym>Q</sym>", 12); break;
					case 0x03:	str.append("<sym>R</sym>", 12); break;
					case 0x04:	str.append("<sym>B</sym>", 12); break;
					case 0x05:	str.append("<sym>N</sym>", 12); break;
					case 0x06:	str.append("<sym>P</sym>", 12); break;
					case 0x07:	str.format("<nag>%u</nag>", unsigned(Byte(*++s))); break;
					case '<':	str.append("&lt;",   4); break;
					case '>':	str.append("&gt;",   4); break;
					case '&':	str.append("&amp;",  5); break;
					case '\'':	str.append("&apos;", 6); break;
					case '"':	str.append("&quot;", 6); break;
					default:		str.append(*s); break;
				}
			}

			str.append("</:", 3);
			if (lang)
				str.append(lang);
			str.append("></xml>", 7);
		}

		// TODO: use character encoding according to language code ?!
		m_codec.toUtf8(str);

		if (!sys::utf8::validate(str))
			m_codec.forceValidUtf8(str);

		unsigned langFlags = 0;

		if (lang)
			langFlags |= (::strcmp(lang, "en") == 0) ? i18n::English : i18n::Other_Lang;

		Comment comment;
		comment.swap(str, langFlags);

		if (node->hasComment(position))
		{
			Comment c;
			node->swapComment(c, position);
			c.append(comment, '\n');
			c.normalize();
			node->swapComment(c, position);
		}
		else
		{
			comment.normalize();
			node->setComment(comment, position);
		}
	}

	m_aStrm.skip(length);
}


void
GameDecoder::decodeSymbols(MoveNode* node, unsigned length)
{
#define NAG(code) wtm ? nag::White##code : nag::Black##code

	static_assert(Annotation::Max_Nags >= 4, "ChessBase need at least four entries");

	if (length == 0)
		return;

	bool wtm = color::isWhite(node->move().color());	// white to move

	switch (m_aStrm.get())
	{
		case 0x01: node->addAnnotation(nag::GoodMove); break;
		case 0x02: node->addAnnotation(nag::PoorMove); break;
		case 0x03: node->addAnnotation(nag::VeryGoodMove); break;
		case 0x04: node->addAnnotation(nag::VeryPoorMove); break;
		case 0x05: node->addAnnotation(nag::SpeculativeMove); break;
		case 0x06: node->addAnnotation(nag::QuestionableMove); break;
		case 0x08: node->addAnnotation(nag::SingularMove); break;
		case 0x16: node->addAnnotation(NAG(IsInZugzwang)); break;
	}

	if (length == 1)
		return;

	switch (m_aStrm.get())
	{
		case 0x0b: node->addAnnotation(nag::DrawishPosition); break;
		case 0x0d: node->addAnnotation(nag::UnclearPosition); break;
		case 0x0e: node->addAnnotation(nag::WhiteHasASlightAdvantage); break;
		case 0x0f: node->addAnnotation(nag::BlackHasASlightAdvantage); break;
		case 0x10: node->addAnnotation(nag::WhiteHasAModerateAdvantage); break;
		case 0x11: node->addAnnotation(nag::BlackHasAModerateAdvantage); break;
		case 0x12: node->addAnnotation(nag::WhiteHasADecisiveAdvantage); break;
		case 0x13: node->addAnnotation(nag::BlackHasADecisiveAdvantage); break;
		case 0x20: node->addAnnotation(NAG(HasAModerateTimeAdvantage)); break;
		case 0x24: node->addAnnotation(NAG(HasTheInitiative )); break;
		case 0x28: node->addAnnotation(NAG(HasTheAttack)); break;
		case 0x2c: node->addAnnotation(NAG(HasSufficientCompensationForMaterialDeficit)); break;
		case 0x84: node->addAnnotation(NAG(HasModerateCounterplay)); break;
		case 0x8a: node->addAnnotation(nag::TimeLimit); break;
		case 0x92: node->addAnnotation(nag::Novelty); break;
	}

	if (length == 2)
		return;

	switch (m_aStrm.get())
	{
		case 0x8C: node->addAnnotation(nag::WithTheIdea); break;
		case 0x8D: node->addAnnotation(nag::AimedAgainst); break;
		case 0x8E: node->addAnnotation(nag::BetterMove); break;
		case 0x8F: node->addAnnotation(nag::WorseMove); break;
		case 0x90: node->addAnnotation(nag::EquivalentMove); break;
		case 0x91: node->addAnnotation(nag::EditorsRemark); break;
	}

#undef NAG
}


void
GameDecoder::decodeSquares(MoveNode* node, unsigned length)
{
	for ( ; length >= 2; length -= 2)
	{
		mark::Color c = ::mapColor(m_aStrm.get());
		Square s = ::mapSquare(m_aStrm.get() - 1);

		if (s <= sq::h8)
			node->addMark(Mark(mark::Full, c, s));
	}

	m_aStrm.skip(length);	// to be sure
}


void
GameDecoder::decodeArrows(MoveNode* node, unsigned length)
{
	for ( ; length >= 3; length -= 3)
	{
		mark::Color c = ::mapColor(m_aStrm.get());
		Square s = ::mapSquare(m_aStrm.get() - 1);
		Square t = ::mapSquare(m_aStrm.get() - 1);

		if (s <= sq::h8 && t <= sq::h8)
			node->addMark(Mark(mark::Arrow, c, s, t));
	}

	m_aStrm.skip(length);	// to be sure
}


void
GameDecoder::appendTextAnnotation(MoveNode* node, mstl::string const& text)
{
	M_ASSERT(node);

	mstl::string str(text);
	Comment comment;
	comment.swap(str, i18n::English);

	if (node->hasComment(move::Post))
	{
		Comment c;
		node->swapComment(c, move::Post);
		c.append(comment, '\n');
		c.normalize();
		node->swapComment(c, move::Post);
	}
	else
	{
		comment.normalize();
		node->setComment(comment, move::Post);
	}
}


// Annotation type 0x07: time spent on the move.
// Payload: hours, minutes, seconds, and a marker byte (0x1e on the
// first record per side).
void
GameDecoder::decodeTimeSpent(MoveNode* node, unsigned length)
{
	if (length < 3)
	{
		m_aStrm.skip(length);
		return;
	}

	unsigned h = m_aStrm.get();
	unsigned m = m_aStrm.get();
	unsigned s = m_aStrm.get();

	m_aStrm.skip(length - 3);

	if (h < 24 && m < 60 && s < 60)
	{
		char buf[16];
		::snprintf(buf, sizeof(buf), "%u:%02u:%02u", h, m, s);

		MoveInfo info;

		if (info.parseElapsedMoveTime(buf))
			node->addMoveInfo(info);
	}
}


// Annotation types 0x16/0x17: white/black clock display after the move.
// Payload: clock time in hundredths of a second (big-endian); the side
// is implied by the move the record is attached to.
void
GameDecoder::decodeClock(MoveNode* node, unsigned length)
{
	if (length < 4)
	{
		m_aStrm.skip(length);
		return;
	}

	unsigned centiSecs = m_aStrm.uint32();

	m_aStrm.skip(length - 4);

	unsigned secs = centiSecs/100;

	if (secs < 24*3600)
	{
		char buf[16];
		::snprintf(buf, sizeof(buf), "%u:%02u:%02u", secs/3600, (secs/60) % 60, secs % 60);

		MoveInfo info;

		if (info.parsePlayersClock(buf))
			node->addMoveInfo(info);
	}
}


// Annotation type 0x18: critical position marker.
// Payload: 1 = opening, 2 = middlegame, 3 = endgame.
// These display records have no equivalent in MoveNode. Keep their complete
// payload at the original node; in particular, 0x23's leading byte is NOT
// always zero (cbm168 has 02 00 00 00), so interpreting it as RGB loses data.
void
GameDecoder::preserveDisplayAnnotation(MoveNode* node, unsigned length, char const* label)
{
	mstl::string text(label);
	text += " (CBH payload:";
	for (unsigned i = 0; i < length; ++i)
	{
		char hex[4];
		::snprintf(hex, sizeof(hex), " %02X", unsigned(m_aStrm.get()));
		text += hex;
	}
	text += ')';
	appendTextAnnotation(node, text);
}


void
GameDecoder::decodeMedal(MoveNode* node, unsigned length)
{
	// A big-endian mask with the same low 16 bits as the index medals.
	// Unlike the index, this record also identifies the annotated move.
	if (length != 4)
	{
		preserveDisplayAnnotation(node, length, "Medal");
		return;
	}

	unsigned medals = m_aStrm.uint32();
	static char const* const names[] =
	{
		"Best game", "Decided tournament", "Model game", "Novelty",
		"Pawn structure", "Strategy", "Tactics", "Attack", "Sacrifice",
		"Defense", "Material", "Piece play", "Endgame", "Tactical blunder",
		"Strategical blunder", "User",
	};
	mstl::string text("Medal: ");
	bool separator = false;
	for (unsigned bit = 0; bit < 16; ++bit)
	{
		if (medals & (1u << bit))
		{
			if (separator) text += ", ";
			text += names[bit];
			separator = true;
		}
	}
	if (medals & 0xffff0000u)
	{
		char unknown[40];
		::snprintf(unknown, sizeof(unknown), "Unknown bits 0x%08X", medals & 0xffff0000u);
		if (separator) text += ", ";
		text += unknown;
	}
	else if (!separator)
	{
		text += "None";
	}
	appendTextAnnotation(node, text);
}


void
GameDecoder::decodeCriticalPosition(MoveNode* node, unsigned length)
{
	if (length < 1)
		return;

	Byte phase = m_aStrm.get();

	m_aStrm.skip(length - 1);

	char const* text = 0;

	switch (phase)
	{
		case 1: text = "Critical opening position"; break;
		case 2: text = "Critical middlegame position"; break;
		case 3: text = "Critical endgame position"; break;
	}

	if (text)
		appendTextAnnotation(node, text);
}


// Annotation type 0x24: time control (game-wide record).
// Payload: up to three 11-byte series - initial time (4 bytes) and
// increment (4 bytes) in hundredths of a second (big-endian), move
// count (2 bytes; 1000 = rest of the game), series type (1 byte).
// Result is stored in PGN TimeControl syntax for the tag section.
void
GameDecoder::decodeTimeControl(unsigned length)
{
	m_timeControl.clear();

	for ( ; length >= 11; length -= 11)
	{
		unsigned initial	= m_aStrm.uint32()/100;
		unsigned increment= m_aStrm.uint32()/100;
		unsigned moves		= m_aStrm.uint16();
		Byte		type		= m_aStrm.get();

		(void)type;

		if (initial == 0 && moves == 0)
			continue;

		if (!m_timeControl.empty())
			m_timeControl.append(':');

		if (moves != 0 && moves != 1000)
			m_timeControl.format("%u/", moves);

		m_timeControl.format("%u", initial);

		if (increment)
			m_timeControl.format("+%u", increment);
	}

	m_aStrm.skip(length);
}


// Read and discard one "string set" as used by annotation type 0x09:
// u16 LE count, then per entry (u16 LE language/kind, u16 LE byte length,
// payload). Language/kind 0 = English text, 1 = German (and other codes
// for further languages), 7 = packed 3-byte (color,from,to) board arrows,
// 8 = packed 2-byte (color,square) colored squares.
// If a preferred-language string is found (lang 0 = English, else the
// first text entry seen), it is appended to *text (nullptr to discard).
// Returns false if the stream is exhausted mid-set.
bool
GameDecoder::skipStringSet(mstl::string* text)
{
	if (m_aStrm.remaining() < 2)
		return false;

	unsigned count = m_aStrm.uint16LE();
	bool haveText = false;

	for (unsigned i = 0; i < count; ++i)
	{
		if (m_aStrm.remaining() < 4)
			return false;

		unsigned lang = m_aStrm.uint16LE();
		unsigned len  = m_aStrm.uint16LE();

		if (len > m_aStrm.remaining())
			return false;

		if (text && !haveText && lang <= 1)
		{
			unsigned char const* p = m_aStrm.data();
			mstl::string s(reinterpret_cast<char const*>(p), len);
			m_codec.toUtf8(s);
			if (!sys::utf8::validate(s))
				m_codec.forceValidUtf8(s);
			text->append(s);
			haveText = lang == 0;	// keep looking only if we haven't seen English yet
		}

		m_aStrm.skip(len);
	}

	return true;
}


// Annotation type 0x09: interactive training question (quiz).
// Payload: u16 version(=1), u8 question type (1=move entry, 2=multiple
// choice), u16 data length, u32 allotted time (seconds), u16 max points,
// then four fixed string sets (question, wrong-move feedback, hint,
// unused). For type 1: u8 candidate count, then per candidate
// (u8 from-square, u8 to-square, s16 BE points, feedback string set),
// squares in the column-major (file*8+rank) encoding used throughout
// .cbg/.cba. For type 2: u8 choice count, then per choice (s8 points,
// text string set, feedback string set).
// Rendered as a readable text comment; there is no scidb model for an
// interactive quiz, so this makes the content visible rather than
// silently dropping it.
void
GameDecoder::decodeTraining(MoveNode* node, unsigned length)
{
	unsigned const start = m_aStrm.remaining();

	if (length < 11 || length > start)
	{
		m_aStrm.skip(length);
		return;
	}

	m_aStrm.uint16LE();				// version (always 1 observed)
	Byte qtype = m_aStrm.get();
	m_aStrm.uint16LE();				// data length (redundant with the annotation length)
	m_aStrm.uint32LE();				// allotted time in seconds
	m_aStrm.uint16LE();				// max points

	mstl::string question;
	mstl::string wrongFeedback;
	mstl::string hint;

	bool ok =		skipStringSet(&question)
					&& skipStringSet(&wrongFeedback)
					&& skipStringSet(&hint)
					&& skipStringSet(0);	// unused fourth slot (always empty)

	mstl::string text;

	if (ok && (qtype == 1 || qtype == 2))
	{
		if (m_aStrm.remaining() < 1)
		{
			ok = false;
		}
		else
		{
			unsigned n = m_aStrm.get();

			text.append("Training: ", 10);
			text.append(question);

			for (unsigned i = 0; ok && i < n; ++i)
			{
				mstl::string feedback;
				int points = 0;

				if (qtype == 1)
				{
					if (m_aStrm.remaining() < 4) { ok = false; break; }

					Byte fromSq = m_aStrm.get();
					Byte toSq   = m_aStrm.get();

					points = int16_t(m_aStrm.uint16());	// signed, big-endian

					if (!skipStringSet(&feedback)) { ok = false; break; }

					char buf[8];
					::snprintf(buf, sizeof(buf), "%c%c-%c%c",
									sq::printFyle(::mapSquare(fromSq)),
									sq::printRank(::mapSquare(fromSq)),
									sq::printFyle(::mapSquare(toSq)),
									sq::printRank(::mapSquare(toSq)));
					text.append("\n- ", 3);
					text.append(buf);
				}
				else
				{
					if (m_aStrm.remaining() < 1) { ok = false; break; }

					points = int8_t(m_aStrm.get());

					mstl::string choiceText;

					if (!skipStringSet(&choiceText) || !skipStringSet(&feedback)) { ok = false; break; }

					text.append("\n- ", 3);
					text.append(choiceText);
				}

				char pbuf[16];
				::snprintf(pbuf, sizeof(pbuf), " (%d pt)", points);
				text.append(pbuf);

				if (!feedback.empty())
				{
					text.append(": ", 2);
					text.append(feedback);
				}
			}
		}
	}
	else
	{
		ok = false;
	}

	unsigned consumed = start - m_aStrm.remaining();

	if (!ok || consumed > length)
	{
		// Grammar mismatch (unexpected variant): skip whatever remains of
		// this record rather than desynchronizing the annotation stream.
		m_aStrm.skip(length - mstl::min(consumed, length));
		return;
	}

	m_aStrm.skip(length - consumed);

	if (!text.empty())
		appendTextAnnotation(node, text);
}


// Annotation type 0x13: game quotation (a reference to a different,
// historical game cited by the annotator). Header: u16 BE total length
// (== the payload length), u16 BE name count (always 2 observed),
// white name (u16 BE lang + u8 len + latin1 bytes), black name (u8 lang +
// u8 len + latin1 bytes), u8 flag + u16 BE white Elo + u16 BE black Elo +
// u16 BE raw ECO, event name (u8 len + latin1 bytes), site name (u8 lang +
// u8 len + latin1 bytes), u16 BE pad + 3-byte BE packed date
// (year = v>>9, month = (v>>5)&0xf, day = v&0x1f - same packing as the
// classic .cbh index date field), u8 time mode, u8 tournament type,
// u16 BE nation + u16 BE category + u16 BE total rounds, u8 subround,
// u8 round, u8 result (0=0-1, 1=1/2-1/2, 2=1-0, 3=*), u16 BE medals, then
// a two-byte-per-move stream (see cbh_quotation.cpp).
// Rendered as a citation with ECO and, when fully validated, numbered SAN.
void
GameDecoder::decodeQuotation(MoveNode* node, unsigned length)
{
	unsigned const start = m_aStrm.remaining();

	if (length < 2 || length > start)
	{
		m_aStrm.skip(length);
		return;
	}

	// Bound every header read to this record, not the following annotations.
	ByteStream strm(m_aStrm.data(), length);
	m_aStrm.skip(length);
	bool ok = true;

	auto need = [&](unsigned n) -> bool { return ok = ok && (strm.remaining() >= n); };

	mstl::string white, black, event, site;
	unsigned round = 0, result = 4, eco = 0;
	unsigned year = 0, month = 0, day = 0;

	if (need(2)) ok = strm.uint16() == length;	// payload length (redundant)
	if (need(2)) ok = strm.uint16() == 2;	// supported name count

	if (need(2)) strm.uint16();			// white name language (2 bytes)
	if (need(1))
	{
		unsigned len = strm.get();
		if (need(len))
		{
			white.assign(reinterpret_cast<char const*>(strm.data()), len);
			m_codec.toUtf8(white);
			if (!sys::utf8::validate(white))
				m_codec.forceValidUtf8(white);
			strm.skip(len);
		}
	}

	if (need(1)) strm.get();				// black name language (1 byte)
	if (need(1))
	{
		unsigned len = strm.get();
		if (need(len))
		{
			black.assign(reinterpret_cast<char const*>(strm.data()), len);
			m_codec.toUtf8(black);
			if (!sys::utf8::validate(black))
				m_codec.forceValidUtf8(black);
			strm.skip(len);
		}
	}

	if (need(7))
	{
		strm.get(); strm.uint16(); strm.uint16(); // flag, Elo x2
		eco = (strm.uint16() >> 7) & 0x1ff;
	}

	if (need(1))
	{
		unsigned len = strm.get();
		if (need(len))
		{
			event.assign(reinterpret_cast<char const*>(strm.data()), len);
			m_codec.toUtf8(event);
			if (!sys::utf8::validate(event))
				m_codec.forceValidUtf8(event);
			strm.skip(len);
		}
	}

	if (need(1)) strm.get();				// site language
	if (need(1))
	{
		unsigned len = strm.get();
		if (need(len))
		{
			site.assign(reinterpret_cast<char const*>(strm.data()), len);
			m_codec.toUtf8(site);
			if (!sys::utf8::validate(site))
				m_codec.forceValidUtf8(site);
			strm.skip(len);
		}
	}

	if (need(2)) strm.uint16();			// pad

	if (need(3))
	{
		unsigned v = (unsigned(strm.get()) << 16) | (unsigned(strm.get()) << 8) | strm.get();
		year = v >> 9;
		month = (v >> 5) & 0xf;
		day = v & 0x1f;
	}

	if (need(2)) { strm.get(); strm.get(); }	// time mode, tournament type
	if (need(6)) { strm.uint16(); strm.uint16(); strm.uint16(); }	// nation, category, total rounds
	if (need(1)) strm.get();				// subround
	if (need(1)) round = strm.get();
	if (need(1)) result = strm.get();
	if (need(2)) strm.uint16();			// medals

	if (!ok || white.empty() || black.empty())
		return;

	mstl::string moves;
	decodeQuotationMoves(strm.data(), strm.remaining(), moves);

	static char const* ResultText[] = { "0-1", "1/2-1/2", "1-0", "*" };

	mstl::string text("Quoted game: ", 13);
	text.append(white);
	text.append(" - ", 3);
	text.append(black);

	if (!event.empty())
	{
		text.append(", ", 2);
		text.append(event);
	}
	if (!site.empty())
	{
		text.append(", ", 2);
		text.append(site);
	}
	if (year)
	{
		char buf[16];
		if (month && day)
			::snprintf(buf, sizeof(buf), " (%04u.%02u.%02u)", year, month, day);
		else
			::snprintf(buf, sizeof(buf), " (%04u)", year);
		text.append(buf);
	}
	if (round)
	{
		char buf[16];
		::snprintf(buf, sizeof(buf), ", round %u", round);
		text.append(buf);
	}
	if (result < 4)
	{
		text.append(", ", 2);
		text.append(ResultText[result]);
	}

	if (eco >= 1 && eco <= 500)
	{
		text += ", ECO ";
		text += Eco::fromShort(eco).asShortString();
	}
	if (!moves.empty())
	{
		text += "\n";
		text += moves;
		if (result < 4)
		{
			text += ' ';
			text += ResultText[result];
		}
	}

	appendTextAnnotation(node, text);
}


void
GameDecoder::getAnnotation(MoveNode* node, int moveNo)
{
	M_ASSERT(moveNo != MaxMoveNo);
	M_ASSERT(node);

	if (moveNo < m_moveNo)
		return;

	if (__m_unlikely(m_aStrm.isEmpty()))
		throw DecodingFailedException("unexpected end of annotation stream (moveNo=%d)", moveNo);

	while (moveNo == m_moveNo)
	{
		Byte		type		= m_aStrm.get();
		unsigned length	= m_aStrm.uint16() - 6;

		if (length > m_aStrm.remaining())
		{
			m_aStrm.skip(m_aStrm.remaining());
			return;
		}

		switch (type)
		{
			case 0x82:	// text before move
				if (!node->atLineStart())
				{
					decodeComment(node, length, move::Ante);
					break;
				}
				// fallthru

			case 0x02:	// text after move
				decodeComment(node, length, move::Post);
				break;

			case 0x03:	// symbols
				if (__m_unlikely(length > 3))
					throw DecodingFailedException("bad data (annotation type 0x03, length=%u)", length);
				decodeSymbols(node, length);
				break;

			case 0x04:	// squares
				decodeSquares(node, length);
				break;

			case 0x05:	// arrows
				decodeArrows(node, length);
				break;

			case 0x07:	// time spent on the move
				decodeTimeSpent(node, length);
				break;

			case 0x16:	// white clock
			case 0x17:	// black clock
				decodeClock(node, length);
				break;

			case 0x18:	// critical position marker
				decodeCriticalPosition(node, length);
				break;

			case 0x24:	// time control (game-wide)
				decodeTimeControl(length);
				break;

			case 0x09:	// training question (quiz)
				decodeTraining(node, length);
				break;

			case 0x13:	// game quotation
				decodeQuotation(node, length);
				break;

			case 0x22:	// medal at this move (or game-wide)
				decodeMedal(node, length);
				break;

			case 0x23:	// variation display color; mode byte unresolved
				preserveDisplayAnnotation(node, length, "Variation color");
				break;

			case 0x14:	// pawn structure display
				preserveDisplayAnnotation(node, length, "Pawn structure");
				break;

			case 0x15:	// piece path display
				preserveDisplayAnnotation(node, length, "Piece path");
				break;

			default:
				m_aStrm.skip(length);
				break;
		}

		if (m_aStrm.isEmpty())
			m_moveNo = MaxMoveNo;
		else if ((m_moveNo = m_aStrm.uint24()) == 0xffffff)
			m_moveNo = -1;
	}
}


#if 0
void
GameDecoder::decodeMoves(Consumer& consumer)
{
	MoveNode	node;
	Comment	comment;
	unsigned	count = 0;
	Move		move;

	while (true)
	{
		switch (decodeMove(move, count))
		{
			case ::Move:
				if (!move)
					return;
				getAnnotation(&node, int(count) - 1);
				if (node.hasNote())
				{
					consumer.putMove(move, node.annotation(), comment, comment, node.marks());
					node.clearAnnotation();
					node.clearMarks();
				}
				else
				{
					consumer.putMove(move);
				}
				break;

			case ::Push:
				IO_RAISE(Game, Corrupted, "unexpected PUSH at move count %u", count);
				break;

			case ::Pop:
				return;
		}
	}
}
#endif


void
GameDecoder::decodeMoves(MoveNode* root, unsigned& count)
{
	typedef mstl::vector<MoveNode*> Vars;

	Vars varList;
	Move move;

	while (true)
	{
		MoveNode* node;

		switch (decodeMove(move, count))
		{
			case Token_Move:
				if (move)
				{
					node = new MoveNode(move);

					if (varList.empty())
					{
						root->setNext(node);
					}
					else
					{
						// first variation is main line
						// main line is last variation

						MoveNode* main = varList[0];

						if (!main->next())
							IO_RAISE(Game, Corrupted, "bad data (variation without next move, count=%u)", count);

						root->setNext(main->removeNext());
						root = root->next();

						for (unsigned i = 1; i < varList.size(); ++i)
						{
							MoveNode* var  = varList[i];
							MoveNode* next = var->next();

#ifndef ALLOW_EMPTY_VARS
							if (next->atLineEnd())
							{
								// Scidb does not support empty variations,
								// but we cannot delete the variation if a
								// comment/annotation/mark exists. As a
								// workaround we insert a null move.
								// Note: Possibly it isn't possible to enter
								// empty variations in ChessBase, but we like
								// to handle this case for safety reasons.
								if (var->hasSupplement() || next->hasSupplement())
								{
									Move null(Move::null());
									null.setColor(move.color());
									next = new MoveNode(null);
									next->setNext(var->removeNext());
									var->setNext(next);
								}
							}
#endif

							if (next->isBeforeLineEnd())
								root->addVariation(var);
						}

						root->addVariation(main);
						main->setNext(node);
						varList.clear();
					}

					getAnnotation(node, int(count) - 1);
					root = node;
				}
				else
				{
					throw DecodingFailedException("corrupted data (null move at count %u)", count);
				}
				break;

			case Token_Push:
				node = new MoveNode;
				varList.push_back(node);
				pushCipherState();
				decodeMoves(node, count);
				popCipherState();
				break;

			case Token_Pop:
				root->setNext(new MoveNode);
				return;
		}
	}
}


void
GameDecoder::decodeMoves(MoveNode* root, unsigned& count, MoveNodeAllocator& allocator)
{
	typedef mstl::vector<MoveNode*> Vars;

	Vars varList;
	Move move;

	while (true)
	{
		MoveNode* node;

		switch (decodeMove(move, count))
		{
			case Token_Move:
				if (move)
				{
					(node = allocator.allocate())->setMove(move);

					if (varList.empty())
					{
						M_REQUIRE(root->next() == 0);
						root->setNext(node);
					}
					else
					{
						// first variation is main line
						// main line is last variation

						MoveNode* main = varList[0];

						if (!main->next())
							IO_RAISE(Game, Corrupted, "bad data (variation without next move, count=%u)", count);

						M_REQUIRE(root->next() == 0);
						root->setNext(main->removeNext());
						root = root->next();

						for (unsigned i = 1; i < varList.size(); ++i)
						{
							MoveNode* var  = varList[i];
							MoveNode* next = var->next();

#ifndef ALLOW_EMPTY_VARS
							if (next->atLineEnd())
							{
								// Scidb does not support empty variations,
								// but we cannot delete the variation if a
								// comment/annotation/mark exists. As a
								// workaround we insert a null move.
								// Note: Possibly it isn't possible to enter
								// empty variations in ChessBase, but we like
								// to handle this case for safety reasons.
								if (var->hasSupplement() || next->hasSupplement())
								{
									Move null(Move::null());
									null.setColor(move.color());
									(next = allocator.allocate())->setMove(null);
									M_REQUIRE(next->next() == 0);
									next->setNext(var->removeNext());
									M_REQUIRE(var->next() == 0);
									var->setNext(next);
								}
							}
#endif

							if (next->isBeforeLineEnd())
								root->addVariation(var);
						}

						root->addVariation(main);
						M_REQUIRE(main->next() == 0);
						main->setNext(node);
						varList.clear();
					}

					getAnnotation(node, int(count) - 1);
					root = node;
				}
				else
				{
					throw DecodingFailedException("corrupted data (null move at count %u)", count);
				}
				break;

			case Token_Push:
				node = allocator.allocate();
				varList.push_back(node);
				pushCipherState();
				decodeMoves(node, count, allocator);
				popCipherState();
				break;

			case Token_Pop:
				M_REQUIRE(root->next() == 0);
				root->setNext(allocator.allocate());
				return;
		}
	}
}


MoveNode*
GameDecoder::decodeMoves(MoveNode* root)
{
	unsigned count = 0;
	getAnnotation(root, -1);	// consume game-level records (moveNo 0xffffff)
	decodeMoves(root, count);
	return root;
}


MoveNode*
GameDecoder::decodeMoves(MoveNodeAllocator& allocator)
{
	unsigned		count	= 0;
	MoveNode*	root	= allocator.allocate();

	getAnnotation(root, -1);	// consume game-level records (moveNo 0xffffff)
	decodeMoves(root, count, allocator);
	return root;
}


void
GameDecoder::startDecoding(TagSet* tags)
{
	unsigned word = m_gStrm.uint32();


	if (word & 0x40000000)
	{
		setupStartPosition(tags);
	}
	else
	{
		m_position.setup();
	}
}


unsigned
GameDecoder::doDecoding(uint16_t* moves, unsigned length, Board& startBoard)
{
	startDecoding();
	startBoard = m_position.board();

	unsigned	count	= 0;
	Move		move;

	for (unsigned i = 0; i < length; ++i)
	{
		switch (decodeMove(move, count))
		{
			case Token_Move:
				moves[i] = move.index();
				break;

			case Token_Pop:
				return i;
		}
	}

	return length;
}


unsigned
GameDecoder::doDecoding(GameData& data)
{
	startDecoding(&data.m_tags);
	data.m_startBoard = m_position.board();
	unsigned plyNumber = m_position.board().plyNumber();
	decodeMoves(data.m_startNode);
	if (!m_timeControl.empty() && !data.m_tags.contains(tag::TimeControl))
		data.m_tags.set(tag::TimeControl, m_timeControl);
	return m_position.board().plyNumber() - plyNumber;
}


save::State
GameDecoder::doDecoding(Consumer& consumer,
								TagSet& tags,
								GameInfo const& info,
								MoveNodeAllocator& allocator)
{
	startDecoding(&tags);

	allocator.release();
	allocator.reserve(mstl::mul2(m_gStrm.size()));

	MoveNode* root = allocator.allocate();
	getAnnotation(root, -1);	// consume game-level records (moveNo 0xffffff)

	if (!m_timeControl.empty() && !tags.contains(tag::TimeControl))
		tags.set(tag::TimeControl, m_timeControl);

	if (!consumer.startGame(tags, m_position.board()))
		return save::UnsupportedVariant;

	unsigned plyNumber = m_position.board().plyNumber();
	consumer.startMoveSection();

#if 0
	// Annoying. We cannot use the direct decoding, because the
	// game may contain wrong information about the existence of
	// sub-variations.
	if (info.countVariations() == 0 && info.countComments() == 0)
	{
		// fast decoding
		decodeMoves(consumer);
	}
	else
#endif
	{
		unsigned count = 0;
		decodeMoves(root, count, allocator);
		traverse(consumer, root);
	}

	char buf[32];
	::snprintf(buf, sizeof(buf), "%u", m_position.board().plyNumber() - plyNumber);
	tags.set(tag::PlyCount, buf);

	if (!m_timeControl.empty() && !tags.contains(tag::TimeControl))
		tags.set(tag::TimeControl, m_timeControl);

	consumer.finishMoveSection(result::fromString(tags.value(tag::Result)));
	return consumer.finishGame(tags);
}


db::Move
GameDecoder::findExactPosition(Board const& position, bool skipVariations)
{
	startDecoding();

	unsigned	count = 0;
	bool		found	= false;
	Move		move;

	if (m_position.board().isEqualPosition(position))
		found = true;

	while (true)
	{
		unsigned tag = decodeMove(move, count);

		if (found)
			return move;

		switch (tag)
		{
			case Token_Move:
				if (!move || !m_position.board().signature().isReachablePawns(position.signature()))
					return Move::invalid();
				if (m_position.board().isEqualPosition(position))
					found = true;
				break;

			case Token_Pop:
				if (skipVariations)
					return Move::invalid();
				break;
		}
	}

	return move;	// not reached
}

// vi:set ts=3 sw=3:
