#include "harness_fake.h"
#ifdef CQL6_ROUNDTRIP
#include "roundtrip_baseline.cpp"
#else
#include "../tcl/tcl_cql6.cpp"
#endif
#include <cstdio>
thread_local Tcl_Interp* tcl::testInterp = nullptr;
::app::Application* tcl::app::scidb = nullptr;
static int openBase(ClientData, Tcl_Interp* ti, int n, Tcl_Obj* const v[]) {
 if(n != 3) return TCL_ERROR;
 int count; if(Tcl_GetIntFromObj(ti,v[2],&count)!=TCL_OK || count<0) return TCL_ERROR;
 auto c = std::make_unique<::app::Cursor>(); c->db.count=count;
 tcl::app::scidb->bases[Tcl_GetString(v[1])] = std::move(c); return TCL_OK;
}
static int closeBase(ClientData, Tcl_Interp*, int n, Tcl_Obj* const v[]) {
 if(n != 2) return TCL_ERROR;
 tcl::app::scidb->bases.erase(Tcl_GetString(v[1])); return TCL_OK;
}
static int jobs(ClientData, Tcl_Interp* ti, int, Tcl_Obj* const*) {
 std::lock_guard<std::mutex> lock(jobTable.mutex);
 Tcl_SetObjResult(ti,Tcl_NewIntObj(jobTable.jobs.size())); return TCL_OK;
}
static int engines(ClientData, Tcl_Interp* ti, int, Tcl_Obj* const*) {
 std::lock_guard<std::mutex> lock(jobTable.mutex);
 #ifdef CQL6_ROUNDTRIP
 Tcl_SetObjResult(ti,Tcl_NewIntObj(jobTable.jobs.size()));
#else
 Tcl_SetObjResult(ti,Tcl_NewIntObj(jobTable.engines));
#endif
 return TCL_OK;
}
static int child(ClientData, Tcl_Interp* ti, int, Tcl_Obj* const*) {
 auto old=tcl::testInterp;
 auto sub=Tcl_CreateInterp(); Tcl_Init(sub); tcl::testInterp=sub;
 tcl::cql6::init(sub);
 int rc=Tcl_Eval(sub,"::scidb::cql6::search big Normal SLOW -command list");
 std::string error=Tcl_GetStringResult(sub);
 Tcl_DoOneEvent(TCL_DONT_WAIT); // delete after a prefetch slice has been serviced
 Tcl_DeleteInterp(sub); tcl::testInterp=old;
 if(rc) Tcl_SetObjResult(ti,Tcl_NewStringObj(error.c_str(),-1)); return rc;
}
int main(int argc, char** argv) {
 Tcl_FindExecutable(argv[0]);
 ::app::Application application; tcl::app::scidb=&application;
 auto ti=Tcl_CreateInterp(); tcl::testInterp=ti;
 if(Tcl_Init(ti)!=TCL_OK) return 2;
 // Initialize the real Tcl notifier before creating any coordinator thread.
 Tcl_DoOneEvent(TCL_DONT_WAIT);
 tcl::cql6::init(ti);
 Tcl_CreateObjCommand(ti,"::scidb::db::open",openBase,nullptr,nullptr);
 Tcl_CreateObjCommand(ti,"::scidb::db::close",closeBase,nullptr,nullptr);
 Tcl_CreateObjCommand(ti,"testJobs",jobs,nullptr,nullptr);
 Tcl_CreateObjCommand(ti,"testEngines",engines,nullptr,nullptr);
 Tcl_CreateObjCommand(ti,"testDelete",child,nullptr,nullptr);
 int rc=argc==2 ? Tcl_EvalFile(ti,argv[1]) : TCL_ERROR;
 if(rc) fprintf(stderr,"%s\n",Tcl_GetVar(ti,"errorInfo",TCL_GLOBAL_ONLY));
 Tcl_DeleteInterp(ti);
 // Interpreter deletion cancels detached jobs; wait until their C++ owners leave.
 for(int i=0;i<1000;++i) { Tcl_DoOneEvent(TCL_DONT_WAIT); std::this_thread::sleep_for(std::chrono::milliseconds(1)); }
 Tcl_Finalize(); return rc==TCL_OK ? 0 : 1;
}
