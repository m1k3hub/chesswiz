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
// ======================================================================

#ifndef _tcl_media_extract_included
#define _tcl_media_extract_included

#include "m_string.h"
#include "m_vector.h"

#include <cstring>

namespace tcl_media {

// Extract media file references from a ChessBase guiding-text HTML body.
// Appends matching filenames to `outFiles` and their types to `outTypes`
// (type: 1=picture 2=audio 3=video 4=stream, matching scm::MediaTable).
// De-duplicates by filename across both passes.
inline
void
extractGuidingTextMedia(mstl::string const& html, mstl::vector<mstl::string>& outFiles,
						mstl::vector<int>& outTypes)
{
	// Scan for <IMG ... src="..." ...> (case-insensitive) and
	// CBLink(tag_stream,...) references.
	char const* p = html.c_str();
	char const* end = p + html.size();
	while (p < end)
	{
		// Find the next '<' that starts an IMG tag or a CBLink( call.
		char const* lt = static_cast<char const*>(::memchr(p, '<', end - p));
		if (!lt)
			break;
		// Check for "<IMG" (case-insensitive).
		bool isImg = false;
		if (end - lt >= 4)
		{
			char c0 = lt[1], c1 = lt[2], c2 = lt[3];
			if ((c0 == 'I' || c0 == 'i') && (c1 == 'M' || c1 == 'm') && (c2 == 'G' || c2 == 'g'))
				isImg = true;
		}
		if (isImg)
		{
			// Find src="..." within this tag (up to the closing '>').
			char const* gt = static_cast<char const*>(::memchr(lt, '>', end - lt));
			if (!gt)
				gt = end;
			char const* s = lt;
			while (s < gt)
			{
				char const* src = nullptr;
				// case-insensitive search for "src="
				for (char const* q = s; q + 4 <= gt; ++q)
				{
					if ((q[0] == 's' || q[0] == 'S') && (q[1] == 'r' || q[1] == 'R') &&
						(q[2] == 'c' || q[2] == 'C') && q[3] == '=')
					{
						src = q + 4;
						break;
					}
				}
				if (!src)
					break;
				// Skip optional whitespace and quote.
				while (src < gt && (*src == ' ' || *src == '\t' || *src == '\r' || *src == '\n'))
					++src;
				char quote = 0;
				if (src < gt && (*src == '"' || *src == '\''))
				{
					quote = *src;
					++src;
				}
				char const* valStart = src;
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
				if (valEnd > valStart)
				{
					mstl::string val(valStart, valEnd - valStart);
					// Strip the "<DBName>.html\" prefix to get the bare filename.
					mstl::string::size_type bs = val.rfind('\\');
					mstl::string filename = (bs != mstl::string::npos) ? val.substr(bs + 1) : val;
					if (!filename.empty())
					{
						// De-dup.
						bool dup = false;
						for (unsigned i = 0; i < outFiles.size(); ++i)
							if (outFiles[i] == filename) { dup = true; break; }
						if (!dup)
						{
							outFiles.push_back(filename);
							outTypes.push_back(1); // picture
						}
					}
				}
				s = valEnd;
				if (s < gt && *s == quote)
					++s;
			}
			p = gt + 1;
			continue;
		}
		// Not an IMG tag — advance past this '<'.
		p = lt + 1;
	}
	// Second pass: find CBLink(tag_stream, ...) references (these are not
	// inside <...> tags).
	{
		char const* q = html.c_str();
		while (q < end)
		{
			char const* cb = nullptr;
			for (char const* r = q; r + 7 <= end; ++r)
			{
				if ((r[0] == 'C' || r[0] == 'c') && (r[1] == 'B' || r[1] == 'b') &&
					(r[2] == 'L' || r[2] == 'l') && (r[3] == 'i' || r[3] == 'I') &&
					(r[4] == 'n' || r[4] == 'N') && (r[5] == 'k' || r[5] == 'K') &&
					r[6] == '(')
				{
					cb = r;
					break;
				}
			}
			if (!cb)
				break;
			// Detect a CBLink tag: tag_stream (video, type 4), tag_audio (audio,
			// type 2) or tag_image (ignored — pictures come via <IMG>).
			int linkType = -1; // -1 = ignore (unknown/tag_image)
			char const* tl = nullptr; // token location
			for (char const* r = cb + 7; r + 5 <= end; ++r)
			{
				if ((r[0] == 't' || r[0] == 'T') && (r[1] == 'a' || r[1] == 'A') &&
					(r[2] == 'g' || r[2] == 'G') && r[3] == '_')
				{
					tl = r;
					char const* k = r + 4; // past "tag_"
					// Case-insensitive match on "stream"/"audio" (tag_image ignored).
					bool isStream = (end - k >= 6)
						&& (k[0]|0x20)=='s' && (k[1]|0x20)=='t' && (k[2]|0x20)=='r'
						&& (k[3]|0x20)=='e' && (k[4]|0x20)=='a' && (k[5]|0x20)=='m';
					bool isAudio = (end - k >= 5)
						&& (k[0]|0x20)=='a' && (k[1]|0x20)=='u' && (k[2]|0x20)=='d'
						&& (k[3]|0x20)=='i' && (k[4]|0x20)=='o';
					if (isStream) linkType = 4;
					else if (isAudio) linkType = 2;
					else linkType = -1;
					break;
				}
			}
			if (tl && linkType > 0)
			{
				// The media path follows "tag_<kind>," up to the next ','.
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
						mstl::string filename = (bs != mstl::string::npos) ? val.substr(bs + 1) : val;
						if (!filename.empty())
						{
							bool dup = false;
							for (unsigned i = 0; i < outFiles.size(); ++i)
								if (outFiles[i] == filename) { dup = true; break; }
							if (!dup)
							{
								outFiles.push_back(filename);
								outTypes.push_back(linkType); // 2 audio, 4 stream/video
							}
						}
					}
				}
			}
			q = cb + 7;
		}
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