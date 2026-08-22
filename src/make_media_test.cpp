// ======================================================================
// make_media_test.cpp — create a .sci database + .scm media companion
// for end-to-end GUI testing of the media viewer panel.
//
// Builds a tiny .sci from a PGN with 3 well-known games, reads back the
// GameInfo headers, computes fingerprints via scm::MediaTable::fingerprint(),
// and writes a .scm manifest with [Game HEX] linkage blocks plus a media
// directory with sample image/audio/video files.
//
// Usage: make_media_test <output-rootname> [<eco.bin>]
// ======================================================================

#include "db/db_board.h"
#include "db/db_board_base.h"
#include "db/db_database.h"
#include "db/db_eco_table.h"
#include "db/db_exception.h"
#include "db/db_game.h"
#include "db/db_game_info.h"
#include "db/db_home_pawns.h"
#include "db/db_pgn_reader.h"
#include "db/db_signature.h"
#include "db/db_statistic.h"
#include "db/sci/sci_encoder.h"
#include "db/scm/scm_media.h"
#include "sys/sys_utf8_codec.h"
#include "util/u_progress.h"
#include "mstl/m_string.h"
#include "mstl/m_ifstream.h"
#include "mstl/m_fstream.h"

#include <tcl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

using namespace db;

namespace tcl { namespace bits { Tcl_Interp* interp = nullptr; } }

namespace {

char const* PGN =
	"[Event \"Bilbao Masters Final\"]\n[Site \"Bilbao ESP\"]\n[Date \"2008.09.20\"]\n"
	"[Round \"1\"]\n[White \"Topalov,V\"]\n[Black \"Anand,V\"]\n"
	"[WhiteElo \"2810\"]\n[BlackElo \"2803\"]\n[Result \"1/2-1/2\"]\n\n"
	"1.e4 e5 2.Nf3 Nc6 3.Bb5 a6 4.Ba4 Nf6 5.O-O Be7 6.Re1 b5 7.Bb3 d6 8.c3 O-O 1/2-1/2\n\n"

	"[Event \"Linares\"]\n[Site \"Linares ESP\"]\n[Date \"2009.02.20\"]\n"
	"[Round \"1\"]\n[White \"Carlsen,M\"]\n[Black \"Kramnik,V\"]\n"
	"[WhiteElo \"2776\"]\n[BlackElo \"2779\"]\n[Result \"1-0\"]\n\n"
	"1.e4 e5 2.Nf3 Nc6 3.Bb5 a6 4.Ba4 Nf6 5.O-O Be7 6.Re1 b5 7.Bb3 d6 8.c3 O-O 9.h3 Nb8 1-0\n\n"

	"[Event \"London Chess Classic\"]\n[Site \"London ENG\"]\n[Date \"2012.12.08\"]\n"
	"[Round \"1\"]\n[White \"Carlsen,M\"]\n[Black \"Kramnik,V\"]\n"
	"[WhiteElo \"2848\"]\n[BlackElo \"2795\"]\n[Result \"1/2-1/2\"]\n\n"
	"1.d4 Nf6 2.c4 e6 3.Nf3 d5 4.Nc3 Bb4 5.Bg5 h6 6.Bxf6 Qxf6 7.Qa4+ Nc6 1/2-1/2\n\n";

class MyPgnReader : public PgnReader
{
public:
	MyPgnReader(mstl::istream& stream, variant::Type v, mstl::string const& encoding)
		:PgnReader(stream, v, encoding, PgnReader::File, PgnReader::Normalize, PgnReader::UseResultTag) {}
	void warning(Warning, unsigned, unsigned, unsigned, variant::Type, mstl::string const&, mstl::string const&) override {}
	void error(Error, unsigned, unsigned, unsigned, variant::Type, mstl::string const&, mstl::string const&, mstl::string const&) override {}
	void error(save::State, unsigned, unsigned, variant::Type) override {}
};

void loadEcoFile(mstl::string const& path)
{
	mstl::ifstream stream(path, mstl::ios_base::in | mstl::ios_base::binary);
	if (!stream) { fprintf(stderr, "warning: cannot open ECO file '%s' (continuing)\n", path.c_str()); return; }
	EcoTable::specimen(variant::Normal).load(stream, variant::Normal);
}

void initializeStatics()
{
	db::tag::initialize();
	db::castling::initialize();
	db::board::base::initialize();
	db::Board::initialize();
	db::HomePawns::initialize();
	db::Signature::initialize();
	db::sci::Encoder::initialize();
}

// Minimal 1x1 PNG (67 bytes, valid).
static unsigned char const Png1x1[] = {
	0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
	0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x02,0x00,0x00,0x00,0x90,0x77,0x53,
	0xDE,0x00,0x00,0x00,0x0C,0x49,0x44,0x41,0x54,0x08,0xD7,0x63,0xF8,0xFF,0xFF,0x3F,
	0x00,0x05,0xFE,0x02,0xFE,0xDC,0xCC,0x59,0xE7,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,
	0x44,0xAE,0x42,0x60,0x82
};
static unsigned const Png1x1Size = sizeof(Png1x1);

void writeFile(mstl::string const& path, void const* data, unsigned size)
{
	FILE* f = fopen(path.c_str(), "wb");
	if (!f) { fprintf(stderr, "cannot write %s\n", path.c_str()); exit(2); }
	fwrite(data, 1, size, f);
	fclose(f);
}

void writeTextFile(mstl::string const& path, char const* text)
{
	FILE* f = fopen(path.c_str(), "w");
	if (!f) { fprintf(stderr, "cannot write %s\n", path.c_str()); exit(2); }
	fputs(text, f);
	fclose(f);
}

void mkdirp(mstl::string const& path)
{
	::mkdir(path.c_str(), 0777);
}

} // namespace

struct TclInterpreter
{
	TclInterpreter()  { tcl::bits::interp = Tcl_CreateInterp(); Tcl_Init(tcl::bits::interp); }
	~TclInterpreter() { Tcl_DeleteInterp(tcl::bits::interp); tcl::bits::interp = nullptr; }
};

int main(int argc, char** argv)
{
	if (argc < 2) { fprintf(stderr, "usage: %s <output-rootname> [<eco.bin>]\n", argv[0]); return 1; }

	mstl::string root(argv[1]);
	mstl::string sciPath(root + ".sci");
	mstl::string pgnPath(root + ".pgn");
	mstl::string scmPath(root + ".scm");
	mstl::string mediaDir(root + ".media");

	// Write the PGN source
	writeTextFile(pgnPath, (char*)PGN);

	util::Progress& progress = util::Progress::null();
	TclInterpreter tcl;
	initializeStatics();
	if (argc >= 3) loadEcoFile(argv[2]);
	else loadEcoFile(SHAREDIR "/data/eco.bin");

	// 1. Create the .sci database
	{
		Database db(sciPath, sys::utf8::Codec::utf8(), storage::OnDisk, variant::Normal);
		mstl::ifstream pgn(pgnPath, mstl::ios_base::in | mstl::ios_base::binary);
		if (!pgn) { fprintf(stderr, "cannot open pgn\n"); return 2; }
		MyPgnReader reader(pgn, variant::Normal, sys::utf8::Codec::automatic());
		db.importGames(reader, progress);
		db.save(progress);
		db.close();
	}

	// 2. Read back game info and compute fingerprints
	unsigned nGames = 0;
	struct GameHdr { mstl::string white, black, event, date; unsigned round; unsigned result; uint64_t fp; };
	GameHdr games[16];

	{
		Database db(sciPath, sys::utf8::Codec::utf8(), permission::ReadOnly, progress);
		nGames = db.countGames();
		printf("Created .sci with %u game(s)\n", nGames);
		if (nGames > 16) nGames = 16;

		for (unsigned i = 0; i < nGames; ++i)
		{
			GameInfo const& info = db.gameInfo(i);
			games[i].white  = info.playerName(color::White);
			games[i].black  = info.playerName(color::Black);
			games[i].event  = info.event();
			games[i].date   = info.date().asString();
			games[i].round  = info.round();
			games[i].result = unsigned(info.result());
			games[i].fp     = scm::MediaTable::fingerprint(
				games[i].white, games[i].black, games[i].event,
				games[i].date, games[i].round, games[i].result);

			printf("  Game %u: %s vs %s | %s | %s | R%u | result=%u\n",
				i, games[i].white.c_str(), games[i].black.c_str(),
				games[i].event.c_str(), games[i].date.c_str(),
				games[i].round, games[i].result);
			printf("    fingerprint = 0x%016llx\n", (unsigned long long)games[i].fp);
		}
		db.close();
	}

	// 3. Create media directory with sample files
	{
		mstl::string imgDir(mediaDir + "/images");
		mstl::string audDir(mediaDir + "/audio");
		mstl::string vidDir(mediaDir + "/video");
		mkdirp(mediaDir);
		mkdirp(imgDir);
		mkdirp(audDir);
		mkdirp(vidDir);

		writeFile(imgDir + "/bilbao2008.png",  Png1x1, Png1x1Size);
		writeFile(imgDir + "/linares2009.png", Png1x1, Png1x1Size);
		writeFile(imgDir + "/london2012.png",  Png1x1, Png1x1Size);
		writeTextFile(audDir + "/interview.wav", "dummy audio file\n");
		writeTextFile(vidDir + "/analysis.mp4", "dummy video file\n");
		printf("Created media directory: %s\n", mediaDir.c_str());
	}

	// 4. Write the .scm manifest
	{
		FILE* f = fopen(scmPath.c_str(), "w");
		if (!f) { fprintf(stderr, "cannot write %s\n", scmPath.c_str()); return 2; }

		// Use just the basename for MediaDir so it's portable
		mstl::string mediaBasename;
		{
			char const* slash = strrchr(mediaDir.c_str(), '/');
			mediaBasename = slash ? (slash + 1) : mediaDir.c_str();
		}

		fprintf(f, "# Test media manifest — auto-generated by make_media_test\n");
		fprintf(f, "[Database \"Test Media Database\"]\n");
		fprintf(f, "[MediaDir \"%s\"]\n", mediaBasename.c_str());
		fprintf(f, "[Encoding \"utf-8\"]\n\n");

		// Media library
		fprintf(f, "[Media \"M01\"]\nType: picture\nPath: images/bilbao2008.png\nTitle: \"Bilbao 2008: Topalov-Anand\"\n\n");
		fprintf(f, "[Media \"M02\"]\nType: audio\nPath: audio/interview.wav\nTitle: \"Post-game interview\"\n\n");
		fprintf(f, "[Media \"M03\"]\nType: picture\nPath: images/linares2009.png\nTitle: \"Linares 2009: Carlsen-Kramnik\"\n\n");
		fprintf(f, "[Media \"M04\"]\nType: video\nPath: video/analysis.mp4\nTitle: \"Game analysis video\"\n\n");
		fprintf(f, "[Media \"M05\"]\nType: picture\nPath: images/london2012.png\nTitle: \"London 2012: Carlsen-Kramnik\"\n\n");

		// Game linkages
		for (unsigned i = 0; i < nGames; ++i)
		{
			fprintf(f, "[Game \"%016llx\"]\n", (unsigned long long)games[i].fp);
			switch (i)
			{
				case 0: fprintf(f, "Media: M01, M02\n\n"); break;
				case 1: fprintf(f, "Media: M03, M04\n\n"); break;
				case 2: fprintf(f, "Media: M05\n\n"); break;
				default: fprintf(f, "Media: M01\n\n"); break;
			}
		}
		fclose(f);
		printf("Wrote manifest: %s\n", scmPath.c_str());
	}

	// 5. Verify: re-open the database and confirm .scm is loaded + media found
	{
		Database db(sciPath, sys::utf8::Codec::utf8(), permission::ReadOnly, progress);
		scm::MediaTable const* table = db.scmMediaTable();
		if (!table || !table->isOpen())
		{
			fprintf(stderr, "VERIFY FAIL: .scm not loaded\n");
			return 1;
		}
		printf("Verify: .scm loaded, %u media entries, %u game linkages\n",
			table->mediaCount(), table->gameCount());

		int fail = 0;
		for (unsigned i = 0; i < nGames; ++i)
		{
			mstl::vector<scm::MediaTable::Entry> entries;
			table->mediaFor(games[i].fp, entries);
			printf("  Game %u (%s vs %s): %u media entries\n",
				i, games[i].white.c_str(), games[i].black.c_str(), (unsigned)entries.size());
			if (entries.empty()) { fprintf(stderr, "  FAIL: no media for game %u\n", i); fail = 1; }
			for (unsigned k = 0; k < entries.size(); ++k)
			{
				mstl::string resolved = table->resolvePath(entries[k]);
				printf("    [%s] type=%d path=%s\n",
					entries[k].mediaId.c_str(), (int)entries[k].type, resolved.c_str());
			}
		}

		// Check hasMedia flags
		for (unsigned i = 0; i < nGames; ++i)
		{
			GameInfo const& info = db.gameInfo(i);
			printf("  Game %u hasMedia: audio=%d picture=%d video=%d\n",
				i, (int)info.hasAudio(), (int)info.hasPicture(), (int)info.hasVideo());
		}

		db.close();

		if (fail) { printf("\nRESULT: FAIL\n"); return 1; }
	}

	printf("\nRESULT: PASS\n");
	printf("\nTo test in GUI:\n");
	printf("  1. Open '%s' in scidb\n", sciPath.c_str());
	printf("  2. Select a game\n");
	printf("  3. Check the Media tab in the right pane\n");
	printf("  4. Double-click a media entry to open it\n");
	return 0;
}

// vi:set ts=3 sw=3: