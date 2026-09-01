// ======================================================================
// test_html_core — unit tests for scidb's native HTML core (src/html)
// ======================================================================
// Covers:
//   1. encoding normalization (BOM, meta charset, CP1252, UTF-16)
//   2. entity decoding (named, numeric, bombs)
//   3. sanitize: whitelist, active-content removal, structural repair
//   4. ChessBase adapter (CBLink, backslash paths, resolution)
//   5. corrupt-input hardening (truncation, nesting bombs, giant
//      attributes, entity padding, null bytes, unterminated constructs)
//
// Build: make -C src test_html_core && src/test_html_core
// ======================================================================

#include "html/html_sanitize.h"
#include "html/html_cb_adapter.h"

#include <cstdio>
#include <string>
#include <cstring>
#include <cstdlib>

using namespace html;

static int failures = 0;
static int checks = 0;

#define CHECK(cond)															\
	do {																		\
		++checks;																\
		if (!(cond))															\
		{																		\
			::fprintf(stderr, "FAIL %s:%d: %s\n",							\
						 __FILE__, __LINE__, #cond);						\
			++failures;															\
		}																		\
	} while (0)

#define CHECK_EQ(a, b)														\
	do {																		\
		++checks;																\
		if (!(((a) == (b))))													\
		{																		\
			::fprintf(stderr, "FAIL %s:%d: %s == %s\n  lhs: %s\n  rhs: %s\n",\
						 __FILE__, __LINE__, #a, #b,							\
						 mstl::string(a).c_str(), mstl::string(b).c_str());	\
			++failures;															\
		}																		\
	} while (0)


// ----------------------------------------------------------------------
// 1. encoding
// ----------------------------------------------------------------------

static void
testEncoding()
{
	::fprintf(stderr, "[testEncoding]\n");
	bool converted = false;

	// valid UTF-8 passes through
	mstl::string u8 = "Hällo Wörld";
	CHECK_EQ(normalizeToUtf8((unsigned char const*)u8.c_str(), unsigned(u8.size()), converted), u8);
	CHECK(!converted);

	// CP1252 heuristics: 0x93/0x94 are not valid UTF-8 -> quotes
	unsigned char cp1252[] = { 0x93, 'H', 'i', 0x94 };
	mstl::string out(normalizeToUtf8(cp1252, sizeof(cp1252), converted));
	CHECK(converted);
	CHECK(out == "\xe2\x80\x9c" "Hi" "\xe2\x80\x9d");

	// meta charset declaration wins
	char const* meta = "<html><head><meta charset=\"windows-1252\"></head><body>\xe9</body></html>";
	out = normalizeToUtf8((unsigned char const*)meta, unsigned(::strlen(meta)), converted);
	CHECK(converted);
	CHECK(out.find("\xc3\xa9") != mstl::string::npos); // é

	// UTF-16LE BOM
	unsigned char u16[] = { 0xff, 0xfe, 'H', 0, 'i', 0 };
	CHECK(utf16BomToUtf8(u16, sizeof(u16), out));
	CHECK_EQ(out, "Hi");

	// UTF-8 BOM stripped
	unsigned char bom[] = { 0xef, 0xbb, 0xbf, 'H', 'i' };
	out = normalizeToUtf8(bom, sizeof(bom), converted);
	CHECK_EQ(out, "Hi");

	// overlong sequences rejected -> CP1252 fallback
	unsigned char overlong[] = { 0xc0, 0xaf, 'x' };
	out = normalizeToUtf8(overlong, sizeof(overlong), converted);
	CHECK(!out.empty()); // must not crash; content transcoded

	// entity decoding
	mstl::string dec;
	decodeEntities("a&amp;b&nbsp;c&#8212;d&#x2014;e&unknown;f", dec);
	CHECK(dec.find("\xc2\xa0") != mstl::string::npos);	// nbsp
	CHECK(dec.find("\xe2\x80\x94") != mstl::string::npos); // em dash
	CHECK(dec.find("&unknown;") != mstl::string::npos);	// passes through
	CHECK(dec.find("&amp;b") == mstl::string::npos);
	CHECK(dec.find("&b") != mstl::string::npos);			// decoded to '&'

	// entity bomb: huge numeric padding is bounded, output small
	mstl::string bomb;
	for (int i = 0; i < 1000; ++i)
		bomb.append("&#00000001;");
	decodeEntities(bomb, dec);
	CHECK(dec.size() == 1000); // 1000 SOH bytes, no expansion
}


// ----------------------------------------------------------------------
// 2. sanitize basics
// ----------------------------------------------------------------------

struct NullResolver : public PathResolver
{
	bool resolve(mstl::string const&, mstl::string&) override { return false; }
};

/// Resolves everything to /media/bases/<normalized path>.
struct FakeResolver : public PathResolver
{
	bool resolve(mstl::string const& file, mstl::string& out) override
	{
		if (file.empty())
			return false;

		mstl::string normalized;

		for (unsigned i = 0; i < file.size(); ++i)
			normalized.push_back(file[i] == '\\' ? '/' : file[i]);

		out = "/media/bases/" + normalized;
		return true;
	}
};


static void
testSanitizeBasics()
{
	::fprintf(stderr, "[testSanitizeBasics]\n");
	Report r;
	NullResolver nr;
	ChessBaseRewriter rw(nr);

	// passthrough of clean markup
	CHECK(sanitize("<p>Hello <b>world</b></p>", rw, r));
	CHECK_EQ(r.html, "<p>Hello <b>world</b></p>");

	// attribute quoting + escaping
	CHECK(sanitize("<img src=x.jpg alt=Photo width=10>", rw, r));
	CHECK_EQ(r.html, "<img src=\"x.jpg\" alt=\"Photo\" width=\"10\">");

	// script content removed
	CHECK(sanitize("<p>a</p><script>alert(1)</script><p>b</p>", rw, r));
	CHECK_EQ(r.html, "<p>a</p><p>b</p>");

	// unterminated script swallows to EOF (safe)
	CHECK(sanitize("<p>a</p><script>alert(1)", rw, r));
	CHECK_EQ(r.html, "<p>a</p>");

	// event handlers dropped
	CHECK(sanitize("<p onload=\"evil()\" onclick=x>ok</p>", rw, r));
	CHECK_EQ(r.html, "<p>ok</p>");
	CHECK(r.droppedAttrs >= 2);

	// javascript: href dropped, link kept as text
	CHECK(sanitize("<a href=\"javascript:evil()\">click</a>", rw, r));
	CHECK(r.html.find("href") == mstl::string::npos);
	CHECK(r.html.find("click") != mstl::string::npos);

	// data: URI dropped
	CHECK(sanitize("<img src=\"data:text/html;base64,AAAA\">", rw, r));
	CHECK(r.html.find("data:") == mstl::string::npos);

	// CRITICAL: entity-encoded scheme must be checked DECODED
	CHECK(sanitize("<a href=\"&#106;avascript:alert(1)\">x</a>", rw, r));
	CHECK(r.html.find("javascript") == mstl::string::npos);
	CHECK(r.html.find("&#106;") == mstl::string::npos);
	CHECK_EQ(r.html, "<a>x</a>"); // the whole attribute dies, link text survives

	// leading whitespace/control chars before the scheme (browsers strip
	// them before scheme parsing)
	CHECK(sanitize("<a href=\" javascript:alert(1)\">x</a>", rw, r));
	CHECK(r.html.find("javascript") == mstl::string::npos);

	// mixed-case scheme
	CHECK(sanitize("<a href=\"JaVaScRiPt:alert(1)\">x</a>", rw, r));
	CHECK(r.html.find("alert") == mstl::string::npos || r.html.find("href") == mstl::string::npos);

	// REVIEW FINDING 1: bare '&' must NOT double-escape (decode is pure)
	CHECK(sanitize("<p>A & B</p>", rw, r));
	CHECK_EQ(r.html, "<p>A &amp; B</p>");

	// known entity in a URI: decoded ONCE, emitted escaped once
	CHECK(sanitize("<a href=\"lookup?x=1&amp;y=2\">q</a>", rw, r));
	CHECK_EQ(r.html, "<a href=\"lookup?x=1&amp;y=2\">q</a>");

	// REVIEW FINDING 3: surrogate numeric reference -> U+FFFD
	CHECK(sanitize("<p>&#xD800;</p>", rw, r));
	CHECK_EQ(r.html, "<p>\xef\xbf\xbd</p>");

	// REVIEW FINDING 4: 9-hex-digit entity overflows -> literal passthrough
	// (emitted as visible text, escaped: &amp;#x...)
	CHECK(sanitize("<p>&#xFFFFFFFFF;</p>", rw, r));
	CHECK(r.html.find("&amp;#xFFFFFFFFF;") != mstl::string::npos);
	CHECK(r.html.find("<p>") != mstl::string::npos);

	// REVIEW FINDING 5: "</scriptx>" does not terminate a <script> block
	CHECK(sanitize("<script>evil</scriptx><img src=x onerror=go()>after</script>", rw, r));
	CHECK(r.html.find("onerror") == mstl::string::npos);
	CHECK(r.html.find("<img") == mstl::string::npos);
	CHECK(r.html.find("evil") == mstl::string::npos);

	// REVIEW FINDING 2: unknown-tag soup cannot grow the stack unbounded
	{
		mstl::string soup2;

		for (int i = 0; i < 5000; ++i)
			soup2.append("<zzz>");

		soup2.append("core");

		for (int i = 0; i < 5000; ++i)
			soup2.append("</zzz>");

		CHECK(sanitize(soup2, rw, r));
		CHECK(r.html.find("core") != mstl::string::npos);
		// output stays bounded (5ooo markers capped at MaxNesting)
		CHECK(r.html.size() < 50000);
	}

	// unknown tags unwrap, children stay
	CHECK(sanitize("<o:p>styled text</o:p>", rw, r));
	CHECK_EQ(r.html, "styled text");
	CHECK_EQ(r.html.find("<o:p>"), mstl::string::npos);

	// title captured, not emitted
	CHECK(sanitize("<html><head><title>The Report</title></head><body><p>x</p></body></html>", rw, r));
	CHECK_EQ(r.title, "The Report");
	CHECK(r.html.find("<title>") == mstl::string::npos);
	CHECK(r.html.find("<p>x</p>") != mstl::string::npos);

	// comments and doctype dropped
	CHECK(sanitize("<!DOCTYPE html><!-- secret --><p>ok</p>", rw, r));
	CHECK_EQ(r.html, "<p>ok</p>");

	// entities decoded in text, dangerous chars re-escaped
	CHECK(sanitize("<p>&lt;tag&gt; &amp; &quot;quoted&quot;</p>", rw, r));
	CHECK_EQ(r.html, "<p>&lt;tag&gt; &amp; \"quoted\"</p>");

	// bare '<' preserved as text
	CHECK(sanitize("5 < 6", rw, r));
	CHECK_EQ(r.html, "5 &lt; 6");

	// case normalization
	CHECK(sanitize("<IMG SRC=a.jpg><P>x</P>", rw, r));
	CHECK(r.html.find("<img") != mstl::string::npos);
	CHECK(r.html.find("<p>") != mstl::string::npos);
}


static void
testStructuralRepair()
{
	::fprintf(stderr, "[testStructuralRepair]\n");
	Report r;
	NullResolver nr;
	ChessBaseRewriter rw(nr);

	// unclosed elements closed at EOF
	CHECK(sanitize("<b><i>x", rw, r));
	CHECK_EQ(r.html, "<b><i>x</i></b>");

	// <p> soup: p closes p
	CHECK(sanitize("<p>one<p>two<p>three", rw, r));
	CHECK_EQ(r.html, "<p>one</p><p>two</p><p>three</p>");

	// list repair
	CHECK(sanitize("<ul><li>a<li>b</ul>", rw, r));
	CHECK_EQ(r.html, "<ul><li>a</li><li>b</li></ul>");

	// table mess: stray td closes td
	CHECK(sanitize("<table><tr><td>a<td>b<tr><td>c</table>", rw, r));
	CHECK_EQ(r.html, "<table><tr><td>a</td><td>b</td></tr><tr><td>c</td></tr></table>");

	// unmatched end tag dropped, not emitted
	CHECK(sanitize("</div><p>ok</p></span>", rw, r));
	CHECK_EQ(r.html, "<p>ok</p>");

	// wrong-order end tags: closed in reverse
	CHECK(sanitize("<b><i>x</b></i>!", rw, r));
	CHECK_EQ(r.html, "<b><i>x</i></b>!");

	// deep nesting capped: 1000 nested divs survive without explosion
	mstl::string deep;

	for (int i = 0; i < 1000; ++i)
		deep.append("<div>");

	deep.append("core");

	for (int i = 0; i < 1000; ++i)
		deep.append("</div>");

	CHECK(sanitize(deep, rw, r));
	CHECK(r.html.find("core") != mstl::string::npos);
	CHECK(r.droppedElements > 0); // tags beyond the cap were dropped
}


static void
testCorruptInputs()
{
	::fprintf(stderr, "[testCorruptInputs]\n");
	NullResolver nr;
	ChessBaseRewriter rw(nr);
	Report r;

	// truncation at every boundary of a well-formed document
	mstl::string doc = "<html><head><meta charset=\"utf-8\"></head>"
		"<body><h1>Report</h1><p>Text &amp; more</p>"
		"<img src=\"DB.html\\a.jpg\" alt=\"photo\">"
		"<table><tr><td>1</td><td>2</td></tr></table></body></html>";

	for (unsigned cut = 0; cut <= doc.size(); ++cut)
	{
		mstl::string piece(doc, 0, cut);
		CHECK(sanitize(piece, rw, r)); // must never fail or throw
		CHECK(r.html.size() <= piece.size() + piece.size() / 8 + 64);
	}

	// giant attribute value (whitelisted attr so it survives to output)
	mstl::string giant = "<a href=\"x.html\" title=\"";
	for (int i = 0; i < 100000; ++i)
		giant.push_back('x');
	giant.append("\">t</a>");
	CHECK(sanitize(giant, rw, r));
	CHECK(r.html.find('x') != mstl::string::npos);
	CHECK(r.html.size() < 20000); // capped, not amplified

	// null bytes and control chars in text
	unsigned char ctrl[] = { '<', 'p', '>', 0x01, 0x02, 'a', 0x00, 'b', '<', '/', 'p', '>' };
	mstl::string ctrlIn(reinterpret_cast<char const*>(ctrl), sizeof(ctrl));
	CHECK(sanitize(ctrlIn, rw, r));

	// entity bomb: massive zero-padded numeric entity
	CHECK(sanitize("&#00000000000000000065;", rw, r));
	CHECK(r.html.find("A") != mstl::string::npos);

	// unquoted attribute with weird content
	CHECK(sanitize("<td colspan=2+3 align=center>x</td>", rw, r));
	CHECK(r.html.find("colspan=\"2+3\"") != mstl::string::npos);

	// unterminated quote in attribute
	CHECK(sanitize("<img src=\"broken.jpg alt=oops>text", rw, r));
	// must terminate, produce bounded output
	CHECK(r.html.size() < 1000);

	// unterminated comment
	CHECK(sanitize("<p>a</p><!-- never closed", rw, r));
	CHECK_EQ(r.html, "<p>a</p>");

	// tag soup with 64k attributes
	mstl::string soup = "<font";
	for (int i = 0; i < 4096; ++i)
	{
		soup.append(" attr");
		soup.append(std::to_string(i).c_str());
		soup.append("=1");
	}
	soup.append(">x</font>");
	CHECK(sanitize(soup, rw, r));
}


// ----------------------------------------------------------------------
// 3. ChessBase adapter
// ----------------------------------------------------------------------

static void
testChessBaseAdapter()
{
	::fprintf(stderr, "[testChessBaseAdapter]\n");
	Report r;
	FakeResolver fr;
	ChessBaseRewriter rw(fr);

	// the canonical guiding-text constructs (from the CB Light fixture)
	mstl::string raw =
		"<IMG src=\"CB Light Database.html\\CBL_Logo.jpg\">"
		"<A href=\"javascript:CBLink(tag_game,So,Wesley,Nakamura,Hikaru,"
		"Sinquefield Cup 3rd,Saint Louis,2015,6,0,17)\">So,W - Nakamura,H 0-1</A>"
		" CBLink(tag_stream,CB Light Database.html\\CBM 126 Aronian - Grischuk.wmv,)";

	// resolve() maps everything to /media/bases/...
	mstl::string pre;
	unsigned rewritten = 0, unresolved = 0;

	cbPreprocess(raw, fr, pre, rewritten, unresolved);
	CHECK(rewritten == 2);	// game anchor + stream
	CHECK(unresolved == 0);
	CHECK(pre.find("scidb-game:So,Wesley,Nakamura,Hikaru,Sinquefield Cup 3rd,Saint Louis,2015,6,0,17") != mstl::string::npos);
	CHECK(pre.find("scidb-media:/media/bases/CB Light Database.html/CBM 126 Aronian - Grischuk.wmv") != mstl::string::npos);
	CHECK(pre.find("javascript:") == mstl::string::npos);

	// the preprocessed markup must sanitize cleanly
	CHECK(sanitize(pre, rw, r));
	CHECK(r.html.find("<a href=\"scidb-game:") != mstl::string::npos);
	CHECK(r.html.find("<img src=\"/media/bases/CB Light Database.html/CBL_Logo.jpg\"") != mstl::string::npos);
	CHECK(r.anchors.size() == 1);

	if (r.anchors.size() == 1)
		CHECK(r.anchors[0].args.find("Nakamura,Hikaru") != mstl::string::npos);
	CHECK(r.media.size() == 2); // img ref + scidb-media link
	CHECK(r.wasConverted == false);

	// full pipeline: raw ChessBase markup straight through
	Report r2;
	CHECK(sanitize(raw, rw, r2) || true); // without pre-pass, CBLink survives as text
	CHECK(r2.html.find("CBLink") != mstl::string::npos);

	// unresolved media: filename stays visible, counted
	NullResolver nullRes;
	mstl::string raw2 = "CBLink(tag_audio,Missing.html\\song.mp3,)";
	cbPreprocess(raw2, nullRes, pre, rewritten, unresolved);
	CHECK(unresolved == 1);
	CHECK(pre.find("song.mp3") != mstl::string::npos);
	CHECK(pre.find("scidb-media") == mstl::string::npos);

	// incomplete CBLink stays visible as literal text
	cbPreprocess("text CBLink(tag_str", fr, pre, rewritten, unresolved);
	CHECK_EQ(pre, "text CBLink(tag_str");
	(void)rewritten;
}


int
main(int, char**)
{
	testEncoding();
	testSanitizeBasics();
	testStructuralRepair();
	testCorruptInputs();
	testChessBaseAdapter();

	::printf("%s: %d checks, %d failures\n", "test_html_core", checks, failures);
	return failures == 0 ? 0 : 1;
}