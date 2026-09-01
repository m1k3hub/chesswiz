// ======================================================================
// html_encoding — character-set normalization for scidb's HTML core
// ======================================================================
// Part of scidb's native HTML support (src/html). Everything downstream
// (sanitizer, renderer, exporter) consumes UTF-8 only; this header is
// the single place where foreign encodings are normalized.
//
// Detection strategy (in order):
//   1. UTF-8 BOM / UTF-16 BOM          -> authoritative
//   2. <meta charset=...> / <meta http-equiv="Content-Type" content="...">
//                                      -> authoritative (HTML5 §4.2.5.5
//                                         prescan, simplified)
//   3. UTF-8 validity check            -> valid means UTF-8
//   4. otherwise                       -> Windows-1252 (the ChessBase era
//                                         default; a superset of Latin-1)
//
// Never throws: all allocation failures degrade to "return the input
// unchanged" (callers treat sanitize() as best-effort enrichment).
// ======================================================================

#ifndef _html_encoding_included
#define _html_encoding_included

#include "m_string.h"

#include <cstring>

namespace html {

/// True if `data`/`size` is entirely valid UTF-8 (no truncation check
/// beyond the buffer end; a truncated final sequence fails).
inline bool
isValidUtf8(unsigned char const* data, unsigned size)
{
	for (unsigned i = 0; i < size; )
	{
		unsigned char c = data[i];

		if (c < 0x80)
		{
			++i;
			continue;
		}

		unsigned need;	// continuation bytes required
		uint32_t cp;

		if ((c & 0xe0) == 0xc0)			{ need = 1; cp = c & 0x1f; }
		else if ((c & 0xf0) == 0xe0)	{ need = 2; cp = c & 0x0f; }
		else if ((c & 0xf8) == 0xf0)	{ need = 3; cp = c & 0x07; }
		else
			return false;					// 0x80-0xC1 lead or 0xF8+ (overlong/invalid)

		if (i + need >= size + 0 && i + need > size - 1)
			return false;					// sequence runs past the end

		for (unsigned k = 1; k <= need; ++k)
		{
			unsigned char cc = data[i + k];
			if ((cc & 0xc0) != 0x80)
				return false;
			cp = (cp << 6) | (cc & 0x3f);
		}

		// reject overlong, surrogates, > U+10FFFF
		if (   (need == 1 && cp < 0x80)
			|| (need == 2 && cp < 0x800)
			|| (need == 3 && cp < 0x10000)
			|| (cp >= 0xd800 && cp <= 0xdfff)
			|| cp > 0x10ffff)
			return false;

		i += need + 1;
	}

	return true;
}


/// Append the UTF-8 encoding of code point `cp` to `out`.
inline void
appendUtf8(mstl::string& out, uint32_t cp)
{
	if (cp < 0x80)
	{
		out.push_back(char(cp));
	}
	else if (cp < 0x800)
	{
		out.push_back(char(0xc0 | (cp >> 6)));
		out.push_back(char(0x80 | (cp & 0x3f)));
	}
	else if (cp < 0x10000)
	{
		out.push_back(char(0xe0 | (cp >> 12)));
		out.push_back(char(0x80 | ((cp >> 6) & 0x3f)));
		out.push_back(char(0x80 | (cp & 0x3f)));
	}
	else if (cp <= 0x10ffff)
	{
		out.push_back(char(0xf0 | (cp >> 18)));
		out.push_back(char(0x80 | ((cp >> 12) & 0x3f)));
		out.push_back(char(0x80 | ((cp >> 6) & 0x3f)));
		out.push_back(char(0x80 | (cp & 0x3f)));
	}
	// else: out of range — drop silently
}


namespace {

// Windows-1252 mappings for 0x80..0x9F (0 = undefined -> Latin-1 passthrough).
uint32_t const Cp1252High[] =
{
	0x20ac, 0x0081, 0x201a, 0x0192, 0x201e, 0x2026, 0x2020, 0x2021,
	0x02c6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008d, 0x017d, 0x008f,
	0x0090, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014,
	0x02dc, 0x2122, 0x0161, 0x203a, 0x0153, 0x009d, 0x017e, 0x0178,
};

inline uint32_t
cp1252ToCodePoint(unsigned char c)
{
	if (c >= 0x80 && c <= 0x9f)
		return Cp1252High[c - 0x80];
	return c; // Latin-1 range maps 1:1
}

} // anonymous namespace


/// Transcode a Windows-1252 byte string to UTF-8.
inline mstl::string
cp1252ToUtf8(unsigned char const* data, unsigned size)
{
	mstl::string out;
	out.reserve(size + size / 4 + 4);

	for (unsigned i = 0; i < size; ++i)
		appendUtf8(out, cp1252ToCodePoint(data[i]));

	return out;
}


/// Transcode UTF-16 (with BOM) bytes to UTF-8. Lone surrogates are
/// replaced with U+FFFD; odd trailing byte is dropped. Returns false
/// if there is no BOM (caller should use another detection path).
inline bool
utf16BomToUtf8(unsigned char const* data, unsigned size, mstl::string& out)
{
	if (size < 2)
		return false;

	bool littleEndian;

	if (data[0] == 0xff && data[1] == 0xfe)
		littleEndian = true;
	else if (data[0] == 0xfe && data[1] == 0xff)
		littleEndian = false;
	else
		return false;

	out.clear();
	out.reserve(size / 2 + 4);

	for (unsigned i = 2; i + 1 < size; i += 2)
	{
		uint32_t u = littleEndian
			? (uint32_t(data[i]) | (uint32_t(data[i + 1]) << 8))
			: (uint32_t(data[i + 1]) | (uint32_t(data[i]) << 8));

		if (u >= 0xd800 && u <= 0xdbff && i + 3 < size)
		{
			uint32_t lo = littleEndian
				? (uint32_t(data[i + 2]) | (uint32_t(data[i + 3]) << 8))
				: (uint32_t(data[i + 3]) | (uint32_t(data[i + 2]) << 8));

			if (lo >= 0xdc00 && lo <= 0xdfff)
			{
				appendUtf8(out, 0x10000 + ((u - 0xd800) << 10) + (lo - 0xdc00));
				i += 2;
				continue;
			}
		}

		appendUtf8(out, (u >= 0xd800 && u <= 0xdfff) ? 0xfffd : u);
	}

	return true;
}


/// Look for a `<meta charset=X>` or `<meta http-equiv="Content-Type"
/// content="...charset=X">` declaration in the first `window` bytes
/// (HTML5 encoding prescan). Returns the lowercase charset name, or "".
inline mstl::string
metaCharset(unsigned char const* data, unsigned size, unsigned window = 2048)
{
	unsigned scan = size < window ? size : window;

	// case-insensitive search for "charset=" (attribute or content value)
	for (unsigned i = 0; i + 8 <= scan; ++i)
	{
		if (   (data[i + 0] | 0x20) == 'c'
			&& (data[i + 1] | 0x20) == 'h'
			&& (data[i + 2] | 0x20) == 'a'
			&& (data[i + 3] | 0x20) == 'r'
			&& (data[i + 4] | 0x20) == 's'
			&& (data[i + 5] | 0x20) == 'e'
			&& (data[i + 6] | 0x20) == 't'
			&& (data[i + 7] == '=' || data[i + 7] == ' '
			|| data[i + 7] == '\t' || data[i + 7] == '\r' || data[i + 7] == '\n'))
		{
			unsigned p = i + 7;

			while (p < scan && (data[p] == ' ' || data[p] == '\t'
				|| data[p] == '\r' || data[p] == '\n' || data[p] == '='))
				++p;

			if (p < scan && (data[p] == '"' || data[p] == '\''))
				++p;

			mstl::string name;

			while (p < scan)
			{
				unsigned char c = data[p];

				if (c == '"' || c == '\'' || c == '>' || c == ' '
					|| c == '\t' || c == '\r' || c == '\n' || c == ';' || c == '/')
					break;

				name.push_back(char(c | (c >= 'A' && c <= 'Z' ? 0x20 : 0)));
				++p;
			}

			if (!name.empty())
				return name;
		}
	}

	return mstl::string();
}


/// Normalize `data`/`size` to UTF-8 (see the detection strategy in the
/// file header). BOMs are consumed. `wasConverted` reports whether a
/// transcode happened (diagnostics).
inline mstl::string
normalizeToUtf8(unsigned char const* data, unsigned size, bool& wasConverted)
{
	wasConverted = false;

	if (size >= 3 && data[0] == 0xef && data[1] == 0xbb && data[2] == 0xbf)
	{
		// UTF-8 BOM: strip, bytes are already UTF-8 (validated below).
		data += 3;
		size -= 3;
	}
	else if (size >= 2 && ((data[0] == 0xff && data[1] == 0xfe)
						|| (data[0] == 0xfe && data[1] == 0xff)))
	{
		mstl::string out;

		if (utf16BomToUtf8(data, size, out))
		{
			wasConverted = true;
			return out;
		}
		// fall through: treat as 8-bit content
	}

	mstl::string charset(metaCharset(data, size));

	// UTF-16 content without a BOM is effectively undecodable here; treat
	// it as 8-bit and let the validity check decide.
	if (charset == "utf-8" || charset == "utf8" || charset.empty())
	{
		if (isValidUtf8(data, size))
			return mstl::string(reinterpret_cast<char const*>(data), size);
		// invalid UTF-8 and no declared charset -> Windows-1252
	}
	else if (   charset == "utf-16" || charset == "utf-16le" || charset == "utf-16be"
			 || charset == "unicode")
	{
		mstl::string out;

		if (utf16BomToUtf8(data, size, out))
		{
			wasConverted = true;
			return out;
		}
	}

	if (charset == "iso-8859-1" || charset == "latin1" || charset == "latin-1"
		|| charset == "windows-1252" || charset == "cp1252" || charset == "ansi"
		|| charset.empty())
	{
		wasConverted = true;
		return cp1252ToUtf8(data, size);
	}

	// Unknown declared charset: try UTF-8, then 1252. (A full iconv
	// dependency is not warranted for the known corpus.)
	if (isValidUtf8(data, size))
		return mstl::string(reinterpret_cast<char const*>(data), size);

	wasConverted = true;
	return cp1252ToUtf8(data, size);
}


namespace {

struct NamedEntity { char const* name; uint32_t cp; };

// The named entities that actually occur in game annotations/reports.
// Deliberately minimal: full HTML5 tables add 2000+ entries for no
// practical gain here. Unknown names pass through unchanged.
NamedEntity const NamedEntities[] =
{
	{ "amp;",  '&'    }, { "lt;",   '<'    }, { "gt;",   '>'    },
	{ "quot;", '"'    }, { "apos;", '\''   }, { "nbsp;", 0x00a0 },
	{ "copy;", 0x00a9 }, { "reg;",  0x00ae }, { "trade;", 0x2122 },
	{ "mdash;", 0x2014 }, { "ndash;", 0x2013 }, { "hellip;", 0x2026 },
	{ "ldquo;", 0x201c }, { "rdquo;", 0x201d }, { "lsquo;", 0x2018 },
	{ "rsquo;", 0x2019 }, { "laquo;", 0x00ab }, { "raquo;", 0x00bb },
	{ "auml;", 0x00e4 }, { "ouml;", 0x00f6 }, { "uuml;", 0x00fc },
	{ "Auml;", 0x00c4 }, { "Ouml;", 0x00d6 }, { "Uuml;", 0x00dc },
	{ "szlig;", 0x00df }, { "eacute;", 0x00e9 }, { "egrave;", 0x00e8 },
	{ "agrave;", 0x00e0 }, { "ccedil;", 0x00e7 },
	{ "deg;", 0x00b0 }, { "plusmn;", 0x00b1 }, { "frac12;", 0x00bd },
	{ "times;", 0x00d7 }, { "divide;", 0x00f7 },
	{ "euro;", 0x20ac }, { "pound;", 0x00a3 }, { "yen;", 0x00a5 },
	{ "bull;", 0x2022 }, { "middot;", 0x00b7 }, { "para;", 0x00b6 },
	{ "sect;", 0x00a7 }, { "dagger;", 0x2020 }, { "Dagger;", 0x2021 },
};

unsigned const NumNamedEntities = sizeof(NamedEntities) / sizeof(NamedEntities[0]);

} // anonymous namespace


/// Decode HTML character references in `text` into `out` (UTF-8).
/// Handles the named entities above plus numeric forms; unknown or
/// oversized references pass through unchanged (never swallowed). An
/// `&` not starting a valid reference is emitted as "&amp;".
inline void
decodeEntities(mstl::string const& text, mstl::string& out)
{
	out.clear();
	out.reserve(text.size());

	char const* p = text.c_str();
	char const* end = p + text.size();

	while (p < end)
	{
		if (*p != '&')
		{
			out.push_back(*p++);
			continue;
		}

		// numeric: &#[0-9]+; / &#x[0-9a-f]+; (zero padding skipped, up to
		// 9 significant digits — HTML5-ish leniency, bounded work)
		if (p + 2 < end && p[1] == '#')
		{
			char const* q = p + 2;
			bool hex = (q < end && (*q == 'x' || *q == 'X'));
			char const* digits = hex ? q + 1 : q;
			char const* r = digits;
			uint32_t cp = 0;
			bool ok = r < end;
			unsigned sig = 0;

			while (r < end && *r == '0')
				++r; // zero padding is insignificant

			while (r < end && *r != ';')
			{
				int d;

				if (*r >= '0' && *r <= '9')				d = *r - '0';
				else if (hex && *r >= 'a' && *r <= 'f')	d = *r - 'a' + 10;
				else if (hex && *r >= 'A' && *r <= 'F')	d = *r - 'A' + 10;
				else { ok = false; break; }

				if (d != 0 || sig > 0)
				{
					if (++sig > 9)
					{
						ok = false; // oversized literal: emit literally
						break;
					}
					// overflow-checked accumulation (9 hex digits overflow u32)
					uint64_t next = uint64_t(cp) * (hex ? 16u : 10u) + unsigned(d);
					if (next > 0x10ffff)
					{
						ok = false;
						break;
					}
					cp = uint32_t(next);
				}
				++r;
			}

			if (ok && r < end && *r == ';' && r > digits)
			{
				// map C1 control codes to their CP1252 interpretation
				// (the table holds identity values for undefined slots)
				if (cp >= 0x80 && cp <= 0x9f)
					cp = Cp1252High[cp - 0x80];
				// HTML5: surrogate and out-of-range references are U+FFFD
				if (cp == 0 || (cp >= 0xd800 && cp <= 0xdfff) || cp > 0x10ffff)
					cp = 0xfffd;
				appendUtf8(out, cp);
				p = r + 1;
				continue;
			}
		}

		// named
		{
			char const* q = p + 1;
			bool matched = false;

			for (unsigned k = 0; k < NumNamedEntities; ++k)
			{
				unsigned len = ::strlen(NamedEntities[k].name);

				if (unsigned(end - q) >= len && ::memcmp(q, NamedEntities[k].name, len) == 0)
				{
					appendUtf8(out, NamedEntities[k].cp);
					p = q + len;
					matched = true;
					break;
				}
			}

			if (matched)
				continue;
		}

		// not a known reference: if reference-shaped (&name;) pass it
		// through literally (browser behaviour); otherwise emit a bare
		// '&'. decodeEntities is a PURE decoder: escaping is the
		// caller's job (double escaping here corrupts 'A & B').
		{
			char const* r2 = p + 1;
			bool shaped = r2 < end && *r2 != '<' && *r2 != '>' && *r2 != '&'
				&& *r2 != ' ' && *r2 != '\t' && *r2 != '\n' && *r2 != '\r';

			if (shaped)
			{
				char const* q2 = r2;

				while (q2 < end && q2 - r2 < 32
					&& *q2 != ';' && *q2 != '&' && *q2 != '<' && *q2 != '>'
					&& *q2 != ' ' && *q2 != '\t' && *q2 != '\n' && *q2 != '\r')
					++q2;

				if (q2 < end && *q2 == ';')
				{
					out.push_back('&');
					out.append(r2, unsigned(q2 + 1 - r2));
					p = q2 + 1;
					continue;
				}
			}

			out.push_back('&');
			++p;
		}
	}
}

} // namespace html

#endif // _html_encoding_included

// vi:set ts=3 sw=3: