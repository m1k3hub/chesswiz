// ======================================================================
// html_sanitize — scidb's native HTML intake pipeline
// ======================================================================
// Part of scidb's native HTML support (src/html). Consumes ANY HTML-ish
// input (ChessBase guiding texts, PGN comment markup, arbitrary web
// pages) and emits the *scidb HTML profile*: a well-formed, safe,
// UTF-8 fragment that the renderer (Tkhtml) and the exporter both
// accept. Nothing downstream ever sees the input's quirks.
//
// The profile (see SCIDB_HTML_PROFILE.md):
//   - fragment (no html/head/body wrapper; title extracted, not emitted)
//   - whitelisted tags only; unknown tags are unwrapped (children kept)
//   - active content (script/style/iframe/object/embed/applet/form/
//     frame/meta/link/base + on*= handlers + script: URIs) removed
//   - all attributes quoted, all text escaped, entities decoded
//   - structural repair: void-element and auto-closing rules, nesting
//     cap, unclosed-tag recovery
//   - URIs checked against a scheme allowlist; rewriting is delegated
//     to a Rewriter (e.g. media-path resolution, scidb-game: anchors)
//
// Guarantees: never throws (try/catch boundary), never runs unboundedly
// (all loops bounded by input size, nesting capped), output is always
// parseable HTML. On any internal failure the result degrades to
// plain escaped text of the input.
// ======================================================================

#ifndef _html_sanitize_included
#define _html_sanitize_included

#include "m_string.h"
#include "m_vector.h"

#include "html_encoding.h"

#include <cstdint>
#include <cstring>
#include <strings.h>
#include <cstdio>

namespace html {

// ----------------------------------------------------------------------
// Policy
// ----------------------------------------------------------------------

/// What happens to a start tag.
enum TagAction
{
	Keep,			///< emit (with whitelisted attributes)
	Unwrap,			///< drop the tag, keep the children (unknown/junk tags)
	DropContent,	///< drop the tag AND its content (script, style, ...)
	Drop,			///< drop the tag; children are processed normally
	CaptureTitle,	///< like Drop, but text content lands in Report::title
};

/// URI reference status (classification completeness is mandatory:
/// every reference is resolved, rewritten, or flagged — never silent).
enum RefStatus
{
	Ref_Kept,			///< safe scheme / relative URI, passed through
	Ref_Rewritten,		///< rewriter produced a replacement URI
	Ref_Dropped,		///< dangerous scheme (script:, data:, ...) removed
	Ref_Unresolved,		///< rewriter could not locate the target
	Ref_External,		///< absolute http(s)/ftp URI (external resource)
	Ref_ScidbGame,		///< scidb-game: internal anchor
	Ref_ScidbMedia,		///< scidb-media: internal media link
};


struct TagPolicy
{
	char const*	name;		///< lowercase
	TagAction	action;
	/// whitelisted attributes (0-terminated); 0 = global list only
	char const* const*	attrs;
};


/// URI schemes scidb accepts in href/src. Anything else is dropped.
inline bool
schemeAllowed(mstl::string const& scheme)
{
	return	   scheme == "http"		|| scheme == "https"
			|| scheme == "mailto"	|| scheme == "ftp"
			|| scheme == "file"		|| scheme == "scidb-game"
			|| scheme == "scidb-media"	|| scheme == "scidb-ai";
}


/// The rewriter hook. `tag` is "a" (href) or "img" (src); `uri` the raw
/// attribute value. Implementations resolve relative media paths, map
/// scidb-internal URIs into the result records, and can replace the URI
/// entirely (write into `out`, empty = drop the attribute). The base
/// implementation only enforces the scheme allowlist.
class Rewriter
{
public:

	virtual ~Rewriter() throw() {}

	virtual void rewrite(	char const* tag,
									mstl::string const& uri,
									RefStatus& status,
									mstl::string& result)
	{
		mstl::string scheme(schemeOf(uri));

		if (!scheme.empty() && !schemeAllowed(scheme))
			status = Ref_Dropped;
		else if (scheme == "http" || scheme == "https" || scheme == "ftp")
			status = Ref_External;
		else
			status = Ref_Kept;

		if (status != Ref_Dropped)
			result = uri;
	}

protected:

	/// Extract the scheme prefix ("http" of "http://x"); "" if relative.
	static mstl::string schemeOf(mstl::string const& uri)
	{
		mstl::string::size_type colon = uri.find(':');

		if (colon == mstl::string::npos || colon == 0 || colon > 32)
			return mstl::string();

		for (mstl::string::size_type i = 0; i < colon; ++i)
		{
			char c = uri[i];
			if (!(   (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
					|| (i > 0 && (c >= '0' && c <= '9'))
					|| c == '+' || c == '-' || c == '.'))
				return mstl::string(); // not a scheme — treat as relative
		}

		mstl::string s(uri, colon);
		for (mstl::string::size_type i = 0; i < s.size(); ++i)
		{
			char c = s[i];
			if (c >= 'A' && c <= 'Z')
				s[i] = char(c + 32);
		}
		return s;
	}
};

// ----------------------------------------------------------------------
// Tag tables
// ----------------------------------------------------------------------

namespace {

char const* const Attrs_None[]			= { 0 };
char const* const Attrs_A[]				= { "href", "name", "title", 0 };
char const* const Attrs_Img[]			= { "src", "alt", "width", "height", "border", "align", 0 };
char const* const Attrs_Font[]			= { "color", "size", "face", 0 };
char const* const Attrs_Align[]			= { "align", 0 };
char const* const Attrs_Table[]			= { "border", "cellspacing", "cellpadding", "width", "bgcolor", "align", 0 };
char const* const Attrs_Row[]			= { "bgcolor", "valign", "align", 0 };
char const* const Attrs_Cell[]			= { "colspan", "rowspan", "valign", "align", "width", "height", "bgcolor", 0 };
char const* const Attrs_Hr[]				= { "size", "width", "noshade", "align", 0 };
char const* const Attrs_List[]			= { "start", "type", 0 };
char const* const Attrs_Li[]				= { "type", "value", 0 };

#define T(name, action, attrs) { name, action, attrs }

TagPolicy const Policies[] =
{
	// unwrapped structure: children kept, tags removed
	T("html",	Unwrap,		Attrs_None),
	T("head",	Unwrap,		Attrs_None),
	T("body",	Unwrap,		Attrs_None),
	T("title",	CaptureTitle,	Attrs_None),

	// active content: removed entirely
	T("script",	DropContent,	Attrs_None),
	T("style",	DropContent,	Attrs_None),
	T("iframe",	DropContent,	Attrs_None),
	T("object",	DropContent,	Attrs_None),
	T("embed",	DropContent,	Attrs_None),
	T("applet",	DropContent,	Attrs_None),
	T("frameset",	DropContent,	Attrs_None),
	T("frame",	DropContent,	Attrs_None),
	T("noscript",	DropContent,	Attrs_None),
	T("form",	DropContent,	Attrs_None),
	T("select",	DropContent,	Attrs_None),
	T("button",	DropContent,	Attrs_None),
	T("svg",	DropContent,	Attrs_None),
	T("math",	DropContent,	Attrs_None),
	T("template",	DropContent,	Attrs_None),

	// dropped head-noise (children processed, content normally empty)
	T("meta",	Drop,			Attrs_None),
	T("link",	Drop,			Attrs_None),
	T("base",	Drop,			Attrs_None),
	T("input",	Drop,			Attrs_None),
	T("frame",	Drop,			Attrs_None),
	T("col",	Drop,			Attrs_None),
	T("colgroup",	Drop,		Attrs_None),

	// blocks
	T("p",		Keep,			Attrs_Align),
	T("div",	Keep,			Attrs_Align),
	T("br",		Keep,			Attrs_None),
	T("hr",		Keep,			Attrs_Hr),
	T("h1",		Keep,			Attrs_Align),
	T("h2",		Keep,			Attrs_Align),
	T("h3",		Keep,			Attrs_Align),
	T("h4",		Keep,			Attrs_Align),
	T("h5",		Keep,			Attrs_Align),
	T("h6",		Keep,			Attrs_Align),
	T("blockquote",	Keep,		Attrs_None),
	T("pre",	Keep,			Attrs_None),
	T("center",	Keep,			Attrs_None),
	T("address",	Keep,		Attrs_None),

	// inline
	T("b",		Keep,			Attrs_None),
	T("i",		Keep,			Attrs_None),
	T("u",		Keep,			Attrs_None),
	T("s",		Keep,			Attrs_None),
	T("em",		Keep,			Attrs_None),
	T("strong",	Keep,			Attrs_None),
	T("span",	Keep,			Attrs_None),
	T("font",	Keep,			Attrs_Font),
	T("sub",	Keep,			Attrs_None),
	T("sup",	Keep,			Attrs_None),
	T("small",	Keep,			Attrs_None),
	T("big",	Keep,			Attrs_None),
	T("tt",		Keep,			Attrs_None),
	T("code",	Keep,			Attrs_None),
	T("cite",	Keep,			Attrs_None),
	T("q",		Keep,			Attrs_None),
	T("kbd",	Keep,			Attrs_None),
	T("samp",	Keep,			Attrs_None),
	T("var",	Keep,			Attrs_None),
	T("dfn",	Keep,			Attrs_None),
	T("abbr",	Keep,			Attrs_None),
	T("acronym",	Keep,		Attrs_None),
	T("del",	Keep,			Attrs_None),
	T("ins",	Keep,			Attrs_None),
	T("mark",	Keep,			Attrs_None),

	// lists
	T("ul",		Keep,			Attrs_List),
	T("ol",		Keep,			Attrs_List),
	T("li",		Keep,			Attrs_Li),
	T("dl",		Keep,			Attrs_None),
	T("dt",		Keep,			Attrs_None),
	T("dd",		Keep,			Attrs_None),
	T("dir",	Keep,			Attrs_None),
	T("menu",	Keep,			Attrs_None),

	// tables
	T("table",	Keep,			Attrs_Table),
	T("thead",	Keep,			Attrs_None),
	T("tbody",	Keep,			Attrs_None),
	T("tfoot",	Keep,			Attrs_None),
	T("tr",		Keep,			Attrs_Row),
	T("td",		Keep,			Attrs_Cell),
	T("th",		Keep,			Attrs_Cell),
	T("caption",	Keep,		Attrs_Align),

	// links & media
	T("a",		Keep,			Attrs_A),
	T("img",	Keep,			Attrs_Img),

	// misc
	T("abbr",	Keep,			Attrs_None),
	T("textarea",	DropContent,	Attrs_None),
};

TagPolicy const* const PoliciesEnd = Policies + sizeof(Policies) / sizeof(Policies[0]);

#undef T

inline TagPolicy const*
findPolicy(char const* name)
{
	for (TagPolicy const* p = Policies; p < PoliciesEnd; ++p)
		if (::strcmp(p->name, name) == 0)
			return p;
	return 0;
}

inline bool
isVoidElement(char const* name)
{
	static char const* const Void[] = { "br", "hr", "img", "area", "wbr", 0 };

	for (char const* const* v = Void; *v; ++v)
		if (::strcmp(*v, name) == 0)
			return true;
	return false;
}

/// Elements implicitly closed by the start of `name` (HTML5 adoption
/// agency, heavily simplified to the cases that occur in the wild).
inline bool
autoCloses(char const* open, char const* start)
{
	if (::strcmp(open, "p") == 0)
		return    ::strcmp(start, "p") == 0 || ::strcmp(start, "div") == 0
			   || ::strcmp(start, "ul") == 0 || ::strcmp(start, "ol") == 0
			   || ::strcmp(start, "dl") == 0 || ::strcmp(start, "table") == 0
			   || ::strcmp(start, "blockquote") == 0 || ::strcmp(start, "pre") == 0
			   || (start[0] == 'h' && start[1] >= '1' && start[1] <= '6' && start[2] == '\0');

	if (::strcmp(open, "li") == 0)
		return ::strcmp(start, "li") == 0 || ::strcmp(start, "ul") == 0 || ::strcmp(start, "ol") == 0;

	if (::strcmp(open, "dt") == 0 || ::strcmp(open, "dd") == 0)
		return ::strcmp(start, "dt") == 0 || ::strcmp(start, "dd") == 0;

	if (::strcmp(open, "option") == 0)
		return ::strcmp(start, "option") == 0;

	if (::strcmp(open, "td") == 0 || ::strcmp(open, "th") == 0)
		return    ::strcmp(start, "td") == 0 || ::strcmp(start, "th") == 0
			   || ::strcmp(start, "tr") == 0;

	if (::strcmp(open, "tr") == 0)
		return ::strcmp(start, "tr") == 0;

	if (   ::strcmp(open, "thead") == 0 || ::strcmp(open, "tbody") == 0
		|| ::strcmp(open, "tfoot") == 0)
		return    ::strcmp(start, "thead") == 0 || ::strcmp(start, "tbody") == 0
			   || ::strcmp(start, "tfoot") == 0;

	if (::strcmp(open, "a") == 0)
		return ::strcmp(start, "a") == 0;

	if (start[0] == 'h' && start[1] >= '1' && start[1] <= '6' && start[2] == '\0'
		&& open[0] == 'h' && open[1] >= '1' && open[1] <= '6' && open[2] == '\0')
		return true;

	return false;
}

} // anonymous namespace

// ----------------------------------------------------------------------
// Result records
// ----------------------------------------------------------------------

/// A media reference found in the document (img src / scidb-media:).
struct MediaRef
{
	mstl::string	file;		///< original reference as written
	mstl::string	resolved;	///< rewritten URI (empty when dropped)
	int				type;		///< 1=picture 2=audio 3=video 4=stream (0 n/a)
	RefStatus		status;

	MediaRef() :type(0), status(Ref_Kept) {}
};


/// A game anchor (scidb-game: href) — the payload is the CBLink-style
/// argument list, kept verbatim for the caller to match against games.
struct GameAnchor
{
	mstl::string	args;		///< "Last,First,Last,First,Event,Site,Year,Round,..."
	mstl::string	label;		///< link text as written
	RefStatus		status;

	GameAnchor() :status(Ref_Kept) {}
};


struct Report
{
	mstl::string					html;			///< sanitized UTF-8 fragment
	mstl::string					title;			///< <title> content (if any)
	mstl::vector<MediaRef>		media;			///< image/media references
	mstl::vector<GameAnchor>	anchors;		///< game anchors (in document order)
	mstl::vector<mstl::string>	warnings;		///< non-fatal diagnostics
	unsigned						droppedElements;
	unsigned						droppedAttrs;
	unsigned						rewrittenUris;
	bool							wasConverted;	///< input was transcoded to UTF-8

	Report() :droppedElements(0), droppedAttrs(0), rewrittenUris(0), wasConverted(false) {}
};

// ----------------------------------------------------------------------
// Sanitizer
// ----------------------------------------------------------------------

namespace {

unsigned const MaxAttrsPerTag		= 64;		///< attrs parsed per tag (pathology cap)
unsigned const MaxAttrName			= 64;		///< chars kept of an attribute name
unsigned const MaxAttrValue			= 4096;	///< chars kept of an attribute value
unsigned const MaxNesting			= 64;
unsigned const MaxEndTagScan		= 64;	///< how far up an end tag may close

inline void
appendEscapedText(mstl::string& out, char const* s, unsigned len)
{
	unsigned start = 0;

	for (unsigned i = 0; i < len; ++i)
	{
		char c = s[i];
		char const* ent = 0;

		if (c == '&')		ent = "&amp;";
		else if (c == '<')	ent = "&lt;";
		else if (c == '>')	ent = "&gt;";

		if (ent)
		{
			if (i > start)
				out.append(s + start, i - start);
			out.append(ent);
			start = i + 1;
		}
	}

	if (start < len)
		out.append(s + start, len - start);
}


/// One open element of the repair stack.
struct OpenElement
{
	char		name[16];
	bool		emitted;	///< tag was emitted (dropped tags don't close)

	OpenElement() :emitted(true) { name[0] = '\0'; }
};

} // anonymous namespace


/// The sanitize pass. See the file header for the contract.
inline bool
sanitize(	mstl::string const& raw,
			Rewriter& rewriter,
			Report& report)
{
	// never throw: the sanitizer is enrichment; any allocation failure
	// degrades to false (caller keeps the raw text).
	try
	{
		mstl::string input(html::normalizeToUtf8(
			reinterpret_cast<unsigned char const*>(raw.c_str()),
			unsigned(raw.size()), report.wasConverted));

		mstl::string& out = report.html;
		out.clear();
		out.reserve(input.size() + input.size() / 8 + 16);

		char const*	p		= input.c_str();
		char const*	end	= p + input.size();
		mstl::vector<OpenElement> stack;
		mstl::string titleText;
		mstl::string text;		// pending text run (entity-decoded)
		bool anyText = false;

		auto flushText = [&]()
		{
		if (anyText && !text.empty())
		{
		// decode entities, THEN re-escape: the output must be
		// well-formed regardless of what the input contained
		mstl::string decoded;
		decodeEntities(text, decoded);
		appendEscapedText(out, decoded.c_str(), unsigned(decoded.size()));
		}
		text.clear();
		anyText = false;
		};

		while (p < end)
		{
			if (*p != '<')
			{
				// text run: until next '<' (or end)
				char const* q = p;

				while (q < end && *q != '<')
					++q;

				text.append(p, unsigned(q - p));
				anyText = true;
				p = q;
				continue;
			}

			// markup
			if (p + 1 >= end)
				break; // dangling '<' — drop (safe: never emit raw '<')

			if (p[1] == '!')
			{
				// comment/doctype/CDATA: drop entirely
				flushText();

				if (p + 3 < end && p[2] == '-' && p[3] == '-')
				{
					char const* q = p + 4;

					while (q + 2 < end && !(q[0] == '-' && q[1] == '-' && q[2] == '>'))
						++q;

					p = (q + 2 < end) ? q + 3 : end;
				}
				else
				{
					char const* q = static_cast<char const*>(::memchr(p, '>', end - p));
					p = q ? q + 1 : end;
				}
				continue;
			}

			if (p[1] == '?')
			{
				// processing instruction (<?xml ...?>): drop
				flushText();
				char const* q = static_cast<char const*>(::memchr(p, '>', end - p));
				p = q ? q + 1 : end;
				continue;
			}

			bool isEnd = (p[1] == '/');

			// tag name
			char const* q = p + (isEnd ? 2 : 1);

			if (q >= end || !((*q >= 'a' && *q <= 'z') || (*q >= 'A' && *q <= 'Z')))
			{
				// '<' not starting a tag: emit as escaped text (XML-ish tolerance)
				text.push_back('&');
				text.append("lt;");
				anyText = true;
				++p;
				continue;
			}

			char name[16];
			unsigned nlen = 0;

			while (q < end && nlen + 1 < sizeof(name))
			{
				char c = *q;

				if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
					|| (c >= '0' && c <= '9') || c == ':' || c == '-' || c == '_'))
					break;

				name[nlen++] = (c >= 'A' && c <= 'Z') ? char(c + 32) : c;
				++q;
			}

			if (nlen == 0 || nlen >= sizeof(name))
			{
				// oversized/garbage tag name: drop the whole construct
				flushText();
				char const* gt = static_cast<char const*>(::memchr(p, '>', end - p));
				p = gt ? gt + 1 : end;
				continue;
			}

			name[nlen] = '\0';

			TagPolicy const* policy = findPolicy(name);
			TagAction action = policy ? policy->action : Unwrap; // unknown: keep children

			// find the end of the open tag (bounded attribute scan)
			char const* tagEnd = q;
			bool selfClosed = false;
			bool unterminated = false;

			while (tagEnd < end && *tagEnd != '>')
			{
				if (*tagEnd == '"' || *tagEnd == '\'')
				{
					char quote = *tagEnd++;
					while (tagEnd < end && *tagEnd != quote)
						++tagEnd;
					if (tagEnd < end)
						++tagEnd;
				}
				else
				{
					++tagEnd; // '/' before '>' is legal but has no effect here
				}
			}

			if (tagEnd >= end)
				unterminated = true;

			flushText();

			if (isEnd)
			{
				// --- end tag ---
				if (action == Keep || action == CaptureTitle || action == Unwrap)
				{
					// </title> is normally consumed inside the CaptureTitle
					// start-tag branch; a stray one is a no-op (it must never
					// clobber a captured title)
					if (action != CaptureTitle && !isVoidElement(name))
					{
						// close matching open element (bounded scan)
						unsigned found = stack.size();

						while (found > 0 && ::strcmp(stack[found - 1].name, name) != 0)
							--found;

						if (found > 0 && stack.size() - found <= MaxEndTagScan)
						{
							// pop down to AND INCLUDING the matched element
							while (stack.size() >= found)
							{
								if (stack.back().emitted)
									out.append("</").append(stack.back().name).append(">");
								stack.pop_back();
							}
						}
						// unmatched end tag: drop silently
					}
				}
				// DropContent/Drop end tags: nothing to do (content already skipped/handled)

				p = unterminated ? end : tagEnd + 1;
				continue;
			}

			// --- start tag ---
			if (action == CaptureTitle)
			{
				// capture the raw-text content up to </title>; the open
				// tag's '>' must not leak into the title
				char const* openGt = static_cast<char const*>(::memchr(q, '>', end - q));
				char const* scan = openGt ? openGt + 1 : q;
				char const* close = 0;

				for (char const* r = scan; r + 8 <= end; ++r)
				{
					if ((r[0] | 0x20) == '<' && (r[1] | 0x20) == '/' && (r[2] | 0x20) == 't'
						&& ::strncasecmp(r + 3, "itle", 4) == 0)
					{
						close = r;
						break;
					}
				}

				if (!close)
				{
					if (openGt)
						titleText.append(openGt + 1, unsigned(end - (openGt + 1)));
					report.title = titleText;
					p = end;
				}
				else
				{
					if (openGt && close > openGt)
						titleText.append(openGt + 1, unsigned(close - (openGt + 1)));
					report.title = titleText;
					char const* gt = static_cast<char const*>(::memchr(close, '>', end - close));
					p = gt ? gt + 1 : end;
				}
				continue;
			}

			if (action == DropContent)
			{
				// skip raw-text content to the matching end tag
				char const* r = tagEnd < end ? tagEnd + 1 : end;

				while (r < end)
				{
					if (*r == '<' && r + 1 < end && r[1] == '/'
						&& r + 2 < end && (r[2] | 0x20) == name[0])
					{
						// verify the rest of the name matches
						unsigned k = 0;

						while (k < nlen && r + 2 + k < end
							&& (r[2 + k] | 0x20) == name[k])
							++k;

						// the name must be followed by a delimiter — otherwise
						// "</scriptx>" would terminate a <script> block early
						if (k == nlen && (r + 2 + k >= end
						|| r[2 + k] == '>' || r[2 + k] == '/'
						|| r[2 + k] == ' ' || r[2 + k] == '\t'
						|| r[2 + k] == '\r' || r[2 + k] == '\n'))
							break;
					}
					++r;
				}

				if (r < end)
				{
					char const* gt = static_cast<char const*>(::memchr(r, '>', end - r));
					p = gt ? gt + 1 : end;
				}
				else
				{
					p = end; // unterminated raw-text element: swallow the rest
				}
				++report.droppedElements;
				continue;
			}

			// parse attributes from [q, tagEnd)
			// collect name=value pairs, whitelist, then emit
			mstl::string attrs;
			mstl::string hrefValue;		// for <a>: classify afterwards
			mstl::string srcValue;		// for <img>
			RefStatus srcStatus = Ref_Kept;
			bool hasHref = false;
			bool hasSrc = false;
			unsigned droppedAttrs = 0;

			char const* ap = q;

			while (ap < tagEnd)
			{
				// skip separators
				while (ap < tagEnd && (*ap == ' ' || *ap == '\t' || *ap == '\r'
					|| *ap == '\n' || *ap == '/' || *ap == '='))
					++ap;

				if (ap >= tagEnd)
					break;

				// attribute name
				if (droppedAttrs >= MaxAttrsPerTag)
				{
				// pathological attribute count: stop scanning this tag
				break;
				}

				char aname[MaxAttrName + 1];
				unsigned alen = 0;

				while (ap < tagEnd && alen < MaxAttrName)
				{
					char c = *ap;

					if (c == '=' || c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '>')
						break;

					aname[alen++] = (c >= 'A' && c <= 'Z') ? char(c + 32) : c;
					++ap;
				}
				aname[alen] = '\0';

				// skip to '=' / value
				char const* vp = ap;

				while (vp < tagEnd && (*vp == ' ' || *vp == '\t'))
					++vp;

				mstl::string value;

				if (vp < tagEnd && *vp == '=')
				{
					++vp;

					while (vp < tagEnd && (*vp == ' ' || *vp == '\t'))
						++vp;

					if (vp < tagEnd && (*vp == '"' || *vp == '\''))
					{
						char quote = *vp++;
						char const* vEnd = static_cast<char const*>(
							::memchr(vp, quote, tagEnd - vp));
						if (!vEnd)
							vEnd = tagEnd;
						value.assign(vp, unsigned(vEnd - vp));
						ap = (vEnd < tagEnd) ? vEnd + 1 : tagEnd;
					}
					else
					{
						char const* vEnd = vp;

						while (vEnd < tagEnd && *vEnd != ' ' && *vEnd != '\t' && *vEnd != '>')
							++vEnd;
						value.assign(vp, unsigned(vEnd - vp));
						ap = vEnd;
					}

					if (value.size() > MaxAttrValue)
					{
						// truncate oversized values (bounded output)
						value.resize(MaxAttrValue);
						++droppedAttrs;
					}
				}
				else
				{
					ap = vp; // valueless attribute
				}

				if (alen == 0)
				{
					// malformed attribute (e.g. a stray '>' inside the tag —
					// the tag scanner skips '>' inside quoted values): force
					// progress, never stall
					++ap;
					continue;
				}

				// event handlers are always dropped
				if (alen >= 2 && aname[0] == 'o' && aname[1] == 'n')
				{
					++droppedAttrs;
					continue;
				}

				// whitelist check
				bool allowed = false;

				if (policy && policy->attrs)
				{
					for (char const* const* a = policy->attrs; *a; ++a)
						if (::strcmp(*a, aname) == 0)
						{
							allowed = true;
							break;
						}
				}

				if (!allowed)
				{
					++droppedAttrs;
					continue;
				}

				// URI attributes: scheme check + rewrite
				if (::strcmp(aname, "href") == 0 || ::strcmp(aname, "src") == 0)
				{
					// entities must be decoded BEFORE the scheme check:
					// "&#106;avascript:..." passes a raw check as "relative" but
					// is javascript: once decoded. The emitted value is always
					// the decoded one, so check it in its final form.
					{
						mstl::string decoded;
						decodeEntities(value, decoded);
						value = decoded;
					}

					// browsers strip leading/trailing C0 controls and space before
					// scheme parsing (" javascript:" is javascript:); do the same
					{
						mstl::string::size_type b = 0;
						mstl::string::size_type e = value.size();

						while (b < e && unsigned((unsigned char)value[b]) <= 0x20)
							++b;
						while (e > b && unsigned((unsigned char)value[e - 1]) <= 0x20)
							--e;

						if (b > 0 || e < value.size())
							value = mstl::string(value, b, e - b);
					}

					RefStatus status = Ref_Kept;
					mstl::string rewritten;

					rewriter.rewrite(name, value, status, rewritten);

					if (status == Ref_Dropped)
					{
						++droppedAttrs;
						continue;
					}

					if (status == Ref_Rewritten)
						++report.rewrittenUris;

					if (::strcmp(aname, "href") == 0)
					{
						hasHref = true;
						hrefValue = rewritten.empty() ? value : rewritten;
					}
					else
					{
						hasSrc = true;
						srcValue = rewritten.empty() ? value : rewritten;
						srcStatus = status;
					}

					// the EMITTED attribute value is the rewritten URI
					if (!rewritten.empty())
						value = rewritten;
				}

				if (!attrs.empty())
					attrs.push_back(' ');

				attrs.append(aname);
				attrs.append("=\"");

				// escape value (entities decoded, quotes escaped)
				{
					mstl::string decoded;
					decodeEntities(value, decoded);

					for (unsigned i = 0; i < decoded.size(); ++i)
					{
						char c = decoded[i];

						if (c == '"')		attrs.append("&quot;");
						else if (c == '<')	attrs.append("&lt;");
						else if (c == '>')	attrs.append("&gt;");
						else if (c == '&')	attrs.append("&amp;");
						else				attrs.push_back(c);
					}
				}
				attrs.append("\"");
			}

			if (droppedAttrs)
				report.droppedAttrs += droppedAttrs;

			// emit the element
			if (action == Keep)
			{
				// structural repair: auto-close
				if (!isVoidElement(name))
				{
					while (!stack.empty() && autoCloses(stack.back().name, name))
					{
						if (stack.back().emitted)
							out.append("</").append(stack.back().name).append(">");
						stack.pop_back();
					}
				}

				if (stack.size() >= MaxNesting)
				{
					// nesting bomb: drop the tag, keep content
					++report.droppedElements;
				}
				else
				{
					out.append("<").append(name);

					if (!attrs.empty())
					{
						out.push_back(' ');
						out.append(attrs);
					}

					if (isVoidElement(name))
					{
						out.append(">");
					}
					else
					{
						out.append(">");
						OpenElement e;
						::strncpy(e.name, name, sizeof(e.name) - 1);
						e.name[sizeof(e.name) - 1] = '\0';
						stack.push_back(e);
					}
				}

				// classify the reference for the caller
				if (::strcmp(name, "a") == 0 && hasHref)
				{
					if (::strncmp(hrefValue.c_str(), "scidb-game:", 11) == 0)
					{
						GameAnchor a;
						a.args = hrefValue.c_str() + 11;
						a.label = ""; // filled by caller from following text (v1)
						a.status = Ref_ScidbGame;
						report.anchors.push_back(a);
					}
					else if (::strncmp(hrefValue.c_str(), "scidb-media:", 12) == 0)
					{
						MediaRef m;
						m.file = hrefValue.c_str() + 12;
						m.resolved = hrefValue.c_str() + 12;
						m.type = 0; // caller classifies by extension
						m.status = Ref_ScidbMedia;
						report.media.push_back(m);
					}
				}
				else if (::strcmp(name, "img") == 0 && hasSrc)
				{
					MediaRef r;
					r.file = srcValue;
					r.resolved = srcValue;
					r.type = 1;
					// keep the rewriter verdict (Ref_Unresolved must stay visible)
					r.status = (::strncmp(srcValue.c_str(), "scidb-media:", 12) == 0)
						? Ref_ScidbMedia : srcStatus;
					report.media.push_back(r);
				}
			}
			else if (action == Unwrap || action == Drop)
			{
				// children flow through; element itself vanishes
				if (action == Drop)
					++report.droppedElements;

				if (!isVoidElement(name) && action == Unwrap
				&& stack.size() < MaxNesting)
				{
					// push a non-emitting marker so the end tag doesn't
					// close a real element (the cap keeps the stack bounded)
					OpenElement e;
					e.emitted = false;
					::strncpy(e.name, name, sizeof(e.name) - 1);
					e.name[sizeof(e.name) - 1] = '\0';
					stack.push_back(e);
				}
			}

			p = unterminated ? end : tagEnd + 1;
		}

		flushText();

		// close whatever is still open
		while (!stack.empty())
		{
			if (stack.back().emitted)
				out.append("</").append(stack.back().name).append(">");
			stack.pop_back();
		}

		return true;
	}
	catch (...)
	{
		// degrade gracefully: emit the raw text escaped, mark the report
		try
		{
			report.html.clear();
			appendEscapedText(report.html, raw.c_str(), unsigned(raw.size()));
			report.warnings.push_back(mstl::string("internal error: degraded to escaped text"));
		}
		catch (...)
		{
		}

		return false;
	}
}

} // namespace html

#endif // _html_sanitize_included

// vi:set ts=3 sw=3: