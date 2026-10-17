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
// MFPlay (paths) and Media Engine (URLs/HLS) render into the Tk HWND. MFPlay reports events
// through window messages; Media Engine state is read by Tcl property polls.
// ======================================================================

#include <windows.h>
#include <tcl.h>
#include <tk.h>
#include <tkPlatDecls.h>

#include <mfapi.h>
#include <mfplay.h>
#include <mfmediaengine.h>
#include <oleauto.h>
#include "media_url.h"
#include <propvarutil.h>

#include <string.h>
#include <stdlib.h>
#include <stdio.h>

namespace {

// Notifications run on MF threads. Playback state is read through the engine
// on Tk's polling thread; the callback never touches Tcl or shared player state.
class EngineNotify final : public IMFMediaEngineNotify
{
    long refs;
public:
    EngineNotify() : refs(1) {}
    STDMETHODIMP QueryInterface(REFIID id, void** out) {
        if (!out) return E_POINTER;
        *out = 0;
        if (id != __uuidof(IUnknown) && id != __uuidof(IMFMediaEngineNotify))
            return E_NOINTERFACE;
        *out = static_cast<IMFMediaEngineNotify*>(this); AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() { return InterlockedIncrement(&refs); }
    STDMETHODIMP_(ULONG) Release() {
        ULONG n = InterlockedDecrement(&refs); if (!n) delete this; return n;
    }
    STDMETHODIMP EventNotify(DWORD event, DWORD_PTR param1, DWORD) {
        if (event == MF_MEDIA_ENGINE_EVENT_NOTIFYSTABLESTATE)
            SetEvent(reinterpret_cast<HANDLE>(param1));
        return S_OK;
    }
};
IMFMediaEngine* Engine = 0;
class Callback;

IMFPMediaPlayer*	Player = 0;
Callback*			Events = 0;
HWND					Window = 0;
RECT					LastRect = { 0, 0, 0, 0 };
double				StartSec = 0.0;
bool					Started = false;	// MFStartup has been called
bool					Paused = false;	// paused on request (not merely buffering)
bool					Ended = false;
bool                    LoadError = false;
char ErrorText[96] = "";

void recordError(HRESULT hr)
{
    sprintf(ErrorText, "Media Foundation error 0x%08lx.", static_cast<unsigned long>(hr));
}


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
                recordError(ev->hrEvent);
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
    if (Engine) {
        Engine->Shutdown(); Engine->Release(); Engine = 0;
    }
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
    ErrorText[0] = 0;
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
    if (Engine && Window && GetClientRect(Window, &r)) {
        IMFMediaEngineEx* ex = 0;
        if (SUCCEEDED(Engine->QueryInterface(__uuidof(IMFMediaEngineEx), reinterpret_cast<void**>(&ex)))) {
            ex->UpdateVideoStream(0, &r, 0); ex->Release();
        }
    }
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


HRESULT openUrl(WCHAR const* url)
{
    IMFMediaEngineClassFactory* factory = 0;
    IMFAttributes* attrs = 0;
    EngineNotify* notify = new EngineNotify;
    HRESULT hr = CoCreateInstance(CLSID_MFMediaEngineClassFactory, 0,
        CLSCTX_INPROC_SERVER, __uuidof(IMFMediaEngineClassFactory),
        reinterpret_cast<void**>(&factory));
    if (SUCCEEDED(hr)) hr = MFCreateAttributes(&attrs, 2);
    if (SUCCEEDED(hr)) hr = attrs->SetUnknown(MF_MEDIA_ENGINE_CALLBACK, notify);
    if (SUCCEEDED(hr)) hr = attrs->SetUINT64(MF_MEDIA_ENGINE_PLAYBACK_HWND,
        static_cast<UINT64>(reinterpret_cast<UINT_PTR>(Window)));
    if (SUCCEEDED(hr)) hr = factory->CreateInstance(0, attrs, &Engine);
    if (attrs) attrs->Release();
    if (factory) factory->Release();
    notify->Release();
    if (SUCCEEDED(hr)) {
        BSTR source = SysAllocString(url);
        hr = source ? Engine->SetSource(source) : E_OUTOFMEMORY;
        SysFreeString(source);
        // Start after metadata is available, so startsec can be applied first.
        if (SUCCEEDED(hr)) hr = Engine->Load();
    }
    return hr;
}

void pollEngine()
{
    if (Engine->GetReadyState() >= MF_MEDIA_ENGINE_READY_HAVE_METADATA && StartSec >= 0) {
        if (StartSec > 0) Engine->SetCurrentTime(StartSec);
        StartSec = -1;
        if (!Paused) Engine->Play();
    }
    followWindowSize();
}

int getEngine(Tcl_Interp* ti, char const* name)
{
    pollEngine();
    IMFMediaError* error = 0;
    Engine->GetError(&error);
    bool failed = error && error->GetErrorCode() != 0;
    if (strcmp(name, "time-pos") == 0 || strcmp(name, "duration") == 0) {
        double value = name[0] == 'd' ? Engine->GetDuration() : Engine->GetCurrentTime();
        // NaN and infinite duration mean unknown/live.
        if (value >= 0 && value < 1e15) Tcl_SetObjResult(ti, Tcl_NewDoubleObj(value));
    } else if (strcmp(name, "volume") == 0) {
        Tcl_SetObjResult(ti, Tcl_NewDoubleObj(Engine->GetVolume()*100));
    } else if (strcmp(name, "error-text") == 0) {
        if (failed) {
            char text[96];
            sprintf(text, "Media Foundation error %u (HRESULT 0x%08lx).",
                unsigned(error->GetErrorCode()), static_cast<unsigned long>(error->GetExtendedErrorCode()));
            Tcl_SetObjResult(ti, Tcl_NewStringObj(text, -1));
        }
    } else {
        bool value = false;
        if (strcmp(name, "load-error") == 0) value = failed;
        else if (strcmp(name, "pause") == 0) value = Paused;
        else if (strcmp(name, "eof-reached") == 0) value = Engine->IsEnded();
        else if (strcmp(name, "core-idle") == 0)
            value = Engine->IsPaused() || Engine->IsEnded()
                || Engine->GetReadyState() < MF_MEDIA_ENGINE_READY_HAVE_FUTURE_DATA;
        else { if (error) error->Release(); return TCL_OK; }
        Tcl_SetObjResult(ti, Tcl_NewStringObj(value ? "yes" : "no", -1));
    }
    if (error) error->Release();
    return TCL_OK;
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
            recordError(hr);
			Tcl_SetObjResult(ti, Tcl_NewIntObj(0));
			return TCL_OK;
		}
        hr = MFStartup(MF_VERSION, MFSTARTUP_FULL);
        if (FAILED(hr))
        {
            recordError(hr);
            Tcl_SetObjResult(ti, Tcl_NewIntObj(0));
			return TCL_OK;
		}
		Started = true;
	}

	// [winfo id] on Windows is the HWND of the Tk window.
	Window = reinterpret_cast<HWND>(static_cast<INT_PTR>(wid));
	StartSec = start > 0.0 ? start : 0.0;

	int len = 0;
	char const* path = Tcl_GetStringFromObj(objv[2], &len);
	Tcl_DString ds;
	Tcl_DStringInit(&ds);
	Tcl_WinUtfToTChar(path, len, &ds);
	WCHAR const* wpath = reinterpret_cast<WCHAR const*>(Tcl_DStringValue(&ds));

	HRESULT hr;
    if (mediaHasUrlScheme(path)) {
        hr = openUrl(wpath);
    } else {
        Events = new Callback;
        hr = MFPCreateMediaPlayer(0, FALSE, 0, Events, Window, &Player);
        if (SUCCEEDED(hr)) hr = Player->CreateMediaItemFromURL(wpath, FALSE, 0, 0);
    } // asynchronous: MFPlay events or Media Engine state polling

	Tcl_DStringFree(&ds);

	if (FAILED(hr))
	{
        closePlayer();
        recordError(hr);
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

    if (strcmp(Tcl_GetString(objv[1]), "error-text") == 0 && ErrorText[0]) {
        Tcl_SetObjResult(ti, Tcl_NewStringObj(ErrorText, -1));
        return TCL_OK;
    }
    if (Engine) return getEngine(ti, Tcl_GetString(objv[1]));
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

    if (Engine) {
        char const* name = Tcl_GetString(objv[1]);
        char const* value = Tcl_GetString(objv[2]);
        if (strcmp(name, "pause") == 0) {
            bool pause = strcmp(value, "yes") == 0;
            ok = SUCCEEDED(pause ? Engine->Pause() : Engine->Play());
            if (ok) Paused = pause;
        } else if (strcmp(name, "time-pos") == 0)
            ok = SUCCEEDED(Engine->SetCurrentTime(strtod(value, 0)));
        else if (strcmp(name, "volume") == 0)
            ok = SUCCEEDED(Engine->SetVolume(strtod(value, 0)/100.0));
    }
    else if (Player)
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
