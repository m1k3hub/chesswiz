// ======================================================================
// html_cb_adapter — ChessBase HTML adapter for scidb's HTML core
// ======================================================================
// One of the source adapters of scidb's native HTML support. ChessBase
// guiding texts (decoded from .cbg by cbh_codec) use constructs outside
// any HTML standard:
//
//   <A href="javascript:CBLink(tag_game,So,Wesley,Nakamura,Hikaru,
//        Sinquefield Cup 3rd,Saint Louis,2015,6,0,17)">So,W - Nakamura,H</A>
//   <IMG src="CB Light Database.html\CBL_Logo.jpg">
//   CBLink(tag_stream,CB Light Database.html\CBM 126 Aronian - Grischuk.wmv,)
//
// This adapter runs BEFORE html::sanitize() and rewrites the constructs
// into the internal URI schemes the sanitizer understands:
//
//   CBLink(tag_game,...)          ->  <a href="scidb-game:ARGS">…</a>
//   CBLink(tag_stream/audio/...,
//          FILE,...)              ->  <a href="scidb-media:RESOLVED">BASENAME</a>
//   src/href "DB.html\file"       ->  resolved through the PathResolver
//
// The sanitize core then scheme-checks, escapes, repairs and classifies
// everything uniformly — ChessBase never reaches any other layer.
//
// Note on argument parsing: CBLink arguments are comma-separated with
// the documented order (tag_game: WhiteLast, WhiteFirst, BlackLast,
// BlackFirst, Event, Site, Year, Round, [Extra...]). An event/site
// containing a comma shifts the tail fields — the same limitation the
// existing extraction code (tcl_media_extract.h) carries; anchor
// matching tolerates it via the event-substring rule.
// ======================================================================

#ifndef _html_cb_adapter_included
#define _html_cb_adapter_included

#include "m_string.h"
#include "m_vector.h"

#include "html_sanitize.h"

#include <cstring>
#include <strings.h>

namespace html {

/// Resolves a media file reference ("<DB>.html\<filename>") to a
/// usable path. The host implements this over
/// tcl_media::resolveMediaFilename() so the core stays filesystem-free.
class PathResolver
{
public:

	virtual ~PathResolver() throw() {}

	/// Return true and set `out` if `file` could be located; false
	/// means the reference stays unresolved (it will be reported).
	virtual bool resolve(mstl::string const& file, mstl::string& out) = 0;
};


namespace {

/// Basename of a Windows- or Unix-style path.
inline mstl::string
cbBasename(mstl::string const& path)
{
	mstl::string::size_type slash = path.rfind('/');
	mstl::string::size_type back = path.rfind('\\');
	mstl::string::size_type cut = mstl::string::npos;

	if (slash != mstl::string::npos)
		cut = slash;
	if (back != mstl::string::npos && (cut == mstl::string::npos || back > cut))
		cut = back;

	return (cut == mstl::string::npos) ? path : mstl::string(path, cut + 1, mstl::string::npos);
}


/// Percent-free attribute-value escaping (quotes/entities) for the
/// markup this adapter generates; the sanitizer re-decodes.
inline void
cbAppendAttrValue(mstl::string& out, mstl::string const& value)
{
	for (unsigned i = 0; i < value.size(); ++i)
	{
		char c = value[i];

		if (c == '"')			out.append("&quot;");
		else if (c == '&')		out.append("&amp;");
		else if (c == '<')		out.append("&lt;");
		else if (c == '>')		out.append("&gt;");
		else						out.push_back(c);
	}
}


/// One parsed CBLink call.
struct CbLink
{
	mstl::string				kind;		// "tag_game", "tag_stream", "tag_audio", ...
	mstl::vector<mstl::string>	args;
	bool							complete;	// closing ')' was found
	unsigned						endPos;	// offset just past ')'

	CbLink() :complete(false), endPos(0) {}
};


/// Parse the CBLink(… ) call starting at `p` (which must point at 'C'
/// of "CBLink"). Returns false if the construct is incomplete; `link`
/// is only valid then.
inline bool
parseCbLink(char const* p, char const* end, CbLink& link)
{
	static char const Prefix[] = "CBLink(";
	static unsigned const PrefixLen = sizeof(Prefix) - 1;

	if (unsigned(end - p) < PrefixLen || ::memcmp(p, Prefix, PrefixLen) != 0)
		return false;

	char const* q = p + PrefixLen;
	char const* kindEnd = static_cast<char const*>(::memchr(q, ',', end - q));

	if (!kindEnd || kindEnd - q > 32)
		return false;

	link.kind.assign(q, unsigned(kindEnd - q));

	// lowercase the kind
	for (unsigned i = 0; i < link.kind.size(); ++i)
	{
		char c = link.kind[i];
		if (c >= 'A' && c <= 'Z')
			link.kind[i] = char(c + 32);
	}

	// split the remaining arguments at ',' up to the closing ')'
	q = kindEnd + 1;
	mstl::string arg;

	while (q < end && *q != ')')
	{
		if (*q == ',')
		{
			link.args.push_back(arg);
			arg.clear();
		}
		else
		{
			arg.push_back(*q);
		}
		++q;
	}

	if (q >= end)
		return false; // unterminated

	if (!arg.empty() || !link.args.empty())
		link.args.push_back(arg); // trailing argument (may be empty)

	link.complete = true;
	link.endPos = unsigned(q - p) + 1;
	return true;
}


inline char const*
mediaKindTag(char const* kind)
{
	if (::strcmp(kind, "tag_stream") == 0)	return "stream";
	if (::strcmp(kind, "tag_video") == 0)	return "video";
	if (::strcmp(kind, "tag_audio") == 0)	return "audio";
	if (::strcmp(kind, "tag_picture") == 0)	return "picture";
	return 0;
}

} // anonymous namespace


/// The ChessBase URI rewriter: implements the core Rewriter contract on
/// top of a PathResolver. Image sources ("DB.html\name.jpg") are
/// resolved; scidb-internal URIs are passed through for classification;
/// foreign schemes die in the base class.
class ChessBaseRewriter : public Rewriter
{
public:

	ChessBaseRewriter(PathResolver& resolver) :m_resolver(resolver) {}

	void rewrite(char const* tag, mstl::string const& uri,
						RefStatus& status, mstl::string& result) override
	{
		mstl::string scheme(schemeOf(uri));

		if (!scheme.empty() && !schemeAllowed(scheme))
		{
			status = Ref_Dropped;
			return;
		}

		if (::strcmp(tag, "img") == 0)
		{
			// ChessBase writes Windows paths with backslashes and
			// "<DB>.html\" prefixes — resolve to a real file if possible.
			mstl::string normalized;

			for (unsigned i = 0; i < uri.size(); ++i)
				normalized.push_back(uri[i] == '\\' ? '/' : uri[i]);

			if (scheme.empty()) // relative: a media file reference
			{
				mstl::string resolved;

				if (m_resolver.resolve(normalized, resolved))
				{
					status = Ref_Rewritten;
					result = resolved;
					return;
				}

				status = Ref_Unresolved;
				result = normalized; // keep for reporting; UI shows a placeholder
				return;
			}
		}

		if (scheme == "http" || scheme == "https" || scheme == "ftp")
		{
			status = Ref_External;
			result = uri;
			return;
		}

		if (scheme == "scidb-game" || scheme == "scidb-media")
		{
			status = (scheme == "scidb-game") ? Ref_ScidbGame : Ref_ScidbMedia;
			result = uri;
			return;
		}

		status = Ref_Kept; // file:, mailto:, relative
		result = uri;
	}

private:

	PathResolver&	m_resolver;
};


/// Pre-pass over raw ChessBase guiding-text markup. Emits sanitized-
/// ready HTML-ish text with all CBLink constructs converted to internal
/// URIs. `stats` is advisory. Never throws.
inline void
cbPreprocess(	mstl::string const& raw,
				PathResolver& resolver,
				mstl::string& out,
				unsigned& rewritten,
				unsigned& unresolved)
{
	out.clear();
	out.reserve(raw.size() + raw.size() / 8);

	rewritten = 0;
	unresolved = 0;

	char const*	base	= raw.c_str();
	char const*	end	= base + raw.size();
	char const*	p		= base;

	static char const Prefix[] = "CBLink(";
	static unsigned const PrefixLen = sizeof(Prefix) - 1;

	while (p < end)
	{
		// next CBLink occurrence (case-sensitive; ChessBase writes it so)
		char const* hit = 0;

		for (char const* q = p; q + PrefixLen <= end; ++q)
		{
			if (::memcmp(q, Prefix, PrefixLen) == 0)
			{
				hit = q;
				break;
			}
		}

		if (!hit)
		{
			out.append(p, unsigned(end - p));
			break;
		}

		// href="javascript:CBLink(...)" wrapper? hit-11 is the 'j'.
		bool			inHrefJs	= false;
		char			quote		= '"';
		char const*	openQ		= 0;

		if (hit - base >= 12 && ::strncasecmp(hit - 11, "javascript:", 11) == 0
			&& (hit[-12] == '"' || hit[-12] == '\''))
		{
			inHrefJs = true;
			openQ = hit - 12;
			quote = hit[-12];
		}

		CbLink link;

		if (!parseCbLink(hit, end, link) || !link.complete)
		{
			// incomplete construct: emit literally, skip the prefix
			out.append(p, unsigned(hit - p) + PrefixLen);
			p = hit + PrefixLen;
			continue;
		}

		char const* after = hit + link.endPos;

		// emit everything before the construct; inside a javascript: href
		// value, emit up to AND INCLUDING the opening quote (the URI is
		// replaced from there)
		if (inHrefJs)
			out.append(p, unsigned(openQ - p) + 1);
		else
			out.append(p, unsigned(hit - p));

		if (link.kind == "tag_game")
		{
			mstl::string args;

			for (unsigned i = 0; i < link.args.size(); ++i)
			{
				if (i)
					args.push_back(',');
				args.append(link.args[i]);
			}

			if (inHrefJs)
			{
				out.append("scidb-game:");
				cbAppendAttrValue(out, args);
				++rewritten;
				p = after;
			}
			else
			{
				// bare tag_game text: anchor with the following inline
				// text as label (bounded, never swallows the document)
				out.append("<a href=\"scidb-game:");
				cbAppendAttrValue(out, args);
				out.append("\">");

				char const* labelEnd = after;
				char const* limit = after + 128 < end ? after + 128 : end;

				while (labelEnd < limit && *labelEnd != '<')
					++labelEnd;

				out.append(after, unsigned(labelEnd - after));
				out.append("</a>");
				++rewritten;
				p = labelEnd;
			}
		}
		else if (   link.kind == "tag_stream" || link.kind == "tag_video"
				 || link.kind == "tag_audio" || link.kind == "tag_picture")
		{
			// the FILE is the first argument after the kind
			// (matches tcl_media_extract.h parsing)
			mstl::string file = !link.args.empty() ? link.args[0] : mstl::string();

			if (!file.empty())
			{
				mstl::string resolved;

				if (resolver.resolve(file, resolved))
				{
					out.append("<a href=\"scidb-media:");
					cbAppendAttrValue(out, resolved);
					out.append("\">");
					cbAppendAttrValue(out, cbBasename(file));
					out.append("</a>");
					++rewritten;
				}
				else
				{
					cbAppendAttrValue(out, cbBasename(file)); // plain text, reported
					++unresolved;
				}

				p = after;
			}
			else
			{
				// no file argument: emit as visible, bracketed text
				out.append("[CBLink(");
				out.append(p < after ? mstl::string(hit, unsigned(after - hit)) : mstl::string());
				out.append(")]");
				p = after;
			}
		}
		else
		{
			// unknown kind: keep visible as bracketed text (never lost)
			out.append("[CBLink(");
			out.append(hit + PrefixLen, unsigned(after - (hit + PrefixLen)));
			out.append(")]");
			p = after;
		}

		if (inHrefJs)
		{
			// swallow through the closing quote of the old href value
			char const* q = p;

			while (q < end && *q != quote && *q != '>')
				++q;

			if (q < end && *q == quote)
			{
				out.push_back(quote);
				p = q + 1;
			}
			else
			{
				p = q; // degraded: let the sanitizer cope with the rest
			}
		}
	}
}

} // namespace html

#endif // _html_cb_adapter_included

// vi:set ts=3 sw=3: