// ======================================================================
// CB2 (ChessBase 17+ "2CBH") Database Codec — read-only.
//
// See docs/2CBH_FORMAT_DESIGN.md for the format specification.
// ======================================================================

#ifndef _cb2_codec_included
#define _cb2_codec_included

#include "db_database_codec.h"
#include "db_consumer.h"
#include "2cbh_annotations.h"
#include "db_date.h"

#include "m_fstream.h"
#include "m_map.h"
#include "m_string.h"
#include "m_vector.h"

namespace sys { namespace utf8 { class Codec; }; };

namespace sys { namespace utf8 { class Codec; }; };

namespace db {

namespace cb2 {

/// Feed one raw .2cbg game payload (a type-1 record's data) into a
/// consumer: mainline + RAV variations + .2cba comments, in PGN order.
/// Thin public wrapper over the codec-internal walkGame so the
/// standalone 2cbh2pgn tool shares the codec's variation walk instead
/// of duplicating it.  Returns false on desync (the caller should skip
/// the game).
bool walkGameRaw(	Consumer& consumer,
						unsigned char const* data,
						uint32_t dataSize,
						mstl::vector<CbaItem> const& items,
						bool annotationsOk,
						unsigned& plyCount);


class Codec : public DatabaseCodec
{
public:

	Codec();
	~Codec() throw();

	bool isWritable() const override;
	bool encodingFailed() const override;
	bool usingAsyncReader() const override;

	Format format() const override;

	unsigned maxGameRecordLength() const override;
	unsigned maxGameLength() const override;
	unsigned maxGameCount() const override;
	unsigned maxPlayerCount() const override;
	unsigned maxEventCount() const override;
	unsigned maxSiteCount() const override;
	unsigned maxAnnotatorCount() const override;
	unsigned minYear() const override;
	unsigned maxYear() const override;
	unsigned maxDescriptionLength() const override;
	unsigned gameFlags() const override;
	mstl::string const& defaultEncoding() const override;

	mstl::string const& extension() const override;
	mstl::string const& encoding() const override;
	db::tag::TagSet tagFilter(Section section, TagSet const& tags) const override;

	void setEncoding(mstl::string const& encoding) override;
	void reset() override;
	void close() override;

	void doOpen(mstl::string const& encoding) override;
	void doOpen(mstl::string const& rootname, mstl::string const& encoding) override;
	void doOpen(	mstl::string const& rootname,
						mstl::string const& originalSuffix,
						mstl::string const& encoding,
						util::Progress& progress) override;

	unsigned doDecoding(	::util::BlockFileReader* reader,
								GameInfo const& info,
								uint16_t* line,
								unsigned length,
								Board& startBoard,
								bool useStartBoard) override;
	void doDecoding(GameData& data, GameInfo& info, unsigned gameIndex, mstl::string*) override;
	save::State doDecoding(	db::Consumer& consumer,
									TagSet& tags,
									GameInfo const& info,
									unsigned gameIndex) override;

	static bool getAttributes(	mstl::string const& filename,
										int& numGames,
										db::type::ID& type,
										mstl::string* description);
	static void getSuffixes(mstl::string const& filename, StringList& result);

private:

	unsigned m_numNames() const;

	NamebasePlayer* getPlayer(unsigned id);
	NamebaseEvent* getEvent(unsigned id);

	void applyEcoTag(TagSet& tags, unsigned gameIndex);
	bool loadAnnotationItems(unsigned gameIndex, mstl::vector<CbaItem>& items);

	typedef mstl::map<uint32_t, NamebaseEntry*> BaseMap;

	unsigned			m_numGames;
	BaseMap				m_playerMap;
	BaseMap				m_eventMap;
	NamebasePlayer*	m_illegalPlayer;
	mstl::fstream		m_gameStream;			// .2cbg
	mstl::fstream		m_annotationStream;	// .2cba
	mstl::string			m_encoding;
	mstl::vector<uint32_t>	m_annotationOffsets;	// .2cba record offset per game
	mstl::vector<uint16_t>	m_ecoValues;			// index @0x80 per game
};

} // namespace cb2
} // namespace db

#endif // _cb2_codec_included