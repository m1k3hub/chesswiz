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

#ifndef _cbh_consumer_included
#define _cbh_consumer_included

#include "cbh_encoder.h"
#include "cbh_annotation_encoder.h"

#include "db_consumer.h"
#include "db_move.h"
#include "db_comment.h"

#include "u_byte_stream.h"

#include "m_stack.h"

namespace db {

class TagSet;
class MarkSet;
class Annotation;
class MoveNode;

namespace cbh {

class Codec;

class Consumer : private Encoder, public db::Consumer
{
public:

	Consumer(format::Type srcFormat,
				Codec& codec,
				mstl::string const& encoding,
				TagBits const& allowedTags,
				bool allowExtraTags,
				LanguageList const* languages = nullptr,
				unsigned significantLanguages = 0);
	~Consumer();

	format::Type format() const override;

private:

	typedef mstl::stack<MoveNode*>	NodeStack;

	void start() override;
	void finish() override;

	bool supportsVariant(variant::Type variant) const override;

	bool beginGame(TagSet const& tags) override;
	save::State endGame(TagSet const& tags) override;
	save::State skipGame(TagSet const& tags) override;

	void sendTrailingComment(Comment const& comment, bool variationIsEmpty) override;
	void sendComment(Comment const& comment) override;
	void sendPrecedingComment(	Comment const& comment,
										Annotation const& annotation,
										MarkSet const& marks) override;
	void sendMoveInfo(MoveInfoSet const& moveInfo) override;
	bool sendMove(Move const& move) override;
	bool sendMove(	Move const& move,
						Annotation const& annotation,
						MarkSet const& marks,
						Comment const& preComment,
						Comment const& comment) override;

	void beginMoveSection() override;
	void endMoveSection(result::ID result) override;
	void beginVariation() override;
	void endVariation(bool isEmpty) override;

	void emitMoveRecords(MoveNode const* node);
	void emitLine(MoveNode const* node);
	void deleteTree();

	util::ByteStream		m_gameStream;
	util::ByteStream		m_annotationStream;
	Byte						m_gameBuffer[131072];
	Byte						m_annotationBuffer[131072];
	Codec&					m_codec;
	AnnotationEncoder		m_annotationEncoder;
	unsigned					m_count;		// monotone move counter (scrambling + annotation keys)
	MoveNode*				m_root;		// buffered game tree (CBH needs reordered emission)
	MoveNode*				m_current;
	NodeStack				m_branchStack;
	bool						m_whiteToMove;
	bool						m_isStandardPosition;
};

} // namespace cbh
} // namespace db

#endif // _cbh_consumer_included

// vi:set ts=3 sw=3:
