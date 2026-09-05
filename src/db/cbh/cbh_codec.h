// ======================================================================
// Author : $Author$
// Version: $Revision: 1452 $
// Date   : $Date: 2017-12-08 08:37:59 -0500 (Fri, 08 Dec 2017) $
// Url    : $URL$
// ======================================================================

// ======================================================================
//    _/|            __
//   // o\         /    )           ,        /    /
//   || ._)    ----\---------__----------__-/----/__-
//   //__\          \      /   '  /    /   /    /   )
//   )___(     _(____/____(___ __/____(___/____(___/_
// ======================================================================

// ======================================================================
// Copyright: (C) 2009-2013 Gregor Cramer
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#ifndef _cbh_codec_included
#define _cbh_codec_included

#include "db_database_codec.h"
#include "db_move_node.h"
#include "db_date.h"
#include "cbh_media.h"
#include "scm/scm_media.h"

#include "sys_mutex.h"

#include "nsUniversalDetector.h"

#include "m_fstream.h"
#include "m_map.h"
#include "m_vector.h"
#include "m_chunk_allocator.h"
#include "m_fixed_size_allocator.h"

namespace sys  { namespace utf8 { class Codec; }; };
namespace mstl { class fstream; }
namespace util { class ByteStream; };

namespace db {

class NamebaseEntry;
class NamebaseEvent;
class NamebasePlayer;
class TagSet;
class GameInfo;
class Date;

namespace cbv { class Codec; }

namespace cbh {

class Codec : public DatabaseCodec, public nsUniversalDetector
{
public:

	Codec();
	~Codec() throw();

	bool isWritable() const override;
	bool encodingFailed() const override;

	/// Optional scidb media manifest (.scm) loaded for this database.
	/// Returns nullptr if no .scm companion is present. Owned by the codec.
	scm::MediaTable const* scmMediaTable() const override;

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
	void readScmMedia(mstl::string const& rootname); ///< load optional <rootname>.scm media manifest (non-fatal)

	void close() override;
	void sync() override;

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
	void setWritable() override;

	void save(mstl::string const& rootname, unsigned start, util::Progress& progress) override;
	void attach(mstl::string const& rootname, util::Progress& progress) override;
	void update(mstl::string const& rootname, unsigned index, bool updateNamebase) override;
	void updateHeader(mstl::string const& rootname) override;

	unsigned putGame(util::ByteStream const& strm) override;
	unsigned putGame(util::ByteStream const& strm,
						unsigned prevOffset,
						unsigned prevRecordLength) override;
	util::ByteStream getGame(GameInfo const& info) override;
	util::ByteStream getGame(GameInfo const& info, ::util::BlockFileReader* reader) override;

	void writeNamebases(mstl::ostream& stream, util::Progress& progress) override;

	db::Consumer* getConsumer(format::Type srcFormat) override;

	static bool getAttributes(	mstl::string const& filename,
										int& numGames,
										db::type::ID& type,
										mstl::string* description);
	static void getSuffixes(mstl::string const& filename, StringList& result);

	struct Tournament
	{
		Tournament();
		Tournament(Byte cat, Byte nrounds);

		Byte category;
		Byte rounds;
	}
	__attribute__((packed));

	save::State addGame(util::ByteStream& gameData,
							util::ByteStream& annotationData,
							TagSet const& tags,
							db::Consumer& consumer);

private:

	friend class Consumer;
	friend class cbv::Codec;

	class Source;

	struct Team
	{
		mstl::string	title;
		country::Code	nation;
	};

	typedef mstl::map<uint32_t,NamebaseEntry*>			BaseMap;
	typedef mstl::map<uint32_t,uint32_t>					AnnotationMap;
	typedef mstl::vector<Source*>								SourceMap;
	typedef mstl::map<NamebaseEvent const*,Tournament>	TournamentMap;
	typedef mstl::chunk_allocator<NamebaseEvent>			Allocator;
	typedef mstl::vector<Team*>								TeamBase;
	typedef mstl::map<GameInfo const*,unsigned>			GameIndexLookup;
	typedef mstl::fixed_size_allocator<db::MoveNode>	MoveNodeAllocator;

	void startDecoding(	util::ByteStream& gameStream,
								util::ByteStream* annotationStream,
								GameInfo const& info,
								bool& isChess960);
	void decodeIndex(util::ByteStream& strm, GameInfo& info);
	void decodeGuidingTextIndex(util::ByteStream& strm, GameInfo& info);
	void decodeGuidingTextBody(GameInfo const& info, mstl::string& title, mstl::string& body);

	unsigned readHeader(mstl::string const& rootname);

	void readIniData(mstl::string const& rootname);
	void readPlayerData(mstl::string const& rootname, util::Progress& progress);
	void readTournamentData(mstl::string const& rootname, util::Progress& progress);
	void readAnnotatorData(mstl::string const& rootname, util::Progress& progress);
	void readSourceData(mstl::string const& rootname, util::Progress& progress);
	void readTeamData(mstl::string const& rootname, util::Progress& progress);
	void readMediaData(mstl::string const& rootname, util::Progress& progress);
	void readIndexData(mstl::string const& rootname, util::Progress& progress);
	void reloadPlayerData(mstl::string const& rootname, util::Progress& progress);
	void reloadTournamentData(mstl::string const& rootname, util::Progress& progress);
	void reloadAnnotatorData(mstl::string const& rootname, util::Progress& progress);
	void reloadSourceData(mstl::string const& rootname, util::Progress& progress);
	void reloadTeamData(mstl::string const& rootname, util::Progress& progress);
	void reloadIndexData(mstl::string const& rootname, util::Progress& progress);
	void preloadPlayerData(mstl::string const& rootname, util::Progress& progress);
	void preloadTournamentData(mstl::string const& rootname, util::Progress& progress);
	void preloadAnnotatorData(mstl::string const& rootname, util::Progress& progress);

	// Write support methods
	void writePlayerData(mstl::string const& rootname, util::Progress& progress);
	void writeTournamentData(mstl::string const& rootname, util::Progress& progress);
	void writeAnnotatorData(mstl::string const& rootname, util::Progress& progress);
	void writeSourceData(mstl::string const& rootname, util::Progress& progress);
	void writeTeamData(mstl::string const& rootname, util::Progress& progress);
	void writeIndexData(mstl::string const& rootname, util::Progress& progress);
	void writeIndexEntry(GameInfo const& info, unsigned index, util::ByteStream& strm);
	void writeIniData(mstl::string const& rootname);

	void setupForWriting(mstl::string const& rootname);

	void addSourceTags(TagSet& tags, unsigned index);
	void addEventTags(TagSet& tags, GameInfo const& info);

	NamebasePlayer* getPlayer(uint32_t ref);
	NamebaseEvent* getEvent(uint32_t ref);
	NamebaseEntry* getAnnotator(uint32_t ref);
	Source* getSource(uint32_t ref);

	void addTeamTags(TagSet& tags, GameInfo const& info);
	void mapPlayerName(mstl::string& str);
	void toUtf8(mstl::string& str);

	void Report(char const* charset) override;

	static void readIniData(mstl::fstream& strm,
									sys::utf8::Codec& codec,
									db::type::ID& type,
									mstl::string& title);

	sys::utf8::Codec*	m_codec;
	mstl::fstream		m_gameStream;
	mstl::fstream		m_annotationStream;
	mstl::fstream		m_teamStream;
	unsigned				m_teamRecords;
	unsigned				m_teamRecordSize;
	AnnotationMap		m_annotationMap;
	BaseMap				m_playerMap;
	BaseMap				m_eventMap;
	BaseMap				m_annotatorMap;
	SourceMap			m_sourceMap;
	BaseMap				m_sourceMap2;
	TournamentMap		m_tournamentMap;
	TeamBase				m_teamBase;
	GameIndexLookup	m_gameIndexLookup;
	MediaTable			m_mediaTable;
	scm::MediaTable	m_scmMedia;		///< optional scidb media manifest (.scm)
	mstl::string		m_encoding;
	Allocator			m_allocator;
	Namebase				m_sourceBase;
	NamebaseEvent*		m_illegalEvent;
	NamebasePlayer*	m_illegalPlayer;
	unsigned				m_numGames;
	bool					m_highQuality;
	MoveNodeAllocator	m_moveNodeAllocator;
	sys::Mutex			m_mutex;

	// Write support
	mstl::string			m_rootname;
	bool					m_isWritable;
	unsigned				m_nextGameOffset;
	unsigned				m_nextAnnotationOffset;
	mstl::fstream		m_namebaseStream;
	mstl::fstream		m_indexStream;
};

} // namespace cbh
} // namespace db

namespace mstl {

template <typename T> struct is_movable;

template <>
struct is_movable<::db::cbh::Codec::Tournament> { enum { value = 1 }; };

}

#endif // _cbh_codec_included

// vi:set ts=3 sw=3:
