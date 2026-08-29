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
#include <cctype>
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

	// Event semantics: dump every guiding-text record's event string, then
	// count regular games whose event() equals a guiding-text event (the
	// tournament-report linkage, CBM_FORMAT_DESIGN §7.6).
	{
		mstl::vector<mstl::string> gtEvents;
		for (unsigned i = 0; i < n; ++i)
		{
			GameInfo const& gi = db.gameInfo(i);
			if (gi.isGuidingText())
			{
				printf("gt rec %u event='%s' round=%u\n", i, gi.event().c_str(), gi.round());
				gtEvents.push_back(gi.event());
			}
		}
		printf("gt events=%u\n", (unsigned)gtEvents.size());

		// Block dump for the Bilbao report (rec 12059) — first 4 blocks with
		// their assigned media.
		{
			Game g;
			if (db.loadGame(12059, g) == load::Ok)
			{
				mstl::vector<tcl_media::GuidingTextGameBlock> bs;
				tcl_media::extractGuidingTextGameBlocks(g.data().m_guidingText, bs);
				printf("report 12059: %u blocks; first 4:\n", (unsigned)bs.size());
				for (unsigned b = 0; b < bs.size() && b < 4; ++b)
				{
					printf("  block %u: '%s'-'%s' y=%u r=%u files=%u:", b,
						bs[b].white.c_str(), bs[b].black.c_str(), bs[b].year, bs[b].round,
						(unsigned)bs[b].files.size());
					for (unsigned f = 0; f < bs[b].files.size(); ++f)
						printf(" [%s t%d]", bs[b].files[f].c_str(), bs[b].types[f]);
					printf("\n");
				}
			}
		}

		// Which guiding-text bodies carry CBLink(tag_game,...) anchors, and
		// how many blocks does the block parser build per report?
		for (unsigned i = 0; i < n; ++i)
		{
			GameInfo const& gi = db.gameInfo(i);
			if (!gi.isGuidingText()) continue;
			Game g;
			if (db.loadGame(i, g) != load::Ok) { printf("gt %u: load FAILED\n", i); continue; }
			mstl::string const& html = g.data().m_guidingText;
			unsigned anchors = 0;
			for (char const* p = html.c_str(); (p = ::strstr(p, "CBLink(tag_game")) != 0; p += 6)
				++anchors;
			mstl::vector<tcl_media::GuidingTextGameBlock> bs;
			tcl_media::extractGuidingTextGameBlocks(html, bs);
			printf("gt %u: html=%uB tag_game-occurrences=%u blocks=%u\n",
				i, unsigned(html.size()), anchors, (unsigned)bs.size());
			for (unsigned b = 0; b < bs.size() && b < 3; ++b)
				printf("    block %u: '%s' vs '%s' event='%s' y=%u r=%u files=%u\n",
					b, bs[b].white.c_str(), bs[b].black.c_str(), bs[b].event.c_str(),
					bs[b].year, bs[b].round, (unsigned)bs[b].files.size());
		}

		mstl::vector<unsigned> matches(gtEvents.size(), 0);
		// Probe: locate a few tag_game-linked games (Topalov–Anand Bilbao
		// 2008, Sinquefield 2015) and print their header fields to design
		// the anchor-matcher name/event/date/round normalization.
		struct ProbeNames { char const* w; char const* b; };
		ProbeNames probes[] =
		{
			{ "Topalov", "Anand" },
			{ "Carlsen", "Topalov" },
			{ "Aronian", "Carlsen" },
			{ "So", "Nakamura" },
		};
		for (unsigned i = 0; i < n; ++i)
		{
			GameInfo const& gi = db.gameInfo(i);
			if (gi.isGuidingText()) continue;
			for (unsigned p = 0; p < 4; ++p)
			{
				if (::strstr(gi.playerName(color::White).c_str(), probes[p].w)
					&& ::strstr(gi.playerName(color::Black).c_str(), probes[p].b))
				{
					printf("hdr %u W='%s' B='%s' event='%s' date=%u.%u round=%u\n",
						i, gi.playerName(color::White).c_str(), gi.playerName(color::Black).c_str(),
						gi.event().c_str(), gi.date().year(), gi.date().month(), gi.round());
				}
			}
		}

		// Match trace: run the exact cache-builder matching for a tagged game.
		{
			unsigned const idx = 12038; // Topalov - Anand, Grand Slam Final 2008 r4
			GameInfo const& gi = db.gameInfo(idx);
			printf("match-trace game %u: W='%s' B='%s' event='%s' y=%u r=%u\n",
				idx, gi.playerName(color::White).c_str(), gi.playerName(color::Black).c_str(),
				gi.event().c_str(), gi.date().year(), gi.round());
			for (unsigned k = 0; k < gtEvents.size(); ++k)
			{
				unsigned rec = 0;
				// load the report html for this gt record
				for (unsigned i = 0; i < n; ++i)
					if (db.gameInfo(i).isGuidingText() && db.gameInfo(i).event() == gtEvents[k])
						{ rec = i; break; }
				if (rec == 0 && k != 0) continue;
				Game g;
				if (db.loadGame(rec, g) != load::Ok) continue;
				mstl::vector<tcl_media::GuidingTextGameBlock> bs;
				tcl_media::extractGuidingTextGameBlocks(g.data().m_guidingText, bs);
				unsigned matched = 0;
				for (unsigned b = 0; b < bs.size(); ++b)
				{
					// replicated matcher key comparison
					mstl::string w = bs[b].white, b2 = bs[b].black;
					// lowercase-compare against the header names
					mstl::string sw = gi.playerName(color::White);
					mstl::string Sb = gi.playerName(color::Black);
					bool wOK = (sw.substr(0, w.size()) == w || sw.find(w) != mstl::string::npos);
					bool bOK = (Sb.find(b2) != mstl::string::npos);
					if (wOK && bOK && (bs[b].year == 0 || bs[b].year == gi.date().year())
						&& (bs[b].round == 0 || bs[b].round == gi.round()))
					{
						printf("  MATCH in report %u block %u: '%s'-%s y=%u r=%u files=%u\n",
							rec, b, w.c_str(), b2.c_str(), bs[b].year, bs[b].round,
							(unsigned)bs[b].files.size());
						for (unsigned f = 0; f < bs[b].files.size(); ++f)
							printf("      [%s t%d]\n", bs[b].files[f].c_str(), bs[b].types[f]);
						++matched;
						break;
					}
				}
				if (matched == 0 && rec != 0)
					printf("  no block matched in report %u (%u blocks)\n",
						rec, (unsigned)bs.size());
			}
		}

		// Simulator: exact replica of buildMediaLinkCache (tcl_database.cpp).
		{
			unsigned nGames = n;
			mstl::vector<unsigned> gts;
			for (unsigned i = 0; i < nGames; ++i)
				if (db.gameInfo(i).isGuidingText())
					gts.push_back(i);
			mstl::vector<tcl_media::GuidingTextGameBlock> all;
			unsigned loadFails = 0;
			for (unsigned k = 0; k < gts.size(); ++k)
			{
				Game g2;
				if (db.loadGame(gts[k], g2) != load::Ok) { ++loadFails; continue; }
				mstl::string const& h = g2.data().m_guidingText;
				if (!h.empty())
				{
					mstl::vector<tcl_media::GuidingTextGameBlock> one;
					tcl_media::extractGuidingTextGameBlocks(h, one);
					for (unsigned q = 0; q < one.size(); ++q)
						all.push_back(one[q]);
				}
			}
			printf("sim: gt=%u loadFails=%u blocks=%u\n",
				(unsigned)gts.size(), loadFails, (unsigned)all.size());

			struct LowerKey {
				static mstl::string key(mstl::string const& s)
				{
					mstl::string o;
					for (unsigned i = 0; i < s.size(); ++i)
						if (::isalnum((unsigned char)s[i]))
							o += ::tolower((unsigned char)s[i]);
					return o;
				}
			};
			mstl::vector<mstl::string> bw(all.size()), bb(all.size()), be(all.size());
			mstl::vector<unsigned> by(all.size(), 0), br(all.size(), 0);
			for (unsigned b = 0; b < all.size(); ++b)
			{
				bw[b] = LowerKey::key(all[b].white);
				bb[b] = LowerKey::key(all[b].black);
				be[b] = LowerKey::key(all[b].event);
				by[b] = all[b].year;
				br[b] = all[b].round;
			}
			unsigned mapped = 0, rows = 0;
			for (unsigned i = 0; i < nGames; ++i)
			{
				GameInfo const& gi = db.gameInfo(i);
				if (gi.isGuidingText()) continue;
				mstl::string wn = gi.playerName(color::White);
				mstl::string bn = gi.playerName(color::Black);
				mstl::string::size_type c1 = wn.find(',');
				mstl::string wk = LowerKey::key(c1 == mstl::string::npos ? wn : wn.substr(0, c1));
				mstl::string::size_type c2 = bn.find(',');
				mstl::string bk = LowerKey::key(c2 == mstl::string::npos ? bn : bn.substr(0, c2));
				mstl::string ev = LowerKey::key(gi.event());
				unsigned yr = gi.date().year();
				unsigned rd = gi.round();
				for (unsigned b = 0; b < all.size(); ++b)
				{
					if (bw[b] != wk || bb[b] != bk) continue;
					if (by[b] != 0 && by[b] != yr) continue;
					if (br[b] != 0 && br[b] != rd) continue;
					if (!be[b].empty() && ev.find(be[b]) == mstl::string::npos) continue;
					if (!all[b].files.empty()) { ++mapped; rows += all[b].files.size(); }
					break;
				}
			}
			printf("sim: mapped=%u rows=%u\n", mapped, rows);
			// show which game indexes mapped
			unsigned shown2 = 0;
			for (unsigned i = 0; i < nGames && shown2 < 26; ++i)
			{
				GameInfo const& gi = db.gameInfo(i);
				if (gi.isGuidingText()) continue;
				mstl::string wn = gi.playerName(color::White);
				mstl::string bn = gi.playerName(color::Black);
				mstl::string::size_type c1 = wn.find(',');
				mstl::string wk = LowerKey::key(c1 == mstl::string::npos ? wn : wn.substr(0, c1));
				mstl::string::size_type c2 = bn.find(',');
				mstl::string bk = LowerKey::key(c2 == mstl::string::npos ? bn : bn.substr(0, c2));
				mstl::string ev = LowerKey::key(gi.event());
				for (unsigned b = 0; b < all.size(); ++b)
				{
					if (bw[b] == wk && bb[b] == bk && (by[b] == 0 || by[b] == gi.date().year())
						&& (br[b] == 0 || br[b] == gi.round())
						&& (be[b].empty() || ev.find(be[b]) != mstl::string::npos))
					{
						if (!all[b].files.empty())
						{
							printf("  mapped %u (%s-%s, '%s') block %u files=%u\n",
								i, wn.c_str(), bn.c_str(), gi.event().c_str(), b,
								(unsigned)all[b].files.size());
							++shown2;
						}
						break;
					}
				}
			}
		}

		unsigned nSampled = 0;
		for (unsigned i = 0; i < n && nSampled < 6; ++i)
		{
			GameInfo const& gi = db.gameInfo(i);
			if (gi.isGuidingText() || gi.event().empty()) continue;
			if (nSampled < 6) { printf("game %u event='%s'\n", i, gi.event().c_str()); ++nSampled; }
		}
		for (unsigned i = 0; i < n; ++i)
		{
			GameInfo const& gi = db.gameInfo(i);
			if (gi.isGuidingText() || gi.event().empty()) continue;
			for (unsigned k = 0; k < gtEvents.size(); ++k)
				if (gi.event() == gtEvents[k]) { ++matches[k]; break; }
		}
		for (unsigned k = 0; k < gtEvents.size(); ++k)
			printf("event[%u]='%s' regular-games=%u\n", k, gtEvents[k].c_str(), matches[k]);
	}

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
