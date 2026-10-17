// ======================================================================
// Author : $Author$
// Version: $Revision: 1162 $
// Date   : $Date: 2017-05-13 09:01:49 -0400 (Sat, 13 May 2017) $
// Url    : $URL$
// ======================================================================

// ======================================================================
//    _/|            __
//   // o\         /    )           ,        /    /
//   || ._)    ----\---------__----------__-/----/__-
//   //__\          \      /   '  /    /   /    /   )
//   )___(     _(____/____(___ __/____(___/____(___/_
// ======================================================================

// ======================================================================
// Copyright: (C) 2009-2013 Gregor Cramer
// Modified for Chesswiz, 2026; see docs/UPSTREAM.md
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

#include "app_application.h"
#include "db_board.h"
#include "db_board_base.h"

#include "tk_init.h"
#include "tcl_base.h"
#include "tcl_application.h"

#include "u_zstream.h"

#include <tcl.h>
#include <tk.h>
#include <stdlib.h>
#include <stdio.h>

//#ifndef BROKEN_LINKER_HACK
//# define BROKEN_LINKER_HACK
//#endif

#ifdef BROKEN_LINKER_HACK
# include "db_board.h"
# include "db_home_pawns.h"
# include "db_signature.h"
# include "db_probe.h"
# include "sci_encoder.h"
# include "si3_encoder.h"
# include "tcl_progress.h"
#endif


static app::Application *m_app = nullptr;


static int
init(Tcl_Interp* ti)
{
	try
	{
		util::ZStream::setZipFileSuffixes(util::ZStream::Strings(1, "pgn"));

		if (Tcl_Init(ti) == TCL_ERROR || Tk_Init(ti) == TCL_ERROR)
			return TCL_ERROR;

		tcl::init(ti);
		tk::init(ti);

		Tcl_PkgProvide(ti, "tkscidb", "1.0");

#ifdef BROKEN_LINKER_HACK

		// HACK!
		// This hack is required for insane systems like Debian Wheezy,
		// and Ubuntu Oneiric. The static object initialization is not
		// properly working on these systems (among other problems).
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

#endif

		tcl::app::setup(m_app = new app::Application);


	}
	catch (mstl::exception const& exc)
	{
		fprintf(stderr, "exception catched: %s\n", exc.what());
	}

	return TCL_OK;	// satisfies the compiler
}


#ifdef _WIN32

# include <windows.h>
# include <shellapi.h>

// Exported by Tk on Windows, but declared only for UNICODE builds.
extern "C" void Tk_MainExW(int argc, wchar_t** argv, Tcl_AppInitProc* appInitProc, Tcl_Interp* interp);
# include <io.h>
# include <string.h>

static bool
isScript(char const* path)
{
	char const* ext = strrchr(path, '.');
	// tcl/chesswiz.exe is the bundle in a build tree.
	return ext && (_stricmp(ext, ".tcl") == 0 || _stricmp(ext, ".exe") == 0);
}


static bool
findBundle(char* path, size_t size)
{
	DWORD n = GetModuleFileNameA(0, path, DWORD(size));

	if (n == 0 || n >= size)
		return false;

	char* sep = strrchr(path, '\\');
	if (!sep || size_t(sep - path) + sizeof("\\chesswiz.tcl") > size)
		return false;

	strcpy(sep, "\\chesswiz.tcl");
	return GetFileAttributesA(path) != INVALID_FILE_ATTRIBUTES;
}


// A self-contained install keeps Tcl's script library in lib\tcl8.6 beside
// the exe; Tcl itself only looks in ..\lib (Tk then finds lib\tk8.6).
static void
setTclLibrary()
{
	char path[MAX_PATH + 32];
	DWORD n = GetModuleFileNameA(0, path, MAX_PATH);

	if (n == 0 || n >= MAX_PATH || getenv("TCL_LIBRARY"))
		return;

	char* sep = strrchr(path, '\\');
	if (!sep)
		return;

	strcpy(sep, "\\lib\\tcl8.6");
	char init[MAX_PATH + 48];
	strcpy(init, path);
	strcat(init, "\\init.tcl");

	if (GetFileAttributesA(init) != INVALID_FILE_ATTRIBUTES)
		_putenv_s("TCL_LIBRARY", path);
}


// The program's fonts (chess figurines, symbols) are registered for this
// process only (FR_PRIVATE): no installation, no admin rights (spec D8).
static void
registerFonts()
{
	char dir[MAX_PATH + 32];
	DWORD n = GetModuleFileNameA(0, dir, MAX_PATH);

	if (n == 0 || n >= MAX_PATH)
		return;

	char* sep = strrchr(dir, '\\');
	if (!sep)
		return;
	strcpy(sep + 1, "fonts\\");

	char pattern[MAX_PATH + 48];
	strcpy(pattern, dir);
	strcat(pattern, "*.ttf");

	WIN32_FIND_DATAA data;
	HANDLE h = FindFirstFileA(pattern, &data);

	if (h == INVALID_HANDLE_VALUE)
		return;

	do
	{
		char path[2*MAX_PATH + 48];
		strcpy(path, dir);
		strcat(path, data.cFileName);
		AddFontResourceExA(path, FR_PRIVATE, 0);
	}
	while (FindNextFileA(h, &data));

	FindClose(h);
}


// A GUI program has no stdout/stderr unless started from a console. Send
// them to %LOCALAPPDATA%\\Chesswiz\\chesswiz.log then, so Tcl gets its
// stdout/stderr channels and the log output isn't lost (spec D7).
static void
redirectStdio()
{
	HANDLE err = GetStdHandle(STD_ERROR_HANDLE);

	if (err && err != INVALID_HANDLE_VALUE)
		return;

	char const* base = getenv("LOCALAPPDATA");
	if (!base)
		return;

	char path[MAX_PATH + 64];
	snprintf(path, sizeof(path), "%s\\Chesswiz", base);
	CreateDirectoryA(path, 0);
	strcat(path, "\\chesswiz.log");

	if (!freopen(path, "w", stderr))
		return;
	setvbuf(stderr, 0, _IONBF, 0);
	if (freopen(path, "a", stdout))
		setvbuf(stdout, 0, _IONBF, 0);

	SetStdHandle(STD_ERROR_HANDLE, HANDLE(_get_osfhandle(_fileno(stderr))));
	SetStdHandle(STD_OUTPUT_HANDLE, HANDLE(_get_osfhandle(_fileno(stdout))));
}

#endif


int
main(int argc, char* argv[])
{
#ifdef _WIN32
	redirectStdio();
	setTclLibrary();
	registerFonts();

	// Without a script (a double click, or files to open as arguments) start
	// the bundle chesswiz.tcl beside the exe. The scripts are UTF-8, but Tk
	// would read the startup script in the system code page.
	{
		static char encodingOpt[] = "-encoding";
		static char utf8[] = "utf-8";
		static char bundle[MAX_PATH + 32];

		char* script = 0;
		int first = 1;

		if (argc > 1 && strcmp(argv[1], "-encoding") == 0)
		{
			// Tk's own "-encoding name script" form: leave it to Tk_Main.
		}
		else if (argc > 1 && argv[1][0] != '-' && isScript(argv[1]))
		{
			script = argv[1];
			first = 2;
		}
		else if (findBundle(bundle, sizeof(bundle)))
		{
			script = bundle;
		}

		if (script)
		{
			// The arguments from the wide command line: argv is in the system
			// code page and loses every file name character outside it.
			int wargc = 0;
			wchar_t** wargv = CommandLineToArgvW(GetCommandLineW(), &wargc);

			if (wargv && wargc == argc)
			{
				wchar_t wscript[MAX_PATH + 32];
				MultiByteToWideChar(CP_ACP, 0, script, -1, wscript, MAX_PATH + 32);
				if (script != bundle)
					wcsncpy(wscript, wargv[1], MAX_PATH + 31), wscript[MAX_PATH + 31] = 0;

				static wchar_t wencodingOpt[] = L"-encoding";
				static wchar_t wutf8[] = L"utf-8";
				wchar_t** args = new wchar_t*[argc + 4];
				int n = 0;

				args[n++] = wargv[0];
				args[n++] = wencodingOpt;
				args[n++] = wutf8;
				args[n++] = wscript;
				for (int i = first; i < argc; ++i)
					args[n++] = wargv[i];
				args[n] = 0;

				// The wide entry leaves [info nameofexecutable] empty.
				Tcl_FindExecutable(argv[0]);
				Tk_MainExW(n, args, init, Tcl_CreateInterp());
				return 0;
			}

			char** args = new char*[argc + 4];
			int n = 0;

			args[n++] = argv[0];
			args[n++] = encodingOpt;
			args[n++] = utf8;
			args[n++] = script;
			for (int i = first; i <= argc; ++i)
				args[n++] = argv[i];

			Tk_Main(n - 1, args, init);
			return 0;
		}
	}
#endif

	Tk_Main(argc, argv, init);
	return 0;
}

// vi:set ts=3 sw=3:
