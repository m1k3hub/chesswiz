// Regression tests for mstl container bugs found in the 2026-11-09 review
// (CORE-01..06, CORE-13, CORE-16..20, CORE-23). Build with -fsanitize=address to catch the double frees.

#include "m_string.h"
#include "m_vector.h"
#include "sys_file.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

// sys_file.cpp converts file names with Tcl's encodings (so Tcl is set up
// before the mapping tests); the app's interpreter pointer can stay empty
#include <tcl.h>
namespace tcl { namespace bits { Tcl_Interp* interp = nullptr; } }

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


// CORE-05/06: a value taken from the container itself survives growth
static void
testSelfReference()
{
	mstl::vector<mstl::string> v;
	v.push_back(str("first-long-string-value"));
	v.reserve(1);
	while (v.size() < v.capacity())
		v.push_back(str("filler-long-string-value"));
	v.push_back(v[0]);	// full: this grows the storage
	CHECK(v.back() == "first-long-string-value");

	mstl::vector<int> w;
	w.push_back(7);
	while (w.size() < w.capacity())
		w.push_back(1);
	w.push_back(w[0]);
	CHECK(w.back() == 7);

	mstl::string s("abcdefghijklmnop");
	s.append(s.c_str(), s.size());	// growth while reading from itself
	CHECK(s == "abcdefghijklmnopabcdefghijklmnop");
	s.append(s.c_str() + 4, 4);
	CHECK(s.size() == 36 && ::strcmp(s.c_str() + 32, "efgh") == 0);
}

// CORE-17, CORE-18: edit distance boundaries, weights, long inputs
static void
testEditDistance()
{
	mstl::string empty, abc("abc"), abd("abd");
	CHECK(empty.levenshtein_distance(abc, 1, 1, 1) == 3);
	CHECK(abc.levenshtein_distance(empty, 1, 1, 1) == 3);
	CHECK(empty.levenshtein_distance(abc, 2, 5, 1) == 6);	// three insertions
	CHECK(abc.levenshtein_distance(empty, 2, 5, 1) == 15);	// three deletions
	CHECK(abc.levenshtein_distance(abd, 1, 1, 1) == 1);
	CHECK(mstl::string("ab").levenshtein_distance(abc, 2, 5, 9) == 2);
	CHECK(abc.levenshtein_distance(mstl::string("ab"), 2, 5, 9) == 5);
	CHECK(mstl::string("kitten").levenshtein_distance(mstl::string("sitting"), 1, 1, 1) == 3);

	// 4000 x 4000 used to need 64 MB of stack
	mstl::string a(4000, 'x'), b(4000, 'x');
	b[0] = 'y';
	CHECK(a.levenshtein_distance(b, 1, 1, 1) == 1);
}


// CORE-19: resize(0) clears the C string
static void
testResizeZero()
{
	mstl::string s("abc");
	s.resize(0);
	CHECK(s.size() == 0);
	CHECK(::strcmp(s.c_str(), "") == 0);
}


// CORE-23: case-insensitive find sees the last position
static void
testFindIgnoreCase()
{
	CHECK(mstl::string("ABC").find_ignore_case("abc") == 0);
	CHECK(mstl::string("xABC").find_ignore_case("abc") == 1);
	CHECK(mstl::string("xABC").find_ignore_case(mstl::string("abc")) == 1);
	CHECK(mstl::string("xABC").find_ignore_case("abc", 2) == mstl::string::npos);
	CHECK(mstl::string("xAB").find_ignore_case("abc") == mstl::string::npos);
	CHECK(mstl::string("ab\xe9").find_ignore_case("\xe9") == 2);
}


// CORE-20: equal(v, n) compares only the first n elements
static void
testVectorPrefix()
{
	mstl::vector<int> a, b;
	a.push_back(1); a.push_back(2); a.push_back(3);
	b.push_back(1); b.push_back(9);
	CHECK(a.equal(b, 1));
	CHECK(!a.equal(b, 2));
	mstl::vector<int> c;
	c.push_back(1);
	CHECK(a.equal(c, 1));
}


static unsigned
mappingsOf(char const* path)
{
	FILE* f = ::fopen("/proc/self/maps", "r");
	char line[4096];
	unsigned n = 0;
	while (f && ::fgets(line, sizeof(line), f))
		if (::strstr(line, path))
			++n;
	if (f)
		::fclose(f);
	return n;
}


// CORE-13, CORE-16: a shrunk mapping unmaps all of itself; a write-only
// request maps the file
static void
testMapping()
{
	::Tcl_FindExecutable(0);

	char path[] = "/tmp/mstl-mapping-XXXXXX";
	int fd = ::mkstemp(path);
	CHECK(fd != -1);
	if (fd == -1)
		return;
	static char page[4096];
	for (int i = 0; i < 16; ++i)
		CHECK(::write(fd, page, sizeof(page)) == ssize_t(sizeof(page)));
	::close(fd);

	{
		sys::file::Mapping m(path, sys::file::Mode(sys::file::Readable | sys::file::Writeable));
		CHECK(m.isOpen());
		m.resize(4096);
		CHECK(m.size() == 4096);
	}
	CHECK(mappingsOf(path) == 0);
	CHECK(sys::file::size(path) == 4096);

	{
		sys::file::Mapping m(path, sys::file::Writeable);
		CHECK(m.isOpen());
		if (m.isOpen())
			m.address()[0] = 'w';
	}
	FILE* f = ::fopen(path, "rb");
	CHECK(f && ::fgetc(f) == 'w');
	if (f)
		::fclose(f);
	::unlink(path);
}


int
main(int argc, char** argv)
{
	// an optional argument runs one section: erase, insert, repeat, format,
	// self, edit, resize, find, prefix or mapping
	char const* only = argc > 1 ? argv[1] : "";

	if (!*only || ::strcmp(only, "erase") == 0) testEraseStrings();
	if (!*only || ::strcmp(only, "insert") == 0) testInsertRange();
	if (!*only || ::strcmp(only, "repeat") == 0) testRepeat();
	if (!*only || ::strcmp(only, "format") == 0) testLongFormat();
	if (!*only || ::strcmp(only, "self") == 0) testSelfReference();
	if (!*only || ::strcmp(only, "edit") == 0) testEditDistance();
	if (!*only || ::strcmp(only, "resize") == 0) testResizeZero();
	if (!*only || ::strcmp(only, "find") == 0) testFindIgnoreCase();
	if (!*only || ::strcmp(only, "prefix") == 0) testVectorPrefix();
	if (!*only || ::strcmp(only, "mapping") == 0) testMapping();

	if (failures)
		printf("mstl core: %d failure(s)\n", failures);
	else
		printf("mstl core: all passed\n");

	return failures ? 1 : 0;
}

// vi:set ts=3 sw=3:
