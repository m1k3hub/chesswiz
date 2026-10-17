// ======================================================================
// SCM Media Table — scidb-native .scm companion-file parser
// ======================================================================
// The .scm is a scidb-native media manifest that companions a scidb
// native database. It is a UTF-8 TEXT manifest (PGN-ish, line-oriented)
// mapping games (by header fingerprint) to media entries, with payloads
// as ordinary files in a sibling media folder.
//
// Lessons from the ChessBase .cbm RE (docs/CBM_FORMAT_DESIGN.md):
//   - text manifest, not opaque binary (debuggable / diffable / VCS-friendly)
//   - fingerprint-keyed linkage, not position- or offset-keyed
//     (scidb has no stable game id; fingerprints survive reindexing)
//   - external payloads in a sibling folder (no duplication, large-media OK)
//   - defensive parse: missing/corrupt .scm never blocks database access
//
// Format grammar (see docs/SCM_FORMAT_DESIGN.md for the full spec):
//
//   [Database "MyBase"]
//   [MediaDir "MyBase.media"]
//   [Encoding "utf-8"]
//
//   [Media "M01"]
//   Type: picture
//   Path: images/bilbao.jpg
//   Title: "Bilbao 2008: Topalov-Anand"
//
//   [Game "<fingerprint-hex>"]
//   Media: M01, M02
// ======================================================================

#ifndef _scm_media_included
#define _scm_media_included

#include "m_string.h"
#include "m_vector.h"
#include "m_map.h"

#include <cstdint>

namespace util { class Progress; }

namespace db { namespace scm {

class MediaTable
{
public:

	/// Media types. Matches the SCM grammar `Type:` values.
	enum MediaType
	{
		Media_None    = 0,
		Media_Picture = 1,
		Media_Audio   = 2,
		Media_Video   = 3,
		Media_Stream  = 4,
	};

	/// A single media library entry.
	struct Entry
	{
		mstl::string	mediaId;
		MediaType		type;
		mstl::string	path;		///< relative path under media dir, or base64 payload
		mstl::string	title;
		bool			inlineData;

		Entry() : type(Media_None), inlineData(false) {}
	};

	MediaTable();
	~MediaTable() throw();

	/// Open and parse the .scm manifest. Returns false if the file is
	/// missing, unreadable, too large (>16 MiB cap), or unparseable.
	/// Never throws — all failures degrade to a clean return-false.
	bool read(mstl::string const& scmPath, util::Progress& progress);

	/// True once the manifest was successfully parsed.
	bool isOpen() const;

	/// Number of distinct [Media] entries in the library.
	unsigned mediaCount() const;

	/// Number of distinct games with at least one media entry.
	unsigned gameCount() const;

	/// PRIMARY QUERY: given a game header fingerprint, append every media
	/// entry associated with it. Returns an empty vector if the game has
	/// no media or is unknown.
	void mediaFor(uint64_t fingerprint, mstl::vector<Entry>& out) const;

	/// Append every media entry in the library (gallery; no linkage filter).
	void collectAll(mstl::vector<Entry>& out) const;

	/// Resolve an entry's path to an absolute filesystem path (joins the
	/// configured media directory with the relative path). For inline
	/// entries returns the base64 payload string itself.
	mstl::string resolvePath(Entry const& e) const;

	/// Classify a media filename to a MediaType by extension (used as a
	/// fallback when the manifest's `Type:` field is absent).
	static MediaType classifyFile(mstl::string const& filename);

	/// Compute the normalized-header fingerprint: FNV-1a-64 of
	/// "white|black|event|date|round|result" (lower-cased, trimmed).
	/// Primary linkage key for [Game HEX]; stable across reindexing
	/// because scidb has no stable game id.
	static uint64_t fingerprint(mstl::string const& white,
							   mstl::string const& black,
							   mstl::string const& event,
							   mstl::string const& date,
							   unsigned round,
							   unsigned result);

	void clear();

	/// Dump the parsed manifest to stdout (RE / debug aid).
	void dump() const;

private:

	/// mediaId -> Entry. The library.
	typedef mstl::map<mstl::string, Entry> Library;
	/// fingerprint -> list of media-id handles.
	typedef mstl::map<uint64_t, mstl::vector<mstl::string> > Linkage;

	Library				m_library;
	Linkage				m_linkage;
	mstl::string			m_mediaDir;		///< payload folder (relative to .scm dir)
	mstl::string			m_databaseRoot;	///< [Database] advisory
	unsigned			m_gameCount;	///< distinct games with >= 1 media entry
	bool				m_isOpen;
};

}} // namespace db::scm

#endif // _scm_media_included

// vi:set ts=3 sw=3:
