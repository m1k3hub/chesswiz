// ======================================================================
// cbh_media.cpp — ChessBase .cbm (media) companion file parser
// ======================================================================
// See cbh_media.h for the reverse-engineered layout. This parser is
// defensive: a missing/corrupt .cbm never prevents database access.
// ======================================================================

#include "cbh_media.h"

#include "m_fstream.h"
#include "m_string.h"
#include "m_vector.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace db { namespace cbh {

namespace {

inline
uint32_t
leU32(unsigned char const* p)
{
	return uint32_t(p[0]) | (uint32_t(p[1]) << 8)
	     | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}

} // namespace

uint32_t
MediaTable::readU32LE(unsigned char const* p)
{
	return leU32(p);
}

unsigned
MediaTable::readLine(unsigned char const* rec, unsigned limit, unsigned pos, char* buf, unsigned bufSize)
{
	unsigned len = 0;
	while (pos < limit && rec[pos] != '\n' && len + 1 < bufSize)
		buf[len++] = rec[pos++];
	buf[len] = '\0';
	return len;
}


MediaTable::MediaTable()
	:m_fileCount(0)
	,m_isOpen(false)
	,m_linkageDecoded(false)
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
MediaTable::entryCount() const
{
	return m_bags.size();
}


unsigned
MediaTable::fileCount() const
{
	return m_fileCount;
}

void
MediaTable::collectManifest(mstl::vector<mstl::string>& out) const
{
	for (unsigned i = 0; i < m_bags.size(); ++i)
		for (unsigned f = 0; f < m_bags[i].files.size(); ++f)
			out.push_back(m_bags[i].files[f]);
}


MediaTable::MediaType
MediaTable::classifyFile(mstl::string const& filename)
{
	// Case-insensitive extension check. Returns Media_None if unrecognized.
	char const		*dot = nullptr;
	char const	*fn	= filename.c_str();
	for (char const* p = fn; *p; ++p)
		if (*p == '.') dot = p;
	if (!dot)
		return Media_None;

	char const* ext = dot + 1;

	// Match a few known lowercase extensions.
	if (::strcmp(ext, "jpg") == 0 || ::strcmp(ext, "jpeg") == 0
		|| ::strcmp(ext, "JPG") == 0 || ::strcmp(ext, "JPEG") == 0
		|| ::strcmp(ext, "bmp") == 0 || ::strcmp(ext, "BMP") == 0
		|| ::strcmp(ext, "gif") == 0 || ::strcmp(ext, "GIF") == 0
		|| ::strcmp(ext, "png") == 0 || ::strcmp(ext, "PNG") == 0)
	{
		return Media_Picture;
	}
	if (::strcmp(ext, "wmv") == 0 || ::strcmp(ext, "WMV") == 0
		|| ::strcmp(ext, "avi") == 0 || ::strcmp(ext, "AVI") == 0
		|| ::strcmp(ext, "mp4") == 0 || ::strcmp(ext, "MP4") == 0
		|| ::strcmp(ext, "mpg") == 0 || ::strcmp(ext, "MPG") == 0
		|| ::strcmp(ext, "mpeg") == 0 || ::strcmp(ext, "MPEG") == 0)
	{
		return Media_Video;
	}
	if (::strcmp(ext, "mp3") == 0 || ::strcmp(ext, "MP3") == 0
		|| ::strcmp(ext, "wav") == 0 || ::strcmp(ext, "WAV") == 0
		|| ::strcmp(ext, "ogg") == 0 || ::strcmp(ext, "OGG") == 0)
	{
		return Media_Audio;
	}
	return Media_None;
}


void
MediaTable::collectMediaFiles(mstl::vector<MediaEntry>& out) const
{
	for (unsigned i = 0; i < m_bags.size(); ++i)
	{
		Bag const& b = m_bags[i];
		for (unsigned f = 0; f < b.files.size(); ++f)
		{
			MediaEntry e;
			e.filename = b.files[f];
			e.type	 = classifyFile(b.files[f]);
			e.bagIndex = i;
			out.push_back(e);
		}
	}
}


unsigned
MediaTable::mediaFlags(unsigned /*gameIndex*/) const
{
	// The .cbm does not encode a direct per-game linkage; per-game media
	// type is read from the CBH game index by the codec. See cbh_media.h.
	return Media_None;
}


bool
MediaTable::hasMedia(unsigned /*gameIndex*/) const
{
	// See mediaFlags(): per-game media is determined from the CBH index.
	return false;
}


bool
MediaTable::isLinkageDecoded() const
{
	// The bag->game offset table is stored raw (see Bag::offsets) but its
	// semantics are not yet reverse-engineered, so it cannot be turned
	// into a per-game mapping. This flag flips to true once that decoding
	// is implemented.
	return m_linkageDecoded;
}


void
MediaTable::clear()
{
	m_bags.clear();
	m_fileCount = 0;
	m_isOpen = false;
	m_linkageDecoded = false;
	m_header = Header();
}


bool
MediaTable::parseHeader(unsigned char const* data, unsigned size)
{
	// The header is 7 little-endian u32 fields = 28 bytes. Some files add a
	// 4-byte trailer (making 32); the 28-byte form is accepted as a fallback.
	if (size < 28)
		return false;

	m_header.version		= leU32(data + 0);
	m_header.recordSize		= leU32(data + 4);
	m_header.numRecords		= leU32(data + 8);
	m_header.firstDeleted	= leU32(data + 12);
	m_header.field16		= leU32(data + 16);
	m_header.field20		= leU32(data + 20);
	m_header.reserved		= leU32(data + 24);

	// Version validation: only version 1 is known/observed. An unknown
	// version is treated as "not a .cbm we understand" (graceful skip —
	// the database still opens, just without media metadata).
	if (m_header.version != 1)
		return false;

	// Empty/sentinel handling. Any of these means "no media records":
	//   numRecords == 0           : genuinely empty
	//   numRecords == 0xFFFFFFFF  : "none" sentinel (same idiom as
	//                              firstDeleted == 0xFFFFFFFF)
	//   recordSize == 0           : no record slab
	//   recordSize == 0xFFFFFFFF : empty-stub sentinel (observed on some
	//                              databases with no media)
	if (   m_header.numRecords  == 0
		|| m_header.numRecords  == 0xFFFFFFFFu
		|| m_header.recordSize == 0
		|| m_header.recordSize == 0xFFFFFFFFu)
	{
		m_header.numRecords = 0; // no records to parse
		return true;             // valid empty media database
	}

	// Sanity bounds (the fixture uses 1024-byte records; allow some range).
	if (m_header.numRecords > 10000000 || m_header.recordSize > 65536)
		return false;

	return true;
}


bool
MediaTable::parseRecord(unsigned char const* rec, unsigned recSize, unsigned recordIndex)
{
	if (recSize < 8)
		return false;

	Bag bag;
	bag.recordIndex = recordIndex;

	// Marker validation: every media bag begins with the 0xFFFFFFFF marker.
	// A record without it is not a valid bag (corrupt or unrecognized slot);
	// skip it rather than poisoning the table.
	bag.marker   = leU32(rec + 0);
	bag.markerOk = (bag.marker == 0xFFFFFFFFu);
	if (!bag.markerOk)
		return false;

	bag.value = leU32(rec + 4); // ofs 4 value (1 normal, 15 special)

	// Find the TEXT manifest region: from offset 8 up to the first byte that
	// is neither a printable ASCII char nor '\n'. A control/null byte (or the
	// first byte of the binary linkage region) terminates it. Manifest
	// filenames observed so far are ASCII (.jpg/.gif/.bmp/.wmv); non-ASCII
	// filenames are not handled and would truncate the region early.
	unsigned textEnd = 8;
	while (textEnd < recSize
		&& ((rec[textEnd] >= 0x20 && rec[textEnd] < 0x7f) || rec[textEnd] == '\n'))
		++textEnd;

	unsigned pos = 8;
	if (pos + 10 <= textEnd && ::memcmp(rec + pos, "FilesUsed\n", 10) == 0)
	{
		bag.isFilesUsed = true;
		pos += 10;

		// Read the count line defensively (it is ADVISORY: a bag frequently
		// lists MORE files than <count>, so we do not bound on it — we read
		// every remaining line in the text region).
		char line[256];
		unsigned llen = readLine(rec, textEnd, pos, line, sizeof(line));
		pos += llen + 1; // skip the count line + its '\n'

		char* endp = nullptr;
		unsigned long parsed = ::strtoul(line, &endp, 10);
		if (endp != line && parsed <= 1000000ul)
			bag.declaredCount = unsigned(parsed); // diagnostic only

		// Read ALL remaining newline-terminated lines in the text region.
		// readLine is bounded by textEnd, so this cannot run past the region
		// or loop forever. Skip empty/whitespace-only lines.
		while (pos < textEnd)
		{
			llen = readLine(rec, textEnd, pos, line, sizeof(line));
			pos += llen + 1;
			if (line[0] != '\0' && line[0] != ' ')
				bag.files.push_back(mstl::string(line));
		}
		m_fileCount += bag.files.size();
	}
	else
	{
		// Non-FilesUsed bag: capture the leading printable run as text.
		for (unsigned p = pos; p < textEnd; ++p)
			bag.textRun.append(char(rec[p]));
		pos = textEnd;
	}

	// BINARY linkage region = [textEnd, recSize), skipping leading null
	// padding. These 4-byte little-endian values map each bag to the
	// games/annotations referencing it, but the semantics are NOT yet
	// reverse-engineered (values do not map cleanly into this DB's .cbg/.cba),
	// so they are stored raw for tooling/dump only.
	unsigned bstart = textEnd;
	while (bstart < recSize && rec[bstart] == 0)
		++bstart;
	for (unsigned p = bstart; p + 4 <= recSize; p += 4)
		bag.offsets.push_back(leU32(rec + p));

	m_bags.push_back(bag);
	return true;
}


bool
MediaTable::read(mstl::string const& rootname, util::Progress& /*progress*/)
{
	mstl::string filename(rootname + ".cbm");

	clear();

	// Optional file — silently skip if absent.
	if (!mstl::ifstream(filename, mstl::ios_base::in | mstl::ios_base::binary))
		return false;

	// read() is documented "Never throws". Guard every step that can throw
	// (allocation, stream ops) so a corrupt/hostile/unseekable .cbm degrades
	// to a clean return-false instead of propagating an exception.
	try
	{
		mstl::ifstream strm(filename, mstl::ios_base::in | mstl::ios_base::binary);
		if (!strm)
			return false;

		strm.seekg(0, mstl::ios_base::end);
		uint64_t fileSize = strm.tellg();
		strm.seekg(0, mstl::ios_base::beg);

		// tellg() returns uint64_t; on failure (unseekable pipe, etc.) mstl
		// throws ios_base::failure (caught below) or yields a bogus value.
		// The size cap rejects bogus/huge values and bounds the allocation.
		static uint64_t const MaxFileSize = 256ull * 1024 * 1024; // 256 MiB
		if (fileSize > MaxFileSize)
			return false; // too large / bad tellg — refuse to slurp
		// 256 MiB also fits in a 32-bit size_t, so the vector/read casts below
		// cannot truncate.

		if (fileSize < 28)
			return false; // too small for a (28-byte) header

		mstl::vector<unsigned char> data((size_t)fileSize);
		if (!strm.read(reinterpret_cast<char*>(data.data()), (size_t)fileSize))
			return false;
		strm.close();

		if (!parseHeader(data.data(), unsigned(fileSize)))
			return false;

		if (m_header.numRecords == 0)
		{
			m_isOpen = true; // empty media database (stub)
			return true;
		}

		// Determine the header size: the canonical layout is 32 bytes, but some
		// files use a 28-byte header (no 4-byte trailer). Pick the one that makes
		// the record slab fit the file exactly; otherwise default to 32 and parse
		// as many records as fit (lenient on trailing/missing bytes — a
		// truncated file yields the records that survived, not a hard failure).
		unsigned headerSize = 32;
		uint64_t slab32 = 32 + uint64_t(m_header.numRecords) * m_header.recordSize;
		uint64_t slab28 = 28 + uint64_t(m_header.numRecords) * m_header.recordSize;
		if (slab32 != fileSize && slab28 == fileSize)
			headerSize = 28;

		unsigned n = m_header.numRecords;
		for (unsigned i = 0; i < n; ++i)
		{
			uint64_t off = headerSize + uint64_t(i) * m_header.recordSize;
			if (off + m_header.recordSize > fileSize)
				break; // truncated — stop gracefully

			parseRecord(data.data() + off, m_header.recordSize, i);
		}

		m_isOpen = true;
		return true;
	}
	catch (...)
	{
		// Never let an allocation/stream/string failure escape: the .cbm is
		// optional enrichment, so drop it and report "not parsed".
		clear();
		return false;
	}
}


void
MediaTable::dump(unsigned maxRecords) const
{
	::printf("=== MediaTable dump (%u bags, %u files) ===\n", unsigned(m_bags.size()), m_fileCount);
	::printf("Header: version=%u recordSize=%u numRecords=%u firstDeleted=0x%08x field16=%u field20=0x%08x\n",
				m_header.version, m_header.recordSize, m_header.numRecords,
				m_header.firstDeleted, m_header.field16, m_header.field20);

	unsigned n = m_bags.size();
	if (n > maxRecords) n = maxRecords;
	for (unsigned i = 0; i < n; ++i)
	{
		Bag const& b = m_bags[i];
		::printf("\n--- Bag %u (record %u, marker=0x%08x%s, value=%u) ---\n",
				i, b.recordIndex, b.marker, (b.markerOk ? " (ok)" : " (BAD)"), b.value);
		if (b.isFilesUsed)
		{
			::printf("  FilesUsed: declaredCount=%u actual=%u file(s)\n",
						b.declaredCount, unsigned(b.files.size()));
			for (unsigned f = 0; f < b.files.size() && f < 12; ++f)
				::printf("    [%u] %s\n", f, b.files[f].c_str());
			if (b.files.size() > 12)
				::printf("    ... (%u more)\n", unsigned(b.files.size()) - 12);
		}
		else
		{
			::printf("  text run: \"%s\"\n", b.textRun.c_str());
		}
		::printf("  offsets: %u entries; first:", unsigned(b.offsets.size()));
		for (unsigned k = 0; k < 8 && k < b.offsets.size(); ++k)
			::printf(" 0x%08x", b.offsets[k]);
		::printf("\n");
	}
}

}} // namespace db::cbh

// vi:set ts=3 sw=3: