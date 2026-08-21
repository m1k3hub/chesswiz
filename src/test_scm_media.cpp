// test_scm_media.cpp — validate db::scm::MediaTable (.scm manifest parser)
// with INDEPENDENT ground-truth checks:
//   1. Independent re-computation of the FNV-1a-64 fingerprint (the header
//      API normalizes internally; we normalize the same way externally and
//      hash with our own FNV-1a-64 to cross-check MediaTable::fingerprint).
//   2. Fingerprint stability: deterministic, trim/lowercase invariant, and
//      distinct headers produce distinct fingerprints — the property that
//      ChessBase's .cbm position/offset linkage could NOT satisfy.
//   3. classifyFile() cross-check (independent extension check vs. the
//      static method).
//   4. Synthetic manifest parse: a known-good .scm string written to a temp
//      file and parsed; verifies library size, linkage map, mediaFor(fp)
//      returns the correct entries (including resolvePath joining MediaDir),
//      unknown-fingerprint returns empty, and inline (base64) payloads are
//      preserved.
//   5. Defensive parse: synthetic corrupt manifests (garbage, empty,
//      oversized, truncated bracket, unknown section) must NOT crash and
//      must return isOpen()==false (or sane partial state for the
//      unknown-section case).
//   6. Optional: parse a real .scm passed on the command line.
//
// Usage: test_scm_media                  # runs all self-contained checks
//        test_scm_media <rootname.scm>   # also parses a real .scm file
// =====================================================================

#include "db/scm/scm_media.h"
#include "util/u_progress.h"

#include "mstl/m_map.h"
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

// ---------- independent ground-truth helpers ----------

static bool endsWith(char const* s, char const* suf)
{
	unsigned ls = strlen(s), lf = strlen(suf);
	return ls >= lf && strcmp(s + ls - lf, suf) == 0;
}

// Independent FNV-1a-64 + normalization that mirrors MediaTable's
// fingerprint() internal computation (lower-case, trim, join with "|").
// This is the cross-check: if the parser's fingerprint() agrees with our
// independent hash, the algorithm is correct.
static void normAndHash(char const* parts[], unsigned nparts,
                        uint64_t expected, char const* label)
{
	uint64_t h = 0xcbf29ce484222325ull;
	for (unsigned i = 0; i < nparts; ++i)
	{
		if (i > 0) { h ^= uint64_t('|'); h *= 0x100000001b3ull; }
		// trim
		char const* s = parts[i];
		while (*s == ' ' || *s == '\t') ++s;
		char const* e = s + strlen(s);
		while (e > s && (e[-1] == ' ' || e[-1] == '\t' || e[-1] == '\n')) --e;
		for (; s < e; ++s)
		{
			char c = *s;
			if (c >= 'A' && c <= 'Z') c = c + 32;
			h ^= uint64_t((unsigned char)c);
			h *= 0x100000001b3ull;
		}
	}
	printf("  %s : independent=0x%016llx  parser=%s\n", label,
			(unsigned long long)h,
			(h == expected) ? "MATCH" : "MISMATCH");
}

// ---------- main ----------

int main(int argc, char** argv)
{
	if (argc < 1) return 1;

	int fail = 0;

	// --------------------------------------------------------------
	// (1) Fingerprint determinism + cross-check
	// --------------------------------------------------------------
	{
		// Canonical Bilbao game header.
		char const* w = "Topalov, Veselin";
		char const* b = "Anand, Viswanathan";
		char const* e = "Bilbao 2008";
		char const* d = "2008.??.??";
		unsigned round = 7, result = 2;

		uint64_t f = db::scm::MediaTable::fingerprint(w, b, e, d, round, result);
		printf("CHECK 1: fingerprint(FNV-1a-64) deterministic + independent match\n");
		printf("  MediaTable::fingerprint(Bilbao) = 0x%016llx\n", (unsigned long long)f);
		{
			char const* parts[] = { w, b, e, d, "7", "2" };
			normAndHash(parts, 6, f, "Bilbao canonical");
		}
		// NOTE: the actual match check is done by printing MISMATCH; do the
		// assert via a second invocation that returns the value:
		uint64_t indep = 0;
		{
			uint64_t hh = 0xcbf29ce484222325ull;
			char const* ps[] = { w, b, e, d, "7", "2" };
			for (unsigned i = 0; i < 6; ++i)
			{
				if (i > 0) { hh ^= uint64_t('|'); hh *= 0x100000001b3ull; }
				char const* s = ps[i];
				while (*s == ' ' || *s == '\t') ++s;
				char const* ee = s + strlen(s);
				while (ee > s && (ee[-1] == ' ' || ee[-1] == '\t' || ee[-1] == '\n')) --ee;
				for (; s < ee; ++s)
				{
					char c = *s;
					if (c >= 'A' && c <= 'Z') c = c + 32;
					hh ^= uint64_t((unsigned char)c);
					hh *= 0x100000001b3ull;
				}
			}
			indep = hh;
		}
		if (indep != f) { fprintf(stderr, "FAIL: fingerprint mismatch\n"); fail = 1; }
		else printf("  (ok) match\n");

		// Trim + case invariance.
		uint64_t f2 = db::scm::MediaTable::fingerprint(
			"  Topalov, Veselin  ", "  Anand, Viswanathan  ",
			"  Bilbao 2008  ", "  2008.??.??  ", 7, 2);
		printf("CHECK 1b: fingerprint normalization (trim + lowercase)\n");
		if (f2 != f)
		{
			fprintf(stderr, "FAIL: normalized fingerprint differs\n"); fail = 1;
		}
		else printf("  (ok) stable across normalization\n");

		// Different header -> different fingerprint.
		uint64_t f3 = db::scm::MediaTable::fingerprint(
			"Topalov, Veselin", "Anand, Viswanathan",
			"Linares 2008", "2008.02.??", 7, 1);
		printf("CHECK 1c: distinct headers -> distinct fingerprints\n");
		if (f3 == f)
		{
			fprintf(stderr, "FAIL: different game produced same fingerprint\n"); fail = 1;
		}
		else printf("  (ok) distinct (0x%016llx vs 0x%016llx)\n",
					(unsigned long long)f, (unsigned long long)f3);
	}

	// --------------------------------------------------------------
	// (2) classifyFile cross-check
	// --------------------------------------------------------------
	{
		printf("CHECK 2: classifyFile() vs independent extension check\n");
		struct { char const* fn; db::scm::MediaTable::MediaType expected; } cases[] = {
			{ "foo.jpg",  db::scm::MediaTable::Media_Picture },
			{ "foo.JPG",  db::scm::MediaTable::Media_Picture },
			{ "foo.gif",  db::scm::MediaTable::Media_Picture },
			{ "foo.mp4",  db::scm::MediaTable::Media_Video   },
			{ "foo.wmv",  db::scm::MediaTable::Media_Video   },
			{ "foo.mp3",  db::scm::MediaTable::Media_Audio   },
			{ "foo.m3u8", db::scm::MediaTable::Media_Stream  },
			{ "noext",    db::scm::MediaTable::Media_None    },
		};
		for (unsigned i = 0; i < sizeof(cases)/sizeof(cases[0]); ++i)
		{
			db::scm::MediaTable::MediaType got =
				db::scm::MediaTable::classifyFile(cases[i].fn);
			printf("  %-10s -> type=%u  (expected %u)\n", cases[i].fn,
					unsigned(got), unsigned(cases[i].expected));
			if (got != cases[i].expected)
			{
				fprintf(stderr, "FAIL: classifyFile(%s) returned %u, expected %u\n",
						cases[i].fn, unsigned(got), unsigned(cases[i].expected));
				fail = 1;
			}
		}
	}

	// --------------------------------------------------------------
	// (3) Synthetic manifest parse (in-memory via temp file)
	// --------------------------------------------------------------
	{
		TclInterpreter tcl;
		util::Progress& progress = util::Progress::null();

		char tmpname[] = "/tmp/scm_test_XXXXXX";
		int fd = mkstemp(tmpname);
		if (fd < 0) { fprintf(stderr, "mkstemp failed\n"); fail = 1; }
		else
		{
			uint64_t fpBilbao = db::scm::MediaTable::fingerprint(
				"Topalov, Veselin", "Anand, Viswanathan",
				"Bilbao 2008", "2008.??.??", 7, 2);
			uint64_t fpLinares = db::scm::MediaTable::fingerprint(
				"Leko, Peter", "Anand, Viswanathan",
				"Linares 2008", "2008.02.??", 7, 0);

			char buf[8192];
			int n = snprintf(buf, sizeof(buf),
				"# scidb media manifest\n"
				"[Database \"MyBase\"]\n"
				"[MediaDir \"MyBase.media\"]\n"
				"[Encoding \"utf-8\"]\n"
				"\n"
				"[Media \"M01\"]\n"
				"Type: picture\n"
				"Path: images/bilbao.jpg\n"
				"Title: \"Bilbao 2008: Topalov-Anand\"\n"
				"\n"
				"[Media \"M02\"]\n"
				"Type: video\n"
				"Path: videos/cbm126.mp4\n"
				"\n"
				"[Media \"M03\"]\n"
				"Type: inline-picture\n"
				"Inline: base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEX///+nxBvIAAAAAXRSTlMAQObYZgAAAApJREFUCNdjYAAAAAIAAeIhvDMAAAAASUVORK5CYII=\n"
				"\n"
				"[Game \"%016llx\"]\n"
				"Media: M01, M02\n"
				"\n"
				"[Game \"%016llx\"]\n"
				"Media: M01, M03\n",
				(unsigned long long)fpBilbao,
				(unsigned long long)fpLinares);
			if (n > 0) write(fd, buf, n);
			close(fd);

			db::scm::MediaTable mt;
			if (!mt.read(tmpname, progress))
			{
				fprintf(stderr, "FAIL: read of synthetic .scm returned false\n");
				fail = 1;
			}
			else
			{
				printf("CHECK 3: synthetic manifest parse\n");
				printf("  isOpen=%d mediaCount=%u gameCount=%u\n",
						mt.isOpen(), mt.mediaCount(), mt.gameCount());
				if (mt.mediaCount() != 3)
				{ fprintf(stderr, "FAIL: expected 3 media, got %u\n", mt.mediaCount()); fail = 1; }
				if (mt.gameCount() != 2)
				{ fprintf(stderr, "FAIL: expected 2 linkages, got %u\n", mt.gameCount()); fail = 1; }

				mstl::vector<db::scm::MediaTable::Entry> v;

				mt.mediaFor(fpBilbao, v);
				printf("  mediaFor(Bilbao fp) -> %u entries\n", unsigned(v.size()));
				if (v.size() != 2)
				{ fprintf(stderr, "FAIL: expected 2 entries for Bilbao, got %u\n", unsigned(v.size())); fail = 1; }
				else if (!endsWith(v[0].path.c_str(), "images/bilbao.jpg"))
				{ fprintf(stderr, "FAIL: Bilbao entry path mismatch: %s\n", v[0].path.c_str()); fail = 1; }
				// resolvePath joins MediaDir
				if (!v.empty())
				{
					mstl::string p = mt.resolvePath(v[0]);
					printf("    resolvePath(M01) = %s\n", p.c_str());
					if (!endsWith(p.c_str(), "MyBase.media/images/bilbao.jpg"))
					{ fprintf(stderr, "FAIL: resolvePath didn't join MediaDir: %s\n", p.c_str()); fail = 1; }
				}
				v.clear();

				mt.mediaFor(fpLinares, v);
				printf("  mediaFor(Linares fp) -> %u entries\n", unsigned(v.size()));
				if (v.size() != 2)
				{ fprintf(stderr, "FAIL: expected 2 entries for Linares, got %u\n", unsigned(v.size())); fail = 1; }
				else
				{
					bool sawInline = false;
					for (unsigned k = 0; k < v.size(); ++k)
						if (v[k].inlineData) sawInline = true;
					if (!sawInline)
					{ fprintf(stderr, "FAIL: expected an inlineData entry for Linares\n"); fail = 1; }
					else
						printf("    (ok) inline media reference preserved\n");
				}
				v.clear();

				mt.mediaFor(0xdeadbeefcafebabeull, v);
				if (!v.empty())
				{ fprintf(stderr, "FAIL: unknown fingerprint returned %u entries (expect 0)\n", unsigned(v.size())); fail = 1; }
				else
					printf("  (ok) unknown fingerprint returns empty\n");

				// STABLE-AFTER-REORDER: the .scm links media to a game by its header
				// FINGERPRINT, never by position/row/offset. To actually EXERCISE this
				// (not just re-query the same table), we write a SECOND manifest with
				// the [Game] and [Media] blocks in REVERSED order, parse it into a
				// FRESH MediaTable, and assert mediaFor(fp) returns byte-identical
				// results to the first manifest. If linkage depended on block/row
				// order (as ChessBase .cbm does on .cbg offsets), this would fail.
				// This is the property .cbm could NOT satisfy.
				mstl::vector<db::scm::MediaTable::Entry> refBilbao, refLinares;
				mt.mediaFor(fpBilbao, refBilbao);
				mt.mediaFor(fpLinares, refLinares);

				char tmpname2[] = "/tmp/scm_test_XXXXXX";
				int fd2 = mkstemp(tmpname2);
				bool reorderOk = false;
				if (fd2 >= 0)
				{
					char buf2[8192];
					// Same content as the first manifest but with blocks REVERSED:
					// Linares [Game] before Bilbao [Game], and M03/M02/M01 reordered.
					int n2 = snprintf(buf2, sizeof(buf2),
						"# scidb media manifest (reordered)\n"
						"[Database \"MyBase\"]\n"
						"[MediaDir \"MyBase.media\"]\n"
						"[Encoding \"utf-8\"]\n\n"
						"[Media \"M03\"]\nType: inline-picture\n"
						"Inline: base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEX///+nxBvIAAAAAXRSTlMAQObYZgAAAApJREFUCNdjYAAAAAIAAeIhvDMAAAAASUVORK5CYII=\n\n"
						"[Media \"M02\"]\nType: video\nPath: videos/cbm126.mp4\n\n"
						"[Media \"M01\"]\nType: picture\nPath: images/bilbao.jpg\n\n"
						"[Game \"%016llx\"]\nMedia: M01, M03\n\n"
						"[Game \"%016llx\"]\nMedia: M01, M02\n",
						(unsigned long long)fpLinares,
						(unsigned long long)fpBilbao);
					if (n2 > 0) write(fd2, buf2, n2);
					close(fd2);

					db::scm::MediaTable mt2;
					if (mt2.read(tmpname2, progress) && mt2.isOpen())
					{
						mstl::vector<db::scm::MediaTable::Entry> rBilbao, rLinares;
						mt2.mediaFor(fpBilbao, rBilbao);
						mt2.mediaFor(fpLinares, rLinares);
						bool same = (rBilbao.size()==refBilbao.size() && rLinares.size()==refLinares.size());
						for (unsigned k = 0; same && k < rBilbao.size(); ++k)
							same = (rBilbao[k].path==refBilbao[k].path && rBilbao[k].mediaId==refBilbao[k].mediaId && rBilbao[k].type==refBilbao[k].type);
						for (unsigned k = 0; same && k < rLinares.size(); ++k)
							same = (rLinares[k].path==refLinares[k].path && rLinares[k].mediaId==refLinares[k].mediaId && rLinares[k].type==refLinares[k].type);
						reorderOk = same;
					}
					unlink(tmpname2);
				}
				printf("CHECK 3b: stable-after-reorder (second manifest, blocks reversed)\n");
				if (!reorderOk)
				{ fprintf(stderr, "FAIL: mediaFor differs when [Game]/[Media] blocks are reordered — linkage is position-dependent!\n"); fail = 1; }
				else
					printf("  (ok) mediaFor(fp) identical across block orderings — linkage is fingerprint-keyed, position-independent\n");
			}
			unlink(tmpname);
		}
	}

	// --------------------------------------------------------------
	// (4) Synthetic corrupt manifests
	// --------------------------------------------------------------
	{
		TclInterpreter tcl;
		util::Progress& progress = util::Progress::null();

		struct Case { char const* desc; char const* content; size_t len; bool expectOpen; } cases[] = {
			{ "garbage",         "this is not a manifest\n",                       0, false },
			{ "empty",           "",                                                0, false },
			{ "truncated-bracket","[Database \"x\"\n",                              0, false },
			{ "unknown-section",
				"[Database \"x\"]\n"
				"[Boardsync \"ignored (v2)\"]\n"
				"[Media \"M01\"]\n"
				"Type: picture\n"
				"Path: a.jpg\n",
				0, true },
		};
		for (unsigned i = 0; i < sizeof(cases)/sizeof(cases[0]); ++i)
		{
			char tmpname[] = "/tmp/scm_test_XXXXXX";
			int fd = mkstemp(tmpname);
			if (fd < 0) continue;
			::write(fd, cases[i].content, strlen(cases[i].content));
			close(fd);

			db::scm::MediaTable mt;
			bool ok = mt.read(tmpname, progress);
			printf("CHECK 4.%u: %-20s read=%d isOpen=%d\n", i, cases[i].desc,
					int(ok), int(mt.isOpen()));
			if (cases[i].expectOpen && !mt.isOpen())
			{
				fprintf(stderr, "FAIL: expected open=true for case '%s'\n", cases[i].desc);
				fail = 1;
			}
			else if (!cases[i].expectOpen && mt.isOpen())
			{
				fprintf(stderr, "FAIL: expected open=false for case '%s' but isOpen=true\n", cases[i].desc);
				fail = 1;
			}
			unlink(tmpname);
		}

		// Oversized: 5 MB garbage. The cap is 16 MB so this passes the cap
		// but should still parse gracefully (open=false because the header
		// is malformed but we didn't crash).
		char tmpname[] = "/tmp/scm_test_XXXXXX";
		int fd = mkstemp(tmpname);
		if (fd >= 0)
		{
			char chunk[65536]; memset(chunk, 'A', sizeof(chunk));
			for (int j = 0; j < 80; ++j) ::write(fd, chunk, sizeof(chunk));
			close(fd);
			db::scm::MediaTable mt;
			bool ok = mt.read(tmpname, progress);
			printf("CHECK 4.4: %-20s read=%d isOpen=%d (under-cap garbage)\n",
					"oversized-5MB", int(ok), int(mt.isOpen()));
			if (mt.isOpen())
			{ fprintf(stderr, "FAIL: oversized garbage should not open\n"); fail = 1; }
			unlink(tmpname);
		}
	}

	// --------------------------------------------------------------
	// (5) Optional: parse a real .scm passed on the command line
	// --------------------------------------------------------------
	if (argc >= 2)
	{
		TclInterpreter tcl;
		util::Progress& progress = util::Progress::null();
		db::scm::MediaTable mt;
		if (!mt.read(argv[1], progress))
			printf("CHECK 5: real .scm '%s' not parsed (or missing)\n", argv[1]);
		else
		{
			printf("CHECK 5: real .scm '%s' parsed\n", argv[1]);
			printf("  isOpen=%d mediaCount=%u gameCount=%u\n",
					mt.isOpen(), mt.mediaCount(), mt.gameCount());
			mt.dump();
		}
	}

	if (fail) { printf("RESULT: FAIL\n"); return 1; }
	printf("RESULT: PASS (fingerprint + classifyFile + synthetic parse + corrupt-file + (optional) real parse)\n");
	return 0;
}

// vi:set ts=3 sw=3:
