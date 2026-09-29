// ======================================================================
// Headless verifier for database maintenance helpers.
// ======================================================================

#include "db/db_board.h"
#include "db/db_board_base.h"
#include "db/db_database.h"
#include "db/db_database_codec.h"
#include "db/db_common.h"
#include "db/db_game.h"
#include "db/db_home_pawns.h"
#include "db/db_maintenance.h"
#include "db/db_pgn_reader.h"
#include "db/db_player_stats.h"
#include "db/db_search.h"
#include "db/db_signature.h"
#include "db/db_exception.h"

#include "db/sci/sci_encoder.h"
#include "db/sci/sci_codec.h"
#include "db/si3/si3_encoder.h"

#include "sys/sys_utf8_codec.h"

#include "util/u_progress.h"
#include "util/u_misc.h"
#include "util/u_byte_stream.h"

#include "mstl/m_sstream.h"
#include "mstl/m_string.h"

#include <tcl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

using namespace db;

namespace tcl { namespace bits { Tcl_Interp* interp = nullptr; } }

namespace {

char const* SamplePgn =
	"[Event \"Duplicate 1\"]\n"
	"[Site \"Test\"]\n"
	"[Date \"2024.01.01\"]\n"
	"[Round \"1\"]\n"
	"[White \"Alpha\"]\n"
	"[Black \"Beta\"]\n"
	"[WhiteElo \"2500\"]\n"
	"[BlackElo \"2400\"]\n"
	"[Result \"1-0\"]\n"
	"[ECO \"C20\"]\n"
	"\n"
	"1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. c3 Nf6 5. d3 d6 1-0\n"
	"\n"
	"[Event \"Duplicate 1\"]\n"
	"[Site \"Test\"]\n"
	"[Date \"2024.01.01\"]\n"
	"[Round \"1\"]\n"
	"[White \"Alpha\"]\n"
	"[Black \"Beta\"]\n"
	"[WhiteElo \"2500\"]\n"
	"[BlackElo \"2400\"]\n"
	"[Result \"1-0\"]\n"
	"[ECO \"C20\"]\n"
	"\n"
	"1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. c3 Nf6 5. d3 d6 1-0\n"
	"\n"
	"[Event \"Unique C20\"]\n"
	"[Site \"Test\"]\n"
	"[Date \"2024.01.03\"]\n"
	"[Round \"1\"]\n"
	"[White \"Gamma\"]\n"
	"[Black \"Delta\"]\n"
	"[WhiteElo \"2300\"]\n"
	"[BlackElo \"2300\"]\n"
	"[Result \"1/2-1/2\"]\n"
	"[ECO \"C20\"]\n"
	"\n"
	"1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. d3 Nf6 5. c3 d6 1/2-1/2\n"
	"\n"
	"[Event \"Unique D00\"]\n"
	"[Site \"Test\"]\n"
	"[Date \"2024.01.04\"]\n"
	"[Round \"1\"]\n"
	"[White \"Epsilon\"]\n"
	"[Black \"Zeta\"]\n"
	"[WhiteElo \"2100\"]\n"
	"[BlackElo \"2200\"]\n"
	"[Result \"0-1\"]\n"
	"[ECO \"D00\"]\n"
	"\n"
	"1. d4 d5 2. Nc3 Nf6 3. Bf4 e6 4. e3 Bd6 5. Bxd6 Qxd6 0-1\n";


struct SilentPgnReader : public PgnReader
{
	SilentPgnReader(mstl::istream& stream)
		:PgnReader(stream,
					 variant::Normal,
					 sys::utf8::Codec::utf8(),
					 PgnReader::File,
					 PgnReader::Normalize,
					 PgnReader::UseResultTag)
		,errors(0)
	{
	}

	void warning(Warning,
					 unsigned,
					 unsigned,
					 unsigned,
					 variant::Type,
					 mstl::string const&,
					 mstl::string const&) override
	{
	}

	void error(Error,
				  unsigned,
				  unsigned,
				  unsigned,
				  variant::Type,
				  mstl::string const&,
				  mstl::string const&,
				  mstl::string const&) override
	{
		++errors;
	}

	void error(save::State, unsigned, unsigned, variant::Type) override
	{
		++errors;
	}

	unsigned estimateNumberOfGames() override
	{
		return 4;
	}

	unsigned errors;
};


struct TclInterpreter
{
	TclInterpreter()
	{
		tcl::bits::interp = Tcl_CreateInterp();
		Tcl_Init(tcl::bits::interp);
	}

	~TclInterpreter()
	{
		Tcl_DeleteInterp(tcl::bits::interp);
		tcl::bits::interp = nullptr;
	}
};


struct ScopedEnv
{
	ScopedEnv(char const* name, char const* value)
		:m_name(name)
		,m_hadValue(false)
	{
		char const* current = ::getenv(name);
		if (current)
		{
			m_hadValue = true;
			m_value = current;
		}

		::setenv(name, value, 1);
	}

	~ScopedEnv()
	{
		if (m_hadValue)
			::setenv(m_name, m_value.c_str(), 1);
		else
			::unsetenv(m_name);
	}

	char const* m_name;
	bool m_hadValue;
	mstl::string m_value;
};


void
initializeStatics()
{
	db::tag::initialize();
	db::castling::initialize();
	db::board::base::initialize();
	db::Board::initialize();
	db::HomePawns::initialize();
	db::Signature::initialize();
	db::sci::Encoder::initialize();
	db::si3::Encoder::initialize();
}


mstl::string
rootFromArg(int argc, char** argv)
{
	if (argc > 1)
		return argv[1];

	char buf[128];
	::snprintf(buf, sizeof(buf), "/tmp/scidb-maintenance-%ld.sci", long(::getpid()));
	return buf;
}


void
cleanup(mstl::string const& filename)
{
	mstl::string root = ::util::misc::file::rootname(filename);

	::remove((root + ".sci").c_str());
	::remove((root + ".scg").c_str());
	::remove((root + ".scn").c_str());
}


bool
checkEcoStat(maintenance::EcoStatsList const& stats,
				 char const* eco,
				 unsigned total,
				 unsigned white,
				 unsigned draws,
				 unsigned black)
{
	for (unsigned i = 0; i < stats.size(); ++i)
	{
		if (stats[i].eco == eco)
		{
			return stats[i].total == total
				&& stats[i].white == white
				&& stats[i].draws == draws
				&& stats[i].black == black;
		}
	}

	return false;
}


bool
sameDuplicateGroups(maintenance::DuplicateGroups const& lhs, maintenance::DuplicateGroups const& rhs)
{
	if (lhs.size() != rhs.size())
		return false;

	for (unsigned i = 0; i < lhs.size(); ++i)
	{
		if (lhs[i].size() != rhs[i].size())
			return false;

		for (unsigned j = 0; j < lhs[i].size(); ++j)
		{
			if (lhs[i][j] != rhs[i][j])
				return false;
		}
	}

	return true;
}


bool
sameEcoStats(maintenance::EcoStatsList const& lhs, maintenance::EcoStatsList const& rhs)
{
	if (lhs.size() != rhs.size())
		return false;

	for (unsigned i = 0; i < lhs.size(); ++i)
	{
		if (lhs[i].eco != rhs[i].eco
			 || lhs[i].total != rhs[i].total
			 || lhs[i].white != rhs[i].white
			 || lhs[i].draws != rhs[i].draws
			 || lhs[i].black != rhs[i].black)
			return false;
	}

	return true;
}


bool
samePlayerStats(PlayerStats const& lhs, PlayerStats const& rhs)
{
	if (lhs.countGames() != rhs.countGames()
		 || lhs.countGames(color::White) != rhs.countGames(color::White)
		 || lhs.countGames(color::Black) != rhs.countGames(color::Black)
		 || lhs.firstDate() != rhs.firstDate()
		 || lhs.lastDate() != rhs.lastDate())
		return false;

	for (unsigned i = 0; i < rating::Last; ++i)
	{
		rating::Type type = rating::Type(i);
		if (lhs.minRating(type) != rhs.minRating(type) || lhs.maxRating(type) != rhs.maxRating(type))
			return false;
	}

	for (unsigned color = 0; color < 2; ++color)
	{
		for (unsigned result = 0; result < 5; ++result)
		{
			if (lhs.score(color::ID(color), result::ID(result))
				 != rhs.score(color::ID(color), result::ID(result)))
				return false;
		}

		if (lhs.countEcoLines(color::ID(color)) != rhs.countEcoLines(color::ID(color)))
			return false;

		for (unsigned i = 0; i < lhs.countEcoLines(color::ID(color)); ++i)
		{
			if (lhs.ecoLine(color::ID(color), i) != rhs.ecoLine(color::ID(color), i)
				 || lhs.ecoCount(color::ID(color), i) != rhs.ecoCount(color::ID(color), i))
				return false;
		}
	}

	return true;
}


bool
verifyParallelParity(Database& db)
{
	NamebasePlayer const& alpha = db.player(0, color::White);

	ScopedEnv serialEnv("SCIDB_MAINTENANCE_THREADS", "1");
	maintenance::DuplicateGroups serialDuplicates = maintenance::findDuplicates(db);
	maintenance::EcoStatsList serialEco = maintenance::computeEcoStats(db, variant::Normal);
	PlayerStats serialPlayerStats;
	db.playerStatistic(alpha, serialPlayerStats);

	ScopedEnv parallelEnv("SCIDB_MAINTENANCE_THREADS", "2");
	maintenance::DuplicateGroups parallelDuplicates = maintenance::findDuplicates(db);
	maintenance::EcoStatsList parallelEco = maintenance::computeEcoStats(db, variant::Normal);
	PlayerStats parallelPlayerStats;
	db.playerStatistic(alpha, parallelPlayerStats);

	if (!sameDuplicateGroups(serialDuplicates, parallelDuplicates))
		return false;

	if (!sameEcoStats(serialEco, parallelEco))
		return false;

	if (!samePlayerStats(serialPlayerStats, parallelPlayerStats))
		return false;

	return serialPlayerStats.countGames() == 2
		&& serialPlayerStats.countGames(color::White) == 2
		&& serialPlayerStats.countGames(color::Black) == 0
		&& serialPlayerStats.score(color::White, result::White) == 2
		&& serialPlayerStats.countEcoLines(color::White) == 1
		&& serialPlayerStats.ecoLine(color::White, 0).asShortString() == "C20"
		&& serialPlayerStats.ecoCount(color::White, 0) == 2;
}


bool
verifyInitialState(Database& db)
{
	maintenance::DuplicateGroups groups = maintenance::findDuplicates(db);
	if (groups.size() != 1 || groups[0].size() != 2 || groups[0][0] != 0 || groups[0][1] != 1)
		return false;

	maintenance::EcoStatsList stats = maintenance::computeEcoStats(db, variant::Normal);
	return checkEcoStat(stats, "C20", 3, 2, 1, 0)
		&& checkEcoStat(stats, "D00", 1, 0, 0, 1);
}


bool
verifyAfterDeletion(Database& db)
{
	maintenance::DuplicateGroups groups = maintenance::findDuplicates(db);
	if (!groups.empty())
		return false;

	if (!db.gameInfo(1).isDeleted())
		return false;

	maintenance::EcoStatsList stats = maintenance::computeEcoStats(db, variant::Normal);
	return checkEcoStat(stats, "C20", 2, 1, 1, 0)
		&& checkEcoStat(stats, "D00", 1, 0, 0, 1);
}


bool
verifyCompactedState(Database& db)
{
	if (db.countGames() != 3)
		return false;

	for (unsigned i = 0; i < db.countGames(); ++i)
	{
		if (db.gameInfo(i).isDeleted())
			return false;
	}

	maintenance::DuplicateGroups groups = maintenance::findDuplicates(db);
	if (!groups.empty())
		return false;

	maintenance::EcoStatsList stats = maintenance::computeEcoStats(db, variant::Normal);
	return checkEcoStat(stats, "C20", 2, 1, 1, 0)
		&& checkEcoStat(stats, "D00", 1, 0, 0, 1);
}


bool
verifyMaterialSearch(Database const& db)
{
	if (db.countGames() < 3)
		return false;

	unsigned reducedIndex = db.countGames() - 1;
	SearchMaterial fullMaterial(db.gameInfo(0).material());
	SearchMaterial reducedMaterial(db.gameInfo(reducedIndex).material());
	SearchMaterialClass fullClass(db.gameInfo(0).material());
	SearchMaterialPawns allPawns(8, 8, 8, 8);

	return fullMaterial.match(db.gameInfo(0))
		&& fullMaterial.match(db.gameInfo(1))
		&& (db.countGames() == 3 || fullMaterial.match(db.gameInfo(2)))
		&& !fullMaterial.match(db.gameInfo(reducedIndex))
		&& !reducedMaterial.match(db.gameInfo(0))
		&& reducedMaterial.match(db.gameInfo(reducedIndex))
		&& fullClass.match(db.gameInfo(0))
		&& fullClass.match(db.gameInfo(1))
		&& (db.countGames() == 3 || fullClass.match(db.gameInfo(2)))
		&& !fullClass.match(db.gameInfo(reducedIndex))
		&& allPawns.match(db.gameInfo(0))
		&& allPawns.match(db.gameInfo(reducedIndex));
}


bool
verifyRatingSearch(Database const& db)
{
	if (db.countGames() < 3)
		return false;

	SearchRating whiteElo(rating::Elo, SearchRating::White, 2400, 2600);
	SearchRating blackElo(rating::Elo, SearchRating::Black, 0, 0, 2300, 2400);
	SearchRating averageElo(rating::Elo, SearchRating::Average, 2450, 2450);
	SearchRating bothElo(rating::Elo, SearchRating::Both, 2400, 2600, 2350, 2450);
	unsigned whiteMatches = 0;
	unsigned blackMatches = 0;
	unsigned averageMatches = 0;
	unsigned bothMatches = 0;

	for (unsigned i = 0; i < db.countGames(); ++i)
	{
		GameInfo const& info = db.gameInfo(i);
		if (whiteElo.match(info))
			++whiteMatches;
		if (blackElo.match(info))
			++blackMatches;
		if (averageElo.match(info))
			++averageMatches;
		if (bothElo.match(info))
			++bothMatches;
	}

	if (db.countGames() == 4)
	{
		return whiteMatches == 2
			&& blackMatches == 3
			&& averageMatches == 2
			&& bothMatches == 2;
	}

	return whiteMatches == 1
		&& blackMatches == 2
		&& averageMatches == 1
		&& bothMatches == 1;
}


bool
verifyPatternSearch(Database const& db)
{
	if (db.countGames() < 3)
		return false;

	SearchPlayerName anyAlpha(SearchPlayerName::Any, "Al*");
	SearchPlayerName blackTa(SearchPlayerName::Black, "*ta");
	SearchPlayerName exactAlpha(SearchPlayerName::Any, "Al*", true);
	SearchEventName uniqueEvent("Unique *");
	SearchEventName exactUnique("Unique *", true);
	SearchSiteName testSite("Te*");

	unsigned anyAlphaMatches = 0;
	unsigned blackTaMatches = 0;
	unsigned exactAlphaMatches = 0;
	unsigned uniqueEventMatches = 0;
	unsigned exactUniqueMatches = 0;
	unsigned testSiteMatches = 0;

	for (unsigned i = 0; i < db.countGames(); ++i)
	{
		GameInfo const& info = db.gameInfo(i);
		if (anyAlpha.match(info))
			++anyAlphaMatches;
		if (blackTa.match(info))
			++blackTaMatches;
		if (exactAlpha.match(info))
			++exactAlphaMatches;
		if (uniqueEvent.match(info))
			++uniqueEventMatches;
		if (exactUnique.match(info))
			++exactUniqueMatches;
		if (testSite.match(info))
			++testSiteMatches;
	}

	if (db.countGames() == 4)
	{
		return anyAlphaMatches == 2
			&& blackTaMatches == 4
			&& exactAlphaMatches == 0
			&& uniqueEventMatches == 2
			&& exactUniqueMatches == 0
			&& testSiteMatches == 4;
	}

	return anyAlphaMatches == 1
		&& blackTaMatches == 3
		&& exactAlphaMatches == 0
		&& uniqueEventMatches == 2
		&& exactUniqueMatches == 0
		&& testSiteMatches == 3;
}


bool
verifyIndexHeader(mstl::string const& filename, unsigned expectedVersion, unsigned expectedGames)
{
	FILE* fp = ::fopen(filename.c_str(), "rb");
	if (!fp)
		return false;

	unsigned char header[14];
	bool ok = ::fread(header, 1, sizeof(header), fp) == sizeof(header);
	::fclose(fp);

	if (!ok)
		return false;

	if (::memcmp(header, "Scidb.i", 7) != 0)
		return false;

	unsigned version = util::ByteStream::uint16(header + 8);
	unsigned games = util::ByteStream::uint32(header + 10);

	if (version != expectedVersion || games != expectedGames)
	{
		::fprintf(stderr,
					 "header mismatch for %s: version=%u expected=%u games=%u expected=%u\n",
					 filename.c_str(),
					 version,
					 expectedVersion,
					 games,
					 expectedGames);
		return false;
	}

	return true;
}


bool
verifyAttributes(mstl::string const& filename, int expectedGames)
{
	int numGames = -1;
	type::ID type = type::Unspecific;
	variant::Type variant = variant::Undetermined;
	uint32_t creationTime = 0;

	if (!DatabaseCodec::getAttributes(filename, numGames, type, variant, creationTime, nullptr))
		return false;

	bool ok = numGames == expectedGames
		&& type == type::Unspecific
		&& variant == variant::Normal;

	if (!ok)
	{
		::fprintf(stderr,
					 "attribute mismatch for %s: games=%d expected=%d type=%d variant=%d creation=%u\n",
					 filename.c_str(),
					 numGames,
					 expectedGames,
					 int(type),
					 int(variant),
					 unsigned(creationTime));
	}

	return ok;
}


// Regression test for the custom-FEN-start decoder fix. A game whose start
// position has no IDN (idn == 0) is decoded through setupBoard(Board const&),
// the path that previously mis-numbered the black pieces and tripped the
// isValidMove assertion in Decoder::decodeMove() on the first black move.
bool
verifyDecodeRoundTrip(mstl::string const& rootname)
{
	static char const* FenPgn =
		"[Event \"FEN Decode Test\"]\n"
		"[Site \"Test\"]\n"
		"[Date \"2024.02.01\"]\n"
		"[Round \"1\"]\n"
		"[White \"FenWhite\"]\n"
		"[Black \"FenBlack\"]\n"
		"[Result \"*\"]\n"
		"[SetUp \"1\"]\n"
		"[FEN \"rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2\"]\n"
		"\n"
		"2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 g6 *\n";

	mstl::string fenFile(::util::misc::file::rootname(rootname) + "-fen.sci");
	cleanup(fenFile);

	util::Progress& progress = util::Progress::null();
	mstl::string pgn(FenPgn);
	mstl::istringstream stream(pgn);
	SilentPgnReader reader(stream);

	Database db(fenFile, sys::utf8::Codec::utf8(), storage::OnDisk, variant::Normal);
	unsigned imported = db.importGames(reader, progress);

	if (imported != 1 || reader.errors != 0)
	{
		::fprintf(stderr, "FEN game import failed: imported=%u errors=%u\n", imported, reader.errors);
		cleanup(fenFile);
		return false;
	}

	// Decode the stored game; this drives Decoder::decodeMove() -> setupBoard().
	Game game;
	load::State state = db.loadGame(0, game);

	bool ok = true;

	if (state != load::Ok)
	{
		::fprintf(stderr, "FEN game decode failed: load state=%d\n", int(state));
		ok = false;
	}
	else if (game.plyCount() != 8)
	{
		::fprintf(stderr, "FEN game decode produced %u plies, expected 8\n", game.plyCount());
		ok = false;
	}
	else
	{
		mstl::string moves;
		game.dumpMoves(moves, Game::SuppressSpace | Game::WhiteNumbers);

		// Black moves (pawn moves stay ASCII; pieces render as figurines).
		// The pre-fix bug mis-numbered the black pieces, so these black pawn
		// moves -- including the cxd4 capture -- would decode incorrectly even
		// where the assertion was compiled out.
		if (moves.find("d6") == mstl::string::npos
			|| moves.find("cxd4") == mstl::string::npos
			|| moves.find("g6") == mstl::string::npos)
		{
			::fprintf(stderr, "FEN game decode produced unexpected moves: %s\n", moves.c_str());
			ok = false;
		}
	}

	cleanup(fenFile);
	return ok;
}


mstl::string
fileBytes(mstl::string const& filename)
{
	mstl::string bytes;
	FILE* file = ::fopen(filename.c_str(), "rb");
	if (!file) M_RAISE("cannot read duplicate fixture");
	char buffer[4096];
	size_t count;
	while ((count = ::fread(buffer, 1, sizeof(buffer), file))) bytes.append(buffer, count);
	::fclose(file);
	return bytes;
}

bool
verifyNormalizedDuplicates(mstl::string const& rootname)
{
	mstl::string filename(::util::misc::file::rootname(rootname) + "-normalized.sci");
	cleanup(filename);
	mstl::string pgn;
	for (unsigned i = 0; i < 15; ++i)
	{
		pgn += i == 1 ? "[Event \"Open\"]\n[Site \"LONDON\"]\n[Date \"2020.??.??\"]\n[Round \"3\"]\n"
			: "[Event \"3rd Open 2020\"]\n[Site \"London (ENG)\"]\n[Date \"2020.04.05\"]\n[Round \"3.1\"]\n";
		pgn += i == 10 ? "[White \"KASPÁROV, Garry\"]\n[Black \"Jose Smith\"]\n"
			: i == 11 ? "[White \"Dr. Garry Kasparov\"]\n[Black \"JOSE SMITH\"]\n"
			: i == 12 || i == 14 ? "[White \"ID Alpha\"]\n[Black \"Jose Smith\"]\n"
			: i == 13 ? "[White \"Other Person\"]\n[Black \"Jose Smith\"]\n"
			: i == 2 ? "[White \"José Smith\"]\n[Black \"Garry Kasparov\"]\n"
			: i == 1 ? "[White \"Kasparov, G.\"]\n[Black \"Smith, J.\"]\n[WhiteElo \"2700\"]\n"
			: "[White \"GM Garry Kasparov\"]\n[Black \"José Smith\"]\n[WhiteElo \"2800\"]\n[ECO \"C20\"]\n";
		if (i == 12 || i == 13) pgn += "[WhiteFideId \"12345\"]\n";
		if (i == 14) pgn += "[WhiteFideId \"54321\"]\n";
		pgn += i == 3 ? "[Result \"0-1\"]\n" : i == 4 ? "[Result \"*\"]\n" : "[Result \"1-0\"]\n";
		if (i == 8) pgn += "[SetUp \"1\"]\n[FEN \"4k3/8/8/8/8/8/8/4K3 w - - 0 1\"]\n";
		if (i == 9) pgn += "[SetUp \"1\"]\n[FEN \"4k3/8/8/8/8/8/8/4K3 b - - 0 1\"]\n";
		pgn += "\n";
		if (i == 1) pgn += "1. e4 {extra comment} e5 (1... c5) 2. Nf3 $1 Nc6 ";
		else if (i == 7) pgn += "1. d4 d5 2. Nf3 Nc6 ";
		else if (i < 5 || i >= 10) pgn += "1. e4 e5 2. Nf3 Nc6 ";
		pgn += i == 3 ? "0-1\n\n" : i == 4 ? "*\n\n" : "1-0\n\n";
	}
	mstl::istringstream stream(pgn);
	SilentPgnReader reader(stream);
	util::Progress& progress = util::Progress::null();
	db::sci::Codec::setCreationVersion(96);
	Database created(filename, sys::utf8::Codec::utf8(), storage::OnDisk, variant::Normal);
	db::sci::Codec::setCreationVersion(95);
	bool ok = created.importGames(reader, progress) == 15 && !reader.errors;
	maintenance::DuplicateGroups expected;
	maintenance::DuplicateGroup played, empty, identified;
	played.push_back(0); played.push_back(1); played.push_back(4);
	played.push_back(10); played.push_back(11);
	empty.push_back(5); empty.push_back(6);
	identified.push_back(12); identified.push_back(13);
	expected.push_back(played); expected.push_back(empty); expected.push_back(identified);
	auto check = [&expected](maintenance::DuplicateGroups actual) {
		actual.qsort([](maintenance::DuplicateGroup const& a, maintenance::DuplicateGroup const& b) -> int {
			return a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0;
		});
		if (!sameDuplicateGroups(actual, expected))
		{
			::fprintf(stderr, "normalized groups:");
			for (unsigned i = 0; i < actual.size(); ++i)
			{
				::fprintf(stderr, " [");
				for (unsigned j = 0; j < actual[i].size(); ++j) ::fprintf(stderr, " %u", actual[i][j]);
				::fprintf(stderr, " ]");
			}
			::fprintf(stderr, "\n");
			return false;
		}
		return true;
	};
	maintenance::DuplicateGroups exactBefore = maintenance::findDuplicates(created);
	mstl::vector<uint32_t> checksums;
	for (unsigned i = 0; i < created.countGames(); ++i) checksums.push_back(created.computeChecksum(i));
	ok = check(maintenance::findDuplicates(created, maintenance::Normalized)) && ok;
	maintenance::DuplicateGroups exact = maintenance::findDuplicates(created);

	ok = sameDuplicateGroups(exactBefore, exact) && ok;
	for (unsigned i = 0; i < created.countGames(); ++i) ok = created.computeChecksum(i) == checksums[i] && ok;
	created.close();
	mstl::string root = ::util::misc::file::rootname(filename);
	mstl::string indexBytes = fileBytes(root + ".sci");
	mstl::string gameBytes = fileBytes(root + ".scg");
	mstl::string nameBytes = fileBytes(root + ".scn");
	Database reopened(filename, sys::utf8::Codec::utf8(), permission::ReadOnly, progress);
	{
		ScopedEnv serial("SCIDB_MAINTENANCE_THREADS", "1");
		maintenance::DuplicateGroups groups = maintenance::findDuplicates(reopened, maintenance::Normalized);
		ok = check(groups) && ok;
		ScopedEnv parallel("SCIDB_MAINTENANCE_THREADS", "2");
		ok = sameDuplicateGroups(groups, maintenance::findDuplicates(reopened, maintenance::Normalized)) && ok;
	}
	reopened.close();
	ok = fileBytes(root + ".sci") == indexBytes && fileBytes(root + ".scg") == gameBytes
		&& fileBytes(root + ".scn") == nameBytes && ok;
	cleanup(filename);
	return ok;
}

} // namespace


// Helper macro: check + labeled failure + cleanup + return.
// Assumes `filename` and `compactedFilename` are in scope.
#define CHECK(label, expr) \
	do { \
		if (!(expr)) { \
			::fprintf(stderr, label " failed\n"); \
			cleanup(filename); \
			cleanup(compactedFilename); \
			return 1; \
		} \
	} while (0)


int
main(int argc, char** argv)
{
	mstl::string filename = rootFromArg(argc, argv);
	mstl::string compactedFilename(::util::misc::file::rootname(filename) + "-compacted.sci");
	util::Progress& progress = util::Progress::null();

	try
	{
		TclInterpreter tcl;
		initializeStatics();
		// Keep the existing exact-mode/index-attribute fixture at its original version.
		db::sci::Codec::setCreationVersion(95);

		cleanup(filename);
		cleanup(compactedFilename);

		mstl::string samplePgn(SamplePgn);
		mstl::istringstream stream(samplePgn);
		SilentPgnReader reader(stream);
		Database created(filename, sys::utf8::Codec::utf8(), storage::OnDisk, variant::Normal);

		unsigned imported = created.importGames(reader, progress);
		CHECK("PGN import", reader.errors == 0 && imported == 4);
		CHECK("Initial maintenance", verifyInitialState(created));
		CHECK("Normalized duplicates", verifyNormalizedDuplicates(filename));
		CHECK("Material search", verifyMaterialSearch(created));
		CHECK("Rating search", verifyRatingSearch(created));
		CHECK("Pattern search", verifyPatternSearch(created));
		CHECK("Custom-FEN decode round-trip", verifyDecodeRoundTrip(filename));
		CHECK("Parallel parity", verifyParallelParity(created));

		created.deleteGame(1, true);
		CHECK("Post-delete maintenance", verifyAfterDeletion(created));
		CHECK("Compaction flag", created.shouldCompact());

		Database compacted(compactedFilename, sys::utf8::Codec::utf8(), storage::OnDisk, variant::Normal);
		created.compact(compacted, progress);
		compacted.close();

		created.close();

		Database reopened(filename, sys::utf8::Codec::utf8(), permission::ReadWrite, progress);
		CHECK("Reopen index header", verifyIndexHeader(filename, 95, 4) && verifyAttributes(filename, 4));
		CHECK("Reopen verification", verifyAfterDeletion(reopened));
		CHECK("Reopen material search", verifyMaterialSearch(reopened));
		CHECK("Reopen rating search", verifyRatingSearch(reopened));
		CHECK("Reopen pattern search", verifyPatternSearch(reopened));
		CHECK("Reopen parallel parity", verifyParallelParity(reopened));
		CHECK("Reopen compaction flag", reopened.shouldCompact());

		Database reopenedCompacted(compactedFilename, sys::utf8::Codec::utf8(), permission::ReadWrite, progress);
		CHECK("Compacted index header",
		      verifyIndexHeader(compactedFilename, 95, 3) && verifyAttributes(compactedFilename, 3));
		CHECK("Compacted database", verifyCompactedState(reopenedCompacted));
		CHECK("Compacted material search", verifyMaterialSearch(reopenedCompacted));
		CHECK("Compacted rating search", verifyRatingSearch(reopenedCompacted));
		CHECK("Compacted pattern search", verifyPatternSearch(reopenedCompacted));
		CHECK("Compacted should not need compaction", !reopenedCompacted.shouldCompact());

		reopenedCompacted.close();
		reopened.close();
		cleanup(filename);
		cleanup(compactedFilename);
		::puts("maintenance verification passed (0 failed)");
		return 0;
	}
	catch (IOException const& exc)
	{
		::fprintf(stderr, "I/O exception: %s\n", exc.what());
	}
	catch (mstl::exception const& exc)
	{
		::fprintf(stderr, "exception: %s\n", exc.what());
	}

	cleanup(filename);
	cleanup(compactedFilename);
	return 1;
}
