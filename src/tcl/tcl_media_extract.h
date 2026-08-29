// ======================================================================
// Guiding-text media extraction helpers (Tcl/ChessBase layer)
// ======================================================================
// Self-contained, dependency-light helpers used by cmdMediaFiles to pull
// media file references out of ChessBase guiding-text HTML bodies and to
// resolve them to filesystem paths. Kept in a header so they can be unit
// tested without linking the Tcl command layer.
//
// The body contains tags like:
//   <IMG src="CB Light Database.html\CBL_Logo.jpg">
//   CBLink(tag_stream,CB Light Database.html\CBM 126 Aronian - Grischuk.wmv,)
// The `src`/stream value is "<DBName>.html\<filename>" (backslash
// separator); the media files live in the database's sibling
// "<DBName>.html" folder.
//
// Regular games are linked to the tournament reports that carry their
// media via game anchors in the report body (CBM_FORMAT_DESIGN.md §7.6):
//   <A href="javascript:CBLink(tag_game,So,Wesley,Nakamura,Hikaru,
//        Sinquefield Cup 3rd,Saint Louis,2015,6,0,17)">So,W - Nakamura,H 0-1</A>
// i.e. CBLink(tag_game, WhiteLast, WhiteFirst, BlackLast, BlackFirst,
//              Event, Site, Year, Round, [Extra...]).
// ChessBase reports embed a game's media between successive anchors: the
// narrative introduces the game and links it (CBLink(tag_game,…)), then
// places its video/audio links and photos, until the next game's anchor
// closes the section. Each reference therefore attaches to the first anchor
// at-or-after it (right-attachment): refs before the first anchor (report
// header art + the section introducing the first game) attach to the first
// anchored game — a known, bounded approximation: ChessBase's own per-game
// linkage lives in the undecoded .cbm binary region (§5.6).
// ======================================================================

#ifndef _tcl_media_extract_included
#define _tcl_media_extract_included

#include "m_string.h"
#include "m_vector.h"

#include <cstring>

namespace tcl_media {

// One CBLink(tag_game,...) anchor and the media references assigned to it.
struct GuidingTextGameBlock
{
	mstl::string					white;		// White lastname ("Topalov")
	mstl::string					black;		// Black lastname ("Anand")
	mstl::string					event;		// Event as written in the anchor
	mstl::string					site;			// Site as written ("Bilbao")
	unsigned						year;			// Year (0 if absent)
	unsigned						round;		// Round (0 if absent/unknown)
	mstl::vector<mstl::string>	files;		// media filenames assigned to this game
	mstl::vector<int>				types;		// 1=picture 2=audio 3=video 4=stream
};

// One media reference found in a body.
struct GuidingTextMediaRef
{
	unsigned		pos;		// document offset of the reference
	mstl::string	file;	// bare filename (backslash prefix stripped)
	int				type;	// 1=picture 2=audio 3=video 4=stream
};


// Case-insensitive substring search over [from, to); 0 if not found.
inline
char const*
ciSearch(char const* from, char const* to, char const* needle, unsigned needleLen)
{
	if (needleLen == 0 || unsigned(to - from) < needleLen)
		return 0;
	char const* last = to - needleLen;
	for (char const* p = from; p <= last; ++p)
	{
		unsigned k = 0;
		while (k < needleLen && (p[k]|0x20) == (needle[k]|0x20))
			++k;
		if (k == needleLen)
			return p;
	}
	return 0;
}


// Scan the range [from, to) of a ChessBase HTML body and append every media
// reference (IMG src / CBLink(tag_stream,...)/CBLink(tag_audio,...)) to
// `out` in document order. No de-duplication (callers decide).
inline
void
scanGuidingTextMediaRefs(	mstl::string const&			html,
									char const*						from,
									char const*						to,
									mstl::vector<GuidingTextMediaRef>&	out)
{
	char const* p = from;
	char const* end = to;

	// Images: <IMG ... src="..." ...> (case-insensitive, quote variants).
	while (p < end)
	{
		char const* lt = static_cast<char const*>(::memchr(p, '<', end - p));
		if (!lt)
			break;
		bool isImg = (end - lt >= 4)
			&& (lt[1]|0x20) == 'i' && (lt[2]|0x20) == 'm' && (lt[3]|0x20) == 'g';
		if (isImg)
		{
			char const* gt = static_cast<char const*>(::memchr(lt, '>', end - lt));
			if (!gt)
				gt = end;
			char const* src = 0;
			for (char const* q = lt; q + 4 <= gt; ++q)
			{
				if ((q[0]|0x20) == 's' && (q[1]|0x20) == 'r' &&
					(q[2]|0x20) == 'c' && q[3] == '=')
				{
					src = q + 4;
					break;
				}
			}
			if (src)
			{
				while (src < gt && (*src == ' ' || *src == '\t'
							|| *src == '\r' || *src == '\n'))
					++src;
				char quote = 0;
				if (src < gt && (*src == '"' || *src == '\''))
				{
					quote = *src;
					++src;
				}
				char const* valEnd = src;
				while (valEnd < gt)
				{
					if (quote)
					{
						if (*valEnd == quote)
							break;
					}
					else if (*valEnd == ' ' || *valEnd == '\t' || *valEnd == '>')
						break;
					++valEnd;
				}
				if (valEnd > src)
				{
					mstl::string val(src, valEnd - src);
					// Strip a "<DBName>.html\" prefix to the bare filename.
					mstl::string::size_type bs = val.rfind('\\');
					mstl::string filename = (bs != mstl::string::npos)
						? val.substr(bs + 1) : val;
					if (!filename.empty())
					{
						GuidingTextMediaRef ref;
						ref.pos = unsigned(lt - html.c_str());
						ref.file = filename;
						ref.type = 1;
						out.push_back(ref);
					}
				}
			}
			p = gt + 1;
			continue;
		}
		p = lt + 1;
	}

	// CBLink(tag_stream/tag_audio) refs (these are not inside <...> tags);
	// collected first, then merged with the IMG refs into document order.
	mstl::vector<GuidingTextMediaRef> links;
	char const* q = from;
	while (q < end)
	{
		char const* cb = ciSearch(q, end, "cblink(", 7);
		if (!cb)
			break;
		int linkType = -1;
		char const* tl = 0;
		for (char const* r = cb + 7; r + 5 <= end; ++r)
		{
			if ((r[0]|0x20) == 't' && (r[1]|0x20) == 'a' && (r[2]|0x20) == 'g'
					&& r[3] == '_')
			{
				tl = r;
				char const* k = r + 4; // past "tag_"
				bool isStream = (end - k >= 6)
					&& (k[0]|0x20)=='s' && (k[1]|0x20)=='t' && (k[2]|0x20)=='r'
					&& (k[3]|0x20)=='e' && (k[4]|0x20)=='a' && (k[5]|0x20)=='m';
				bool isAudio = (end - k >= 5)
					&& (k[0]|0x20)=='a' && (k[1]|0x20)=='u' && (k[2]|0x20)=='d'
					&& (k[3]|0x20)=='i' && (k[4]|0x20)=='o';
				if (isStream)
					linkType = 4;
				else if (isAudio)
					linkType = 2;
				break;
			}
		}
		if (tl && linkType > 0)
		{
			char const* comma = static_cast<char const*>(::memchr(tl, ',', end - tl));
			if (comma)
			{
				char const* valStart = comma + 1;
				char const* valEnd = valStart;
				while (valEnd < end && *valEnd != ',' && *valEnd != ')')
					++valEnd;
				if (valEnd > valStart)
				{
					mstl::string val(valStart, valEnd - valStart);
					mstl::string::size_type bs = val.rfind('\\');
					mstl::string filename = (bs != mstl::string::npos)
						? val.substr(bs + 1) : val;
					if (!filename.empty())
					{
						GuidingTextMediaRef ref;
						ref.pos = unsigned(cb - html.c_str());
						ref.file = filename;
						ref.type = linkType; // 2 audio, 4 stream/video
						links.push_back(ref);
					}
				}
			}
		}
		q = cb + 7;
	}

	// Merge the two ordered streams into document order.
	if (!links.empty())
	{
		unsigned a = 0, b = 0;
		while (a < out.size() && b < links.size())
		{
			if (out[a].pos <= links[b].pos)
				{ ++a; continue; }
			out.insert(out.begin() + a, links[b]);
			++a;
			++b;
		}
		while (b < links.size())
		{
			out.push_back(links[b]);
			++b;
		}
	}
}


inline
unsigned
parseDigits(char const* from, char const* to)
{
	unsigned value = 0;
	bool digits = false;
	for (char const* p = from; p < to; ++p)
	{
		if ('0' <= *p && *p <= '9')
		{
			value = 10*value + (*p - '0');
			digits = true;
		}
		else if (digits && *p != ' ')
		{
			break;
		}
	}
	return digits ? value : 0;
}


// Extract media file references from the range [from, to) of a ChessBase
// guiding-text HTML body: <IMG ... src="..."> (picture, type 1) and
// CBLink(tag_stream,...)/CBLink(tag_audio,...) refs (type 4/2). Appends
// matching filenames to `outFiles` and their types to `outTypes`,
// de-duplicated across the picture and link passes in the documented
// order (pictures first).
inline
void
extractGuidingTextMediaRange(	mstl::string const&			html,
										char const*						from,
										char const*						to,
										mstl::vector<mstl::string>&	outFiles,
										mstl::vector<int>&				outTypes)
{
	mstl::vector<GuidingTextMediaRef> refs;
	scanGuidingTextMediaRefs(html, from, to, refs);

	// Picture pass first (document order), then the link pass;
	// de-duplicate by filename across both.
	for (unsigned i = 0; i < refs.size(); ++i)
	{
		if (refs[i].type != 1)
			continue;
		bool dup = false;
		for (unsigned k = 0; k < outFiles.size(); ++k)
			if (outFiles[k] == refs[i].file) { dup = true; break; }
		if (!dup)
		{
			outFiles.push_back(refs[i].file);
			outTypes.push_back(1);
		}
	}
	for (unsigned i = 0; i < refs.size(); ++i)
	{
		if (refs[i].type == 1)
			continue;
		bool dup = false;
		for (unsigned k = 0; k < outFiles.size(); ++k)
			if (outFiles[k] == refs[i].file) { dup = true; break; }
		if (!dup)
		{
			outFiles.push_back(refs[i].file);
			outTypes.push_back(refs[i].type);
		}
	}
}


// Extract media file references from a whole guiding-text HTML body.
inline
void
extractGuidingTextMedia(mstl::string const& html, mstl::vector<mstl::string>& outFiles,
						mstl::vector<int>& outTypes)
{
	extractGuidingTextMediaRange(
		html, html.c_str(), html.c_str() + html.size(), outFiles, outTypes);
}


// Parse the CBLink(tag_game,...) anchors of a guiding-text HTML body and
// associate the body's media references with the anchored games (nearest
// anchor in document order, see the header comment above).
inline
void
extractGuidingTextGameBlocks(	mstl::string const&						html,
										mstl::vector<GuidingTextGameBlock>&	blocks)
{
	static char const* const TAG = "cblink(tag_game,";
	static unsigned const TAG_LEN = 16;

	char const* begin = html.c_str();
	char const* end = begin + html.size();
	blocks.clear();

	// Pass 1: locate the anchors and parse their fields.
	char const* anchor = begin;
	while ((anchor = ciSearch(anchor, end, TAG, TAG_LEN)) != 0)
	{
		char const* next = ciSearch(anchor + TAG_LEN, end, TAG, TAG_LEN);
		char const* blockEnd = (next ? next : end);
		char const* f = anchor + TAG_LEN;
		char const* rpar = static_cast<char const*>(::memchr(f, ')', blockEnd - f));
		if (!rpar)
			rpar = blockEnd;

		GuidingTextGameBlock block;
		block.year = 0;
		block.round = 0;

		mstl::string fields[10];
		unsigned fieldCount = 0;
		char const* fieldStart = f;
		for (char const* c = f; c <= rpar && fieldCount < 10; ++c)
		{
			if (c == rpar || *c == ',')
			{
				fields[fieldCount].assign(fieldStart, c - fieldStart);
				++fieldCount;
				fieldStart = c + 1;
				if (c == rpar)
					break;
			}
		}

		if (fieldCount >= 8)
		{
			block.white = fields[0];
			block.black = fields[2];
			block.event = fields[4];
			block.site = fields[5];
			block.year = parseDigits(fields[6].c_str(),
											 fields[6].c_str() + fields[6].size());
			block.round = parseDigits(fields[7].c_str(),
											 fields[7].c_str() + fields[7].size());
			blocks.push_back(block);
		}
		anchor = blockEnd;
	}
	if (blocks.empty())
		return;

	// Recompute the anchor positions of the VALID anchors (pass-1 skips
	// anchors with unrecognized field layouts).
	mstl::vector<unsigned> apos;
	anchor = begin;
	unsigned b = 0;
	while ((anchor = ciSearch(anchor, end, TAG, TAG_LEN)) != 0 && b < blocks.size())
	{
		char const* next = ciSearch(anchor + TAG_LEN, end, TAG, TAG_LEN);
		char const* blockEnd = (next ? next : end);
		char const* f = anchor + TAG_LEN;
		char const* rpar = static_cast<char const*>(::memchr(f, ')', blockEnd - f));
		if (!rpar)
			rpar = blockEnd;
		unsigned commas = 1;
		for (char const* c = f; c < rpar; ++c)
			if (*c == ',')
				++commas;
		if (commas >= 8)
		{
			apos.push_back(unsigned(anchor - begin));
			++b;
		}
		anchor = blockEnd;
	}

	// Pass 2: collect every media reference in document order.
	mstl::vector<GuidingTextMediaRef> refs;
	scanGuidingTextMediaRefs(html, begin, end, refs);

	// Pass 3: attach each reference to its owning section: the last anchor
	// at-or-before the reference opens the section that carries the media
	// ("…can start the video of Daniel King: <A…CBLink(tag_stream,…)") and
	// the next anchor closes it. Refs before the first anchor (report
	// header art + the section introducing the first game) attach to the
	// first anchored game.
	for (unsigned i = 0; i < refs.size(); ++i)
	{
		unsigned pos = refs[i].pos;
		unsigned best = 0;
		bool found = false;
		for (unsigned k = 0; k < apos.size(); ++k)
		{
			if (apos[k] <= pos)
			{
				best = k;   // keep the latest anchor not after the reference
				found = true;
			}
		}
		if (!found)
			best = 0;      // refs before the first anchor: first anchored game
		// De-duplicate per block (first occurrence in document order wins).
		bool dup = false;
		for (unsigned k = 0; k < blocks[best].files.size(); ++k)
			if (blocks[best].files[k] == refs[i].file) { dup = true; break; }
		if (dup)
			continue;
		blocks[best].files.push_back(refs[i].file);
		blocks[best].types.push_back(refs[i].type);
	}
}


// Resolve a guiding-text media filename to "<dbdir>/<DBName>.html/<filename>".
// `database` is the database path (with or without an extension). The
// extension is replaced by ".html" to form the sibling media folder; the
// database path's directory is preserved (so an absolute or relative-with-dir
// database yields a fully-qualified media path). No extra prefixing is
// applied — `base + ".html"` already carries the directory.
inline
mstl::string
resolveGuidingTextPath(mstl::string const& database, mstl::string const& filename)
{
	mstl::string base(database);
	mstl::string::size_type dot = base.rfind('.');
	if (dot != mstl::string::npos)
		base.resize(dot);
	mstl::string htmlDir(base + ".html");
	return htmlDir + "/" + filename;
}

} // namespace tcl_media

#endif // _tcl_media_extract_included