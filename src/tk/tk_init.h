// ======================================================================
// Author : $Author$
// Version: $Revision: 1213 $
// Date   : $Date: 2017-06-24 09:30:42 -0400 (Sat, 24 Jun 2017) $
// Url    : $URL$
// ======================================================================

// ======================================================================
// Copyright: (C) 2008-2013 Gregor Cramer
// Modified for Chesswiz, 2026; see docs/UPSTREAM.md
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#ifndef _tk_init_defined
#define _tk_init_defined

extern "C" { struct Tcl_Interp; }

namespace tk { void init(Tcl_Interp* ti); }

// internally used
namespace tk {

void fixes_init(Tcl_Interp*);
void selection_init(Tcl_Interp*);
void image_init(Tcl_Interp*);
void jpeg_init(Tcl_Interp*);
void png_init(Tcl_Interp*);
void gif_init(Tcl_Interp*);
void window_manager_init(Tcl_Interp*);
void twm_init(Tcl_Interp*);
void xcursor_init(Tcl_Interp*);
void x11_init(Tcl_Interp*);
void busy_init(Tcl_Interp*);
void multiwindow_init(Tcl_Interp*);
void panedwindow_init(Tcl_Interp*);
void notebook_init(Tcl_Interp*);
void clockInit(Tcl_Interp*);
void miscInit(Tcl_Interp*);
void glboard_init(Tcl_Interp*);

}

#endif // _tk_init_defined

// vi:set ts=3 sw=3:
