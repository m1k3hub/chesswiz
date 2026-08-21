// ======================================================================
// probe_cbm — ChessBase .cbm (media) file structure probe tool
// ======================================================================
// Dumps the structure of a .cbm (ChessBase Media) file for reverse
// engineering. Layout (reverse-engineered from a Mega Database 2010
// fixture, validated end-to-end):
//
//   32-byte header:
//     ofs  0 (u32): version       (observed: 1)
//     ofs  4 (u32): recordSize    (observed: 1024)
//     ofs  8 (u32): numRecords    (observed: 64)
//     ofs 12 (u32): firstDeleted  (0xFFFFFFFF = none)
//     ofs 16 (u32): ?             (observed: 36)
//     ofs 20 (u32): ?             (observed: 0x00B1CF3B, likely checksum)
//     ofs 24 (u32): reserved      (0)
//   followed by numRecords records of recordSize bytes, at offset
//   32 + i*recordSize. File size == 32 + numRecords*recordSize.
//
//   Each record is a media "bag":
//     ofs 0 (u32): marker  (0xFFFFFFFF)
//     ofs 4 (u32): value   (observed: 1; type/version?)
//     ofs 8..     : a text manifest  "FilesUsed\n<count>\n<file1>\n...\n"
//                   (<count> newline-terminated filenames)
//     remainder   : a binary table of 4-byte little-endian pointers
//                   (values ~50MB => likely offsets into .cbg/.cba that
//                   link this media bag to the games/annotations that
//                   reference it), padded to recordSize.
//
// Usage:
//   probe_cbm <file.cbm> [max-records] [html-dir]
//     max-records: limit number of bags dumped (default: all)
//     html-dir:    if given, verify each manifest filename exists there
//
// Build: make -C src probe_cbm
// ======================================================================

#include "mstl/m_fstream.h"
#include "mstl/m_string.h"
#include "mstl/m_vector.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unistd.h>
#include <sys/stat.h>

using namespace mstl;

namespace {

uint32_t readU32LE(unsigned char const* p)
{
	return uint32_t(p[0]) | (uint32_t(p[1]) << 8)
	     | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}

// Read one newline-terminated line from rec at offset pos (up to bufSize-1
// chars). Returns the line length (excluding the '\n'). pos is advanced past
// the '\n' by the caller.
unsigned readLine(unsigned char const* rec, unsigned recSize, unsigned pos, char* buf, unsigned bufSize)
{
	unsigned len = 0;
	while (pos < recSize && rec[pos] != '\n' && len + 1 < bufSize)
		buf[len++] = rec[pos++];
	buf[len] = '\0';
	return len;
}

void dumpBag(unsigned char const* rec, unsigned recSize, unsigned idx, unsigned offset, char const* htmlDir)
{
	::printf("\n--- Bag %u (offset %u, %u bytes) ---\n", idx, offset, recSize);

	uint32_t marker = readU32LE(rec);
	uint32_t value  = readU32LE(rec + 4);
	::printf("  marker=0x%08x%s  value=%u\n", marker,
				(marker == 0xFFFFFFFFu ? " (ok)" : " (UNEXPECTED)"), value);

	// TEXT manifest region = from offset 8 to the first byte that is neither
	// printable ASCII nor '\n' (control/null, or the start of the binary region).
	unsigned textEnd = 8;
	while (textEnd < recSize
		&& ((rec[textEnd] >= 0x20 && rec[textEnd] < 0x7f) || rec[textEnd] == '\n'))
		++textEnd;

	unsigned pos = 8;
	if (pos + 10 <= textEnd && ::memcmp(rec + pos, "FilesUsed\n", 10) == 0)
	{
		pos += 10;
		char line[256];
		unsigned llen = readLine(rec, textEnd, pos, line, sizeof(line));
		pos += llen + 1; // skip the count line + '\n'
		unsigned declared = unsigned(::atoi(line));

		// Read ALL remaining lines in the text region (the declared count is
		// advisory — a bag often lists more files than it declares).
		unsigned actual = 0;
		unsigned existCnt = 0;
		while (pos < textEnd)
		{
			llen = readLine(rec, textEnd, pos, line, sizeof(line));
			pos += llen + 1;
			if (line[0] == '\0' || line[0] == ' ')
				continue;
			if (actual < 12)
				::printf("    [%u] %s\n", actual, line);
			else if (actual == 12)
				::printf("    ... (more)\n");
			++actual;
			if (htmlDir)
			{
				char path[2048];
				::snprintf(path, sizeof(path), "%s/%s", htmlDir, line);
				if (::access(path, F_OK) == 0) ++existCnt;
			}
		}
		::printf("  FilesUsed: declaredCount=%u actual=%u file(s)\n", declared, actual);
		if (htmlDir)
			::printf("  present in html-dir: %u/%u\n", existCnt, actual);
	}
	else
	{
		// Not a FilesUsed bag: dump the leading printable run as text.
		::printf("  (non-FilesUsed) text run: \"");
		for (unsigned p = pos; p < textEnd; ++p)
			::putchar(rec[p]);
		::printf("\"\n");
		pos = textEnd;
	}

	// BINARY linkage region = [textEnd, recSize), skipping leading null padding.
	// Each 4-byte LE value appears to be (offset_into_.cbg [low 24 bits]) |
	// (tag [high 8 bits]); decode a few for inspection.
	unsigned bstart = textEnd;
	while (bstart < recSize && rec[bstart] == 0) ++bstart;
	unsigned remaining = (bstart < recSize) ? recSize - bstart : 0;
	unsigned nptr = remaining / 4;
	::printf("  linkage region: %u bytes @%u -> %u entries; first:", remaining, bstart, nptr);
	for (unsigned k = 0; k < 8 && k < nptr; ++k)
	{
		uint32_t v = readU32LE(rec + bstart + k*4);
		::printf(" 0x%08x(off=0x%06x,tag=0x%02x)", v, v & 0x00FFFFFFu, (v >> 24) & 0xFFu);
	}
	::printf("\n");
}

} // namespace

int main(int argc, char** argv)
{
	if (argc < 2)
	{
		::fprintf(stderr, "usage: %s <file.cbm> [max-records] [html-dir]\n", argv[0]);
		return 1;
	}

	char const* path = argv[1];
	unsigned maxRecords = ~0u;
	char const* htmlDir = nullptr;
	if (argc >= 3) maxRecords = unsigned(::strtoul(argv[2], 0, 10));
	if (argc >= 4) htmlDir = argv[3];

	FILE* fp = ::fopen(path, "rb");
	if (!fp)
	{
		::fprintf(stderr, "cannot open '%s'\n", path);
		return 1;
	}
	::fseek(fp, 0, SEEK_END);
	long sz = ::ftell(fp);
	::fseek(fp, 0, SEEK_SET);
	vector<unsigned char> data(sz);
	if (sz > 0 && ::fread(data.data(), 1, sz, fp) != size_t(sz))
	{
		::fprintf(stderr, "read error\n");
		::fclose(fp);
		return 1;
	}
	::fclose(fp);
	uint64_t fileSize = data.size();
	::printf("File: %s\nSize: %llu bytes\n", path, (unsigned long long)fileSize);
	if (fileSize < 32)
	{
		::fprintf(stderr, "file too small to contain a 32-byte header\n");
		return 1;
	}

	// --- 32-byte header ---
	uint32_t version      = readU32LE(data.data() + 0);
	uint32_t recordSize   = readU32LE(data.data() + 4);
	uint32_t numRecords   = readU32LE(data.data() + 8);
	uint32_t firstDeleted = readU32LE(data.data() + 12);
	uint32_t field16      = readU32LE(data.data() + 16);
	uint32_t field20      = readU32LE(data.data() + 20);
	uint32_t reserved24   = readU32LE(data.data() + 24);

	::printf("\n=== Header (32 bytes) ===\n");
	::printf("  ofs  0 (u32): version      = %u\n", version);
	::printf("  ofs  4 (u32): recordSize   = %u\n", recordSize);
	::printf("  ofs  8 (u32): numRecords   = %u\n", numRecords);
	::printf("  ofs 12 (u32): firstDeleted = 0x%08x%s\n", firstDeleted,
				(firstDeleted == 0xFFFFFFFFu ? " (none)" : ""));
	::printf("  ofs 16 (u32): field16      = %u (0x%08x)\n", field16, field16);
	::printf("  ofs 20 (u32): field20      = %u (0x%08x)  [likely checksum]\n", field20, field20);
	::printf("  ofs 24 (u32): reserved     = %u\n", reserved24);

	uint64_t expected = 32 + uint64_t(numRecords) * recordSize;
	::printf("\n=== Layout check ===\n");
	::printf("  expected size = 32 + %u*%u = %llu ; actual = %llu -> %s\n",
				numRecords, recordSize, (unsigned long long)expected, (unsigned long long)fileSize,
				(expected == fileSize) ? "MATCH ✓" : "MISMATCH ✗");
	if (expected != fileSize)
		::printf("  (slab = %lld)\n", (long long)(fileSize - expected));

	if (recordSize == 0 || numRecords == 0)
	{
		::fprintf(stderr, "degenerate header (recordSize=%u numRecords=%u); aborting record scan\n",
					recordSize, numRecords);
		return 1;
	}

	unsigned n = (numRecords < maxRecords) ? numRecords : maxRecords;
	::printf("\n=== Bags (dumping %u of %u) ===\n", n, numRecords);

	unsigned totalFiles = 0;
	unsigned totalPointers = 0;
	for (unsigned i = 0; i < n; ++i)
	{
		uint64_t off = 32 + uint64_t(i) * recordSize;
		if (off + recordSize > fileSize)
		{
			::printf("\n  Bag %u: TRUNCATED (offset %llu)\n", i, (unsigned long long)off);
			break;
		}
		// cheap tally of pointers for the summary (4-byte slots after the text)
		dumpBag(data.data() + off, recordSize, i, unsigned(off), htmlDir);
		// re-scan to count files/pointers for summary (uses the same text-region
		// boundary as the parser; the declared count is advisory).
		unsigned char const* rec = data.data() + off;
		unsigned textEnd = 8;
		while (textEnd < recordSize
			&& ((rec[textEnd] >= 0x20 && rec[textEnd] < 0x7f) || rec[textEnd] == '\n'))
			++textEnd;
		if (textEnd >= 18 && ::memcmp(rec + 8, "FilesUsed\n", 10) == 0)
		{
			unsigned pos = 18;
			char line[256];
			unsigned llen = readLine(rec, textEnd, pos, line, sizeof(line));
			pos += llen + 1; // skip count line
			unsigned files = 0;
			while (pos < textEnd)
			{
				llen = readLine(rec, textEnd, pos, line, sizeof(line));
				pos += llen + 1;
				if (line[0] != '\0' && line[0] != ' ') ++files;
			}
			unsigned bstart = textEnd;
			while (bstart < recordSize && rec[bstart] == 0) ++bstart;
			totalFiles += files;
			totalPointers += (recordSize - bstart) / 4;
		}
	}

	::printf("\n=== Summary ===\n");
	::printf("  File size:     %llu\n", (unsigned long long)fileSize);
	::printf("  Header size:   32\n");
	::printf("  recordSize:    %u\n", recordSize);
	::printf("  numRecords:    %u (dumped %u)\n", numRecords, n);
	::printf("  total manifest files referenced: %u\n", totalFiles);
	::printf("  total pointer-table entries:     %u\n", totalPointers);
	if (htmlDir)
		::printf("  html-dir checked: %s\n", htmlDir);

	return 0;
}

// vi:set ts=3 sw=3: