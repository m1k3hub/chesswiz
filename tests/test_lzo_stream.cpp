// LzoByteStream round trip (review finding CORE-11): what is written in
// frames reads back byte for byte, whether a frame was compressed or
// stored raw, short or full, and a corrupt frame header is refused.

#include "u_lzo_byte_stream.h"
#include "u_exception.h"

#include "m_fstream.h"
#include "m_string.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

namespace tcl { namespace bits { struct Tcl_Interp* interp = 0; } }

using namespace util;

static int failures = 0;

static void
check(bool ok, char const* what)
{
	printf("%s %s\n", ok ? "ok  " : "FAIL", what);
	if (!ok)
		++failures;
}


static mstl::string
tempName(char const* tag)
{
	char const* dir = getenv("TMPDIR");
	mstl::string name(dir ? dir : "/tmp");
	char buf[64];
	snprintf(buf, sizeof(buf), "/lzo-stream-%d-%s", int(getpid()), tag);
	name += buf;
	return name;
}


// a mixture: compressible runs, incompressible noise, numbers and strings
static void
writeAll(LzoByteStream& out, unsigned seed)
{
	srand(seed);

	for (unsigned i = 0; i < 70000; ++i)
		out.put(ByteStream::Byte(i % 7));

	for (unsigned i = 0; i < 50000; ++i)
		out.put(ByteStream::Byte(rand()));

	for (unsigned i = 0; i < 5000; ++i)
	{
		out << uint32_t(i * 2654435761u);
		out.put("name", 4);
		out.put(ByteStream::Byte(i));
		out.put(ByteStream::Byte(0));
	}

	ByteStream::Byte block[1000];
	for (unsigned i = 0; i < 100; ++i)
	{
		for (unsigned k = 0; k < sizeof(block); ++k)
			block[k] = ByteStream::Byte(rand() % (i % 3 == 0 ? 4 : 256));
		out.put(block, sizeof(block));
	}

	out.flush();
}


static bool
readAll(LzoByteStream& in, unsigned seed)
{
	srand(seed);

	for (unsigned i = 0; i < 70000; ++i)
		if (in.get() != ByteStream::Byte(i % 7))
			return false;

	for (unsigned i = 0; i < 50000; ++i)
		if (in.get() != ByteStream::Byte(rand()))
			return false;

	for (unsigned i = 0; i < 5000; ++i)
	{
		if (in.uint32() != uint32_t(i * 2654435761u))
			return false;

		mstl::string s;
		in.get(s);
		mstl::string want("name");
		if (ByteStream::Byte(i) != 0)
			want += char(ByteStream::Byte(i));
		if (s != want)
			return false;
		if (ByteStream::Byte(i) == 0 && in.get() != 0)
			return false;
	}

	ByteStream::Byte block[1000], got[1000];
	for (unsigned i = 0; i < 100; ++i)
	{
		for (unsigned k = 0; k < sizeof(block); ++k)
			block[k] = ByteStream::Byte(rand() % (i % 3 == 0 ? 4 : 256));
		in.get(got, sizeof(got));
		if (memcmp(block, got, sizeof(block)) != 0)
			return false;
	}

	return true;
}


static bool
readRaises(char const* bytes, unsigned size)
{
	mstl::string name = tempName("bad");
	FILE* f = fopen(name.c_str(), "wb");
	fwrite(bytes, 1, size, f);
	fclose(f);

	bool raised = false;
	{
		mstl::fstream strm(name.c_str(), mstl::ios_base::in | mstl::ios_base::binary);
		LzoByteStream in(strm);
		try { in.get(); } catch (Exception const&) { raised = true; }
	}
	unlink(name.c_str());
	return raised;
}


int
main()
{
	mstl::string name = tempName("data");

	{
		mstl::fstream strm(name.c_str(),
			mstl::ios_base::out | mstl::ios_base::trunc | mstl::ios_base::binary);
		LzoByteStream out(strm);
		writeAll(out, 17);
	}

	bool same = false;
	bool atEnd = false;
	try
	{
		mstl::fstream strm(name.c_str(), mstl::ios_base::in | mstl::ios_base::binary);
		LzoByteStream in(strm);
		same = readAll(in, 17);
		try { in.get(); } catch (Exception const&) { atEnd = true; }
	}
	catch (Exception const& exc)
	{
		printf("     raised: %s\n", exc.what());
	}
	unlink(name.c_str());

	check(same, "lzo-round-trip");
	check(atEnd, "lzo-end-of-stream");

	char const badKind[] = { 7, 0, 1, 'x' };
	char const emptyRaw[] = { 0, 0, 0 };
	char const shortRaw[] = { 0, 0, 5, 'a', 'b' };
	char const hugeLzo[] = { 1, char(0x80), 0, 0 };
	check(readRaises(badKind, sizeof(badKind)), "lzo-bad-kind");
	check(readRaises(emptyRaw, sizeof(emptyRaw)), "lzo-empty-frame");
	check(readRaises(shortRaw, sizeof(shortRaw)), "lzo-short-frame");
	check(readRaises(hugeLzo, sizeof(hugeLzo)), "lzo-oversized-frame");

	return failures ? 1 : 0;
}
