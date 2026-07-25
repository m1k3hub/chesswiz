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

#ifndef _cbh_annotation_encoder_included
#define _cbh_annotation_encoder_included

#include "db_common.h"

namespace util { class ByteStream; }
namespace sys  { namespace utf8 { class Codec; } }

namespace db {

class Comment;
class Annotation;
class MarkSet;

namespace cbh {

class AnnotationEncoder
{
public:

	AnnotationEncoder(util::ByteStream& aStrm, sys::utf8::Codec& codec);

	/// Write a comment annotation record.
	void encodeComment(unsigned moveNo, Comment const& comment, move::Position position);

	/// Write a symbol (NAG) annotation record.
	void encodeAnnotation(unsigned moveNo, Annotation const& annotation, bool whiteToMove);

	/// Write square mark and arrow annotation records.
	void encodeMarks(unsigned moveNo, MarkSet const& marks);

private:

	AnnotationEncoder(AnnotationEncoder const&);
	AnnotationEncoder& operator=(AnnotationEncoder const&);

	void writeRecordHeader(unsigned moveNo, Byte type, unsigned dataLength);

	util::ByteStream&		m_aStrm;
	sys::utf8::Codec&		m_codec;
};

} // namespace cbh
} // namespace db

#endif // _cbh_annotation_encoder_included

// vi:set ts=3 sw=3:
