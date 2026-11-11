// Reading a zip member line by line with tellg after every line, as the
// PGN reader does, stays linear. On macOS each ftell made stdio seek back
// over its buffer, and a zip member re-inflated from its start on every
// backward seek: importing a weekly TWIC zip did not finish in minutes.

#include "u_zstream.h"

#include "m_string.h"

#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

namespace tcl { namespace bits { struct Tcl_Interp* interp = 0; } }

static double
now()
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}


static mstl::string
line(unsigned i)
{
	char buf[96];
	snprintf(buf, sizeof(buf), "[Event \"line %u\"] 1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 %u", i, i * 7919u);
	return buf;
}


int
main()
{
	enum { Lines = 120000 };	// about 8 MB, the size of a TWIC issue

	char const* dir = getenv("TMPDIR");
	char path[512];
	snprintf(path, sizeof(path), "%s/zstream-tell-%d.zip", dir ? dir : "/tmp", int(getpid()));

	{
		util::ZStream out(path, util::ZStream::Zip, mstl::ios_base::out);
		for (unsigned i = 0; i < Lines; ++i)
		{
			mstl::string s = line(i);
			s += '\n';
			out.write(s);
		}
	}

	double t0 = now();
	bool same = true;
	bool tells = true;
	unsigned count = 0;
	uint64_t consumed = 0;
	{
		util::ZStream in(path);
		mstl::string s;
		while (in.getline(s))
		{
			consumed += s.size() + 1;
			if (in.tellg() != consumed)
				tells = false;
			if (count >= Lines || s != line(count))
				same = false;
			++count;
			s.clear();
			if (now() - t0 > 60)
				break;
		}
	}
	double secs = now() - t0;
	unlink(path);

	int failures = 0;
	printf("%s zstream-lines (%u of %u)\n", same && count == Lines ? "ok  " : "FAIL", count, unsigned(Lines));
	failures += !(same && count == Lines);
	printf("%s zstream-tellg\n", tells ? "ok  " : "FAIL");
	failures += !tells;
	printf("%s zstream-linear (%.2f s)\n", secs < 15 ? "ok  " : "FAIL", secs);
	failures += !(secs < 15);
	return failures ? 1 : 0;
}
