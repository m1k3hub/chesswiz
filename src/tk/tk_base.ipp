// ======================================================================
// Author : $Author: gcramer $
// Version: $Revision: 1295 $
// Date   : $Date: 2017-07-24 15:35:37 -0400 (Mon, 24 Jul 2017) $
// Url    : $URL: https://svn.code.sf.net/p/scidb/code/trunk/src/tk/tk_base.ipp $
// ======================================================================

// ======================================================================
//    _/|            __
//   // o\         /    )           ,        /    /
//   || ._)    ----\---------__----------__-/----/__-
//   //__\          \      /   '  /    /   /    /   )
//   )___(     _(____/____(___ __/____(___/____(___/_
// ======================================================================

// ======================================================================
// Copyright: (C) 2017 Gregor Cramer
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#include "tcl_base.h"

#include "m_assert.h"


inline Tk_Window tk::window(Tcl_Obj* path) { return window(tcl::asString(path)); }


inline
Tk_Window
tk::parent(Tk_Window window)
{
	M_REQUIRE(window);
	return Tk_Parent(window);
}


inline
int
tk::x(Tk_Window window)
{
	M_REQUIRE(window);
	return Tk_X(window);
}


inline
int
tk::y(Tk_Window window)
{
	M_REQUIRE(window);
	return Tk_Y(window);
}


inline
int
tk::width(Tk_Window window)
{
	M_REQUIRE(window);
	return Tk_Width(window);
}


inline
int
tk::height(Tk_Window window)
{
	M_REQUIRE(window);
	return Tk_Height(window);
}


inline
int
tk::rootx(Tk_Window window)
{
	M_REQUIRE(window);

	int x, y;
	Tk_GetRootCoords(window, &x, &y);
	return x;
}


inline
int
tk::rooty(Tk_Window window)
{
	M_REQUIRE(window);

	int x, y;
	Tk_GetRootCoords(window, &x, &y);
	return y;
}


inline
void
tk::makeExists(Tk_Window window)
{
	M_REQUIRE(window);
	Tk_MakeWindowExist(window);
}


inline
bool
tk::exists(char const* path)
{
	M_REQUIRE(path);

	// During exit teardown Tk destroys the main window before its children;
	// the <Destroy> bindings of the children still run and ask whether their
	// window exists. With no main window the honest answer is "no" --
	// mainWindow() would throw, and throws from destructors (Node::~Node)
	// and raw event callbacks terminate the process.
	Tk_Window main = Tk_MainWindow(::tcl::interp());
	return main && Tk_NameToWindow(::tcl::interp(), path, main);
}


inline bool tk::exists(Tcl_Obj* obj) { return exists(tcl::asString(obj)); }


inline
bool
tk::isToplevel(Tk_Window window)
{
	M_REQUIRE(window);
	return Tk_IsTopLevel(window);
}


inline
bool
tk::isMapped(Tk_Window window)
{
	M_REQUIRE(window);
	return Tk_IsMapped(window);
}


inline
char const*
tk::name(Tk_Window window)
{
	M_REQUIRE(window);
	return Tk_PathName(window);
}


inline
void
tk::unmap(Tk_Window window)
{
	M_REQUIRE(window);
	Tk_UnmapWindow(window);
}


inline
void
tk::unmanage(Tk_Window window)
{
	M_REQUIRE(window);
	Tk_ManageGeometry(window, nullptr, nullptr);
}


inline
void
tk::resize(Tk_Window window, int width, int height)
{
	M_REQUIRE(window);
	M_REQUIRE(width >= 0);
	M_REQUIRE(height >= 0);

	Tk_ResizeWindow(window, width > 0 ? width : 1, height > 0 ? height : 1);
}


inline
void
tk::createEventHandler(Tk_Window window, unsigned long mask, Tk_EventProc* proc, void* clientData)
{
	M_REQUIRE(window);
	M_REQUIRE(mask);
	M_REQUIRE(proc);

	Tk_CreateEventHandler(window, mask, proc, clientData);
}


inline
void
tk::deleteEventHandler(Tk_Window window, unsigned long mask, Tk_EventProc* proc, void* clientData)
{
	M_REQUIRE(window);
	M_REQUIRE(mask);
	M_REQUIRE(proc);

	Tk_DeleteEventHandler(window, mask, proc, clientData);
}

// vi:set ts=3 sw=3:
