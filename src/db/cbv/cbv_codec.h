// ======================================================================
// CBV Archive Codec — ChessBase Volume container format
// ======================================================================

#ifndef _cbv_codec_included
#define _cbv_codec_included

#include "db_database_codec.h"

#include "m_string.h"

namespace db {

namespace cbv {

class Codec : public DatabaseCodec
{
public:

	Codec();
	~Codec() throw();

	bool isWritable() const override;
	bool encodingFailed() const override;

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
	mstl::string const& defaultEncoding() const override;

	unsigned gameFlags() const override;

	mstl::string const& extension() const override;
	mstl::string const& encoding() const override;
	db::tag::TagSet tagFilter(Section section, TagSet const& tags) const override;

	void doOpen(mstl::string const& encoding) override;
	void doOpen(mstl::string const& rootname, mstl::string const& encoding) override;
	void doOpen(mstl::string const& rootname,
					mstl::string const& originalSuffix,
					mstl::string const& encoding,
					util::Progress& progress) override;
	void reloadDescription(mstl::string const& rootname) override;
	void reloadNamebases(mstl::string const& rootname,
								mstl::string const& originalSuffix,
								util::Progress& progress) override;

	void close() override;

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

	void reset() override;
	void setEncoding(mstl::string const& encoding) override;

	static bool getAttributes(	mstl::string const& filename,
										int& numGames,
										db::type::ID& type,
										mstl::string* description);
	static void getSuffixes(mstl::string const& filename, StringList& result);

	static bool isCBV(mstl::string const& filename);

private:

	void cleanupTempDir();

	mstl::string	m_tempDir;
	mstl::string	m_extractedRoot;
	DatabaseCodec*	m_innerCodec;
	mstl::string	m_encoding;
};

} // namespace cbv
} // namespace db

#endif // _cbv_codec_included

// vi:set ts=3 sw=3: