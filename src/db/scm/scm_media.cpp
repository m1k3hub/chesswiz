// ======================================================================
// scm_media.cpp — scidb-native .scm manifest parser
// ======================================================================
// See scm_media.h and docs/formats/SCM_FORMAT_DESIGN.md for the format grammar and
// rationale. Parsing is defensive: any error is non-fatal so a corrupt or
// unexpected .scm never blocks database access (same principle as the
// ChessBase .cbm parser).
// ======================================================================

#include "scm_media.h"

#include "m_fstream.h"
#include "m_string.h"
#include "m_vector.h"

#include <cctype>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace db { namespace scm {

namespace {

// FNV-1a-64 (matching the spec; same algorithm used by authoring + loading).
uint64_t fnv1a64(uint64_t h, char const* s, unsigned n)
{
	for (unsigned i = 0; i < n; ++i)
	{
		h ^= uint64_t(uint8_t(s[i]));
		h *= 0x100000001b3ull;
	}
	return h;
}

// Normalize: ASCII lowercase, trim leading/trailing whitespace.
void normalize(char const* in, unsigned len, mstl::string& out)
{
	out.clear();
	unsigned a = 0;
	while (a < len && (unsigned char)in[a] <= 0x20) ++a;
	unsigned b = len;
	while (b > a && (unsigned char)in[b-1] <= 0x20) --b;
	for (unsigned i = a; i < b; ++i)
	{
		unsigned char c = (unsigned char)in[i];
		out.append(char(c >= 'A' && c <= 'Z' ? c + 32 : c));
	}
}

// Classify a media-type token from the manifest.
MediaTable::MediaType parseTypeToken(char const* s)
{
	struct { char const* name; MediaTable::MediaType t; } table[] = {
		{ "picture",        MediaTable::Media_Picture },
		{ "audio",          MediaTable::Media_Audio   },
		{ "video",          MediaTable::Media_Video   },
		{ "stream",         MediaTable::Media_Stream  },
		{ "inline-picture", MediaTable::Media_Picture },
	};
	for (unsigned i = 0; i < sizeof(table)/sizeof(table[0]); ++i)
		if (std::strcmp(s, table[i].name) == 0) return table[i].t;
	return MediaTable::Media_None;
}

// Trim ASCII whitespace.
void trim(mstl::string& s)
{
	unsigned a = 0;
	while (a < s.size() && (unsigned char)s[a] <= 0x20) ++a;
	unsigned b = s.size();
	while (b > a && (unsigned char)s[b-1] <= 0x20) --b;
	if (a == 0 && b == s.size()) return;
	s = s.substr(a, b - a);
}

// Unquote a "..." token (PGN convention).
bool unquote(mstl::string const& in, mstl::string& out)
{
	unsigned len = in.size();
	if (len >= 2 && in[0] == '"' && in[len-1] == '"')
	{
		out = in.substr(1, len-2);
		return true;
	}
	out = in;
	return false;
}

// Parse a hex uint64 (any length <= 16).
bool parseHexU64(mstl::string const& s, uint64_t& v)
{
	if (s.empty() || s.size() > 16) return false; // reject >16 hex chars (overflow guard)
	v = 0;
	for (unsigned i = 0; i < s.size(); ++i)
	{
		char c = s[i];
		int d = -1;
		if (c >= '0' && c <= '9') d = c - '0';
		else if (c >= 'a' && c <= 'f') d = c - 'a' + 10;
		else if (c >= 'A' && c <= 'F') d = c - 'A' + 10;
		else return false;
		v = (v << 4) | uint64_t(d);
	}
	return true;
}

void splitMediaList(mstl::string const& in, mstl::vector<mstl::string>& out)
{
	unsigned a = 0;
	for (unsigned i = 0; i <= in.size(); ++i)
	{
		if (i == in.size() || in[i] == ',')
		{
			mstl::string tok = in.substr(a, i - a);
			trim(tok);
			if (!tok.empty()) out.push_back(tok);
			a = i + 1;
		}
	}
}

} // namespace


MediaTable::MediaTable()
	:m_isOpen(false)
{
}


MediaTable::~MediaTable() throw()
{
}


bool
MediaTable::isOpen() const
{
	return m_isOpen;
}


unsigned
MediaTable::mediaCount() const
{
	return unsigned(m_library.size());
}


unsigned
MediaTable::gameCount() const
{
	return unsigned(m_gameCount);
}


void
MediaTable::clear()
{
	m_library.clear();
	m_linkage.clear();
	m_mediaDir.clear();
	m_databaseRoot.clear();
	m_gameCount = 0;
	m_isOpen = false;
}


void
MediaTable::collectAll(mstl::vector<Entry>& out) const
{
	for (Library::const_iterator i = m_library.begin(); i != m_library.end(); ++i)
		out.push_back(i->second);
}


void
MediaTable::mediaFor(uint64_t fingerprint, mstl::vector<Entry>& out) const
{
	Linkage::const_iterator it = m_linkage.find(fingerprint);
	if (it == m_linkage.end()) return;
	for (unsigned k = 0; k < it->second.size(); ++k)
	{
		Library::const_iterator e = m_library.find(it->second[k]);
		if (e != m_library.end())
			out.push_back(e->second);
	}
}


mstl::string
MediaTable::resolvePath(Entry const& e) const
{
	if (e.inlineData) return e.path;
	if (e.path.empty()) return mstl::string();
	if (e.path[0] == '/' || e.path[0] == '\\') return e.path;
	if (!m_mediaDir.empty()) return m_mediaDir + "/" + e.path;
	return e.path;
}


MediaTable::MediaType
MediaTable::classifyFile(mstl::string const& filename)
{
	char const* dot = nullptr;
	for (unsigned i = 0; i < filename.size(); ++i)
		if (filename[i] == '.') dot = filename.c_str() + i;
	if (!dot) return Media_None;
	char const* ext = dot + 1;
	auto eq = [&](char const* a){ return std::strcmp(ext,a)==0; };
	if (eq("jpg")||eq("JPG")||eq("jpeg")||eq("JPEG")||eq("bmp")||eq("BMP")
		||eq("gif")||eq("GIF")||eq("png")||eq("PNG")) return Media_Picture;
	if (eq("wmv")||eq("WMV")||eq("avi")||eq("AVI")||eq("mp4")||eq("MP4")
		||eq("mpg")||eq("MPG")||eq("mpeg")||eq("MPEG")) return Media_Video;
	if (eq("mp3")||eq("MP3")||eq("wav")||eq("WAV")||eq("ogg")||eq("OGG")) return Media_Audio;
	if (eq("m3u8")||eq("M3U8")||eq("pls")||eq("PLS")) return Media_Stream;
	return Media_None;
}


uint64_t
MediaTable::fingerprint(mstl::string const& white,
					   mstl::string const& black,
					   mstl::string const& event,
					   mstl::string const& date,
					   unsigned round,
					   unsigned result)
{
	uint64_t h = 0xcbf29ce484222325ull;
	mstl::string buf;
	normalize(white.c_str(), white.size(), buf); h = fnv1a64(h, buf.c_str(), unsigned(buf.size()));
	h = fnv1a64(h, "|", 1);
	normalize(black.c_str(), black.size(), buf); h = fnv1a64(h, buf.c_str(), unsigned(buf.size()));
	h = fnv1a64(h, "|", 1);
	normalize(event.c_str(), event.size(), buf); h = fnv1a64(h, buf.c_str(), unsigned(buf.size()));
	h = fnv1a64(h, "|", 1);
	normalize(date.c_str(),  date.size(),  buf); h = fnv1a64(h, buf.c_str(), unsigned(buf.size()));
	h = fnv1a64(h, "|", 1);
	char tmp[32];
	int rl = std::snprintf(tmp, sizeof(tmp), "%u|%u", round, result);
	if (rl > 0) h = fnv1a64(h, tmp, unsigned(rl));
	return h;
}


namespace {

// Lowercase comparison helper.
bool ieq(mstl::string const& s, char const* lit)
{
	if (s.size() != std::strlen(lit)) return false;
	for (unsigned i = 0; i < s.size(); ++i)
	{
		char a = s[i], b = lit[i];
		if (a >= 'A' && a <= 'Z') a = a + 32;
		if (a != b) return false;
	}
	return true;
}

} // namespace


bool
MediaTable::read(mstl::string const& scmPath, util::Progress& /*progress*/)
{
	clear();

	mstl::ifstream strm(scmPath, mstl::ios_base::in | mstl::ios_base::binary);
	if (!strm) return false;

	strm.seekg(0, mstl::ios_base::end);
	uint64_t fileSize = strm.tellg();
	strm.seekg(0, mstl::ios_base::beg);

	static uint64_t const MaxManifest = 16ull * 1024 * 1024; // 16 MiB
	if (fileSize > MaxManifest) return false;
	if (fileSize < 4) return false;

	mstl::vector<unsigned char> data((size_t)fileSize);
	if (!strm.read(reinterpret_cast<char*>(data.data()), (size_t)fileSize))
		return false;
	strm.close();

	mstl::string text(reinterpret_cast<char const*>(data.data()),
					 reinterpret_cast<char const*>(data.data()) + (size_t)fileSize);

	Entry curEntry;
	bool curEntryOpen = false;
	bool recognized = false;
	mstl::string curGameFp;
	mstl::vector<mstl::string> curGameMedia;
	enum Section { kNone, kMedia, kGame } section = kNone;

	unsigned pos = 0;
	while (pos < text.size())
	{
		unsigned eol = pos;
		while (eol < text.size() && text[eol] != '\n' && text[eol] != '\r')
			++eol;
		mstl::string line = text.substr(pos, eol - pos);
		pos = eol;
		while (pos < text.size() && (text[pos] == '\n' || text[pos] == '\r'))
			++pos;

		// strip leading whitespace + comments
		unsigned hash = 0;
		while (hash < line.size() && (line[hash] == ' ' || line[hash] == '\t')) ++hash;
		if (hash >= line.size() || line[hash] == '#') continue;
		if (hash > 0) line = line.substr(hash);
		trim(line);
		if (line.empty()) continue;

		// Section header [Name "value"] or [Name]
		if (line[0] == '[' && line[line.size()-1] == ']')
		{
			// commit pending
			if (curEntryOpen)
			{
				if (curEntry.type == Media_None)
					curEntry.type = classifyFile(curEntry.path);
				m_library[curEntry.mediaId] = curEntry;
				curEntry = Entry();
				curEntryOpen = false;
			}
			if (!curGameFp.empty())
			{
				uint64_t fp = 0;
				if (parseHexU64(curGameFp, fp))
				{
					mstl::vector<mstl::string>& dst = m_linkage[fp];
					for (unsigned k = 0; k < curGameMedia.size(); ++k)
						dst.push_back(curGameMedia[k]);
				}
				curGameFp.clear();
				curGameMedia.clear();
			}

			mstl::string inside = line.substr(1, line.size() - 2);
			trim(inside);
			unsigned sp = 0;
			while (sp < inside.size() && inside[sp] != ' ' && inside[sp] != '\t') ++sp;
			mstl::string name = inside.substr(0, sp);
			mstl::string rest = inside.substr(sp);
			trim(rest);

			if (ieq(name, "media"))
			{
				recognized = true;
				mstl::string id;
				unquote(rest, id);
				unsigned sp2 = 0;
				while (sp2 < id.size() && id[sp2] != ' ' && id[sp2] != '\t') ++sp2;
				curEntry.mediaId = id.substr(0, sp2);
				trim(curEntry.mediaId);
				curEntryOpen = !curEntry.mediaId.empty();
				section = kMedia;
			}
			else if (ieq(name, "game"))
			{
				recognized = true;
				mstl::string fp;
				unquote(rest, fp);
				unsigned sp2 = 0;
				while (sp2 < fp.size() && fp[sp2] != ' ' && fp[sp2] != '\t') ++sp2;
				curGameFp = fp.substr(0, sp2);
				trim(curGameFp);
				section = kGame;
			}
			else if (ieq(name, "database") || ieq(name, "databasedir"))
			{
				recognized = true;
				unquote(rest, m_databaseRoot);
			}
			else if (ieq(name, "mediadir"))
			{
				recognized = true;
				unquote(rest, m_mediaDir);
			}
			else if (ieq(name, "encoding"))
			{
				recognized = true;
			}
			else
			{
				// unknown section: ignore (forward-compat)
				section = kNone;
			}
			continue;
		}

		// key: value
		unsigned cpos = 0;
		while (cpos < line.size() && line[cpos] != ':' && line[cpos] != ' ' && line[cpos] != '\t')
			++cpos;
		if (cpos >= line.size() || line[cpos] != ':') continue;
		mstl::string key = line.substr(0, cpos);
		mstl::string val = line.substr(cpos + 1);
		trim(key); trim(val);

		if (section == kMedia && curEntryOpen)
		{
			if (ieq(key, "type"))
			{
				curEntry.type = parseTypeToken(val.c_str());
			}
			else if (ieq(key, "path"))
			{
				curEntry.path = val;
				curEntry.inlineData = false;
			}
			else if (ieq(key, "inline"))
			{
				if (val.size() > 7 && ieq(val.substr(0,7), "base64,"))
				{
					curEntry.path = val.substr(7);
					curEntry.inlineData = true;
				}
				else
				{
					curEntry.path = val;
				}
			}
			else if (ieq(key, "title"))
			{
				unquote(val, curEntry.title);
			}
		}
		else if (section == kGame)
		{
			if (ieq(key, "media"))
			{
				splitMediaList(val, curGameMedia);
			}
		}
		// unknown keys ignored (forward-compat)
	}

	// commit trailing
	if (curEntryOpen)
	{
		if (curEntry.type == Media_None)
			curEntry.type = classifyFile(curEntry.path);
		m_library[curEntry.mediaId] = curEntry;
	}
	if (!curGameFp.empty())
	{
		uint64_t fp = 0;
		if (parseHexU64(curGameFp, fp))
		{
			mstl::vector<mstl::string>& dst = m_linkage[fp];
			for (unsigned k = 0; k < curGameMedia.size(); ++k)
				dst.push_back(curGameMedia[k]);
		}
	}

	m_gameCount = 0;
	for (Linkage::const_iterator i = m_linkage.begin(); i != m_linkage.end(); ++i)
		if (!i->second.empty()) ++m_gameCount;

	m_isOpen = recognized || !m_library.empty();
	return m_isOpen;
}


void
MediaTable::dump() const
{
	::printf("=== MediaTable dump (%u media entries, %u game linkages) ===\n",
				unsigned(m_library.size()), m_gameCount);
	if (!m_databaseRoot.empty()) ::printf("Database: %s\n", m_databaseRoot.c_str());
	if (!m_mediaDir.empty())     ::printf("MediaDir: %s\n", m_mediaDir.c_str());
	unsigned n = 0;
	for (Library::const_iterator i = m_library.begin(); i != m_library.end() && n < 20; ++i, ++n)
	{
		::printf("  [%s] type=%u inline=%d path=%s%s%s\n",
				i->second.mediaId.c_str(), unsigned(i->second.type),
				int(i->second.inlineData),
				i->second.inlineData ? "<base64 " : "",
				i->second.path.c_str(),
				i->second.title.empty() ? "" : " title=\"...\"");
	}
	for (Linkage::const_iterator i = m_linkage.begin(); i != m_linkage.end(); ++i)
	{
		::printf("  Game 0x%016llx -> [", (unsigned long long)i->first);
		for (unsigned k = 0; k < i->second.size(); ++k)
			::printf(" %s", i->second[k].c_str());
		::printf(" ]\n");
	}
}

}} // namespace db::scm

// vi:set ts=3 sw=3:
