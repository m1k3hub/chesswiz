// ======================================================================
// test_corr_moveinfo.cpp
//
// Unit test for CorrespondenceClock and CorrespondenceElapsed MoveInfo
// parsing and printing.
//
// Verifies:
//   1. parseCorrespondenceClock parses ISO 8601 durations correctly
//   2. parseCorrespondenceElapsed reuses the clock parser
//   3. print() outputs valid PGN annotations [%cclk ...] and [%cemt ...]
//   4. CorrDuration fields (days, hours, minutes, seconds) are correct
//   5. Edge cases: bare P[n]D, zero values, all components
//
// Usage: test_corr_moveinfo
// ======================================================================

#include "db_move_info.h"
#include "db_engine_list.h"
#include "m_string.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static int pass = 0;
static int fail = 0;

static void checkEqual(const char* label, unsigned expected, unsigned actual)
{
	if (expected == actual) { ++pass; }
	else { ++fail; printf("FAIL: %s -- expected %u, got %u\n", label, expected, actual); }
}

static void checkStr(const char* label, const char* expected, const char* actual)
{
	if (strcmp(expected, actual) == 0) { ++pass; }
	else { ++fail; printf("FAIL: %s -- expected '%s', got '%s'\n", label, expected, actual); }
}

static void checkNonNull(const char* label, const void* p)
{
	if (p != nullptr) { ++pass; }
	else { ++fail; printf("FAIL: %s -- expected non-null\n", label); }
}

int main()
{
	db::EngineList engines;
	mstl::string result;

	// Test 1: parseCorrespondenceClock with full duration
	{
		db::MoveInfo info;
		const char* rest = info.parseCorrespondenceClock("P28DT12H30M45S");
		checkNonNull("parse P28DT12H30M45S", rest);
		checkEqual("clock type", db::MoveInfo::CorrespondenceClock, info.content());
		checkEqual("clock days", 28, info.corrDuration().m_days);
		checkEqual("clock hours", 12, info.corrDuration().m_hours);
		checkEqual("clock minutes", 30, info.corrDuration().m_minutes);
		checkEqual("clock seconds", 45, info.corrDuration().m_seconds);
	}

	// Test 2: parseCorrespondenceClock with days only
	{
		db::MoveInfo info;
		const char* rest = info.parseCorrespondenceClock("P40D");
		checkNonNull("parse P40D", rest);
		checkEqual("days-only days", 40, info.corrDuration().m_days);
		checkEqual("days-only hours", 0, info.corrDuration().m_hours);
		checkEqual("days-only minutes", 0, info.corrDuration().m_minutes);
		checkEqual("days-only seconds", 0, info.corrDuration().m_seconds);
	}

	// Test 3: parseCorrespondenceClock with zero
	{
		db::MoveInfo info;
		const char* rest = info.parseCorrespondenceClock("P0DT0H0M0S");
		checkNonNull("parse P0DT0H0M0S", rest);
		checkEqual("zero days", 0, info.corrDuration().m_days);
		checkEqual("zero hours", 0, info.corrDuration().m_hours);
	}

	// Test 4: parseCorrespondenceElapsed
	{
		db::MoveInfo info;
		const char* rest = info.parseCorrespondenceElapsed("P2DT4H30M");
		checkNonNull("parse elapsed P2DT4H30M", rest);
		checkEqual("elapsed type", db::MoveInfo::CorrespondenceElapsed, info.content());
		checkEqual("elapsed days", 2, info.corrDuration().m_days);
		checkEqual("elapsed hours", 4, info.corrDuration().m_hours);
		checkEqual("elapsed minutes", 30, info.corrDuration().m_minutes);
	}

	// Test 5: print CorrespondenceClock in PGN format
	{
		db::MoveInfo info;
		info.parseCorrespondenceClock("P28DT12H30M");
		result.clear();
		info.print(engines, result, db::MoveInfo::Pgn);
		checkStr("print cclk PGN", "[%cclk P28DT12H30M]", result.c_str());
	}

	// Test 6: print CorrespondenceClock with seconds
	{
		db::MoveInfo info;
		info.parseCorrespondenceClock("P28DT12H30M45S");
		result.clear();
		info.print(engines, result, db::MoveInfo::Pgn);
		checkStr("print cclk with seconds", "[%cclk P28DT12H30M45S]", result.c_str());
	}

	// Test 7: print CorrespondenceClock days only (no T section)
	{
		db::MoveInfo info;
		info.parseCorrespondenceClock("P40D");
		result.clear();
		info.print(engines, result, db::MoveInfo::Pgn);
		checkStr("print cclk days only", "[%cclk P40D]", result.c_str());
	}

	// Test 8: print CorrespondenceElapsed in PGN format
	{
		db::MoveInfo info;
		info.parseCorrespondenceElapsed("P2DT4H30M");
		result.clear();
		info.print(engines, result, db::MoveInfo::Pgn);
		checkStr("print cemt PGN", "[%cemt P2DT4H30M]", result.c_str());
	}

	// Test 9: print in Text format — zero minutes are omitted
	{
		db::MoveInfo info;
		info.parseCorrespondenceClock("P15DT3H0M");
		result.clear();
		info.print(engines, result, db::MoveInfo::Text);
		// Zero minutes are omitted per ISO 8601 convention
		checkStr("print cclk text", "P15DT3H", result.c_str());
	}

	// Test 10: parse invalid input returns null
	{
		db::MoveInfo info;
		const char* rest = info.parseCorrespondenceClock("not a duration");
		if (rest == nullptr) ++pass;
		else { ++fail; printf("FAIL: invalid input should return null\n"); }
	}

	// Test 11: roundtrip — parse then print then verify fields match
	{
		db::MoveInfo info;
		info.parseCorrespondenceClock("P10DT5H30M20S");
		result.clear();
		info.print(engines, result, db::MoveInfo::Pgn);
		// Re-parse the printed output (minus the [%cclk prefix and ] suffix)
		db::MoveInfo info2;
		const char* printed = result.c_str() + 7; // skip "[%cclk "
		char buf[32];
		strncpy(buf, printed, strlen(printed) - 1); // remove trailing ]
		buf[strlen(printed) - 1] = '\0';
		info2.parseCorrespondenceClock(buf);
		checkEqual("roundtrip days", 10, info2.corrDuration().m_days);
		checkEqual("roundtrip hours", 5, info2.corrDuration().m_hours);
		checkEqual("roundtrip minutes", 30, info2.corrDuration().m_minutes);
		checkEqual("roundtrip seconds", 20, info2.corrDuration().m_seconds);
	}

	// Summary
	printf("\n==============================================\n");
	printf("Correspondence MoveInfo Test Results\n");
	printf("==============================================\n");
	printf("Passed: %d\n", pass);
	printf("Failed: %d\n", fail);
	printf("Status: %s\n", fail == 0 ? "PASSED" : "FAILED");
	return fail == 0 ? 0 : 1;
}

// vi:set ts=3 sw=3: