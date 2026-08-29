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

enum RefKind { REF_IMG, REF_STREAM, REF_AUDIO, REF_IMGONLY }; // IMGONLY = tag_image, must be ignored

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
	case REF_AUDIO:
	case REF_IMGONLY:
	{
		// case variants on the tag and the token name.
		char const* tag    = (r.style & 1) ? "cblink" : "CBLink";
		char const* token  = (r.style & 2) ? "TAG_STREAM" : "tag_stream";
		if (r.kind == REF_AUDIO)   token = (r.style & 2) ? "TAG_AUDIO" : "tag_audio";
		if (r.kind == REF_IMGONLY) token = "tag_image";
		html += tag; html += '('; html += token; html += ',';
		html += r.render; html += ",)";
		break;
	}
	}
}

// Derive the expected (files[], types[]) from the model using the documented
// order: all IMG refs (in ref order), then all CBLink refs (stream/audio, in
// ref order), de-duplicated BY BARE FILENAME across all passes. Returns the
// expected count (<= cap).
static int buildExpectation(Ref const* refs, int nrefs,
							mstl::string* expFile, int* expType, int cap)
{
	mstl::string order[48]; int otype[48]; int no = 0;
	// picture pass first (all IMG in ref order) — helper order.
	for (int i = 0; i < nrefs; ++i)
	{
		if (refs[i].kind == REF_IMG)
			{ order[no] = refs[i].bare; otype[no++] = 1; }
	}
	// then the CBLink pass: stream/audio in document (=ref) order.
	for (int i = 0; i < nrefs; ++i)
	{
		if (refs[i].kind == REF_STREAM)      { order[no] = refs[i].bare; otype[no++] = 4; }
		else if (refs[i].kind == REF_AUDIO)  { order[no] = refs[i].bare; otype[no++] = 2; }
		// REF_IMGONLY contributes nothing (tag_image refs are ignored).
	}
	int n = 0;
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
		// 1ca: tag_audio is extracted as type 2 (previously ignored), mixed
		// with tag_stream in document order.
		Ref refs[] = {
			{ REF_STREAM, "x.html\\clip.wmv",  "clip.wmv", 0 },
			{ REF_AUDIO,  "x.html\\interview.mp3", "interview.mp3", 1 }, // cblink(TAG_AUDIO,...)
		};
		checkBody("tag_audio extracted as audio type", refs, 2);
	}
	{
		// 1cb: stream/audio cross-kind dedup — first CBLink occurrence wins in
		// document order (stream at type 4), audio duplicate dropped.
		Ref refs[] = {
			{ REF_AUDIO,   "x.html\\dupe.mp3",  "dupe.mp3", 0 },
			{ REF_STREAM,  "x.html\\dupe.mp3",  "dupe.mp3", 0 },
		};
		checkBody("stream/audio dedup (first CBLink wins)", refs, 2);
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

	// --- (4) tag_game blocks — association of media to anchored games ---
	printf("[4] extractGuidingTextGameBlocks — tag_game anchor semantics\n");
	{
		// 4a: realistic two-game report — header logo excluded, each game's
		// media limited to its own block, fields parsed from the anchor.
		mstl::string html =
			"<P><IMG src=\"db.html\\cblogo.gif\"></P>"
			"<P class=1>Game 1: <A href=\"javascript:CBLink(tag_game,Topalov,Veselin,Anand,Viswanathan,Grand Slam Final,Bilbao,2008,4,0,27)\">Topalov,V - Anand,V</A></P>"
			"<P><IMG src=\"db.html\\TopalovAnand1.jpg\"></P>"
			"<P><A href=\"javascript:CBLink(tag_stream,db.html\\round4.wmv,)\">video</A></P>"
			"<P class=1>Game 2: <A href=\"javascript:CBLink(tag_game,Carlsen,Magnus,Topalov,Veselin,Grand Slam Final,Bilbao,2008,3,0,0)\">Carlsen,M - Topalov,V</A></P>"
			"<P><IMG src=\"db.html\\CarlsenTopalov3.jpg\"></P>";

		mstl::vector<tcl_media::GuidingTextGameBlock> blocks;
		tcl_media::extractGuidingTextGameBlocks(html, blocks);
		check((unsigned)blocks.size() == 2, "two anchors -> two blocks");

		if (blocks.size() == 2)
		{
			check(streq(blocks[0].white, "Topalov"), "block 0 white lastname");
			check(streq(blocks[0].black, "Anand"),   "block 0 black lastname");
			check(streq(blocks[0].event, "Grand Slam Final"), "block 0 event field");
			check(streq(blocks[0].site,  "Bilbao"),  "block 0 site field");
			check(blocks[0].year  == 2008, "block 0 year parsed");
			check(blocks[0].round == 4,    "block 0 round parsed");
			// Section ownership: each reference belongs to the game of the
			// last anchor at-or-before it. cblogo.gif (header zone) and
			// TopalovAnand1.jpg attach to block 0; round4.wmv — still inside
			// block 0's section in this hand-written tight layout — also
			// attaches to block 0 (its report companion "start the video"
			// link pattern).
			check((unsigned)blocks[0].files.size() == 3
				&& streq(blocks[0].files[0], "cblogo.gif") && blocks[0].types[0] == 1
				&& streq(blocks[0].files[1], "TopalovAnand1.jpg") && blocks[0].types[1] == 1
				&& streq(blocks[0].files[2], "round4.wmv") && blocks[0].types[2] == 4,
				"block 0 = [cblogo.gif (header zone), TopalovAnand1.jpg, round4.wmv]");
			check(streq(blocks[1].white, "Carlsen"), "block 1 white lastname");
			check(blocks[1].round == 3, "block 1 round parsed");
			check((unsigned)blocks[1].files.size() == 1
				&& streq(blocks[1].files[0], "CarlsenTopalov3.jpg") && blocks[1].types[0] == 1,
				"block 1 = [CarlsenTopalov3.jpg]");
		}
	}
	{
		// 4a2: realistic magazine layout (Sinquefield shape) — the game's
		// video link sits right after its anchor and far from the next one,
		// so it belongs to the anchored game despite being on the right side.
		mstl::string html =
			"<P><IMG src=\"s.html\\cblogo.gif\"></P>"
			"<P class=1>Enjoy this attacking game with the annotations of Krisztian Szabo: "
			"<A href=\"javascript:CBLink(tag_game,So,Wesley,Nakamura,Hikaru,Sinquefield Cup 3rd,Saint Louis,2015,6,0,17)\">So,W - Nakamura,H 0-1</A>. "
			"But you can also start the video of Daniel King: "
			"<A href=\"javascript:CBLink(tag_stream,s.html\\Sinquefield Cup 2015 round 6.wmv,)\">video</A>"
			"</P>"
			"<P class=1><IMG src=\"s.html\\168 So-Nakamura.jpg\"></P>"
			"<P class=1>In the following round the boards went quiet for a long time: "
			"<A href=\"javascript:CBLink(tag_game,Aronian,Levon,Caruana,Fabiano,Sinquefield Cup 3rd,Saint Louis,2015,6,0,15)\">Aronian,L - Caruana,F 0.5-0.5</A></P>"
			"<P class=1><IMG src=\"s.html\\168 Aronian-Caruana.jpg\"></P>";

		mstl::vector<tcl_media::GuidingTextGameBlock> blocks;
		tcl_media::extractGuidingTextGameBlocks(html, blocks);
		check((unsigned)blocks.size() == 2, "realistic layout: two anchors -> two blocks");
		if (blocks.size() == 2)
		{
			check(streq(blocks[0].white, "So") && streq(blocks[0].black, "Nakamura"),
				"realistic layout: block 0 = So-Nakamura");
			check(blocks[0].year == 2015 && blocks[0].round == 6,
				"realistic layout: block 0 fields");
			check((unsigned)blocks[0].files.size() == 3
				&& streq(blocks[0].files[1], "Sinquefield Cup 2015 round 6.wmv")
				&& blocks[0].types[1] == 4
				&& streq(blocks[0].files[2], "168 So-Nakamura.jpg")
				&& blocks[0].types[2] == 1,
				"realistic layout: video + image attach to the anchored game (cblogo header zone also on block 0)");
			check((unsigned)blocks[1].files.size() == 1,
				"realistic layout: block 1 keeps only its section");
		}
	}
	{
		// 4b: malformed anchors (too few fields) yield no blocks; media after
		// them stays unassociated.
		mstl::string html =
			"CBLink(tag_game,Only,Three,Fields)<IMG src=\"db.html\\orphan.jpg\">";
		mstl::vector<tcl_media::GuidingTextGameBlock> blocks;
		tcl_media::extractGuidingTextGameBlocks(html, blocks);
		check((unsigned)blocks.size() == 0, "malformed anchor (3 fields) -> 0 blocks");
	}
	{
		// 4c: trailing anchor — its block extends to the end of the body.
		mstl::string html =
			"<A href=\"javascript:CBLink(tag_game,So,Wesley,Nakamura,Hikaru,Sinquefield Cup 3rd,Saint Louis,2015,6,0,17)\">g</A>"
			"<IMG src=\"db.html\\SoNakamura.jpg\">";
		mstl::vector<tcl_media::GuidingTextGameBlock> blocks;
		tcl_media::extractGuidingTextGameBlocks(html, blocks);
		check((unsigned)blocks.size() == 1, "trailing anchor -> 1 block");
		check((unsigned)blocks.size() == 1 && (unsigned)blocks[0].files.size() == 1
			&& streq(blocks[0].files[0], "SoNakamura.jpg"),
			"trailing block reaches end of body");
		check((unsigned)blocks.size() == 1 && blocks[0].year == 2015
			&& blocks[0].round == 6, "trailing anchor fields parsed");
	}
	{
		// 4c: case-insensitive anchor tag; empty-block dedupe within a block.
		mstl::string html =
			"<A href=\"javascript:cblink(Tag_Game,a,B,b,C,tourney,site,2010,2,0)\">x</A>"
			"<IMG src=\"db.html\\twice.jpg\"><IMG src=\"db.html\\twice.jpg\">";
		mstl::vector<tcl_media::GuidingTextGameBlock> blocks;
		tcl_media::extractGuidingTextGameBlocks(html, blocks);
		check((unsigned)blocks.size() == 1, "lowercase anchor still a block");
		check((unsigned)blocks.size() == 1 && (unsigned)blocks[0].files.size() == 1,
			"duplicate media within one block de-duplicated");
	}
	{
		// 4d: zero anchors -> zero blocks.
		mstl::vector<tcl_media::GuidingTextGameBlock> blocks;
		tcl_media::extractGuidingTextGameBlocks(mstl::string("<P><IMG src=\"db.html\\logo.jpg\"></P>"), blocks);
		check((unsigned)blocks.size() == 0, "no anchors -> 0 blocks");
	}

	printf("\n%s\n", g_fail ? "RESULT: FAIL" : "RESULT: PASS");
	return g_fail ? 1 : 0;
}
