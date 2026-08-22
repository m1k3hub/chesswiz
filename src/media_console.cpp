// ======================================================================
// media_console — headless scidb "media console" for end-to-end (e2e)
// testing of the media commands (::scidb::db::mediaFiles, mediaGallery,
// etc.) without booting the full GUI app.
//
// Unlike `tclscidb` (which only registers zlib::crc), this console boots the
// scidb Tcl + Tk layers and creates the app::Application singleton — the same
// registration path tkscidb uses — so every ::scidb::db::* command is present.
// Tk_Init requires a display, so run under xvfb-run:
//   xvfb-run -a ./src/media_console script.tcl
//
// The ECO opening table is loaded at startup (build-tree or SCIDB_ECO_FILE)
// so getGameInfo()/mediaFiles() do not recurse in EcoTable::getOpening.
//
// Usage (like tclsh):
//   ./media_console script.tcl                # run a script
//   ./media_console                           # interactive REPL
// ======================================================================

#include "tcl/tcl_base.h"
#include "tcl/tcl_application.h"
#include "app/app_application.h"
#include "tk_init.h"

#include "db/db_common.h"
#include "db/db_eco_table.h"
#include "db/db_board.h"
#include "db/db_board_base.h"
#include "db/db_home_pawns.h"
#include "db/db_signature.h"
#include "db/sci/sci_encoder.h"
#include "m_ifstream.h"

namespace db { class EcoTable; }
using db::EcoTable;

#include <tcl.h>
#include <tk.h>

#include <stdlib.h>

static ::app::Application* m_app = nullptr;

#ifndef SHAREDIR
# define SHAREDIR ""
#endif

// Initialize the static move/codec tables (mirrors make_media_test.cpp's
// initializeStatics). Required before EcoTable::load can replay moves.
static void
initializeStatics()
{
	db::tag::initialize();
	db::castling::initialize();
	db::board::base::initialize();
	db::Board::initialize();
	db::HomePawns::initialize();
	db::Signature::initialize();
	db::sci::Encoder::initialize();
}

// Load the ECO opening table. getGameInfo()/gameInfo() render the opening
// name and recurse forever (EcoTable::getOpening) if the specimen table is
// empty, so we must populate it before any game-info lookup. Try the install
// sharedir, an env override, and a couple of build-tree locations.
static void
loadEcoTable()
{
	char const* candidates[] = {
		::getenv("SCIDB_ECO_FILE")		? ::getenv("SCIDB_ECO_FILE")	: "",
		"src/data/eco.bin",
		"data/eco.bin",
		SHAREDIR "/data/eco.bin",
	};

	for (unsigned i = 0; i < sizeof(candidates) / sizeof(candidates[0]); ++i)
	{
		char const* path = candidates[i];
		if (!path || !*path)
			continue;
		mstl::ifstream stream(path, mstl::ios_base::in | mstl::ios_base::binary);
		if (!stream)
			continue;
		try
		{
			EcoTable::specimen(db::variant::Normal).load(stream, db::variant::Normal);
			fprintf(stderr, "media_console: loaded ECO from %s\n", path);
		}
		catch (...)
		{
			fprintf(stderr, "media_console: failed to parse ECO from %s\n", path);
			continue;
		}
		return;
	}
	fprintf(stderr, "media_console: no ECO file found; opening-name lookup may recurse\n");
}

static int
init(Tcl_Interp* ti)
{
	// Tcl + Tk are both required: tcl::init() registers the ::scidb::db::*
	// commands but also pulls in Treectrl (via tcl::init), whose option-table
	// machinery dereferences the Tk main window. So we boot Tk, tcl::init and
	// tk::init exactly like tkscidb does, and create the app::Application
	// singleton that the ::scidb::db::* commands call into.
	// This needs a display; run under xvfb-run (the media e2e tests do).
	if (Tcl_Init(ti) == TCL_ERROR || Tk_Init(ti) == TCL_ERROR)
		return TCL_ERROR;

	tcl::init(ti);
	tk::init(ti);

	tcl::app::setup(m_app = new ::app::Application);

	// Static tables (move gen, castling, tags, ...) must be initialized before
	// the ECO table is loaded — otherwise loading opening lines (which replay
	// moves on a Board) hits low-level board I-clean assertions. Mirror
	// make_media_test's initializeStatics().
	initializeStatics();

	loadEcoTable();

	return Tcl_PkgProvide(ti, "mediaconsole", "1.0");
}

int
main(int argc, char* argv[])
{
	Tcl_Main(argc, argv, init);
	return 0;
}

// vi:set ts=3 sw=3:
