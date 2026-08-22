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
#include "db/db_game_info.h"
#include "db/db_home_pawns.h"
#include "db/db_signature.h"
#include "db/db_statistic.h"
#include "db/sci/sci_encoder.h"
#include "db/cbh/cbh_media.h"
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

	// First few guiding-text games: report whether their HTML body really
	// references media (the .html sibling folder is where ChessBase files live).
	unsigned shown = 0;
	for (unsigned i = 0; i < n && shown < 8; ++i)
	{
		GameInfo const& gi = db.gameInfo(i);
		if (!gi.isGuidingText()) continue;
		Game g;
		mstl::string html;
		if (db.loadGame(i, g) == load::Ok)
			html = g.data().m_guidingText;
		int cImg = 0, cTs = 0;
		{ // substring counts for "<IMG" and "tag_stream" (body is ASCII)
			char const* s = html.c_str();
			for (mstl::string::size_type j = 0; j + 4 <= html.size(); ++j)
				if (s[j] == '<' && (s[j+1]=='I'||s[j+1]=='i')
					&& (s[j+2]=='M'||s[j+2]=='m') && (s[j+3]=='G'||s[j+3]=='g'))
					++cImg;
			for (mstl::string::size_type j = 0; j + 10 <= html.size(); ++j)
				if (strncmp(s+j, "tag_stream", 10) == 0) ++cTs;
		}
		printf("game %u hasMedia(idx)=%d htmlLen=%lu <IMG>=%d tag_stream=%d\n", i,
			gi.hasMedia()?1:0, (unsigned long)html.size(), cImg, cTs);
		++shown;
	}

	db.close();
	return 0;
}
