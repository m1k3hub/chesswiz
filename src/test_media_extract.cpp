// test_media_extract — unit tests for the guiding-text media helpers in
// tcl/tcl_media_extract.h (used by ::scidb::db::mediaFiles).
//
// The assertions here are STRUCTURAL rather than fixture-specific. Instead of
// asserting literal `files[2] == "..."` positions against a single hand-typed
// HTML body, each test derives its expectation from a small data model (a set
// of media Refs) plus the documented rules:
//
//   * extraction lists one entry per UNIQUE bare filename, de-duplicated
//     across both the <IMG> pass and the CBLink(tag_stream,...) pass, with
//     pictures (type 1) from IMG refs and streams (type 4) from stream refs,
//     and with the backslash "<DBName>.html\" prefix stripped to the bare
//     filename;
//   * resolveGuidingTextPath maps (database, filename) to
//     "<dbdir>/<DBName>.html/<filename>" preserving the database directory,
//     replacing the database extension with ".html" (no double prefix).
//
// Expectations are generated from the model and then every extracted value is
// checked against INVARIANTS (uniqueness, type correspondence, prefix
// stripping, no-backslash, base-name preservation, single ".html/" occurrence)
// — so the tests stay valid when fixtures are reworded or reordered and only
// fail when the helper's behavior actually changes.
//
// Build (from src/): make test_media_extract
// Run: ./test_media_extract

#include "tcl/tcl_media_extract.h"

#include "m_string.h"
#include "m_vector.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cerrno>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static int g_fail = 0;

static void check(bool cond, char const* msg)
{
	printf("  [%s] %s\n", cond ? " OK " : "FAIL", msg);
	if (!cond) ++g_fail;
}

static bool streq(mstl::string const& a, char const* b)
{
	return a == mstl::string(b);
}

// ---------------------------------------------------------------------
// Section 1 model: a list of media references and a body renderer.
// The expectation (expected files + types, in the order the helper must
// emit them) is derived from the model by the documented rules, NOT typed
// in by hand. So re-ordering or re-wording the refs below exercises more of
// the search space without the test depending on exact positions.
// ---------------------------------------------------------------------

enum RefKind { REF_IMG, REF_STREAM, REF_IMGONLY }; // IMGONLY = tag_image, must be ignored

struct Ref { RefKind kind; char const* render; char const* bare; int style; };

// Render one Ref into HTML. `style` varies the casing/quoting so we cover
// the parser's case-insensitive and single/double/unquoted handling.
static void renderRef(mstl::string& html, Ref const& r)
{
	switch (r.kind)
	{
	case REF_IMG:
		switch (r.style % 3)
		{
		case 0: html += "<IMG src=\""; html += r.render; html += "\">"; break;
		case 1: html += "<img SRC='"; html += r.render; html += "'>"; break;
		default: html += "<IMG src="; html += r.render; html += ">"; break;
		}
		break;
	case REF_STREAM:
	case REF_IMGONLY:
	{
		// case variants on the tag and the token name.
		char const* tag    = (r.style & 1) ? "cblink" : "CBLink";
		char const* token  = (r.style & 2) ? "TAG_STREAM" : "tag_stream";
		if (r.kind == REF_IMGONLY) token = "tag_image";
		html += tag; html += '('; html += token; html += ',';
		html += r.render; html += ",)";
		break;
	}
	}
}

// Derive the expected (files[], types[]) from the model using the documented
// order: all IMG refs (in ref order), then all stream refs (in ref order),
// de-duplicated BY BARE FILENAME across both passes. Returns expected count
// (<= cap).
static int buildExpectation(Ref const* refs, int nrefs,
							mstl::string* expFile, int* expType, int cap)
{
	mstl::string imgF[32]; int ni = 0;
	mstl::string strF[32]; int ns = 0;
	for (int i = 0; i < nrefs; ++i)
	{
		if (refs[i].kind == REF_IMG)       imgF[ni++] = refs[i].bare;
		else if (refs[i].kind == REF_STREAM) strF[ns++] = refs[i].bare;
		// REF_IMGONLY contributes nothing (tag_image refs are ignored).
	}
	int n = 0;
	mstl::string order[32]; int otype[32]; int no = 0;
	// picture pass first, then stream pass — this is the helper's order.
	for (int i = 0; i < ni; ++i) { order[no] = imgF[i]; otype[no++] = 1; }
	for (int i = 0; i < ns; ++i) { order[no] = strF[i]; otype[no++] = 4; }
	for (int i = 0; i < no; ++i)
	{
		bool dup = false;
		for (int j = 0; j < n; ++j)
			if (expFile[j] == order[i]) { dup = true; break; }
		if (!dup && n < cap) { expFile[n] = order[i]; expType[n] = otype[i]; ++n; }
	}
	return n;
}

// Run a full model -> body -> extract -> compare cycle, asserting structural
// invariants rather than literal positions.
static void checkBody(char const* label, Ref const* refs, int nrefs)
{
	mstl::string html;
	for (int i = 0; i < nrefs; ++i)
		renderRef(html, refs[i]);

	mstl::vector<mstl::string> files;
	mstl::vector<int> types;
	tcl_media::extractGuidingTextMedia(html, files, types);

	mstl::string expFile[32]; int expType[32];
	int expN = buildExpectation(refs, nrefs, expFile, expType, 32);

	char msg[512];
	snprintf(msg, sizeof(msg), "%s: extracted count == model-derived count (%d)", label, expN);
	check((int)files.size() == expN, msg);

	// Structural invariants that must hold for ANY input.
	bool noDup = true, noBs = true, orderTyped = true;
	for (unsigned i = 0; i < files.size(); ++i)
	{
		for (unsigned j = i + 1; j < files.size(); ++j)
			if (files[i] == files[j]) noDup = false;
		if (files[i].find("\\", 0) != mstl::string::npos) noBs = false;
		if (i < (unsigned)expN && !(streq(files[i], expFile[i]) && types[i] == expType[i]))
			orderTyped = false;
	}
	check(noDup,   "  (invariant) no filename appears twice");
	check(noBs,    "  (invariant) no filename retains a backslash prefix");
	check(orderTyped, "  (invariant) emitted order == model order and each type matches ");

	// Every extracted (filename,type) must equal a model-derived entry, and the
	// bare filename must equal only the final path segment of some render.
	// Type is taken from the MODEL (picture pass before stream pass) — that is
	// authoritative for cross-pass dedup, not input/HTML order.
	for (unsigned i = 0; i < files.size(); ++i)
	{
		bool seen = false; int wantType = -1;
		for (int e = 0; e < expN; ++e)
			if (streq(expFile[e], files[i].c_str())) { seen = true; wantType = expType[e]; break; }
		snprintf(msg, sizeof(msg), "  (invariant) file \"%s\" maps to a model ref", files[i].c_str());
		check(seen, msg);
		snprintf(msg, sizeof(msg), "  (invariant) type of \"%s\" is %d (picture/stream)", files[i].c_str(), wantType);
		check(types[i] == wantType, msg);
	}
}

// ---------------------------------------------------------------------
// Path helpers for the structural resolve tests.
// ---------------------------------------------------------------------

static int lastSlash(char const* p)
{
	char const* s = strrchr(p, '/');
	return s ? (int)(s - p) : -1;
}

static void dirAndBase(char const* path, char* dir, size_t dsz, char const** base)
{
	int ls = lastSlash(path);
	if (ls < 0) { dir[0] = '\0'; *base = path; }
	else { snprintf(dir, dsz, "%.*s", ls, path); *base = path + ls + 1; }
}

static void stemNoExt(char const* base, char* out, size_t osz)
{
	char const* dot = strrchr(base, '.');
	if (dot) snprintf(out, osz, "%.*s", (int)(dot - base), base);
	else snprintf(out, osz, "%s", base);
}

static int countSubstr(char const* s, char const* sub)
{
	int n = 0; size_t sl = strlen(sub); char const* p = s;
	while ((p = strstr(p, sub)) != 0) { ++n; p += sl; }
	return n;
}

int main()
{
	printf("== test_media_extract (structural) ==\n");

	// --- (1) extraction -------------------------------------------------
	printf("[1] extractGuidingTextMedia — structural, model-derived\n");
	{
		// 1a: a realistic composite. Deliberately DEFAULT ordering stripped:
		// the test derives positions, so a messy interleaving is fine.
		Ref refs[] = {
			{ REF_IMG,     "CB Light Database.html\\CBL_Logo.jpg",       "CBL_Logo.jpg", 0 },
			{ REF_IMG,     "CB Light Database.html\\dup.jpg",            "dup.jpg",      0 },
			{ REF_IMG,     "CB Light Database.html\\team_photo.bmp",     "team_photo.bmp", 1 }, // lowercase <img SRC='...'>
			{ REF_IMG,     "CB Light Database.html\\dup.jpg",            "dup.jpg",      0 }, // duplicate -> dropped
			{ REF_IMGONLY, "CB Light Database.html\\should_be_ignored.png","should_be_ignored.png", 0 },
			{ REF_STREAM,  "CB Light Database.html\\CBM 126 Aronian - Grischuk.wmv", "CBM 126 Aronian - Grischuk.wmv", 0 },
		};
		checkBody("composite (dedup + ignore tag_image + backslash strip)", refs, 6);
	}
	{
		// 1ab: unquoted attribute must still parse (use a value with NO space,
		// since unquoted attrs terminate at whitespace — ChessBase always quotes).
		Ref refs[] = {
			{ REF_IMG, "logo.png", "logo.png", 2 } // <IMG src=logo.png> unquoted
		};
		checkBody("unquoted src attribute", refs, 1);
	}
	{
		// 1b: cross-pass de-dup — the same bare filename supplied by BOTH an
		// IMG and a stream. The picture pass runs first, so it must win.
		Ref refs[] = {
			{ REF_STREAM, "x.html\\shared.jpg", "shared.jpg", 0 },
			{ REF_IMG,    "x.html\\shared.jpg", "shared.jpg", 0 },
		};
		checkBody("cross-pass dedup (IMG pass wins)", refs, 2);
	}
	{
		// 1c: bare filenames with no "<DBName>.html\" prefix and mixed casing.
		Ref refs[] = {
			{ REF_IMG,     "logo.png",        "logo.png", 1 },   // no prefix, single-quote
			{ REF_STREAM,  "clip.avi",        "clip.avi", 2 },   // TAG_STREAM uppercase token
		};
		checkBody("bare names + uppercase tokens", refs, 2);
	}
	{
		// 1d: plain text, and only tag_image links -> nothing extracted.
		mstl::vector<mstl::string> f; mstl::vector<int> t;
		tcl_media::extractGuidingTextMedia(mstl::string("<P>just text</P>"), f, t);
		check(f.size() == 0, "plain text body -> 0 refs");
		mstl::vector<mstl::string> f2; mstl::vector<int> t2;
		tcl_media::extractGuidingTextMedia(mstl::string("CBLink(tag_image,a.html\\b.png,)"),
			f2, t2);
		check(f2.size() == 0, "body with only tag_image link -> 0 refs");
	}
	{
		// 1d2: empty body.
		mstl::vector<mstl::string> f; mstl::vector<int> t;
		tcl_media::extractGuidingTextMedia(mstl::string(""), f, t);
		check(f.size() == 0, "empty body -> 0 refs");
	}

	// --- (2) path resolution — structural invariants over a cross-product --
	printf("[2] resolveGuidingTextPath — structural, generated cases\n");
	{
		char const* dirs[]  = { "", "sub", "/home/me", "/a/b/c", "/x y/z dir" };
		char const* stems[] = { "foo", "CB Light Database.cbh", "Mega Database 2010.cbh",
							   "x.bmp.bak", "Already.html" };
		char const* files[] = { "CBL_Logo.jpg", "CBM 126.wmv", "a.bmp", "team_photo.bmp" };

		for (size_t d = 0; d < sizeof(dirs)/sizeof(dirs[0]); ++d)
		for (size_t s = 0; s < sizeof(stems)/sizeof(stems[0]); ++s)
		for (size_t fl = 0; fl < sizeof(files)/sizeof(files[0]); ++fl)
		{
			char db[4096];
			if (dirs[d][0]) snprintf(db, sizeof(db), "%s/%s", dirs[d], stems[s]);
			else snprintf(db, sizeof(db), "%s", stems[s]);

			mstl::string got = tcl_media::resolveGuidingTextPath(mstl::string(db), mstl::string(files[fl]));

			// Derive the expected html-dir independently from the parts.
			char dir[4096], stemBuf[4096], htmlDir[4096];
			char const* base;
			dirAndBase(db, dir, sizeof(dir), &base);
			stemNoExt(base, stemBuf, sizeof(stemBuf));
			if (dir[0]) snprintf(htmlDir, sizeof(htmlDir), "%s/%s.html", dir, stemBuf);
			else snprintf(htmlDir, sizeof(htmlDir), "%s.html", stemBuf);

			char msg[512];
			char full[4600];
			snprintf(full, sizeof(full), "%s/%s", htmlDir, files[fl]);
			// Main structural check: resolved == independently-derived path.
			snprintf(msg, sizeof(msg), "  %-28s + %-16s -> %s", db, files[fl], got.c_str());
			check(streq(got, full), msg);
			// Independent invariants (not derived from the mirror algorithm):
			// the resolved path is htmlDir-prefixed (db dir preserved, ext replaced)
			// and its own parent directory equals htmlDir (sibling, not nested).
			{
				char htmlDirSlash[4100];
				snprintf(htmlDirSlash, sizeof(htmlDirSlash), "%s/", htmlDir);
				snprintf(msg, sizeof(msg), "    .html dir is a sibling of the database (%s)", htmlDir);
				check(strncmp(got.c_str(), htmlDirSlash, strlen(htmlDirSlash)) == 0, msg);
			}
			// basename(resolved) == filename:
			char const* rb = got.c_str() + lastSlash(got.c_str()) + 1;
			snprintf(msg, sizeof(msg), "    basename preserved (%s)", rb);
			check(streq(mstl::string(rb), files[fl]), msg);
			// Exactly one ".html/" (no double prefixing).
			snprintf(msg, sizeof(msg), "    exactly one \".html/\" occurrence");
			check(countSubstr(got.c_str(), ".html/") == 1, msg);
			// Regression: no "html.html" when the database ends in ".html".
			snprintf(msg, sizeof(msg), "    no double extension");
			check(countSubstr(got.c_str(), ".html.html") == 0, msg);
		}
	}

	// --- (3) on-disk existence — structural ------------------------------
	printf("[3] resolved media path exists on disk\n");
	{
		char tmpl[] = "/tmp/scidb_media_testXXXXXX";
		char* td = mkdtemp(tmpl);
		check(td != nullptr, "mkdtemp created a temp dir");
		if (!td) return g_fail ? 1 : 0;

		// Choose db/filename via the same rule, build the file, check it.
		char dbDir[4096];
		snprintf(dbDir, sizeof(dbDir), "%s/My DB.cbh", td);
		mstl::string resolved = tcl_media::resolveGuidingTextPath(
			mstl::string(dbDir), mstl::string("logo.jpg"));

		// Structural: the resolved dir == "<tmp>/My DB.html".
		char wantDir[4096];
		snprintf(wantDir, sizeof(wantDir), "%s/My DB.html", td);
		{
			char wantSlash[4100];
			snprintf(wantSlash, sizeof(wantSlash), "%s/", wantDir);
			check(strncmp(resolved.c_str(), wantSlash, strlen(wantSlash)) == 0,
				  "resolved path is <tmp>/My DB.html/ prefix (sibling)");
		}

		// Build the tree (mkdir -p parent, write the file), then check FS.
		char mk[4600];
		snprintf(mk, sizeof(mk), "mkdir -p '%s'", wantDir);
		int rc = ::system(mk);
		check(rc == 0, "created <DBName>.html dir");
		char data[4600];
		snprintf(data, sizeof(data), "%s/logo.jpg", wantDir);
		FILE* fp = fopen(data, "wb");
		if (fp) { fputs("media", fp); fclose(fp); }
		check(fp != nullptr, "wrote file on disk");
		check(access(resolved.c_str(), F_OK) == 0, "resolved media path exists on disk");

		char cmd[4200];
		snprintf(cmd, sizeof(cmd), "rm -rf %s", td);
		(void)::system(cmd);
	}

	printf("\n%s\n", g_fail ? "RESULT: FAIL" : "RESULT: PASS");
	return g_fail ? 1 : 0;
}
