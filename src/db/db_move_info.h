// ======================================================================
// Author : $Author$
// Version: $Revision: 1453 $
// Date   : $Date: 2017-12-11 09:27:52 -0500 (Mon, 11 Dec 2017) $
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

#ifndef _db_move_info_included
#define _db_move_info_included

#include "db_date.h"
#include "db_clock.h"

#include "u_crc.h"

#include "m_string.h"

namespace util { class ByteStream; }

namespace db {

class EngineList;

class MoveInfo
{
public:

	static uint16_t const MinYear	= Date::MinYear;
	static uint16_t const MaxYear = Date::MaxYear;

	enum Type
	{
		None,
		Evaluation,
		PlayersClock,
		ElapsedGameTime,
		ElapsedMoveTime,
		ElapsedMilliSeconds,
		ClockTime,
		CorrespondenceChessSent,
		VideoTime,
		CorrespondenceClock,
		CorrespondenceElapsed,

		LAST = CorrespondenceElapsed,
	};

	enum Format
	{
		Pgn,
		Text,
	};

	MoveInfo();

	bool operator==(MoveInfo const& info) const;
	bool operator!=(MoveInfo const& info) const;

	bool isEmpty() const;
	bool hasTimeInfo() const;
	bool hasEvaluationInfo() const;

	Type content() const;

	Clock const& clock() const;
	Date const& date() const;

	unsigned engine() const;
	unsigned depth() const;
	unsigned pawns() const;
	unsigned centipawns() const;
	unsigned centiSeconds() const;
	float value() const;

	::util::crc::checksum_t computeChecksum(EngineList const& engines, util::crc::checksum_t crc) const;
	int compare(MoveInfo const& info) const;

	void setAnalysisEngine(unsigned engine);
	void setClockEngine(unsigned engine);

	void print(EngineList const& engines, mstl::string& result, Format format = Pgn) const;
	void clear();

	void decode(util::ByteStream& strm);
	void decodeVersion92(util::ByteStream& strm);
	void encode(util::ByteStream& strm) const;

	/// SCI v96 extended-envelope wire support (see docs/formats/SCI_CORRESPONDENCE_FORMAT.md §4).
	/// Record layout: 0x00 sentinel, full-byte info-type, payload-length byte, payload.
	void encodeExtended(util::ByteStream& strm) const;
	void decodeExtended(util::ByteStream& strm);
	static void skipExtended(util::ByteStream& strm);
	/// Raw-pointer variant for skip/strip paths; advances p past one extended record.
	/// Raises on truncation, wrong known-type length, or cursor overrun.
	static unsigned char const* skipExtended(unsigned char const* strm, unsigned char const* eos);
	static unsigned const Extended_Sentinel = 0x00;
	static unsigned const Extended_Header_Size = 3;	// sentinel + info-type + payload-length
	static unsigned const Duration_Payload_Size = 5;	// uint16 days + h + m + s (BE)

	// wire info-type ids for correspondence durations (docs §4.2)
	static unsigned const wireIdClock = 0x01;
	static unsigned const wireIdElapsed = 0x02;

	static unsigned wireType(Type type)
	{
		M_REQUIRE(type == CorrespondenceClock || type == CorrespondenceElapsed);
		return type == CorrespondenceClock ? wireIdClock : wireIdElapsed;
	}

	static Type wireType(unsigned wireId)
	{
		M_REQUIRE(wireId == wireIdClock || wireId == wireIdElapsed);
		return wireId == wireIdClock ? CorrespondenceClock : CorrespondenceElapsed;
	}

	/// Version-aware serializability (docs/formats/SCI_CORRESPONDENCE_FORMAT.md §5):
	/// correspondence durations are binary-encodable only in SCI v96+.
	static bool isEncodable(Type type, unsigned sciVersion);
	bool isEncodable(unsigned sciVersion) const;

	char const* parseCorrespondenceChessSent(char const* s);
	char const* parseCorrespondenceClock(char const* s);
	char const* parseCorrespondenceElapsed(char const* s);
	char const* parsePlayersClock(char const* s);
	char const* parseClockTime(char const* s);
	char const* parseElapsedGameTime(char const* s);
	char const* parseElapsedMoveTime(char const* s);
	char const* parseTimeInfo(char const* s);
	char const* parseEvaluation(char const* s);
	char const* parseVideoTime(char const* s);

	static bool isMoveInfo(unsigned char firstByte);
	static Type type(unsigned char firstByte);
	static unsigned length(unsigned char firstByte);
	static void skip(util::ByteStream& strm);
	static unsigned char const* skip(unsigned char const* strm, unsigned char const* eos);

private:

	struct TimeInfo
	{
		Clock	m_clock;
		Date	m_date;
	};

	struct AnalysisInfo
	{
		AnalysisInfo();

		uint8_t	m_depth;
		uint8_t	m_sign;
		uint16_t	m_pawns;
		uint8_t	m_centipawns;
	};

	struct ElapsedTime
	{
		ElapsedTime();

		uint16_t	m_seconds;
		uint16_t	m_milliSeconds;
	};

	struct CorrDuration
	{
		CorrDuration();

		uint16_t	m_days;
		uint8_t	m_hours;
		uint8_t	m_minutes;
		uint8_t	m_seconds;
	};

public:
	/// Access correspondence duration (days/hours/minutes/seconds)
	CorrDuration const& corrDuration() const { return m_corrDuration; }

private:

	char const* parseTime(Type type, char const* s);
	char const* parseElapsedTime(char const* s);
	char const* parseCentiSeconds(char const* s);

	void printClock(char const* id, mstl::string& result, Format format) const;

	Type		m_content;
	uint8_t	m_engine;

#if HAVE_C11_UNRESTRICTED_UNIONS
	union
	{
#endif

		TimeInfo			m_time;
		ElapsedTime		m_elapsed;
		AnalysisInfo	m_analysis;
		uint32_t			m_centiSeconds;
		CorrDuration	m_corrDuration;

#if HAVE_C11_UNRESTRICTED_UNIONS
	};
#endif
};

} // namespace db

namespace mstl {

template <typename T> struct is_pod;

template <>
struct is_pod<db::MoveInfo>
{
	enum { value = is_pod<db::Clock>::value && is_pod<db::Date>::value };
};

} // namespace mstl

#include "db_move_info.ipp"

#endif // _db_move_info_included

// vi:set ts=3 sw=3:
