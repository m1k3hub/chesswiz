// ======================================================================
// 3D OpenGL Chessboard Renderer for Tk / Togl
// ======================================================================

#ifndef _tk_glboard_defined
#define _tk_glboard_defined

extern "C" { struct Tcl_Interp; }

namespace tk {

void glboard_init(Tcl_Interp* ti);

}

#endif // _tk_glboard_defined
