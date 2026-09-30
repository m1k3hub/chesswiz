// ======================================================================
// tcl_diag.cpp — hang diagnosis for the running program.
//
// A frozen GUI cannot be inspected from inside (the assistant runs in the
// same event loop), so two out-of-band triggers dump what the program is
// doing:
//
//   SIGUSR1  posts a Tcl async handler, which runs ::application::diagnose::
//            dumpStack at the next command boundary of the interpreter.
//            That is where a Tcl-level stall lives: a busy-wait loop, a
//            synchronous exec or socket wait between commands, a long proc.
//   SIGUSR2  writes a native backtrace of the main thread to a file. It
//            works even if the thread sits in a C call that never returns
//            to the interpreter (the Tcl dump cannot run then).
//
//   ::diag::install NATIVEFILE   install both handlers (idempotent)
//   ::diag::tick                 the event loop is alive (called by a timer)
//   ::diag::watchdog SECONDS     when no tick arrives for SECONDS, raise both
//                                signals on the main thread once per stall;
//                                0 switches the watchdog off
//
// Nothing here does any work until a signal arrives or the watchdog fires.
// ======================================================================

#include "tcl_base.h"

#include <atomic>
#include <execinfo.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>

using namespace tcl;

namespace {

Tcl_AsyncHandler	Async = 0;
Tcl_Interp*			Interp = 0;
pthread_t			MainThread;
bool					Installed = false;
char					NativePath[1024] = "";

std::atomic<unsigned long>	Ticks(0);
std::atomic<int>				Threshold(0);	// seconds; 0 = watchdog off
bool								WatchdogStarted = false;


int
asyncProc(ClientData, Tcl_Interp*, int code)
{
	if (!Interp)
		return code;

	// the handler runs in the middle of whatever the interpreter was doing:
	// its result and error state must survive
	Tcl_InterpState state = Tcl_SaveInterpState(Interp, code);
	Tcl_EvalEx(Interp, "catch { ::application::diagnose::dumpStack signal }", -1, TCL_EVAL_GLOBAL);
	return Tcl_RestoreInterpState(Interp, state);
}


void
onUsr1(int)
{
	if (Async)
		Tcl_AsyncMark(Async);	// async-signal-safe
}


void
onUsr2(int)
{
	if (!NativePath[0])
		return;

	int fd = ::open(NativePath, O_WRONLY | O_CREAT | O_APPEND, 0644);

	if (fd < 0)
		return;

	static char const Header[] = "--- native backtrace of the main thread ---\n";
	void* frames[64];
	int n = ::backtrace(frames, 64);

	if (::write(fd, Header, sizeof(Header) - 1) < 0)
		n = 0;

	::backtrace_symbols_fd(frames, n, fd);
	::close(fd);
}


void*
watchdog(void*)
{
	unsigned long last = Ticks.load();
	int stalled = 0;
	bool dumped = false;

	while (true)
	{
		::sleep(1);

		int limit = Threshold.load();
		unsigned long now = Ticks.load();

		if (limit <= 0 || now != last)
		{
			last = now;
			stalled = 0;
			dumped = false;
		}
		else if (++stalled >= limit && !dumped)
		{
			dumped = true;	// once per stall
			pthread_kill(MainThread, SIGUSR2);
			pthread_kill(MainThread, SIGUSR1);
		}
	}

	return 0;
}


int
cmdInstall(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 2)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "nativeFile");
		return TCL_ERROR;
	}

	strncpy(NativePath, Tcl_GetString(objv[1]), sizeof(NativePath) - 1);

	if (!Installed)
	{
		Interp = ti;
		MainThread = pthread_self();
		Async = Tcl_AsyncCreate(asyncProc, 0);

		struct sigaction sa;
		memset(&sa, 0, sizeof(sa));
		sigemptyset(&sa.sa_mask);
		sa.sa_flags = SA_RESTART;

		sa.sa_handler = onUsr1;
		sigaction(SIGUSR1, &sa, 0);
		sa.sa_handler = onUsr2;
		sigaction(SIGUSR2, &sa, 0);

		Installed = true;
	}

	Tcl_SetObjResult(ti, Tcl_NewIntObj(1));
	return TCL_OK;
}


int
cmdTick(ClientData, Tcl_Interp*, int, Tcl_Obj* const[])
{
	++Ticks;
	return TCL_OK;
}


int
cmdWatchdog(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	int secs = 0;

	if (objc != 2)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "seconds");
		return TCL_ERROR;
	}
	if (Tcl_GetIntFromObj(ti, objv[1], &secs) != TCL_OK)
		return TCL_ERROR;
	if (!Installed)
	{
		Tcl_SetObjResult(ti, Tcl_NewStringObj("::diag::install must come first", -1));
		return TCL_ERROR;
	}

	Threshold = secs < 0 ? 0 : secs;

	if (secs > 0 && !WatchdogStarted)
	{
		pthread_t thread;

		if (pthread_create(&thread, 0, watchdog, 0) == 0)
		{
			pthread_detach(thread);
			WatchdogStarted = true;
		}
	}

	Tcl_SetObjResult(ti, Tcl_NewIntObj(WatchdogStarted || secs <= 0 ? 1 : 0));
	return TCL_OK;
}

} // namespace


namespace tcl {
namespace diag {

void
init(Tcl_Interp* ti)
{
	Tcl_CreateObjCommand(ti, "::diag::install",	cmdInstall,		0, 0);
	Tcl_CreateObjCommand(ti, "::diag::tick",		cmdTick,			0, 0);
	Tcl_CreateObjCommand(ti, "::diag::watchdog",	cmdWatchdog,	0, 0);
}

} // namespace diag
} // namespace tcl

// vi:set ts=3 sw=3:
