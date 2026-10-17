// ======================================================================
// tcl_media.cpp — in-process libmpv playback for the media panel.
//
// One player at a time, embedded into a Tk window (--wid) with the plain
// X11 video output. The GL/EGL render API is deliberately not used: it
// was what crashed against Tk's X11 windows (BadMatch on teardown) in an
// earlier backend. The Tcl side (tcl/app-media-mpv.tcl) wraps these
// commands as ::media::mpv::*.
//
//   ::mpv::open WID FILE ?STARTSEC?   start playback; 1, or 0 on failure
//   ::mpv::get PROPERTY               property as a string, {} if unavailable;
//                                     "load-error" is "yes" once the file failed to load
//   ::mpv::set PROPERTY VALUE         1 on success, else 0
//   ::mpv::close                      stop and release the player
//   ::mpv::available                  1 (the command exists only when linked)
//
// Properties are read in-process (microseconds), so the GUI thread never
// waits on a socket or a helper process.
// ======================================================================

#include <stdlib.h>
#include "tcl_base.h"

#include <mpv/client.h>
#include <tk.h>
#include <X11/Xlib.h>

#include <string.h>
#include <map>
#include <string>

using namespace tcl;

namespace {

mpv_handle* Player = 0;

// The X error handler is process-global. mpv's X11 output installs its own
// and, on shutdown, puts back the Xlib default, which silently removes Tk's
// handler: Tk's routine queries of windows that are just being destroyed
// then become fatal "BadWindow" errors. Tk's handler is saved before mpv
// starts and restored after it is gone.
XErrorHandler TkErrorHandler = 0;
bool TkErrorHandlerSaved = false;

// A synchronous property read waits for mpv's playback thread, which costs
// about a frame (tens of milliseconds) per call: far too slow for the
// follow and seek ticks. The properties the panel polls are therefore
// observed, and reads are served from a cache that the events keep current.
std::map<std::string,std::string> Cache;

const char* const Observed[] =
	{ "time-pos", "duration", "pause", "core-idle", "eof-reached", "volume", 0 };


bool
isObserved(char const* name)
{
	for (char const* const* p = Observed; *p; ++p)
	{
		if (strcmp(*p, name) == 0)
			return true;
	}

	return false;
}


void
drainEvents()
{
	while (Player)
	{
		mpv_event* ev = mpv_wait_event(Player, 0);

		if (ev->event_id == MPV_EVENT_NONE)
			return;

		if (ev->event_id == MPV_EVENT_PROPERTY_CHANGE)
		{
			mpv_event_property* prop = static_cast<mpv_event_property*>(ev->data);

			if (prop->format == MPV_FORMAT_STRING && prop->data)
				Cache[prop->name] = *static_cast<char**>(prop->data);
			else
				Cache.erase(prop->name);	// unavailable (no file, not yet known)
		}
		else if (ev->event_id == MPV_EVENT_START_FILE)
		{
			Cache.erase("load-error");
			Cache.erase("error-text");
		}
		else if (ev->event_id == MPV_EVENT_END_FILE)
		{
			mpv_event_end_file* end = static_cast<mpv_event_end_file*>(ev->data);

			if (end->reason == MPV_END_FILE_REASON_ERROR)
			{
				Cache["load-error"] = "yes";
				Cache["error-text"] = mpv_error_string(end->error);
			}
		}
		else if (ev->event_id == MPV_EVENT_SHUTDOWN)
		{
			return;
		}
	}
}


void
closePlayer()
{
	if (Player)
	{
		// Blocks until the core has shut down, which also removes mpv's
		// child window: it must run while the embedding Tk window exists.
		mpv_terminate_destroy(Player);
		Player = 0;
	}

	if (TkErrorHandlerSaved)
	{
		XSetErrorHandler(TkErrorHandler);
		TkErrorHandlerSaved = false;
	}

	Cache.clear();
}


int
cmdOpen(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc < 3 || objc > 4)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "wid file ?startSec?");
		return TCL_ERROR;
	}

	Tcl_WideInt wid = 0;
	double start = 0.0;

	if (Tcl_GetWideIntFromObj(ti, objv[1], &wid) != TCL_OK)
		return TCL_ERROR;
	if (objc == 4 && Tcl_GetDoubleFromObj(ti, objv[3], &start) != TCL_OK)
		return TCL_ERROR;

	closePlayer();

	if (Tk_Window main = Tk_MainWindow(ti))
	{
		// make sure Tk has installed its handler (it does so lazily), then keep it
		Tk_DeleteErrorHandler(Tk_CreateErrorHandler(Tk_Display(main), -1, -1, -1, 0, 0));
		TkErrorHandler = XSetErrorHandler(0);
		XSetErrorHandler(TkErrorHandler);
		TkErrorHandlerSaved = true;
	}

	Player = mpv_create();
	if (!Player)
	{
		Cache["error-text"] = "Could not create the libmpv player.";
		Tcl_SetObjResult(ti, Tcl_NewIntObj(0));
		return TCL_OK;
	}

	int64_t id = wid;
	mpv_set_option(Player, "wid", MPV_FORMAT_INT64, &id);
	mpv_set_option_string(Player, "config", "no");
	mpv_set_option_string(Player, "terminal", "no");
	mpv_set_option_string(Player, "vo", "x11");
	// Decode on the GPU when there is one that works, else on the CPU; the
	// copy modes hand the frames back, so any video output can show them.
	// SCIDB_MEDIA_CUDA_DEVICE pins NVIDIA decoding to one GPU, numbered in
	// PCI bus order as nvidia-smi lists them (CUDA would order fastest
	// first); SCIDB_MEDIA_HWDEC overrides the mode.
	char const* hwdec = getenv("SCIDB_MEDIA_HWDEC");
	char const* device = getenv("SCIDB_MEDIA_CUDA_DEVICE");
	if (device && *device)
	{
		if (!getenv("CUDA_DEVICE_ORDER"))
		{
#ifdef _WIN32
			_putenv("CUDA_DEVICE_ORDER=PCI_BUS_ID");
#else
			setenv("CUDA_DEVICE_ORDER", "PCI_BUS_ID", 0);
#endif
		}
		mpv_set_option_string(Player, "cuda-decode-device", device);
		if (!hwdec || !*hwdec)
			hwdec = "nvdec-copy,auto-copy-safe";
	}
	mpv_set_option_string(Player, "hwdec", hwdec && *hwdec ? hwdec : "auto-copy-safe");
	mpv_set_option_string(Player, "load-scripts", "yes");
	// stream links (YouTube, Twitch, ...) through yt-dlp, when installed
	mpv_set_option_string(Player, "ytdl", "yes");
	mpv_set_option_string(Player, "ytdl-format", "bestvideo[height<=?1080]+bestaudio/best");
	mpv_set_option_string(Player, "keep-open", "always");
	mpv_set_option_string(Player, "osd-level", "0");
	mpv_set_option_string(Player, "osc", "no");
	// Scidb owns the keyboard and mouse; mpv must not steal them.
	mpv_set_option_string(Player, "input-default-bindings", "no");
	mpv_set_option_string(Player, "input-vo-keyboard", "no");
	mpv_set_option_string(Player, "input-cursor", "no");
	mpv_set_option_string(Player, "cursor-autohide", "no");

	if (start > 0.0)
	{
		char buf[64];
		snprintf(buf, sizeof(buf), "%.3f", start);
		mpv_set_option_string(Player, "start", buf);
	}

	int rc = mpv_initialize(Player);
	if (rc < 0)
	{
		closePlayer();
		Cache["error-text"] = mpv_error_string(rc);
		Tcl_SetObjResult(ti, Tcl_NewIntObj(0));
		return TCL_OK;
	}

	for (char const* const* p = Observed; *p; ++p)
		mpv_observe_property(Player, 0, *p, MPV_FORMAT_STRING);

	const char* args[] = { "loadfile", Tcl_GetString(objv[2]), 0 };

	rc = mpv_command(Player, args);
	if (rc < 0)
	{
		closePlayer();
		Cache["error-text"] = mpv_error_string(rc);
		Tcl_SetObjResult(ti, Tcl_NewIntObj(0));
		return TCL_OK;
	}

	Tcl_SetObjResult(ti, Tcl_NewIntObj(1));
	return TCL_OK;
}


int
cmdGet(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 2)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "property");
		return TCL_ERROR;
	}

	char const* name = Tcl_GetString(objv[1]);
	if (!Player && strcmp(name, "error-text") == 0)
		Tcl_SetObjResult(ti, Tcl_NewStringObj(Cache[name].c_str(), -1));
	if (Player)
	{
		if (isObserved(name) || strcmp(name, "load-error") == 0 || strcmp(name, "error-text") == 0)
		{
			drainEvents();

			std::map<std::string,std::string>::const_iterator i = Cache.find(name);

			if (i != Cache.end())
				Tcl_SetObjResult(ti, Tcl_NewStringObj(i->second.c_str(), -1));
		}
		else if (char* value = mpv_get_property_string(Player, name))
		{
			Tcl_SetObjResult(ti, Tcl_NewStringObj(value, -1));
			mpv_free(value);
		}
	}

	return TCL_OK;	// the empty result: no player, or the property is unavailable
}


int
cmdSet(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 3)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "property value");
		return TCL_ERROR;
	}

	int rc = -1;

	if (Player)
	{
		char const* name = Tcl_GetString(objv[1]);
		char const* value = Tcl_GetString(objv[2]);

		rc = mpv_set_property_string(Player, name, value);

		// the change event follows asynchronously; reflect the new value now
		if (rc >= 0 && (strcmp(name, "pause") == 0 || strcmp(name, "volume") == 0))
			Cache[name] = value;
	}

	Tcl_SetObjResult(ti, Tcl_NewIntObj(rc >= 0 ? 1 : 0));
	return TCL_OK;
}


int
cmdClose(ClientData, Tcl_Interp* ti, int, Tcl_Obj* const[])
{
	closePlayer();
	Tcl_ResetResult(ti);
	return TCL_OK;
}


int
cmdAvailable(ClientData, Tcl_Interp* ti, int, Tcl_Obj* const[])
{
	Tcl_SetObjResult(ti, Tcl_NewIntObj(1));
	return TCL_OK;
}

} // namespace


namespace tcl {
namespace media {

void
init(Tcl_Interp* ti)
{
	Tcl_CreateObjCommand(ti, "::mpv::open",      cmdOpen,      0, 0);
	Tcl_CreateObjCommand(ti, "::mpv::get",       cmdGet,       0, 0);
	Tcl_CreateObjCommand(ti, "::mpv::set",       cmdSet,       0, 0);
	Tcl_CreateObjCommand(ti, "::mpv::close",     cmdClose,     0, 0);
	Tcl_CreateObjCommand(ti, "::mpv::available", cmdAvailable, 0, 0);
}

} // namespace media
} // namespace tcl

// vi:set ts=3 sw=3:
