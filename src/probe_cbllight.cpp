// probe_cbllight — open a ChessBase .cbh database and report, per game, the
// GameInfo hasMedia flags (which drive the game-list hasMedia indicator) and
// whether guiding-text media references are present. Used to decide what the
// "has media" indicator really reflects for .cbh databases.
//
// Build (from src/): make probe_cbllight
// Run: ./probe_cbllight "/home/michael-g-thomas/Documents/ChessBase/Bases/CB Light Database.cbh"

#include "db/db_board.h"
#include "db/db_board_base.h"
#include "db/db_database.h"
#include "db/db_game.h"
#include "db/db_eco_table.h"
#include "db/db_game_info.h"
#include "db/db_home_pawns.h"
#include "db/db_signature.h"
#include "db/db_statistic.h"
#include "db/sci/sci_encoder.h"
#include "db/cbh/cbh_media.h"
#include "tcl/tcl_media_extract.h"
#include "sys/sys_utf8_codec.h"
#include "util/u_progress.h"
#include "mstl/m_string.h"
#include "mstl/m_vector.h"
#include "mstl/m_ifstream.h"
#include "mstl/m_fstream.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <tcl.h>

namespace tcl { namespace bits { Tcl_Interp* interp = nullptr; } }

using namespace db;

struct TclInterpreter
{
	TclInterpreter()  { tcl::bits::interp = Tcl_CreateInterp(); Tcl_Init(tcl::bits::interp); }
	~TclInterpreter() { Tcl_DeleteInterp(tcl::bits::interp); tcl::bits::interp = nullptr; }
};

static char const* typeName(int t)
{
	switch (t)
	{
	case 1: return "picture";
	case 2: return "audio";
	case 4: return "stream";
	default: return "?";
	}
}

static void initStuff()
{
	tag::initialize();
	castling::initialize();
	board::base::initialize();
	Board::initialize();
	HomePawns::initialize();
	Signature::initialize();
	sci::Encoder::initialize();
}

int main(int argc, char** argv)
{
	if (argc < 2)
	{
		printf("usage: %s <database.cbh>\n", argv[0]);
		return 2;
	}
	initStuff();
	setvbuf(stdout, nullptr, _IOLBF, 0);
	TclInterpreter tcl;

	// Load the opening table so getGameInfo()/loadGame() won't recurse in
	// EcoTable::getOpening (stack overflow). Mirrors media_console.
	{
		char const* candidates[] = {
			::getenv("SCIDB_ECO_FILE") ? ::getenv("SCIDB_ECO_FILE") : "",
			"data/eco.bin",
			"/media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/src/data/eco.bin",
		};
		for (unsigned ci = 0; ci < sizeof(candidates)/sizeof(candidates[0]); ++ci)
		{
			char const* p = candidates[ci];
			if (!p || !*p) continue;
			mstl::ifstream es(p, mstl::ios_base::in|mstl::ios_base::binary);
			if (!es) continue;
			try { EcoTable::specimen(db::variant::Normal).load(es, db::variant::Normal); }
			catch (...) { continue; }
			fprintf(stderr, "[probe] loaded ECO from %s\n", p);
			break;
		}
	}

	const char* cbhPath = argv[1];
	Database db(cbhPath, sys::utf8::Codec::utf8(), permission::ReadOnly,
				util::Progress::null());
	if (!db.isOpen())
	{
		printf("cannot open %s\n", cbhPath);
		return 1;
	}

	unsigned n = db.countGames();
	printf("games=%u\n", n);

	// Companion .cbm media manifest present?
	cbh::MediaTable cbm;
	mstl::string base(cbhPath);
	mstl::string::size_type dot = base.rfind('.');
	if (dot != mstl::string::npos) base.resize(dot);
	mstl::string cbmPath = base + ".cbm";
	{
		mstl::ifstream f(cbmPath.c_str(), mstl::ios_base::in | mstl::ios_base::binary);
		if (f) { cbm.read(base, util::Progress::null()); f.close(); }
	}
	printf("cbm.open=%d cbm.files=%u\n", cbm.isOpen() ? 1 : 0, cbm.fileCount());

	unsigned nGuiding = 0, nHasMediaFlag = 0, nHasAudio = 0, nHasPic = 0, nHasVideo = 0;

	for (unsigned i = 0; i < n; ++i)
	{
		GameInfo const& gi = db.gameInfo(i);
		if (gi.isGuidingText()) ++nGuiding;
		if (gi.hasMedia()) ++nHasMediaFlag;
		if (gi.hasAudio()) ++nHasAudio;
		if (gi.hasPicture()) ++nHasPic;
		if (gi.hasVideo()) ++nHasVideo;
	}

	printf("guidingText games=%u\n", nGuiding);
	printf("hasMedia()>0  games=%u (audio=%u picture=%u video=%u)\n",
		nHasMediaFlag, nHasAudio, nHasPic, nHasVideo);

	// First few guiding-text games: run the real extractor + path resolver
	// against their HTML body and report what the Media tab would show,
	// including whether each resolved media file exists on disk.
	unsigned shown = 0;
	for (unsigned i = 0; i < n && shown < 8; ++i)
	{
		try
		{
			GameInfo const& gi = db.gameInfo(i);
			if (!gi.isGuidingText()) continue;
			Game g;
			mstl::string html;
			if (db.loadGame(i, g) == load::Ok)
				html = g.data().m_guidingText;
			mstl::vector<mstl::string> files; mstl::vector<int> types;
			tcl_media::extractGuidingTextMedia(html, files, types);
			printf("game %u hasMedia(idx)=%d guiding refs=%u:\n", i, gi.hasMedia()?1:0,
				(unsigned)files.size());
			for (unsigned k = 0; k < files.size(); ++k)
			{
				mstl::string path = tcl_media::resolveGuidingTextPath(cbhPath, files[k]);
				printf("    [%s] %s -> %s (exists=%d)\n",
					typeName(types[k]), files[k].c_str(), path.c_str(),
					access(path.c_str(), F_OK) == 0 ? 1 : 0);
			}
			if (files.empty())
				printf("    (no media refs in guiding-text body)\n");
			++shown;
		}
		catch (...)
		{
			printf("game %u loadGame/gameInfo threw (skipping)\n", i);
		}
	}

	db.close();
	return 0;
}
