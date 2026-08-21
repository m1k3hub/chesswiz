// ======================================================================
// CBH Media Table — ChessBase .cbm companion file parser
// ======================================================================
// The .cbm (ChessBase Media) file stores a manifest of media entries
// (images, audio, video clips, stream references) associated with the
// games/guiding-text of a ChessBase database. It is a companion to .cbh.
//
// NOTE: the per-game media *type* (audio/picture/video) is read directly
// from the CBH game index (offsets 39-41 / 18-19 for guiding-text) by
// the codec — see cbh_codec.cpp. The .cbm itself is a media *manifest*
// (which files exist + a binary table linking them back to the
// games/annotations); the bag->game linkage in that binary table is not
// yet reverse-engineered, so mediaFlags()/hasMedia() cannot return
// per-game results from the .cbm alone.
//
// Layout (reverse-engineered and validated end-to-end against a real
// media-rich fixture — "CB Light Database.cbm" (10 bags × 1024 bytes,
// 57 manifest file references, all images present in the database's
// .html folder). See CBM_FORMAT_DESIGN.md §5.5 and probe_cbm.)
//
//   28-byte header (little-endian uint32 fields); some files add a 4-byte
//   trailer making 32 bytes. read() accepts either form (28-byte fallback):
//     ofs  0: version       (1; only known value — validated)
//     ofs  4: recordSize    (1024)
//     ofs  8: numRecords    (number of media "bags"; 0 or 0xFFFFFFFF = empty)
//     ofs 12: firstDeleted  (0xFFFFFFFF = none)
//     ofs 16: field16       (varies; meaning unknown)
//     ofs 20: field20       (varies; likely a checksum/sentinel)
//     ofs 24: reserved      (varies)
//   file size == headerSize + numRecords * recordSize
//     (headerSize = 32 canonical, 28 fallback)
//
//   Each record is a media "bag" of recordSize bytes:
//     ofs 0 (u32): marker  (0xFFFFFFFF — validated; bad markers are skipped)
//     ofs 4 (u32): value   (1 for normal bags; 15 for a special sub-type)
//     ofs 8..textEnd: a TEXT manifest region:
//         "FilesUsed\n<count>\n<file1>\n<file2>\n...\n"
//       <count> is ADVISORY only — a bag frequently lists MORE files than
//       <count> (observed: count=4 with 7 filenames). The parser therefore
//       reads ALL newline-terminated lines in the text region, not just
//       <count>. The text region ends at the first byte that is neither a
//       printable ASCII char nor '\n' (a control/null byte, or the start of
//       the binary linkage region). Manifest filenames observed so far are
//       ASCII (.jpg/.gif/.bmp/.wmv); non-ASCII filenames are not handled.
//     textEnd..recSize: a BINARY linkage region (4-byte little-endian
//       entries) that maps the bag to the games/annotations referencing it.
//       This region is NOT yet reverse-engineered — its 4-byte values do
//       not map cleanly into this database's own .cbg/.cba (some values
//       exceed the file sizes), so they likely index a shared/global media
//       store. Stored raw in Bag::offsets for tooling; isLinkageDecoded()
//       stays false until the per-game mapping is cracked.
//
// Parsing is defensive: any error is non-fatal so a corrupt or unexpected
// .cbm never prevents database access.
// ======================================================================

#ifndef _cbh_media_included
#define _cbh_media_included

#include "m_string.h"
#include "m_vector.h"

#include <cstdint>

namespace util { class Progress; }

namespace db { namespace cbh {

class MediaTable
{
public:

	/// Media types (bitmask), matching CBH index offset 40 flags.
	enum MediaType
	{
		Media_None   = 0,
		Media_Audio  = 1 << 0,
		Media_Picture= 1 << 1,
		Media_Video  = 1 << 2,
		Media_Stream = 1 << 3,
	};

	MediaTable();
	~MediaTable() throw();

	/// Open and parse the .cbm file. Returns false if the file is missing
	/// or unreadable (non-fatal — media is optional). Never throws.
	bool read(mstl::string const& rootname, util::Progress& progress);

	/// True if the .cbm file was found and successfully parsed.
	bool isOpen() const;

	/// Number of media bags (records) in the table.
	unsigned entryCount() const;

	/// Total number of media files referenced across all bags.
	unsigned fileCount() const;

	/// Append every manifest filename (across all bags) to `out`.
	void collectManifest(mstl::vector<mstl::string>& out) const;

	/// A manifest file reference with its classified media type and the
	/// bag that references it. Used by collectMediaFiles().
	struct MediaEntry
	{
		mstl::string	filename;	///< manifest filename (e.g. "CBL_Logo.jpg")
		MediaType		type;		///< classified by extension (see classifyFile)
		unsigned		bagIndex;	///< index of the referencing bag in m_bags

		MediaEntry() :type(Media_None), bagIndex(0) {}
	};

	/// Append every manifest file reference (across all bags) with its
	/// classified media type. This enables a "database media gallery"
	/// (enumerate all media referenced by the .cbm) WITHOUT the
	/// bag->game linkage — image files can be located on disk in the
	/// database's .html folder by the caller.
	void collectMediaFiles(mstl::vector<MediaEntry>& out) const;

	/// Classify a manifest filename to a MediaType by extension.
	static MediaType classifyFile(mstl::string const& filename);

	/// Per-game media type bitmask. NOTE: the .cbm does not encode a
	/// direct per-game linkage (the bag->game offset table is not yet
	/// reverse-engineered); per-game media type is read from the CBH
	/// index by the codec. This therefore always returns Media_None.
	unsigned mediaFlags(unsigned gameIndex) const;

	/// True if the game has any media associated with it. NOTE: same
	/// caveat as mediaFlags(); returns false from the .cbm alone.
	bool hasMedia(unsigned gameIndex) const;

	/// True once the bag->game linkage offset table has been reverse-
	/// engineered and decoded into a usable per-game mapping. Until
	/// then, mediaFlags()/hasMedia() cannot return per-game results
	/// from the .cbm alone (per-game media type comes from the CBH
	/// index). Always false in the current implementation.
	bool isLinkageDecoded() const;

	void clear();

	/// Dump parsed structure to stdout for reverse engineering.
	void dump(unsigned maxRecords = 20) const;

private:

	/// One media "bag" (a 1024-byte record).
	struct Bag
	{
		uint32_t						marker;			///< ofs 0 marker (expected 0xFFFFFFFF)
		uint32_t						value;			///< ofs 4 value (1 normal, 15 special)
		bool							markerOk;	///< marker == 0xFFFFFFFF
		bool							isFilesUsed;	///< bag starts with "FilesUsed\n"
		unsigned						declaredCount;	///< advisory <count> from the manifest (files.size() may exceed it)
		mstl::vector<mstl::string>		files;			///< manifest filenames (ALL lines in the text region)
		mstl::vector<uint32_t>		offsets;		///< binary 4-byte linkage table after the text region
		mstl::string					textRun;		///< printable run for non-FilesUsed bags
		unsigned						recordIndex;	///< position in the .cbm (record number)

		Bag() :marker(0), value(0), markerOk(false), isFilesUsed(false),
				 declaredCount(0), recordIndex(0) {}
	};

	/// 32-byte header.
	struct Header
	{
		uint32_t	version;
		uint32_t	recordSize;
		uint32_t	numRecords;
		uint32_t	firstDeleted;
		uint32_t	field16;
		uint32_t	field20;		///< likely checksum
		uint32_t	reserved;

		Header() :version(0), recordSize(0), numRecords(0),
					 firstDeleted(0), field16(0), field20(0), reserved(0) {}
	};

	static uint32_t readU32LE(unsigned char const* p);
	static unsigned readLine(unsigned char const* rec, unsigned limit,
									 unsigned pos, char* buf, unsigned bufSize);

	Header				m_header;
	mstl::vector<Bag>	m_bags;
	unsigned			m_fileCount;
	bool				m_isOpen;
	bool				m_linkageDecoded;	///< bag->game linkage decoded yet?

	/// Parse the 32-byte header. Returns false on malformed data.
	bool parseHeader(unsigned char const* data, unsigned size);

	/// Parse a single media bag. Returns false if the record looks invalid.
	bool parseRecord(unsigned char const* data, unsigned recSize, unsigned recordIndex);
};

}} // namespace db::cbh

#endif // _cbh_media_included

// vi:set ts=3 sw=3: