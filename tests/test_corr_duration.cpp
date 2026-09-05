// ======================================================================
// Unit tests for the SCI v96 correspondence-duration extended envelope.
// Spec: docs/SCI_CORRESPONDENCE_FORMAT.md
//
// Covers spec §6.1 (round-trip), §6.2 (corruption: truncation at every
// byte boundary, wrong payload length, unknown info-type skip), and the
// version-aware eligibility predicate (§5).
// ======================================================================

#include "db/db_move_info.h"
#include "db/db_time_table.h"
#include "db/db_engine_list.h"
#include "db/db_exception.h"
#include "u_byte_stream.h"

#include <cstdio>
#include <cstring>

using namespace db;

static unsigned g_failures = 0;

#define CHECK(cond) \
	do { \
		if (!(cond)) \
		{ \
			++g_failures; \
			std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
		} \
	} while (0)

// Build a correspondence duration through the public parse path.
static MoveInfo makeDuration(MoveInfo::Type type, unsigned days, unsigned h, unsigned m, unsigned s)
{
	MoveInfo info;
	mstl::string text;
	text.format("P%uD", days);
	if (h || m || s)
	{
		text.append("T");
		if (h) text.format("%uH", h);
		if (m) text.format("%uM", m);
		if (s) text.format("%uS", s);
	}

	char const* result =	(type == MoveInfo::CorrespondenceClock)
									? info.parseCorrespondenceClock(text)
									: info.parseCorrespondenceElapsed(text);

	CHECK(result != 0);
	CHECK(info.content() == type);
	return info;
}

// Copy a growable stream's written bytes into an exact-size fixed buffer
// (production streams are fixed-size records; remaining()-based checks
// assume that).
static util::ByteStream fixedCopy(util::ByteStream& strm)
{
	static char buf[128];
	unsigned n = strm.tellp();
	::memcpy(buf, strm.base(), n);
	return util::ByteStream(buf, n);
}

static mstl::string printPgn(MoveInfo const& info)
{
	EngineList engines;
	mstl::string result;
	info.print(engines, result, MoveInfo::Pgn);
	return result;
}

static void test_wire_bytes()
{
	// docs §4.2: 0x00, info-type, 0x05, then uint16 days BE + h + m + s
	MoveInfo info = makeDuration(MoveInfo::CorrespondenceClock, 3, 4, 5, 6);

	util::ByteStream strm(64);
	info.encodeExtended(strm);

	static unsigned char const expected[] = {
		0x00, 0x01, 0x05,		// sentinel, wire info-type 0x01 (clock), payload length 5
		0x00, 0x03,				// days = 3 (big-endian)
		0x04, 0x05, 0x06		// h, m, s
	};

	CHECK(strm.tellp() == sizeof(expected));
	CHECK(::memcmp(strm.base(), expected, sizeof(expected)) == 0);
}

static void checkRoundTrip(MoveInfo::Type type, unsigned days, unsigned h, unsigned m, unsigned s)
{
	MoveInfo src = makeDuration(type, days, h, m, s);

	util::ByteStream strm(64);
	src.encodeExtended(strm);

	MoveInfo dst;
	dst.decodeExtended(strm);

	CHECK(dst.content() == type);
	CHECK(printPgn(dst) == printPgn(src));
}

static void test_elapsed_wire_bytes()
{
	MoveInfo info = makeDuration(MoveInfo::CorrespondenceElapsed, 1, 0, 0, 0);

	util::ByteStream strm(64);
	info.encodeExtended(strm);

	static unsigned char const expected[] = {
		0x00, 0x02, 0x05,		// sentinel, wire info-type 0x02 (elapsed), length 5
		0x00, 0x01, 0x00, 0x00, 0x00
	};

	CHECK(strm.tellp() == sizeof(expected));
	CHECK(::memcmp(strm.base(), expected, sizeof(expected)) == 0);
}

static void test_unknown_type_decodes_to_none()
{
	// unknown info-types are skipped length-delimited; result is empty (docs §4.1)
	static unsigned char record[] = { 0x00, 0x7f, 0x02, 0xde, 0xad };

	util::ByteStream strm(reinterpret_cast<char*>(record), sizeof(record));
	MoveInfo info;
	info.decodeExtended(strm);
	CHECK(info.isEmpty());
	CHECK(strm.remaining() == 0);
}

static void test_round_trip()
{
	static unsigned const days[]		= { 0, 1, 65535 };
	static unsigned const hours[]		= { 0, 255 };
	static unsigned const minutes[]	= { 0, 59, 255 };
	static unsigned const seconds[]	= { 0, 255 };

	for (unsigned t = 0; t < 2; ++t)
	{
		MoveInfo::Type type =	(t == 0)
										? MoveInfo::CorrespondenceClock
										: MoveInfo::CorrespondenceElapsed;

		for (unsigned d = 0; d < 3; ++d)
		for (unsigned h = 0; h < 2; ++h)
		for (unsigned m = 0; m < 3; ++m)
		for (unsigned s = 0; s < 2; ++s)
			checkRoundTrip(type, days[d], hours[h], minutes[m], seconds[s]);
	}
}

static void test_truncation_at_every_byte()
{
	MoveInfo src = makeDuration(MoveInfo::CorrespondenceClock, 7, 8, 9, 10);

	util::ByteStream writer(64);
	src.encodeExtended(writer);
	unsigned total = writer.tellp();
	util::ByteStream full = fixedCopy(writer);

	for (unsigned cut = 1; cut < total; ++cut)
	{
		util::ByteStream strm(full.base(), cut);
		MoveInfo info;
		bool raised = false;

		try { info.decodeExtended(strm); }
		catch (...) { raised = true; }

		if (!raised) std::printf("NO-RAISE decodeExtended cut=%u\n", cut);
		CHECK(raised);
	}
}

static void test_wrong_payload_length()
{
	static unsigned char record[] = { 0x00, 0x01, 0x04, 0x00, 0x01, 0x02, 0x03 };

	util::ByteStream strm(reinterpret_cast<char*>(record), sizeof(record));
	MoveInfo info;
	bool raised = false;

	try { info.decodeExtended(strm); }
	catch (...) { raised = true; }

	CHECK(raised);	// known type requires payload length exactly 5 (docs §4.1)
}

static void test_unknown_info_type_skip()
{
	// info-type 0x42 (unknown), payload length 3
	static unsigned char record[] = { 0x00, 0x42, 0x03, 0xaa, 0xbb, 0xcc, 0xff };

	util::ByteStream strm(reinterpret_cast<char*>(record), sizeof(record));

	// caller peeks the sentinel (cursor stays on it); skipExtended validates
	// and consumes sentinel + header + payload
	MoveInfo::skipExtended(strm);
	CHECK(strm.remaining() == 1);
	CHECK(strm.get() == 0xff);	// stream remains aligned
}

static void test_skip_extended_bytestream()
{
	MoveInfo src = makeDuration(MoveInfo::CorrespondenceElapsed, 2, 0, 0, 0);

	util::ByteStream writer(64);
	src.encodeExtended(writer);
	writer << uint8_t(0x42);	// trailing byte must remain aligned after skip

	util::ByteStream strm = fixedCopy(writer);

	MoveInfo::skipExtended(strm);	// cursor is at the sentinel (peeked)
	CHECK(strm.remaining() == 1);
	CHECK(strm.get() == 0x42);
}

static void test_skip_known_wire_type_wrong_length()
{
	// docs §4.1: known wire ids (0x01/0x02) require payload length exactly 5;
	// both skip overloads must reject 4- and 6-byte variants
	for (unsigned type = 0x01; type <= 0x02; ++type)
	for (unsigned badLen = 4; badLen <= 6; badLen += 2)
	{
		unsigned char record[16] = { 0x00, (unsigned char)type, (unsigned char)badLen, 0 };
		unsigned n = 3 + badLen;
		for (unsigned i = 3; i < n; ++i)
			record[i] = 0xee;

		{
			util::ByteStream strm(reinterpret_cast<char*>(record), n);
			bool raised = false;
			try { MoveInfo::skipExtended(strm); }
			catch (...) { raised = true; }
			CHECK(raised);
		}

		{
			bool raised = false;
			try { MoveInfo::skipExtended(record, record + n); }
			catch (...) { raised = true; }
			CHECK(raised);
		}
	}
}

static void test_skip_unknown_wire_types()
{
	// unknown wire ids (including internal-looking 9/10) are skipped
	// length-delimited by both overloads (docs §4.1)
	for (unsigned type = 0x03; type <= 0x0a; ++type)
	{
		unsigned char record[7] = { 0x00, (unsigned char)type, 0x03, 0xaa, 0xbb, 0xcc, 0x99 };

		{
			util::ByteStream strm(reinterpret_cast<char*>(record), sizeof(record));
			MoveInfo::skipExtended(strm);
			CHECK(strm.remaining() == 1);
			CHECK(strm.get() == 0x99);
		}

		{
			unsigned char const* p = MoveInfo::skipExtended(record, record + sizeof(record));
			CHECK(p == record + sizeof(record) - 1);
			CHECK(*p == 0x99);
		}
	}
}

static void test_raw_pointer_skip()
{
	MoveInfo src = makeDuration(MoveInfo::CorrespondenceClock, 65535, 255, 255, 255);

	util::ByteStream strm(64);
	src.encodeExtended(strm);
	strm << uint8_t(0x77);

	unsigned char const* eos = strm.base() + strm.tellp();
	unsigned char const* p = MoveInfo::skipExtended(strm.base(), eos);

	CHECK(p == eos - 1);
	CHECK(*p == 0x77);
}

static void test_raw_pointer_skip_truncated()
{
	MoveInfo src = makeDuration(MoveInfo::CorrespondenceClock, 1, 2, 3, 4);

	util::ByteStream strm(64);
	src.encodeExtended(strm);

	unsigned total = strm.tellp();
	for (unsigned cut = 1; cut < total; ++cut)
	{
		bool raised = false;

		try { MoveInfo::skipExtended(strm.base(), strm.base() + cut); }
		catch (...) { raised = true; }

		if (!raised) std::printf("NO-RAISE raw skipExtended cut=%u\n", cut);
		CHECK(raised);
	}
}

static void test_time_table_exclusion()
{
	// docs §4.3.2: correspondence durations never enter time tables,
	// regardless of SCI version
	db::TimeTable table;
	MoveInfoSet set;

	set.add(makeDuration(MoveInfo::CorrespondenceClock, 1, 2, 3, 4));
	{ MoveInfo eval; CHECK(eval.parseClockTime("0:00:01") != 0); set.add(eval); }
	set.add(makeDuration(MoveInfo::CorrespondenceElapsed, 5, 0, 0, 0));

	table.set(0, set, 96);	// v96 mode

	CHECK(table.size(MoveInfo::CorrespondenceClock - 1) == 0);
	CHECK(table.size(MoveInfo::CorrespondenceElapsed - 1) == 0);
	CHECK(table.size(MoveInfo::ClockTime - 1) == 1);

	table.set(1, set);		// legacy overload — also excluded

	CHECK(table.size(MoveInfo::CorrespondenceClock - 1) == 0);
	CHECK(table.size(MoveInfo::CorrespondenceElapsed - 1) == 0);
}

static void test_eligibility()
{
	// docs §5: correspondence durations are binary-encodable only in v96+
	CHECK(MoveInfo::isEncodable(MoveInfo::CorrespondenceClock, 95) == false);
	CHECK(MoveInfo::isEncodable(MoveInfo::CorrespondenceElapsed, 95) == false);
	CHECK(MoveInfo::isEncodable(MoveInfo::CorrespondenceClock, 96) == true);
	CHECK(MoveInfo::isEncodable(MoveInfo::CorrespondenceElapsed, 96) == true);

	// all other types remain encodable in every version
	CHECK(MoveInfo::isEncodable(MoveInfo::Evaluation, 95) == true);
	CHECK(MoveInfo::isEncodable(MoveInfo::ClockTime, 96) == true);
	CHECK(MoveInfo::isEncodable(MoveInfo::VideoTime, 95) == true);
	CHECK(MoveInfo::isEncodable(MoveInfo::None, 95) == true);
}

#define RUN(fn) do { std::printf("== %s\n", #fn); std::fflush(stdout); try { fn(); } catch (...) { std::printf("ESCAPED EXCEPTION in %s\n", #fn); ++g_failures; } } while (0)

int main()
{
	RUN(test_wire_bytes);
	RUN(test_elapsed_wire_bytes);
	RUN(test_unknown_type_decodes_to_none);
	RUN(test_skip_known_wire_type_wrong_length);
	RUN(test_skip_unknown_wire_types);
	RUN(test_round_trip);
	RUN(test_truncation_at_every_byte);
	RUN(test_wrong_payload_length);
	RUN(test_unknown_info_type_skip);
	RUN(test_skip_extended_bytestream);
	RUN(test_raw_pointer_skip);
	RUN(test_raw_pointer_skip_truncated);
	RUN(test_time_table_exclusion);
	RUN(test_eligibility);

	if (g_failures)
	{
		std::printf("test_corr_duration: %u failure(s)\n", g_failures);
		return 1;
	}

	std::printf("test_corr_duration: all tests passed\n");
	return 0;
}
