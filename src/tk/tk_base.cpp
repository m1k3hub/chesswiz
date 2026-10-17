// ======================================================================
// Author : $Author: gcramer $
// Version: $Revision: 1295 $
// Date   : $Date: 2017-07-24 15:35:37 -0400 (Mon, 24 Jul 2017) $
// Url    : $URL: https://svn.code.sf.net/p/scidb/code/trunk/src/tk/tk_base.cpp $
// ======================================================================

// ======================================================================
//    _/|            __
//   // o\         /    )           ,        /    /
//   || ._)    ----\---------__----------__-/----/__-
//   //__\          \      /   '  /    /   /    /   )
//   )___(     _(____/____(___ __/____(___/____(___/_
// ======================================================================

// ======================================================================
// Copyright: (C) 2010-2017 Gregor Cramer
// Modified for Chesswiz, 2026; see docs/UPSTREAM.md
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#include "tk_base.h"

#include "tcl_exception.h"

#include <tkInt.h>
#ifdef __APPLE__
# include <tkMacOSXInt.h>
#endif
#ifdef _WIN32
# include <tkWinInt.h>
#endif


#ifndef _WIN32
extern "C" { void TkpWmSetState(TkWindow* winPtr, int state); }
#endif


static void
reparent(TkWindow* childPtr, TkWindow* newParentPtr = nullptr)
{
	M_ASSERT(childPtr);
	M_ASSERT(childPtr->window);
	M_ASSERT(!newParentPtr || newParentPtr->window);

#if defined(__WIN32__) || defined(__WIN64__)

	// Reparent to nullptr so UpdateWrapper won't delete our original parent window
	HWND handle = newParentPtr ? TkWinGetHWND(newParentPtr->window) : nullptr;
	SetParent(TkWinGetHWND(childPtr->window), handle);

#elif defined(__APPLE__)

	// Aqua child windows share their toplevel drawable and NSView.
	if (newParentPtr) {
		MacDrawable* draw = childPtr->privatePtr;
		MacDrawable* top = newParentPtr->privatePtr->toplevel;
		if (draw->toplevel != top) {
			draw->toplevel->referenceCount--;
			draw->toplevel = top;
			top->referenceCount++;
		}
		draw->view = top->view;
		draw->xOff = newParentPtr->privatePtr->xOff + childPtr->changes.x;
		draw->yOff = newParentPtr->privatePtr->yOff + childPtr->changes.y;
		TkMacOSXInvalidateWindow(draw, TK_PARENT_WINDOW);
		for (TkWindow* child = childPtr->childList; child; child = child->nextPtr)
			if (!(child->flags & TK_TOP_LEVEL) && child->window)
				reparent(child, childPtr);
	}

#else // if defined(__unix__)

	Window parent = newParentPtr ?
		newParentPtr->window : XRootWindow(childPtr->display, childPtr->screenNum);
	XReparentWindow(childPtr->display, childPtr->window, parent, 0, 0);

#endif
}


static void
unlinkWindow(TkWindow* winPtr)
{
	M_ASSERT(winPtr);

	if (!winPtr->parentPtr)
		return;

	TkWindow* prevPtr = winPtr->parentPtr->childList;

	if (prevPtr == winPtr)
	{
		if (!(winPtr->parentPtr->childList = winPtr->nextPtr))
			winPtr->parentPtr->lastChildPtr = nullptr;
	}
	else
	{
		for ( ; prevPtr->nextPtr != winPtr; prevPtr = prevPtr->nextPtr)
			M_ASSERT(prevPtr);

		if (!(prevPtr->nextPtr = prevPtr->nextPtr->nextPtr))
			winPtr->parentPtr->lastChildPtr = prevPtr;
	}

	winPtr->nextPtr = nullptr;
}


static void
linkWindow(TkWindow* winPtr)
{
	M_ASSERT(winPtr);

	if (!winPtr->parentPtr)
		return;

	TkWindow* parent = winPtr->parentPtr;

	if (TkWindow* prevPtr = parent->childList)
	{
		while (prevPtr->nextPtr)
			prevPtr = prevPtr->nextPtr;

		prevPtr->nextPtr = winPtr;
	}
	else
	{
		parent->childList = winPtr;
	}

	winPtr->nextPtr = nullptr;
	parent->lastChildPtr = winPtr;
}


static void
relink(TkWindow* childPtr, TkWindow* newParentPtr)
{
	M_ASSERT(childPtr);
	M_ASSERT(newParentPtr);
	M_ASSERT(childPtr->parentPtr != newParentPtr);

	unlinkWindow(childPtr);
	childPtr->parentPtr = newParentPtr;
	linkWindow(childPtr);
}


bool
tk::isAlreadyDead(Tcl_Obj* obj)
{
	M_ASSERT(obj);
	return exists(obj) && bool(reinterpret_cast<TkWindow*>(window(obj))->flags & TK_ALREADY_DEAD);
}


Tk_Window
tk::mainWindow()
{
	Tk_Window w = Tk_MainWindow(::tcl::interp());

	if (!w)
		M_THROW(tcl::Exception("no main window exists"));
	
	return w;
}


Tk_Window
tk::window(char const* path)
{
	M_REQUIRE(path);

	Tk_Window w = Tk_NameToWindow(::tcl::interp(), path, mainWindow());

	if (!w)
		M_THROW(tcl::Exception("invalid window '%s'", path));
	
	return w;
}


Tk_Window
tk::toplevel(Tk_Window window)
{
	M_ASSERT(window);

	while (!isToplevel(window))
		window = parent(window);

	return window;
}


void
tk::raise(Tk_Window window, Tk_Window aboveThis)
{
	M_REQUIRE(window);
	M_REQUIRE(aboveThis);

	if (Tk_RestackWindow(window, Above, aboveThis) != TCL_OK)
	{
		M_THROW(tcl::Exception(
			"can't raise \"%s\" above \"%s\"",
			Tk_PathName(window),
			Tk_PathName(aboveThis)));
	}
}


void
tk::reparent(Tk_Window child, Tk_Window newParent)
{
	M_REQUIRE(child);
	M_REQUIRE(newParent);

	if (parent(child) == newParent)
		return;

	TkWindow* childPtr	= reinterpret_cast<TkWindow*>(child);
	TkWindow* parentPtr	= reinterpret_cast<TkWindow*>(newParent);

	if (!isToplevel(child) && parentPtr->window == None)
		unmap(child);
	
	::relink(childPtr, parentPtr);

	if (!isToplevel(child) && childPtr->window != None && parentPtr->window != None)
		::reparent(childPtr, parentPtr);
}


#ifdef __APPLE__
static bool aquaWm(Tk_Window window, const char* operation)
{
	Tcl_Interp* ti = Tk_Interp(window);
	Tcl_Obj* args[] = { Tcl_NewStringObj("wm", -1),
	    Tcl_NewStringObj(operation, -1), Tcl_NewStringObj(Tk_PathName(window), -1) };
	for (unsigned i = 0; i < 3; ++i) Tcl_IncrRefCount(args[i]);
	int rc = Tcl_EvalObjv(ti, 3, args, TCL_EVAL_GLOBAL);
	for (unsigned i = 0; i < 3; ++i) Tcl_DecrRefCount(args[i]);
	return rc == TCL_OK;
}
#endif


bool
tk::release(Tk_Window window)
{
	M_REQUIRE(window);

	if (isToplevel(window))
		return false;

#ifdef __APPLE__
	return aquaWm(window, "manage");
#endif

	// detach the window from its gemoetry manager, if any
	unmanage(window);

	TkWindow* winPtr = reinterpret_cast<TkWindow*>(window);

	// TkFocusSplit(winPtr); // has hidden scope
	// We hope that this toplevel don't has a focus record.

	if (winPtr->window == None)
	{
		// The window is not created yet, we still have time
		// to make it an legitimate toplevel window.
		winPtr->dirtyAtts |= CWBorderPixel;
	}
	else
	{
		if (winPtr->flags & TK_MAPPED)
			unmap(window);

		::reparent(winPtr);
	}

	winPtr->flags |= TK_TOP_HIERARCHY | TK_TOP_LEVEL | TK_HAS_WRAPPER | TK_WIN_MANAGED;

	TkWmNewWindow(winPtr);
	TkpWmSetState(winPtr, WithdrawnState);

	// Size was set - force a call to Geometry Manager
	winPtr->reqWidth++;
	winPtr->reqHeight++;
	Tk_GeometryRequest(window, winPtr->reqWidth - 1, winPtr->reqHeight - 1);
	//Tk_GeometryRequest(mainWindow(), winPtr->reqWidth - 1, winPtr->reqHeight - 1);

	TkWmMapWindow(winPtr);

	return true;
}


bool
tk::capture(Tk_Window tkwin, Tk_Window tkparent)
{
	TkWindow* winPtr = reinterpret_cast<TkWindow*>(tkwin);

	if (!winPtr->parentPtr)
		return false;

	if (!(winPtr->flags & TK_TOP_LEVEL))
		return true; // window is already captured

#ifdef __APPLE__
	if (tkparent && tkparent != reinterpret_cast<Tk_Window>(winPtr->parentPtr))
		::relink(winPtr, reinterpret_cast<TkWindow*>(tkparent));
	return aquaWm(tkwin, "forget");
#endif

	// withdraw the window
	TkpWmSetState(winPtr, WithdrawnState);

	if (tkparent && tkparent != reinterpret_cast<Tk_Window>(winPtr->parentPtr))
		::relink(winPtr, reinterpret_cast<TkWindow*>(tkparent));

	if (winPtr->window == None)
	{
		// cause this and parent window to exist
		winPtr->atts.event_mask &= ~StructureNotifyMask;
		winPtr->flags &= ~TK_TOP_LEVEL;
	}
	else
	{
		XSetWindowAttributes atts;

#ifdef __WIN32__

		// SetParent must be done before TkWmDeadWindow or it's DestroyWindow on the
		// parent Hwnd will also destroy the child
		makeExists(reinterpret_cast<Tk_Window>(winPtr->parentPtr));
		::reparent(winPtr, winPtr->parentPtr);
		// Dis-associate from wm
		TkWmDeadWindow(winPtr);

#elif defined(__APPLE__)
	// Handled above by Tk Aqua wm forget.

#else // if defined(__unix__)

		TkWmDeadWindow(winPtr);
		XUnmapWindow(winPtr->display, winPtr->window);
		makeExists(reinterpret_cast<Tk_Window>(winPtr->parentPtr));
		::reparent(winPtr, winPtr->parentPtr);

#endif

		// clear those attributes that non-toplevel windows don't possess
		winPtr->flags &= ~(TK_TOP_HIERARCHY | TK_TOP_LEVEL | TK_HAS_WRAPPER | TK_WIN_MANAGED);
		atts.event_mask = winPtr->atts.event_mask;
		atts.event_mask &= ~StructureNotifyMask;
		Tk_ChangeWindowAttributes(tkwin, CWEventMask, &atts);
	}

	unmanage(tkwin);

	// Can't delete the TopLevelEventProc, because this definition only exists
	// in tkWinWm.c or tkUnixWm.c. Is having this event handler around really cause
	// a problem?
//	Tk_DeleteEventHandler(tkwin, StructureNotifyMask, TopLevelEventProc, winPtr);

	return true;
}

// vi:set ts=3 sw=3:
