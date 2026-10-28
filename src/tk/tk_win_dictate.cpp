// ======================================================================
// Copyright: (C) 2026 Chesswiz
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

// Windows voice typing (Win+H) only types into controls that UI Automation
// reports as text fields; Tk 8.6 windows expose no UIA/MSAA provider. While
// dictating, a native EDIT control is laid exactly over the Tk entry, takes
// the focus and receives the dictated text. On commit the text is handed
// back to Tcl as UTF-16 and the EDIT is destroyed.
//
//   ::chesswiz::win::dictateEdit begin WINDOW TEXT CURSOR FAMILY SIZE WEIGHT COMMAND ?WINH?
//   ::chesswiz::win::dictateEdit settext TEXT    (test aid: WM_SETTEXT)
//   ::chesswiz::win::dictateEdit get
//   ::chesswiz::win::dictateEdit commit|cancel
//   ::chesswiz::win::dictateEdit active
//   ::chesswiz::win::dictateEdit hwnd
//
// COMMAND is called (at idle) as "COMMAND commit TEXT" or "COMMAND cancel {}".
// Commit happens on Enter, focus loss, or a timeout; Esc cancels.

#include "tk_init.h"

#ifdef _WIN32

#include <windows.h>
#include <tcl.h>
#include <tk.h>
#include <tkPlatDecls.h>
#include <string.h>

static_assert(sizeof(Tcl_UniChar) == sizeof(WCHAR), "Tcl_UniChar must be UTF-16");

namespace {

enum { PollMs = 250, IdleCommitMs = 8000, MaxMs = 120000, FocusGraceMs = 1500 };

struct State
{
	Tcl_Interp*			interp	= nullptr;
	HWND					edit		= nullptr;
	HWND					restore	= nullptr;
	HFONT					font		= nullptr;
	WNDPROC				proc		= nullptr;
	Tcl_Obj*				command	= nullptr;
	Tcl_TimerToken		timer		= nullptr;
	bool					finishing = false;
	DWORD					started	= 0;
	DWORD					changed	= 0;
	int					lastLen	= 0;
	bool					edited	= false;
};

State s;

Tcl_Obj*
editText()
{
	int len = GetWindowTextLengthW(s.edit);
	WCHAR* buf = reinterpret_cast<WCHAR*>(ckalloc((len + 1)*sizeof(WCHAR)));
	len = GetWindowTextW(s.edit, buf, len + 1);
	Tcl_Obj* obj = Tcl_NewUnicodeObj(reinterpret_cast<Tcl_UniChar*>(buf), len);
	ckfree(reinterpret_cast<char*>(buf));
	return obj;
}

void
teardown()
{
	if (s.timer)
		Tcl_DeleteTimerHandler(s.timer);
	s.timer = nullptr;
	if (s.edit)
	{
		SetWindowLongPtrW(s.edit, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(s.proc));
		DestroyWindow(s.edit);
	}
	if (s.font)
		DeleteObject(s.font);
	if (s.restore && IsWindow(s.restore))
		SetFocus(s.restore);
	s.edit = nullptr;
	s.font = nullptr;
	s.restore = nullptr;
}

// Runs at idle: never destroy the EDIT from inside its own window procedure.
void
finishIdle(ClientData data)
{
	bool commit = data != nullptr;
	if (!s.edit)
		return;

	Tcl_Obj* text = commit ? editText() : Tcl_NewObj();
	Tcl_IncrRefCount(text);
	Tcl_Obj* cmd = s.command;
	Tcl_Interp* ti = s.interp;
	s.command = nullptr;
	teardown();
	s.finishing = false;

	if (cmd)
	{
		Tcl_Obj* call = Tcl_DuplicateObj(cmd);
		Tcl_IncrRefCount(call);
		Tcl_ListObjAppendElement(ti, call, Tcl_NewStringObj(commit ? "commit" : "cancel", -1));
		Tcl_ListObjAppendElement(ti, call, text);
		if (Tcl_EvalObjEx(ti, call, TCL_EVAL_GLOBAL) != TCL_OK)
			Tcl_BackgroundException(ti, TCL_ERROR);
		Tcl_DecrRefCount(call);
		Tcl_DecrRefCount(cmd);
	}
	Tcl_DecrRefCount(text);
}

void
finish(bool commit)
{
	if (!s.edit || s.finishing)
		return;
	s.finishing = true;
	Tcl_DoWhenIdle(finishIdle, commit ? reinterpret_cast<ClientData>(1) : nullptr);
}

void
poll(ClientData)
{
	s.timer = nullptr;
	if (!s.edit || s.finishing)
		return;

	DWORD now = GetTickCount();
	int len = GetWindowTextLengthW(s.edit);
	if (len != s.lastLen)
	{
		s.lastLen = len;
		s.changed = now;
		s.edited = true;
	}

	// Focus moved elsewhere in this thread (click into the app) commits.
	// The voice-typing bar does not take the focus; ignore the first moments
	// while Win+H is being processed.
	HWND focus = GetFocus();
	if (focus != s.edit && now - s.started > FocusGraceMs)
		return finish(true);
	// Dictation stopped (the bar closes after silence) or ran too long.
	if (s.edited && now - s.changed > IdleCommitMs)
		return finish(true);
	if (now - s.started > MaxMs)
		return finish(true);

	s.timer = Tcl_CreateTimerHandler(PollMs, poll, nullptr);
}

LRESULT CALLBACK
editProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
	switch (msg)
	{
		case WM_GETDLGCODE:
			return DLGC_WANTALLKEYS | CallWindowProcW(s.proc, hwnd, msg, wp, lp);

		case WM_KEYDOWN:
			if (wp == VK_RETURN) { finish(true); return 0; }
			if (wp == VK_ESCAPE) { finish(false); return 0; }
			break;

		case WM_CHAR:
			if (wp == L'\r' || wp == 27 || wp == L'\n')
				return 0;	// no beep
			break;
	}
	return CallWindowProcW(s.proc, hwnd, msg, wp, lp);
}

void
sendWinH()
{
	INPUT in[4];
	memset(in, 0, sizeof(in));
	WORD keys[4] = { VK_LWIN, 'H', 'H', VK_LWIN };
	for (int i = 0; i < 4; ++i)
	{
		in[i].type = INPUT_KEYBOARD;
		in[i].ki.wVk = keys[i];
		in[i].ki.dwFlags = i < 2 ? 0 : KEYEVENTF_KEYUP;
	}
	SendInput(4, in, sizeof(INPUT));
}

int
begin(Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc < 9 || objc > 10)
	{
		Tcl_WrongNumArgs(ti, 2, objv, "window text cursor family size weight command ?winh?");
		return TCL_ERROR;
	}
	if (s.edit)
	{
		Tcl_SetObjResult(ti, Tcl_NewStringObj("dictation is already active", -1));
		return TCL_ERROR;
	}

	Tk_Window main = Tk_MainWindow(ti);
	Tk_Window tkwin = main ? Tk_NameToWindow(ti, Tcl_GetString(objv[2]), main) : nullptr;
	if (!tkwin)
		return TCL_ERROR;
	Tk_MakeWindowExist(tkwin);
	HWND entry = Tk_GetHWND(Tk_WindowId(tkwin));
	HWND parent = entry ? GetParent(entry) : nullptr;
	if (!entry || !parent)
	{
		Tcl_SetObjResult(ti, Tcl_NewStringObj("entry has no native window", -1));
		return TCL_ERROR;
	}

	int cursor, size, weight, winh = 1;
	if (	Tcl_GetIntFromObj(ti, objv[4], &cursor) != TCL_OK
		|| Tcl_GetIntFromObj(ti, objv[6], &size) != TCL_OK
		|| Tcl_GetIntFromObj(ti, objv[7], &weight) != TCL_OK
		|| (objc == 10 && Tcl_GetBooleanFromObj(ti, objv[9], &winh) != TCL_OK))
	{
		return TCL_ERROR;
	}

	RECT r;
	GetWindowRect(entry, &r);
	MapWindowPoints(nullptr, parent, reinterpret_cast<POINT*>(&r), 2);

	HINSTANCE inst = reinterpret_cast<HINSTANCE>(GetWindowLongPtrW(entry, GWLP_HINSTANCE));
	HWND edit = CreateWindowExW(
		0, L"EDIT", L"",
		WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | WS_BORDER | ES_AUTOHSCROLL | ES_LEFT,
		r.left, r.top, r.right - r.left, r.bottom - r.top,
		parent, nullptr, inst, nullptr);
	if (!edit)
	{
		Tcl_SetObjResult(ti, Tcl_NewStringObj("cannot create the dictation field", -1));
		return TCL_ERROR;
	}
	SetWindowPos(edit, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);

	// Tk font sizes: positive = points, negative = pixels.
	HDC dc = GetDC(nullptr);
	int height = size < 0 ? size : -MulDiv(size, GetDeviceCaps(dc, LOGPIXELSY), 72);
	ReleaseDC(nullptr, dc);
	int flen;
	Tcl_UniChar const* family = Tcl_GetUnicodeFromObj(objv[5], &flen);
	LOGFONTW lf;
	memset(&lf, 0, sizeof(lf));
	lf.lfHeight = height;
	lf.lfWeight = weight;
	lf.lfCharSet = DEFAULT_CHARSET;
	lf.lfQuality = CLEARTYPE_QUALITY;
	wcsncpy(lf.lfFaceName, reinterpret_cast<WCHAR const*>(family), LF_FACESIZE - 1);
	s.font = CreateFontIndirectW(&lf);
	if (s.font)
		SendMessageW(edit, WM_SETFONT, reinterpret_cast<WPARAM>(s.font), TRUE);

	int tlen;
	Tcl_UniChar const* text = Tcl_GetUnicodeFromObj(objv[3], &tlen);
	SetWindowTextW(edit, reinterpret_cast<WCHAR const*>(text));
	if (cursor < 0) cursor = 0;
	if (cursor > tlen) cursor = tlen;
	SendMessageW(edit, EM_SETSEL, cursor, cursor);

	s.interp = ti;
	s.edit = edit;
	s.restore = entry;
	s.proc = reinterpret_cast<WNDPROC>(
		SetWindowLongPtrW(edit, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(editProc)));
	s.command = objv[8];
	Tcl_IncrRefCount(s.command);
	s.started = s.changed = GetTickCount();
	s.lastLen = tlen;
	s.edited = false;
	s.finishing = false;

	SetFocus(edit);
	if (winh)
		sendWinH();
	s.timer = Tcl_CreateTimerHandler(PollMs, poll, nullptr);
	return TCL_OK;
}

int
cmdDictateEdit(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	static char const* subcmds[] = { "begin", "settext", "get", "commit", "cancel", "active", "hwnd", nullptr };
	enum { Begin, SetText, Get, Commit, Cancel, Active, Hwnd };
	int index;

	if (objc < 2)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "subcommand ?arg ...?");
		return TCL_ERROR;
	}
	if (Tcl_GetIndexFromObj(ti, objv[1], subcmds, "subcommand", 0, &index) != TCL_OK)
		return TCL_ERROR;

	switch (index)
	{
		case Begin:
			return begin(ti, objc, objv);

		case Active:
			Tcl_SetObjResult(ti, Tcl_NewBooleanObj(s.edit != nullptr));
			return TCL_OK;

		case Hwnd:
			Tcl_SetObjResult(ti, Tcl_NewWideIntObj(reinterpret_cast<Tcl_WideInt>(s.edit)));
			return TCL_OK;
	}

	if (!s.edit)
	{
		Tcl_SetObjResult(ti, Tcl_NewStringObj("dictation is not active", -1));
		return TCL_ERROR;
	}

	switch (index)
	{
		case SetText:
		{
			if (objc != 3)
			{
				Tcl_WrongNumArgs(ti, 2, objv, "text");
				return TCL_ERROR;
			}
			Tcl_UniChar const* text = Tcl_GetUnicodeFromObj(objv[2], nullptr);
			SendMessageW(s.edit, WM_SETTEXT, 0, reinterpret_cast<LPARAM>(text));
			break;
		}

		case Get:
			Tcl_SetObjResult(ti, editText());
			break;

		case Commit:
		case Cancel:
			finish(index == Commit);
			break;
	}
	return TCL_OK;
}

} // namespace

void
tk::win_dictate_init(Tcl_Interp* ti)
{
	Tcl_Eval(ti, "namespace eval ::chesswiz::win {}");
	Tcl_CreateObjCommand(ti, "::chesswiz::win::dictateEdit", cmdDictateEdit, nullptr, nullptr);
}

#else

void tk::win_dictate_init(Tcl_Interp*) {}

#endif

// vi:set ts=3 sw=3:
