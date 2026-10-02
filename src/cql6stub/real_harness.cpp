// Headless app-backed runner: real database/codecs and Tcl, without Tk startup.
#include "../app/app_application.h"
#include "../tcl/tcl_application.h"
#include "../tcl/tcl_base.h"
#include "../util/u_zstream.h"
#include <tcl.h>
#include <cstdio>
#include "db_board.h"
#include "db_board_base.h"
#include "db_home_pawns.h"
#include "db_signature.h"
#include "db_probe.h"
#include "sci_encoder.h"
#include "si3_encoder.h"
#include "tcl_progress.h"
extern "C" int Treectrl_Init(Tcl_Interp*) { return TCL_OK; }
int main(int argc,char** argv) {
 Tcl_FindExecutable(argv[0]);
 auto ti=Tcl_CreateInterp();
 if(Tcl_Init(ti)!=TCL_OK) return 2;
 Tcl_DoOneEvent(TCL_DONT_WAIT);
 util::ZStream::setZipFileSuffixes(util::ZStream::Strings(1,"pgn"));
 db::tag::initialize();
 db::castling::initialize();
 db::board::base::initialize();
 db::Board::initialize();
 db::HomePawns::initialize();
 db::Signature::initialize();
 db::Probe::initialize();
 db::sci::Encoder::initialize();
 db::si3::Encoder::initialize();
 tcl::Progress::initialize();
 tcl::init(ti);
 auto application = new app::Application;
 tcl::app::setup(application);
 if(Tcl_Eval(ti,"::scidb::app::load eco src/data/eco.bin; ::scidb::app::load done")!=TCL_OK) {fprintf(stderr,"%s\n",Tcl_GetStringResult(ti)); return 2;}
 int rc=argc==2 ? Tcl_EvalFile(ti,argv[1]) : TCL_ERROR;
 if(rc) fprintf(stderr,"%s\n",Tcl_GetVar(ti,"errorInfo",TCL_GLOBAL_ONLY));
 Tcl_DeleteInterp(ti);
 // Match tkscidb: its process-lifetime Application is not destroyed.
 Tcl_Finalize(); return rc==TCL_OK ? 0 : 1;
}
