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
// Copyright: (C) 2026 Michael Thomas (Chesswiz)
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#include "cbh_consumer.h"
#include "cbh_codec.h"

#include "db_game_info.h"
#include "db_tag_set.h"
#include "db_mark_set.h"
#include "db_annotation.h"
#include "db_move.h"
#include "db_move_node.h"
#include "db_comment.h"

#include "sys_utf8_codec.h"

using namespace util;

namespace db {
namespace cbh {

Consumer::Consumer(	format::Type srcFormat,
							Codec& codec,
							mstl::string const& encoding,
							TagBits const& allowedTags,
							bool allowExtraTags,
							LanguageList const* languages,
							unsigned significantLanguages)
	:Encoder(m_gameStream)
	,db::Consumer(srcFormat, encoding, allowedTags, allowExtraTags, languages, significantLanguages)
	,m_gameStream(m_gameBuffer, sizeof(m_gameBuffer))
	,m_annotationStream(m_annotationBuffer, sizeof(m_annotationBuffer))
	,m_codec(codec)
	,m_annotationEncoder(m_annotationStream, *codec.m_codec)
	,m_count(0)
	,m_root(0)
	,m_current(0)
	,m_whiteToMove(true)
	,m_isStandardPosition(true)
	,m_isGuidingText(false)
{
}


Consumer::~Consumer()
{
	deleteTree();
}


void
Consumer::deleteTree()
{
	delete m_root;	// recursively deletes next chain and variations
	m_root = 0;
	m_current = 0;
	m_branchStack.clear();
}


format::Type
Consumer::format() const
{
	return format::ChessBase;
}


bool
Consumer::supportsVariant(variant::Type variant) const
{
	return variant == variant::Normal;
}


bool
Consumer::beginGame(TagSet const& tags)
{
	m_gameStream.reset(sizeof(m_gameBuffer));
	m_gameStream.resetp();
	m_annotationStream.reset(sizeof(m_annotationBuffer));
	m_annotationStream.resetp();

	m_isGuidingText = tags.contains(tag::Remark) && tags.value(tag::Remark) == "GUIDING_TEXT";

	bool isStandard = startBoard().isStandardPosition(variant::Normal);
	m_isStandardPosition = isStandard;
	if (!m_isGuidingText)
		Encoder::startEncoding(board(), isStandard);

	m_count = 0;
	deleteTree();
	m_root = new MoveNode;
	m_current = m_root;
	m_whiteToMove = (board().sideToMove() == color::White);

	return true;
}


save::State
Consumer::endGame(TagSet const& tags)
{
	if (m_isGuidingText)
	{
		m_gameStream.reset(sizeof(m_gameBuffer));
		m_gameStream.resetp();
		m_annotationStream.reset(sizeof(m_annotationBuffer));
		m_annotationStream.resetp();

		mstl::string title = tags.value(tag::Event);
		mstl::string body;
		if (m_root)
		{
			body = m_root->comment(move::Post).content();
			deleteTree();
		}

		if (m_codec.m_codec)
		{
			m_codec.m_codec->fromUtf8(title);
			m_codec.m_codec->fromUtf8(body);
		}

		// Write guiding-text .cbg record (type 1) matching decodeGuidingTextBody():
		// 8-byte header:
		//   uint32 BE: 0x80000000 | totalSize
		//   uint8:     1 (type 1)
		//   uint8:     0
		//   uint16 LE: numTitles (1 if title non-empty, else 0)
		// Title (if numTitles == 1):
		//   uint16 LE: 0 (English)
		//   uint16 LE: titleLen
		//   bytes:     title
		// Body (type 1):
		//   uint8:     0 (language)
		//   uint32 LE: 0 (id)
		//   uint16 LE: bodyLen
		//   bytes:     body
		//   uint8:     0 (trailing padding so remaining() > 7 before body even when bodyLen == 0)
		unsigned titleLen = mstl::min(unsigned(title.size()), 65535u);
		unsigned maxBody = sizeof(m_gameBuffer) - 32 - titleLen;
		unsigned bodyLen = mstl::min(unsigned(body.size()), mstl::min(65535u, maxBody));
		unsigned numTitles = titleLen > 0 ? 1u : 0u;
		unsigned totalSize = 8 + (numTitles ? (4 + titleLen) : 0) + 7 + bodyLen + 1;

		m_gameStream << uint32_t(0x80000000u | totalSize);
		m_gameStream.put(Byte(1));
		m_gameStream.put(Byte(0));
		m_gameStream.put(Byte(numTitles & 0xff));
		m_gameStream.put(Byte((numTitles >> 8) & 0xff));

		if (numTitles)
		{
			m_gameStream.put(Byte(0));
			m_gameStream.put(Byte(0));
			m_gameStream.put(Byte(titleLen & 0xff));
			m_gameStream.put(Byte((titleLen >> 8) & 0xff));
			m_gameStream.put(reinterpret_cast<Byte const*>(title.data()), titleLen);
		}

		m_gameStream.put(Byte(0));
		m_gameStream.put(Byte(0));
		m_gameStream.put(Byte(0));
		m_gameStream.put(Byte(0));
		m_gameStream.put(Byte(0));
		m_gameStream.put(Byte(bodyLen & 0xff));
		m_gameStream.put(Byte((bodyLen >> 8) & 0xff));
		if (bodyLen > 0)
			m_gameStream.put(reinterpret_cast<Byte const*>(body.data()), bodyLen);
		m_gameStream.put(Byte(0));

		m_gameStream.provide();
		m_annotationStream.provide();

		return m_codec.addGame(m_gameStream, m_annotationStream, tags, *this);
	}

	m_gameStream.provide();
	m_annotationStream.provide();

	unsigned gameSize = m_gameStream.size();
	uint32_t gameHeader = gameSize;
	if (!m_isStandardPosition)
		gameHeader |= 0x40000000;
	if (isChess960())
		gameHeader |= 0x0a000000;  // Chess960 (0x08000000 | 0x02000000)
	util::ByteStream::set(m_gameStream.base(), gameHeader);

	return m_codec.addGame(m_gameStream, m_annotationStream, tags, *this);
}


save::State
Consumer::skipGame(TagSet const&)
{
	return save::Ok;
}


void Consumer::start() {}
void Consumer::finish() {}
void Consumer::beginMoveSection() {}


void
Consumer::endMoveSection(result::ID)
{
	// CBH stores the main continuation of a branch as the FIRST pushed
	// variation and the last alternative inline ("first variation is main
	// line, main line is last variation" — see GameDecoder::decodeMoves).
	// The consumer callbacks arrive in source order (variations after the
	// mainline move), so the game is buffered as a tree and emitted here
	// in ChessBase order. Every CBH game move stream ends with a final
	// Token_Pop (which also guarantees size > 4 for zero-move games).
	if (m_root && !m_isGuidingText)
	{
		// Game-level records use the 0xffffff sentinel (decoder maps it to -1).
		m_annotationEncoder.encodeComment(0xffffff, m_root->comment(move::Post), move::Ante);
		m_annotationEncoder.encodeAnnotation(0xffffff, m_root->annotation(), m_whiteToMove);
		m_annotationEncoder.encodeMarks(0xffffff, m_root->marks());

		emitLine(m_root->next());
		Encoder::encodePop(m_count);
		deleteTree();
	}
}


void
Consumer::emitMoveRecords(MoveNode const* node)
{
	// The decoder attaches annotation records via getAnnotation(node, count - 1),
	// where count is its monotone move counter after decoding this move, and
	// restores symbol colors from the color of the annotated move.
	unsigned moveNo = m_count;

	m_annotationEncoder.encodeComment(moveNo, node->comment(move::Ante), move::Ante);

	Encoder::encodeMove(node->move(), m_count);

	m_annotationEncoder.encodeComment(moveNo, node->comment(move::Post), move::Post);
	m_annotationEncoder.encodeAnnotation(	moveNo,
														node->annotation(),
														color::isWhite(node->move().color()));
	m_annotationEncoder.encodeMarks(moveNo, node->marks());
}


void
Consumer::emitLine(MoveNode const* node)
{
	for ( ; node; node = node->next())
	{
		// Collect variations that contain at least one move
		// (CBH cannot represent empty variations).
		unsigned varCount = 0;
		unsigned lastVar  = 0;

		for (unsigned i = 0; i < node->variationCount(); ++i)
		{
			if (node->variation(i)->next())
			{
				++varCount;
				lastVar = i;
			}
		}

		if (varCount == 0)
		{
			emitMoveRecords(node);
			continue;
		}

		// Main continuation first, as a pushed variation.
		position().push();
		Encoder::encodePush(m_count);
		emitMoveRecords(node);
		emitLine(node->next());
		Encoder::encodePop(m_count);
		position().pop();

		// Middle alternatives, each as a pushed variation.
		for (unsigned i = 0; i < node->variationCount(); ++i)
		{
			MoveNode const* var = node->variation(i);

			if (i == lastVar || !var->next())
				continue;

			position().push();
			Encoder::encodePush(m_count);
			// Preceding comment of the variation (stored Post on its header)
			m_annotationEncoder.encodeComment(m_count, var->comment(move::Post), move::Ante);
			emitLine(var->next());
			Encoder::encodePop(m_count);
			position().pop();
		}

		// Last alternative inline: it ends this line (the decoder returns to
		// the parent at the enclosing Pop or at end of stream).
		MoveNode const* last = node->variation(lastVar);
		m_annotationEncoder.encodeComment(m_count, last->comment(move::Post), move::Ante);
		emitLine(last->next());
		return;
	}
}


void
Consumer::sendPrecedingComment(	Comment const& comment,
											Annotation const& annotation,
											MarkSet const& marks)
{
	// Attach to the current line header (game root or variation header);
	// the decoder's traverse() reads preceding comments from the Post slot.
	if (!comment.isEmpty())
	{
		Comment merged(m_current->comment(move::Post));
		merged.append(comment, ' ');
		m_current->setComment(merged, move::Post);
	}

	for (unsigned i = 0; i < annotation.count(); ++i)
		m_current->addAnnotation(annotation[i]);

	for (unsigned i = 0; i < marks.count(); ++i)
		m_current->addMark(marks[i]);
}


void
Consumer::sendTrailingComment(Comment const& comment, bool)
{
	sendComment(comment);
}


void
Consumer::sendComment(Comment const& comment)
{
	if (!comment.isEmpty())
	{
		Comment merged(m_current->comment(move::Post));
		merged.append(comment, ' ');
		m_current->setComment(merged, move::Post);
	}
}


void
Consumer::sendMoveInfo(MoveInfoSet const&)
{
	// CBH format does not support move info (engine analysis, clock times, etc.)
}


bool
Consumer::sendMove(Move const& move)
{
	M_REQUIRE(move);

	if (!move.isLegal())
		return false;

	MoveNode* node = new MoveNode(move);
	m_current->setNext(node);
	m_current = node;

	return true;
}


bool
Consumer::sendMove(	Move const& move,
							Annotation const& annotation,
							MarkSet const& marks,
							Comment const& preComment,
							Comment const& comment)
{
	if (!sendMove(move))
		return false;

	if (!preComment.isEmpty())
		m_current->setComment(preComment, move::Ante);
	if (!comment.isEmpty())
		m_current->setComment(comment, move::Post);

	for (unsigned i = 0; i < annotation.count(); ++i)
		m_current->addAnnotation(annotation[i]);

	for (unsigned i = 0; i < marks.count(); ++i)
		m_current->addMark(marks[i]);

	return true;
}


void
Consumer::beginVariation()
{
	M_ASSERT(m_current != m_root);	// a variation must follow a move

	MoveNode* header = new MoveNode;

	m_current->addVariation(header);
	m_branchStack.push(m_current);
	m_current = header;
}


void
Consumer::endVariation(bool)
{
	M_ASSERT(!m_branchStack.empty());

	m_current = m_branchStack.top();
	m_branchStack.pop();
}

} // namespace cbh
} // namespace db

// vi:set ts=3 sw=3:
