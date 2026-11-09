// Regression tests for mstl container bugs found in the 2026-11-09 review
// (CORE-01..04). Build with -fsanitize=address to catch the double frees.

#include "m_string.h"
#include "m_vector.h"

#include <stdio.h>
#include <string.h>

static int failures = 0;

#define CHECK(cond) \
	do { if (!(cond)) { ++failures; printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while (0)

static mstl::string
str(char const* s)
{
	return mstl::string(s);
}


// CORE-01: erasing from a vector of strings must not free survivors
static void
testEraseStrings()
{
	{
		mstl::vector<mstl::string> v;
		v.push_back(str("alpha-long-enough"));
		v.push_back(str("bravo-long-enough"));
		v.push_back(str("charlie-long-enough"));
		v.erase(v.begin(), v.begin() + 1);
		CHECK(v.size() == 2);
		CHECK(v[0] == "bravo-long-enough");
		CHECK(v[1] == "charlie-long-enough");
		v.push_back(str("delta"));
		CHECK(v[1] == "charlie-long-enough");
	}
	{
		mstl::vector<mstl::string> v;
		for (int i = 0; i < 6; ++i)
		{
			mstl::string s;
			s.format("item-%d-xxxxxxxx", i);
			v.push_back(s);
		}
		v.erase(v.begin() + 1, v.begin() + 3);	// middle range
		CHECK(v.size() == 4);
		CHECK(v[0] == "item-0-xxxxxxxx");
		CHECK(v[1] == "item-3-xxxxxxxx");
		CHECK(v[3] == "item-5-xxxxxxxx");
		v.erase(v.begin() + 2, v.end());	// tail
		CHECK(v.size() == 2);
		CHECK(v[1] == "item-3-xxxxxxxx");
	}
}


// CORE-02: range insert into spare capacity
static void
testInsertRange()
{
	{
		mstl::vector<int> v;
		v.reserve(16);
		for (int i = 1; i <= 4; ++i)
			v.push_back(i);
		int extra[] = { 8, 9 };
		v.insert(v.begin() + 1, extra, extra + 2);
		CHECK(v.size() == 6);
		int want[] = { 1, 8, 9, 2, 3, 4 };
		for (unsigned i = 0; i < 6 && i < v.size(); ++i)
			CHECK(v[i] == want[i]);
		v.insert(v.end(), extra, extra + 1);	// append
		CHECK(v.size() == 7);
		CHECK(v.back() == 8);
	}
	{
		mstl::vector<mstl::string> v;
		v.reserve(16);
		v.push_back(str("one-xxxxxxxxxxxx"));
		v.push_back(str("two-xxxxxxxxxxxx"));
		v.push_back(str("three-xxxxxxxxxx"));
		mstl::string extra[] = { str("new-a-xxxxxxxxxx"), str("new-b-xxxxxxxxxx") };
		v.insert(v.begin() + 1, extra, extra + 2);
		CHECK(v.size() == 5);
		CHECK(v[0] == "one-xxxxxxxxxxxx");
		CHECK(v[1] == "new-a-xxxxxxxxxx");
		CHECK(v[2] == "new-b-xxxxxxxxxx");
		CHECK(v[3] == "two-xxxxxxxxxxxx");
		CHECK(v[4] == "three-xxxxxxxxxx");
		v.insert(v.end(), extra, extra + 2);
		CHECK(v.size() == 7);
		CHECK(v[6] == "new-b-xxxxxxxxxx");
	}
	{
		// without spare capacity (the reallocating path)
		mstl::vector<int> v;
		v.push_back(1);
		v.push_back(2);
		int extra[] = { 5, 6, 7, 8, 9, 10, 11, 12 };
		v.insert(v.begin() + 1, extra, extra + 8);
		CHECK(v.size() == 10);
		CHECK(v[0] == 1 && v[1] == 5 && v[8] == 12 && v[9] == 2);
	}
}


// CORE-03: repetition
static void
testRepeat()
{
	CHECK(mstl::string(2, str("abc")) == "abcabc");
	CHECK(mstl::string(2, str("abcdef")) == "abcdefabcdef");
	CHECK(mstl::string(5, str("ab")) == "ababababab");
	CHECK(mstl::string(1, str("x")) == "x");
	CHECK(mstl::string(0, str("abc")).empty());

	mstl::string s;
	s.assign(3, str("abcdef"));
	CHECK(s == "abcdefabcdefabcdef");
	s.assign(4, str("z"));
	CHECK(s == "zzzz");
}


// CORE-04: output longer than the stack buffer keeps its arguments
static void
testLongFormat()
{
	mstl::string big(3000, 'x');
	mstl::string s;
	int n = s.format("%s|%d|%s", big.c_str(), 42, "end");
	CHECK(n == 3000 + 7);
	CHECK(s.size() == 3007);
	CHECK(s.size() >= 7 && ::strcmp(s.c_str() + 3000, "|42|end") == 0);

	mstl::string t;
	t.format("%d", 7);
	CHECK(t == "7");
}


int
main(int argc, char** argv)
{
	// an optional argument runs one section: erase, insert, repeat or format
	char const* only = argc > 1 ? argv[1] : "";

	if (!*only || ::strcmp(only, "erase") == 0) testEraseStrings();
	if (!*only || ::strcmp(only, "insert") == 0) testInsertRange();
	if (!*only || ::strcmp(only, "repeat") == 0) testRepeat();
	if (!*only || ::strcmp(only, "format") == 0) testLongFormat();

	if (failures)
		printf("mstl core: %d failure(s)\n", failures);
	else
		printf("mstl core: all passed\n");

	return failures ? 1 : 0;
}

// vi:set ts=3 sw=3:
