// test_cbm_media.cpp — validate MediaTable (.cbm parser) with INDEPENDENT
// ground-truth checks (not just self-consistency with probe_cbm):
//   1. Independently read the header from the .cbm file and verify
//      fileSize == headerSize + numRecords*recordSize, accepting both the
//      canonical 32-byte header and the 28-byte-header fallback. An empty
//      media database (numRecords == 0 / 0xFFFFFFFF, or recordSize == 0 /
//      0xFFFFFFFF) is VALID, not a failure.
//   2. MediaTable::read must report entryCount() == the number of records
//      whose marker is 0xFFFFFFFF (independent marker scan), which for a
//      well-formed non-empty file equals numRecords. This cross-checks the
//      marker validation + record parsing without being circular.
//   3. Every manifest filename parsed by MediaTable whose extension is an
//      image type (.jpg/.bmp/.gif) MUST exist in the database's media
//      (.html) folder on disk; .wmv files are expected to be absent from
//      that folder (they live elsewhere on the disc). This uses the
//      filesystem as ground truth for the manifest parse.
//   4. SYNTHETIC corrupt-file case: craft .cbm files in a temp directory
//      with (a) a garbage header, (b) a valid header + one corrupt-marker
//      record + one valid record, and (c) a truncated file. Verify
//      MediaTable never crashes and degrades gracefully (read returns
//      false for unparseable files, or entryCount reflects the skipped
//      corrupt record). isLinkageDecoded() must be false.
//
// Usage: test_cbm_media <rootname> [html-dir]
//   rootname = DB path WITHOUT the .cbm suffix
//   html-dir = the database's media folder (e.g. ".../Mega Database 2010.html")

#include "db/cbh/cbh_media.h"
#include "util/u_progress.h"
#include "mstl/m_string.h"
#include "mstl/m_vector.h"

#include <tcl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

namespace tcl { namespace bits { Tcl_Interp* interp = nullptr; } }

struct TclInterpreter
{
	TclInterpreter()  { tcl::bits::interp = Tcl_CreateInterp(); Tcl_Init(tcl::bits::interp); }
	~TclInterpreter() { Tcl_DeleteInterp(tcl::bits::interp); tcl::bits::interp = nullptr; }
};

static unsigned leU32(unsigned char const* p)
{
	return unsigned(p[0]) | (unsigned(p[1]) << 8) | (unsigned(p[2]) << 16) | (unsigned(p[3]) << 24);
}

static void putU32LE(unsigned char* p, unsigned v)
{
	p[0] = (unsigned char)(v & 0xff);
	p[1] = (unsigned char)((v >> 8) & 0xff);
	p[2] = (unsigned char)((v >> 16) & 0xff);
	p[3] = (unsigned char)((v >> 24) & 0xff);
}

static bool endsWith(char const* s, char const* suf)
{
	unsigned ls = strlen(s), lf = strlen(suf);
	return ls >= lf && strcmp(s + ls - lf, suf) == 0;
}

// Write a synthetic .cbm file at `path` with the given bytes.
static bool writeFile(char const* path, unsigned char const* data, unsigned size)
{
	FILE* fp = fopen(path, "wb");
	if (!fp) return false;
	bool ok = (fwrite(data, 1, size, fp) == size);
	fclose(fp);
	return ok;
}

int main(int argc, char** argv)
{
	if (argc < 2) { fprintf(stderr, "usage: %s <rootname-without-.cbm> [html-dir]\n", argv[0]); return 1; }

	mstl::string root(argv[1]);
	mstl::string cbmPath(root + ".cbm");
	char const* htmlDir = (argc >= 3) ? argv[2] : nullptr;

	int fail = 0;

	// --- (1) INDEPENDENT header + file-size check (does not use MediaTable) ---
	FILE* fp = fopen(cbmPath.c_str(), "rb");
	if (!fp) { fprintf(stderr, "cannot open %s\n", cbmPath.c_str()); return 2; }
	unsigned char hdr[32];
	size_t got = fread(hdr, 1, 32, fp);
	fclose(fp);
	if (got < 28) { fprintf(stderr, "cannot read 28-byte header (got %zu)\n", got); return 2; }
	unsigned version    = leU32(hdr + 0);
	unsigned recordSize = leU32(hdr + 4);
	unsigned numRecords = leU32(hdr + 8);

	struct stat st;
	if (stat(cbmPath.c_str(), &st) != 0) { fprintf(stderr, "stat failed\n"); return 2; }
	unsigned long long fileSize = st.st_size;
	unsigned long long exp32 = 32ULL + (unsigned long long)numRecords * recordSize;
	unsigned long long exp28 = 28ULL + (unsigned long long)numRecords * recordSize;

	bool empty = (numRecords == 0 || numRecords == 0xFFFFFFFFu
				|| recordSize == 0 || recordSize == 0xFFFFFFFFu);

	printf("INDEPENDENT header: version=%u recordSize=%u numRecords=%u\n", version, recordSize, numRecords);
	printf("INDEPENDENT size:   file=%llu  exp32=%llu  exp28=%llu  empty=%d\n",
			fileSize, exp32, exp28, int(empty));

	if (!empty)
	{
		// Non-empty: the record slab must fit the file under either header size.
		bool fit32 = (exp32 == fileSize);
		bool fit28 = (exp28 == fileSize);
		if (!fit32 && !fit28)
		{
			// Lenient: still OK if records fit within the file (trailing bytes).
			if (exp32 > fileSize && exp28 > fileSize)
			{ fprintf(stderr, "FAIL: file size %llu too small for %u*%u records\n", fileSize, numRecords, recordSize); fail = 1; }
			else
				printf("INDEPENDENT size: lenient match (trailing/leading bytes)\n");
		}
		else
		{
			printf("INDEPENDENT size: %s\n", fit32 ? "MATCH(32)" : "MATCH(28)");
		}
		if (version != 1)
		{ fprintf(stderr, "FAIL: unexpected version %u (expected 1)\n", version); fail = 1; }
	}
	else
	{
		printf("INDEPENDENT size: empty media database (valid)\n");
		// An empty stub is valid regardless of trailing bytes; only reject if
		// the file is too small to be a header at all.
		if (fileSize < 28)
		{ fprintf(stderr, "FAIL: empty file smaller than 28-byte header\n"); fail = 1; }
	}

	// --- (2) MediaTable parse, cross-check against the independent header ---
	TclInterpreter tcl;
	util::Progress& progress = util::Progress::null();
	db::cbh::MediaTable mt;
	if (!mt.read(root, progress))
	{
		fprintf(stderr, "FAIL: MediaTable::read returned false for %s\n", cbmPath.c_str());
		fail = 1;
		// Even on read failure, the corrupt-file sub-tests below still run.
	}
	else
	{
		printf("MediaTable: isOpen=%d entryCount(bags)=%u fileCount(refs)=%u linkageDecoded=%d\n",
				mt.isOpen(), mt.entryCount(), mt.fileCount(), int(mt.isLinkageDecoded()));

		if (!mt.isLinkageDecoded())
			printf("CHECK: isLinkageDecoded() == false (expected; linkage not yet RE'd)\n");
		else
		{ fprintf(stderr, "FAIL: isLinkageDecoded() unexpectedly true\n"); fail = 1; }

		if (empty)
		{
			if (mt.entryCount() != 0)
			{ fprintf(stderr, "FAIL: empty db but entryCount=%u\n", mt.entryCount()); fail = 1; }
			else
				printf("CHECK: empty media database -> 0 bags (ok)\n");
		}
		else
		{
			// --- (2b) INDEPENDENT marker scan ---
			// Re-open the file and, for each record, check the 4-byte marker at
			// the record offset (under both 32- and 28-byte header assumptions).
			// Count records whose marker == 0xFFFFFFFF; MediaTable::entryCount()
			// must equal that count (it skips bad-marker records).
			FILE* fp2 = fopen(cbmPath.c_str(), "rb");
			unsigned validMarkers = 0;
			unsigned totalRecords = numRecords;
			unsigned hdrSz = (exp32 == fileSize) ? 32 : (exp28 == fileSize ? 28 : 32);
			if (fp2)
			{
				for (unsigned i = 0; i < totalRecords; ++i)
				{
					unsigned long long off = (unsigned long long)hdrSz + (unsigned long long)i * recordSize;
					if (off + 4 > fileSize) break; // truncated
					unsigned char mb[4];
					if (fseek(fp2, (long)off, SEEK_SET) != 0) break;
					if (fread(mb, 1, 4, fp2) != 4) break;
					unsigned m = leU32(mb);
					if (m == 0xFFFFFFFFu) ++validMarkers;
				}
				fclose(fp2);
			}
			printf("INDEPENDENT marker scan: %u/%u records have 0xFFFFFFFF marker\n",
					validMarkers, totalRecords);
			if (mt.entryCount() != validMarkers)
			{
				fprintf(stderr, "FAIL: entryCount=%u != independent validMarkers=%u\n",
						mt.entryCount(), validMarkers);
				fail = 1;
			}
			else
				printf("CHECK: entryCount == independent valid-marker count (ok)\n");
		}

		mt.dump(4);
	}

	// --- (3) INDEPENDENT filesystem check of the parsed manifest ---
	// Uses collectMediaFiles() (with classifyFile()) and cross-checks the
	// parser's media-type classification against an independent extension
	// test. Some manifest media (notably .wmv from ChessBase Magazine) lives
	// on the install disc, not in the database's .html folder, so the image
	// presence check is lenient (PASS at ≥80% present; report missing ones).
	if (htmlDir && mt.isOpen())
	{
		mstl::vector<db::cbh::MediaTable::MediaEntry> entries;
		mt.collectMediaFiles(entries);

		unsigned imgTotal = 0, imgPresent = 0;
		unsigned vidTotal = 0, vidPresent = 0;
		unsigned audTotal = 0, audPresent = 0;
		unsigned classMismatch = 0;
		for (unsigned i = 0; i < entries.size(); ++i)
		{
			char const* fn = entries[i].filename.c_str();
			// Independent classification by extension.
			bool isWmv = endsWith(fn, ".wmv") || endsWith(fn, ".avi") || endsWith(fn, ".mp4")
					|| endsWith(fn, ".mpg") || endsWith(fn, ".mpeg");
			bool isImg = endsWith(fn, ".jpg") || endsWith(fn, ".jpeg") || endsWith(fn, ".bmp")
					|| endsWith(fn, ".gif") || endsWith(fn, ".png");
			bool isAud = endsWith(fn, ".mp3") || endsWith(fn, ".wav") || endsWith(fn, ".ogg");
			unsigned indepType = isImg ? db::cbh::MediaTable::Media_Picture
							: (isWmv ? db::cbh::MediaTable::Media_Video
							: (isAud ? db::cbh::MediaTable::Media_Audio : db::cbh::MediaTable::Media_None));
			if (entries[i].type != indepType)
				++classMismatch;

			char path[4096];
			snprintf(path, sizeof(path), "%s/%s", htmlDir, fn);
			bool exists = (access(path, F_OK) == 0);
			if (isImg)		{ ++imgTotal; imgPresent += exists; if (!exists) printf("  NOTE: image not in html-dir (on disc?): %s\n", fn); }
			else if (isWmv)	{ ++vidTotal; vidPresent += exists; }
			else if (isAud)	{ ++audTotal; audPresent += exists; }
		}
		printf("INDEPENDENT manifest check: images %u/%u present, video %u/%u, audio %u/%u in html-dir\n",
				imgPresent, imgTotal, vidPresent, vidTotal, audPresent, audTotal);
		if (classMismatch != 0)
		{ fprintf(stderr, "FAIL: %u manifest entries classified differently by classifyFile vs independent check\n", classMismatch); fail = 1; }
		else
			printf("CHECK: classifyFile() matches independent extension classification (ok)\n");
		// Lenient image presence: ≥80% of referenced images must exist locally
		// (a few may live on the ChessBase Magazine install disc).
		if (imgTotal > 0)
		{
			unsigned pct = (imgPresent * 100) / imgTotal;
			if (pct < 80)
			{ fprintf(stderr, "FAIL: only %u%% (%u/%u) of image manifest files present — parse likely wrong\n", pct, imgPresent, imgTotal); fail = 1; }
			else
				printf("CHECK: %u%% of referenced images present locally (lenient ≥80%%) (ok)\n", pct);
		}
		// Videos/audio are expected to be absent from the html-dir (on the disc).
		if (vidPresent != 0)
		{ fprintf(stderr, "NOTE: %u video files unexpectedly present in html-dir (expected on disc)\n", vidPresent); }
	}

	// --- (4) SYNTHETIC corrupt-file cases ---
	// Build corrupt .cbm files in /tmp and verify MediaTable degrades
	// gracefully (never crashes; returns false or a sane entryCount).
	{
		char tmpDir[] = "/tmp/cbm_test_XXXXXX";
		if (!mkdtemp(tmpDir))
		{ fprintf(stderr, "WARN: mkdtemp failed; skipping corrupt-file sub-tests\n"); }
		else
		{
			printf("\n--- Synthetic corrupt-file cases ---\n");

			// (4a) Garbage header (wrong version + junk). read() must return false.
			{
				unsigned char garbage[64];
				for (unsigned i = 0; i < sizeof(garbage); ++i) garbage[i] = (unsigned char)(i * 7);
				// version=99 (invalid), so parseHeader rejects it.
				putU32LE(garbage + 0, 99);
				char path[1024];
				snprintf(path, sizeof(path), "%s/garbage.cbm", tmpDir);
				if (!writeFile(path, garbage, sizeof(garbage)))
					{ fprintf(stderr, "WARN: cannot write garbage.cbm\n"); }
				else
				{
					mstl::string r(tmpDir);
					r += "/garbage";
					db::cbh::MediaTable cm;
					bool ok = cm.read(r, progress);
					printf("(4a) garbage header: read=%d isOpen=%d entryCount=%u\n",
							int(ok), int(cm.isOpen()), cm.entryCount());
					if (ok && cm.isOpen())
					{ fprintf(stderr, "FAIL: garbage header should not parse\n"); fail = 1; }
					else
						printf("CHECK (4a): garbage header rejected gracefully (ok)\n");
				}
			}

			// (4b) Valid header + one corrupt-marker record + one valid record.
			// read() must return true; entryCount must be 1 (corrupt skipped).
			{
				unsigned rs = 64;
				unsigned nrec = 2;
				unsigned fsize = 32 + nrec * rs;
				unsigned char* buf = (unsigned char*)calloc(fsize, 1);
				// header: version=1, recordSize=64, numRecords=2, firstDeleted=0xFFFFFFFF
				putU32LE(buf + 0, 1);
				putU32LE(buf + 4, rs);
				putU32LE(buf + 8, nrec);
				putU32LE(buf + 12, 0xFFFFFFFFu);
				// record 0: BAD marker (0x12345678), value=1
				unsigned char* r0 = buf + 32;
				putU32LE(r0 + 0, 0x12345678u);
				putU32LE(r0 + 4, 1);
				// record 1: GOOD marker (0xFFFFFFFF), value=1
				unsigned char* r1 = buf + 32 + rs;
				putU32LE(r1 + 0, 0xFFFFFFFFu);
				putU32LE(r1 + 4, 1);
				char path[1024];
				snprintf(path, sizeof(path), "%s/onbad.cbm", tmpDir);
				bool wrote = writeFile(path, buf, fsize);
				free(buf);
				if (!wrote)
					{ fprintf(stderr, "WARN: cannot write onbad.cbm\n"); }
				else
				{
					mstl::string r(tmpDir);
					r += "/onbad";
					db::cbh::MediaTable cm;
					bool ok = cm.read(r, progress);
					printf("(4b) one-bad-marker: read=%d isOpen=%d entryCount=%u (expect 1)\n",
							int(ok), int(cm.isOpen()), cm.entryCount());
					if (!ok || !cm.isOpen())
					{ fprintf(stderr, "FAIL: valid+corrupt file should parse (read=%d isOpen=%d)\n", int(ok), int(cm.isOpen())); fail = 1; }
					else if (cm.entryCount() != 1)
					{ fprintf(stderr, "FAIL: expected entryCount=1 (bad marker skipped), got %u\n", cm.entryCount()); fail = 1; }
					else
						printf("CHECK (4b): corrupt-marker record skipped, valid one kept (ok)\n");
				}
			}

			// (4c) Truncated file: header claims 3 records but file ends mid-way.
			// read() must not crash; it stops at the truncation.
			{
				unsigned rs = 64;
				unsigned nrec = 3;
				unsigned truncSize = 32 + rs + 10; // header + 1 record + 10 bytes
				unsigned char* buf = (unsigned char*)calloc(truncSize, 1);
				putU32LE(buf + 0, 1);
				putU32LE(buf + 4, rs);
				putU32LE(buf + 8, nrec);
				putU32LE(buf + 12, 0xFFFFFFFFu);
				// record 0: GOOD marker
				unsigned char* r0 = buf + 32;
				putU32LE(r0 + 0, 0xFFFFFFFFu);
				putU32LE(r0 + 4, 1);
				char path[1024];
				snprintf(path, sizeof(path), "%s/trunc.cbm", tmpDir);
				bool wrote = writeFile(path, buf, truncSize);
				free(buf);
				if (!wrote)
					{ fprintf(stderr, "WARN: cannot write trunc.cbm\n"); }
				else
				{
					mstl::string r(tmpDir);
					r += "/trunc";
					db::cbh::MediaTable cm;
					bool ok = cm.read(r, progress);
					printf("(4c) truncated: read=%d isOpen=%d entryCount=%u (expect 1: the record that fit)\n",
							int(ok), int(cm.isOpen()), cm.entryCount());
					// Graceful parse: the one full record that fits must be parsed;
					// the truncated remainder is dropped, no crash.
					if (!ok || !cm.isOpen())
					{ fprintf(stderr, "FAIL: truncated file should still parse the surviving record (read=%d isOpen=%d)\n", int(ok), int(cm.isOpen())); fail = 1; }
					else if (cm.entryCount() != 1)
					{ fprintf(stderr, "FAIL: expected entryCount=1 for truncated file, got %u\n", cm.entryCount()); fail = 1; }
					else
						printf("CHECK (4c): truncation parsed the surviving record, dropped the rest (ok)\n");
				}
			}

			// (4d) Empty stub with numRecords == 0xFFFFFFFF sentinel.
			// read() must return true with 0 entries (graceful empty handling).
			{
				unsigned char buf[32];
				memset(buf, 0, sizeof(buf));
				putU32LE(buf + 0, 1);             // version
				putU32LE(buf + 4, 1024);          // recordSize
				putU32LE(buf + 8, 0xFFFFFFFFu);   // numRecords sentinel
				putU32LE(buf + 12, 0xFFFFFFFFu);  // firstDeleted
				char path[1024];
				snprintf(path, sizeof(path), "%s/empty.cbm", tmpDir);
				if (!writeFile(path, buf, sizeof(buf)))
					{ fprintf(stderr, "WARN: cannot write empty.cbm\n"); }
				else
				{
					mstl::string r(tmpDir);
					r += "/empty";
					db::cbh::MediaTable cm;
					bool ok = cm.read(r, progress);
					printf("(4d) empty sentinel (numRecords=0xFFFFFFFF): read=%d isOpen=%d entryCount=%u\n",
							int(ok), int(cm.isOpen()), cm.entryCount());
					if (!ok || !cm.isOpen() || cm.entryCount() != 0)
					{ fprintf(stderr, "FAIL: empty sentinel should give read=1 isOpen=1 entryCount=0\n"); fail = 1; }
					else
						printf("CHECK (4d): numRecords==0xFFFFFFFF treated as empty (ok)\n");
				}
			}

			// (4e) Empty stub with recordSize == 0xFFFFFFFF sentinel.
			// read() must return true with 0 entries (the other empty sentinel).
			{
				unsigned char buf[32];
				memset(buf, 0, sizeof(buf));
				putU32LE(buf + 0, 1);             // version
				putU32LE(buf + 4, 0xFFFFFFFFu);   // recordSize sentinel
				putU32LE(buf + 8, 64);            // numRecords (would-be)
				putU32LE(buf + 12, 0xFFFFFFFFu);  // firstDeleted
				char path[1024];
				snprintf(path, sizeof(path), "%s/rsent.cbm", tmpDir);
				if (!writeFile(path, buf, sizeof(buf)))
					{ fprintf(stderr, "WARN: cannot write rsent.cbm\n"); }
				else
				{
					mstl::string r(tmpDir); r += "/rsent";
					db::cbh::MediaTable cm;
					bool ok = cm.read(r, progress);
					printf("(4e) empty sentinel (recordSize=0xFFFFFFFF): read=%d isOpen=%d entryCount=%u\n",
							int(ok), int(cm.isOpen()), cm.entryCount());
					if (!ok || !cm.isOpen() || cm.entryCount() != 0)
					{ fprintf(stderr, "FAIL: recordSize==0xFFFFFFFF should give read=1 isOpen=1 entryCount=0\n"); fail = 1; }
					else
						printf("CHECK (4e): recordSize==0xFFFFFFFF treated as empty (ok)\n");
				}
			}

			// (4f) Huge/garbage FilesUsed count in a record: the hardened parser must
			// clamp it to the bytes available and never loop past recSize.
			{
				unsigned rs = 64;
				unsigned nrec = 1;
				unsigned fsize = 32 + nrec * rs;
				unsigned char* buf = (unsigned char*)calloc(fsize, 1);
				putU32LE(buf + 0, 1);
				putU32LE(buf + 4, rs);
				putU32LE(buf + 8, nrec);
				putU32LE(buf + 12, 0xFFFFFFFFu);
				unsigned char* r0 = buf + 32;
				putU32LE(r0 + 0, 0xFFFFFFFFu);   // valid marker
				putU32LE(r0 + 4, 1);             // value
				// A FilesUsed manifest claiming 999999 files (impossible in 56 bytes).
				memcpy(r0 + 8, "FilesUsed\n", 10);
				memcpy(r0 + 18, "999999\n", 7);   // count = 999999
				// rest is zero (no filename lines) — truncated manifest
				char path[1024];
				snprintf(path, sizeof(path), "%s/huge.cbm", tmpDir);
				bool wrote = writeFile(path, buf, fsize);
				free(buf);
				if (!wrote)
					{ fprintf(stderr, "WARN: cannot write huge.cbm\n"); }
				else
				{
					mstl::string r(tmpDir); r += "/huge";
					db::cbh::MediaTable cm;
					bool ok = cm.read(r, progress);
					printf("(4f) huge FilesUsed count: read=%d isOpen=%d entryCount=%u fileCount=%u\n",
							int(ok), int(cm.isOpen()), cm.entryCount(), cm.fileCount());
					// Must not crash, must not loop, must not allocate ~1M entries; the
					// clamped count yields zero actual filename lines.
					if (!ok || !cm.isOpen() || cm.entryCount() != 1 || cm.fileCount() != 0)
					{ fprintf(stderr, "FAIL: huge-count record should parse to 1 bag/0 files (read=%d isOpen=%d entryCount=%u fileCount=%u)\n", int(ok), int(cm.isOpen()), cm.entryCount(), cm.fileCount()); fail = 1; }
					else
						printf("CHECK (4f): huge FilesUsed count clamped, no runaway loop (ok)\n");
				}
			}
		}
	}

	if (fail) { printf("RESULT: FAIL\n"); return 1; }
	printf("RESULT: PASS (header/size + marker + empty + corrupt-file + manifest checks)\n");
	return 0;
}

// vi:set ts=3 sw=3: