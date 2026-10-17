// ======================================================================
// tcl_media_mf.cpp — Windows media playback through Media Foundation.
//
// The Windows counterpart of tcl_media.cpp (libmpv), with the same Tcl
// commands, so tcl/app-media-mpv.tcl runs unchanged:
//
//   ::mpv::open WID FILE ?STARTSEC?   start playback; 1, or 0 on failure
//   ::mpv::get PROPERTY               time-pos, duration, pause, core-idle,
//                                     eof-reached, volume, load-error; {} if unknown
//   ::mpv::set PROPERTY VALUE         pause, time-pos, volume; 1 on success, else 0
//   ::mpv::close                      stop and release the player
//   ::mpv::available                  1
//
// Decoding is done by Windows itself (WMV/VC-1, H.264, AAC, MP3, ...), so
// Chesswiz ships no codecs of its own (see docs/legal/PATENT_REVIEW.md). The
// MFPlay player renders into the Tk window's HWND and reports its events
// through window messages, which Tk's event loop already pumps.
// ======================================================================

#include <windows.h>
#include <tcl.h>
#include <tk.h>
#include <tkPlatDecls.h>

#include <mfapi.h>
#include <mfplay.h>
#include <propvarutil.h>

#include <string.h>
#include <stdlib.h>

namespace {

class Callback;

IMFPMediaPlayer*	Player = 0;
Callback*			Events = 0;
HWND					Window = 0;
RECT					LastRect = { 0, 0, 0, 0 };
double				StartSec = 0.0;
bool					Started = false;	// MFStartup has been called
bool					Paused = false;	// paused on request (not merely buffering)
bool					Ended = false;
bool					LoadError = false;


class Callback final : public IMFPMediaPlayerCallback
{
public:

	Callback() : m_refs(1) {}

	STDMETHODIMP QueryInterface(REFIID riid, void** ppv)
	{
		if (riid == __uuidof(IUnknown) || riid == __uuidof(IMFPMediaPlayerCallback))
		{
			*ppv = static_cast<IMFPMediaPlayerCallback*>(this);
			AddRef();
			return S_OK;
		}
		*ppv = 0;
		return E_NOINTERFACE;
	}

	STDMETHODIMP_(ULONG) AddRef()		{ return InterlockedIncrement(&m_refs); }
	STDMETHODIMP_(ULONG) Release()
	{
		ULONG n = InterlockedDecrement(&m_refs);
		if (n == 0)
			delete this;
		return n;
	}

	void STDMETHODCALLTYPE OnMediaPlayerEvent(MFP_EVENT_HEADER* ev)
	{
		if (!Player || !ev)
			return;

		if (FAILED(ev->hrEvent))
		{
			if (ev->eEventType == MFP_EVENT_TYPE_MEDIAITEM_CREATED
				|| ev->eEventType == MFP_EVENT_TYPE_MEDIAITEM_SET
				|| ev->eEventType == MFP_EVENT_TYPE_ERROR)
			{
				LoadError = true;
			}
			return;
		}

		switch (ev->eEventType)
		{
			case MFP_EVENT_TYPE_MEDIAITEM_CREATED:
			{
				MFP_MEDIAITEM_CREATED_EVENT* e = MFP_GET_MEDIAITEM_CREATED_EVENT(ev);
				if (FAILED(Player->SetMediaItem(e->pMediaItem)))
					LoadError = true;
				break;
			}

			case MFP_EVENT_TYPE_MEDIAITEM_SET:
				if (StartSec > 0.0)
				{
					PROPVARIANT pos;
					PropVariantInit(&pos);
					pos.vt = VT_I8;
					pos.hVal.QuadPart = LONGLONG(StartSec*1e7);
					Player->SetPosition(MFP_POSITIONTYPE_100NS, &pos);
					PropVariantClear(&pos);
				}
				Player->Play();
				break;

			case MFP_EVENT_TYPE_PLAYBACK_ENDED:
				Ended = true;
				break;

			case MFP_EVENT_TYPE_ERROR:
				LoadError = true;
				break;

			default:
				break;
		}
	}

private:

	long m_refs;
};


void
closePlayer()
{
	if (Player)
	{
		Player->Shutdown();
		Player->Release();
		Player = 0;
	}
	if (Events)
	{
		Events->Release();
		Events = 0;
	}
	Window = 0;
	Paused = Ended = LoadError = false;
	StartSec = 0.0;
	SetRectEmpty(&LastRect);
}


// The video is scaled to the window when the player starts; the media
// pane can be resized afterwards, which the property polls notice.
void
followWindowSize()
{
	RECT r;
	if (Player && Window && GetClientRect(Window, &r) && !EqualRect(&r, &LastRect))
	{
		LastRect = r;
		Player->UpdateVideo();
	}
}


double
seconds(REFGUID type, bool duration)
{
	PROPVARIANT v;
	PropVariantInit(&v);
	HRESULT hr = duration ? Player->GetDuration(type, &v) : Player->GetPosition(type, &v);
	double result = -1.0;
	// The position comes as VT_I8, the duration as VT_UI8.
	if (SUCCEEDED(hr) && v.vt == VT_I8)
		result = double(v.hVal.QuadPart)/1e7;
	else if (SUCCEEDED(hr) && v.vt == VT_UI8)
		result = double(v.uhVal.QuadPart)/1e7;
	PropVariantClear(&v);
	return result;
}


int
cmdOpen(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 3 && objc != 4)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "wid file ?startsec?");
		return TCL_ERROR;
	}

	Tcl_WideInt wid;
	double start = 0.0;

	if (Tcl_GetWideIntFromObj(ti, objv[1], &wid) != TCL_OK)
		return TCL_ERROR;
	if (objc == 4 && Tcl_GetDoubleFromObj(ti, objv[3], &start) != TCL_OK)
		return TCL_ERROR;

	closePlayer();

	if (!Started)
	{
		// Tk may already have initialised COM for its own use (drag and drop).
		HRESULT hr = CoInitializeEx(0, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
		if (FAILED(hr) && hr != RPC_E_CHANGED_MODE)
		{
			Tcl_SetObjResult(ti, Tcl_NewIntObj(0));
			return TCL_OK;
		}
		if (FAILED(MFStartup(MF_VERSION, MFSTARTUP_FULL)))
		{
			Tcl_SetObjResult(ti, Tcl_NewIntObj(0));
			return TCL_OK;
		}
		Started = true;
	}

	// [winfo id] on Windows is the HWND of the Tk window.
	Window = reinterpret_cast<HWND>(static_cast<INT_PTR>(wid));
	StartSec = start;

	int len = 0;
	char const* path = Tcl_GetStringFromObj(objv[2], &len);
	Tcl_DString ds;
	Tcl_DStringInit(&ds);
	Tcl_WinUtfToTChar(path, len, &ds);
	WCHAR const* wpath = reinterpret_cast<WCHAR const*>(Tcl_DStringValue(&ds));

	Events = new Callback;
	HRESULT hr = MFPCreateMediaPlayer(0, FALSE, 0, Events, Window, &Player);
	if (SUCCEEDED(hr))
		hr = Player->CreateMediaItemFromURL(wpath, FALSE, 0, 0);	// asynchronous: see MEDIAITEM_CREATED

	Tcl_DStringFree(&ds);

	if (FAILED(hr))
	{
		closePlayer();
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

	if (!Player)
		return TCL_OK;	// the empty result: no player

	followWindowSize();

	char const*	name = Tcl_GetString(objv[1]);
	MFP_MEDIAPLAYER_STATE state = MFP_MEDIAPLAYER_STATE_EMPTY;
	Player->GetState(&state);

	if (strcmp(name, "time-pos") == 0 || strcmp(name, "duration") == 0)
	{
		double s = seconds(MFP_POSITIONTYPE_100NS, name[0] == 'd');
		if (s >= 0.0)
			Tcl_SetObjResult(ti, Tcl_NewDoubleObj(s));
	}
	else if (strcmp(name, "pause") == 0)
	{
		Tcl_SetObjResult(ti, Tcl_NewStringObj(Paused ? "yes" : "no", -1));
	}
	else if (strcmp(name, "core-idle") == 0)
	{
		bool playing = state == MFP_MEDIAPLAYER_STATE_PLAYING && !Ended;
		Tcl_SetObjResult(ti, Tcl_NewStringObj(playing ? "no" : "yes", -1));
	}
	else if (strcmp(name, "eof-reached") == 0)
	{
		Tcl_SetObjResult(ti, Tcl_NewStringObj(Ended ? "yes" : "no", -1));
	}
	else if (strcmp(name, "load-error") == 0)
	{
		Tcl_SetObjResult(ti, Tcl_NewStringObj(LoadError ? "yes" : "no", -1));
	}
	else if (strcmp(name, "volume") == 0)
	{
		float v = 0.0f;
		if (SUCCEEDED(Player->GetVolume(&v)))
			Tcl_SetObjResult(ti, Tcl_NewDoubleObj(v*100.0));
	}

	return TCL_OK;
}


int
cmdSet(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 3)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "property value");
		return TCL_ERROR;
	}

	bool ok = false;

	if (Player)
	{
		char const* name = Tcl_GetString(objv[1]);
		char const* value = Tcl_GetString(objv[2]);

		if (strcmp(name, "pause") == 0)
		{
			bool pause = strcmp(value, "yes") == 0;
			ok = SUCCEEDED(pause ? Player->Pause() : Player->Play());
			if (ok)
			{
				Paused = pause;
				if (!pause)
					Ended = false;
			}
		}
		else if (strcmp(name, "time-pos") == 0)
		{
			PROPVARIANT pos;
			PropVariantInit(&pos);
			pos.vt = VT_I8;
			pos.hVal.QuadPart = LONGLONG(strtod(value, 0)*1e7);
			ok = SUCCEEDED(Player->SetPosition(MFP_POSITIONTYPE_100NS, &pos));
			PropVariantClear(&pos);
			if (ok)
				Ended = false;
		}
		else if (strcmp(name, "volume") == 0)
		{
			ok = SUCCEEDED(Player->SetVolume(float(strtod(value, 0)/100.0)));
		}
	}

	Tcl_SetObjResult(ti, Tcl_NewIntObj(ok ? 1 : 0));
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
