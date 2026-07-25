// ======================================================================
// Inspect CBH/CBG records for Chess960 reverse-engineering.
// Reports per-game header flags and dumps custom-position bytes.
// ======================================================================

#include "mstl/m_string.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

namespace {

enum { IndexRecordSize = 46 };

struct Summary
{
	unsigned total;
	unsigned deleted;
	unsigned customStart;
	unsigned chess960;
	unsigned newerFlag;
	unsigned encrypted;
	unsigned customAnd960;

	Summary()
		:total(0)
		,deleted(0)
		,customStart(0)
		,chess960(0)
		,newerFlag(0)
		,encrypted(0)
		,customAnd960(0)
	{
	}
};


static uint32_t
readBe32(unsigned char const* p)
{
	return (uint32_t(p[0]) << 24)
			 | (uint32_t(p[1]) << 16)
			 | (uint32_t(p[2]) << 8)
			 | (uint32_t(p[3]));
}


static void
dumpHex(unsigned char const* data, unsigned size)
{
	for (unsigned i = 0; i < size; ++i)
	{
		if (i != 0)
			::putchar(' ');

		::printf("%02x", unsigned(data[i]));
	}
}


static bool
readExact(FILE* file, void* data, size_t size)
{
	return ::fread(data, 1, size, file) == size;
}


static bool
seekAbs(FILE* file, long offset)
{
	return ::fseek(file, offset, SEEK_SET) == 0;
}


static void
usage(char const* argv0)
{
	::fprintf(stderr,
				 "usage: %s <database.cbh> [max-games]\n"
				 "Prints CBH/CBG flags and custom-start bytes for Chess960 analysis.\n",
				 argv0);
}

} // namespace


int
main(int argc, char** argv)
{
	if (argc < 2 || argc > 3)
	{
		usage(argv[0]);
		return 1;
	}

	mstl::string cbhPath(argv[1]);
	mstl::string root(cbhPath);

	if (root.size() < 4 || root.substr(root.size() - 4) != ".cbh")
	{
		::fprintf(stderr, "expected a .cbh path, got '%s'\n", cbhPath.c_str());
		return 1;
	}

	root.resize(root.size() - 4);
	mstl::string cbgPath(root + ".cbg");

	unsigned maxGames = ~0u;
	bool dumpMoves = false;
	if (argc == 3)
	{
		if (::strcmp(argv[2], "--dump-moves") == 0)
			dumpMoves = true;
		else
			maxGames = ::strtoul(argv[2], 0, 10);
	}

	FILE* cbh = ::fopen(cbhPath.c_str(), "rb");
	if (cbh == 0)
	{
		::fprintf(stderr, "cannot open '%s'\n", cbhPath.c_str());
		return 1;
	}

	FILE* cbg = ::fopen(cbgPath.c_str(), "rb");
	if (cbg == 0)
	{
		::fprintf(stderr, "cannot open '%s'\n", cbgPath.c_str());
		::fclose(cbh);
		return 1;
	}

	unsigned char header[IndexRecordSize];
	if (!readExact(cbh, header, sizeof(header)))
	{
		::fprintf(stderr, "failed to read CBH header\n");
		::fclose(cbg);
		::fclose(cbh);
		return 1;
	}

	if (header[0] != 0 || header[1] != 0 || header[4] != 0x2e)
	{
		::fprintf(stderr, "unexpected CBH magic in '%s'\n", cbhPath.c_str());
		::fclose(cbg);
		::fclose(cbh);
		return 1;
	}

	unsigned totalGames = readBe32(header + 6) - 1;
	Summary summary;
	summary.total = totalGames;

	::printf("database=%s\n", cbhPath.c_str());
	::printf("games=%u\n", totalGames);
	::printf("max_inspected=%u\n", maxGames == ~0u ? totalGames : maxGames);

	for (unsigned i = 0; i < totalGames && i < maxGames; ++i)
	{
		unsigned char indexRecord[IndexRecordSize];

		if (!readExact(cbh, indexRecord, sizeof(indexRecord)))
		{
			::fprintf(stderr, "failed to read index record %u\n", i);
			break;
		}

		bool deleted = (indexRecord[0] & 0x80) != 0;
		uint32_t gameOffset = readBe32(indexRecord + 1);

		if (deleted)
		{
			++summary.deleted;
			continue;
		}

		if (!seekAbs(cbg, gameOffset))
		{
			::fprintf(stderr, "cannot seek CBG offset %u for game %u\n", gameOffset, i);
			continue;
		}

		unsigned char wordBytes[4];
		if (!readExact(cbg, wordBytes, sizeof(wordBytes)))
		{
			::fprintf(stderr, "cannot read game header at offset %u for game %u\n", gameOffset, i);
			continue;
		}

		uint32_t word = readBe32(wordBytes);
		unsigned size = word & 0x00ffffff;
		bool chess960 = (word & 0x02000000) != 0;
		bool newerFlag = (word & 0x08000000) != 0;
		bool customStart = (word & 0x40000000) != 0;
		bool encrypted = (word & 0x80000000) != 0;

		if (chess960) ++summary.chess960;
		if (newerFlag) ++summary.newerFlag;
		if (customStart) ++summary.customStart;
		if (encrypted) ++summary.encrypted;
		if (customStart && (chess960 || newerFlag)) ++summary.customAnd960;

		if (!(customStart || chess960 || newerFlag || encrypted))
			continue;

		::printf(
			"game=%u offset=%u size=%u flags=0x%08x chess960=%u newer=%u custom=%u encrypted=%u\n",
			i,
			gameOffset,
			size,
			word,
			chess960 ? 1 : 0,
			newerFlag ? 1 : 0,
			customStart ? 1 : 0,
			encrypted ? 1 : 0);

		if (dumpMoves && chess960 && customStart && size > 4 + 36)
		{
			// game record: 4-byte word, 28-byte position, 8-byte extension,
			// then the move bytes
			unsigned char setupBytes[36];
			unsigned moveLen = size - 4 - 36;

			if (readExact(cbg, setupBytes, 36))
			{
				unsigned char* moveBytes = new unsigned char[moveLen];

				if (readExact(cbg, moveBytes, moveLen))
				{
					::printf("  pos=");
					dumpHex(setupBytes, 36);
					::printf("\n  moves=");
					dumpHex(moveBytes, moveLen);
					::putchar('\n');
				}

				delete[] moveBytes;
			}

			continue;
		}

		if (customStart)
		{
			unsigned available = size > 4 ? size - 4 : 0;
			unsigned probeSize = available < 36 ? available : 36;
			unsigned char setupBytes[36];
			::memset(setupBytes, 0, sizeof(setupBytes));

			if (probeSize != 0 && readExact(cbg, setupBytes, probeSize))
			{
				unsigned firstChunk = probeSize < 28 ? probeSize : 28;
				::printf("  setup[0:%u]=", firstChunk);
				dumpHex(setupBytes, firstChunk);
				::putchar('\n');

				if (probeSize > 28)
				{
					::printf("  setup[28:%u]=", probeSize);
					dumpHex(setupBytes + 28, probeSize - 28);
					::putchar('\n');
				}
			}
		}
	}

	::printf(
		"summary total=%u deleted=%u custom=%u chess960=%u newer=%u encrypted=%u custom_and_960=%u\n",
		summary.total,
		summary.deleted,
		summary.customStart,
		summary.chess960,
		summary.newerFlag,
		summary.encrypted,
		summary.customAnd960);

	::fclose(cbg);
	::fclose(cbh);
	return 0;
}
