// Explicit MEDIA_BACKEND=none: expose capability detection without a decoder.
#include <tcl.h>
#include <stdio.h>
namespace {
int unavailable(ClientData, Tcl_Interp* ti, int, Tcl_Obj* const*)
{
    Tcl_SetObjResult(ti, Tcl_NewBooleanObj(0));
    return TCL_OK;
}
int empty(ClientData, Tcl_Interp* ti, int, Tcl_Obj* const*)
{
    Tcl_ResetResult(ti);
    return TCL_OK;
}
}
namespace tcl { namespace media {
void init(Tcl_Interp* ti)
{
    fprintf(stderr, "Chesswiz: media playback disabled (MEDIA_BACKEND=none)\n");
    Tcl_EvalEx(ti, "namespace eval ::mpv {}", -1, TCL_EVAL_GLOBAL);
    Tcl_CreateObjCommand(ti, "::mpv::available", unavailable, 0, 0);
    Tcl_CreateObjCommand(ti, "::mpv::open", unavailable, 0, 0);
    Tcl_CreateObjCommand(ti, "::mpv::set", unavailable, 0, 0);
    Tcl_CreateObjCommand(ti, "::mpv::get", empty, 0, 0);
    Tcl_CreateObjCommand(ti, "::mpv::close", empty, 0, 0);
}
}}
