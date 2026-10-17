// ======================================================================
// tcl_media_avf.mm — macOS media playback through AVFoundation.
//
// The macOS counterpart of tcl_media.cpp (libmpv), with the same Tcl
// commands, so tcl/app-media-mpv.tcl runs unchanged:
//
//   ::mpv::open WID FILE ?STARTSEC?   start playback; 1, or 0 on failure
//   ::mpv::get PROPERTY               time-pos, duration, pause, core-idle,
//                                     eof-reached, volume, load-error; {} if unknown
//   ::mpv::set PROPERTY VALUE         pause, time-pos, volume; 1 on success, else 0
//   ::mpv::close                      stop and release the player
//   ::mpv::available                  1
//
// Decoding is done by macOS (H.264, HEVC, AAC, MP3, ...), so Chesswiz ships
// no codecs of its own (see docs/legal/PATENT_REVIEW.md). macOS has no decoder for
// WMV/ASF: such files report load-error, and the media pane offers to open
// them externally.
//
// Tk on macOS draws every child window into its toplevel's NSView, so the
// video is an AVPlayerLayer placed at the Tk window's rectangle inside that
// view; the rectangle is re-checked on every property poll, which keeps the
// video in place when the pane is moved or resized.
// ======================================================================

#include <tcl.h>
#include <tk.h>
#include <tkMacOSX.h>

#import <AVFoundation/AVFoundation.h>
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include <string.h>
#include <stdlib.h>
#include "media_url.h"

namespace {

AVPlayer*		Player = nil;
AVPlayerLayer*	Layer = nil;
id					EndObserver = nil;
Tk_Window		TkWin = 0;
bool				Paused = false;	// paused on request (not merely buffering)
bool				Ended = false;


void
closePlayer()
{
	if (EndObserver)
	{
		[[NSNotificationCenter defaultCenter] removeObserver:EndObserver];
		[EndObserver release];
		EndObserver = nil;
	}
	if (Player)
	{
		[Player pause];
		[Player release];
		Player = nil;
	}
	if (Layer)
	{
		[Layer removeFromSuperlayer];
		[Layer release];
		Layer = nil;
	}
	TkWin = 0;
	Paused = Ended = false;
}


// Places the video layer over the Tk window, in the toplevel view's coordinates.
void
followWindow()
{
	if (!Layer || !TkWin || !Tk_IsMapped(TkWin))
	{
		[Layer setHidden:YES];
		return;
	}

	NSView* view = static_cast<NSView*>(Tk_MacOSXGetNSViewForDrawable(Tk_WindowId(TkWin)));
	if (!view)
		return;

	if (Layer.superlayer != view.layer)
	{
		[view setWantsLayer:YES];
		[view.layer addSublayer:Layer];
	}

	// offset of the window inside its toplevel
	int x = 0, y = 0;
	for (Tk_Window w = TkWin; w && !Tk_IsTopLevel(w); w = Tk_Parent(w))
	{
		x += Tk_X(w);
		y += Tk_Y(w);
	}

	CGFloat h = Tk_Height(TkWin);
	CGFloat top = view.isFlipped ? y : view.bounds.size.height - y - h;

	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	Layer.frame = CGRectMake(x, top, Tk_Width(TkWin), h);
	[Layer setHidden:NO];
	[CATransaction commit];
}


double
seconds(CMTime t)
{
	if (CMTIME_IS_NUMERIC(t))
		return CMTimeGetSeconds(t);
	return -1.0;
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

	Tk_Window main = Tk_MainWindow(ti);
	TkWin = main ? Tk_IdToWindow(Tk_Display(main), Window(wid)) : 0;
	if (!TkWin)
	{
		Tcl_SetObjResult(ti, Tcl_NewIntObj(0));
		return TCL_OK;
	}

	@autoreleasepool
	{
		NSString* path = [NSString stringWithUTF8String:Tcl_GetString(objv[2])];
		NSURL* url = mediaHasUrlScheme(Tcl_GetString(objv[2]))
            ? [NSURL URLWithString:path] : [NSURL fileURLWithPath:path];
        if (!url) {
            Tcl_SetObjResult(ti, Tcl_NewIntObj(0));
            return TCL_OK;
        }
		AVPlayerItem* item = [AVPlayerItem playerItemWithURL:url];

		Player = [[AVPlayer alloc] initWithPlayerItem:item];
		Player.actionAtItemEnd = AVPlayerActionAtItemEndPause;	// like mpv's keep-open
		Layer = [[AVPlayerLayer playerLayerWithPlayer:Player] retain];
		Layer.videoGravity = AVLayerVideoGravityResizeAspect;

		EndObserver = [[[NSNotificationCenter defaultCenter]
			addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
							object:item
							 queue:[NSOperationQueue mainQueue]
						usingBlock:^(NSNotification*) { Ended = true; }] retain];

		if (start > 0.0)
			[Player seekToTime:CMTimeMakeWithSeconds(start, 1000)
				toleranceBefore:kCMTimeZero
				 toleranceAfter:kCMTimeZero];

		followWindow();
		[Player play];
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

	followWindow();

	char const* name = Tcl_GetString(objv[1]);
	AVPlayerItem* item = Player.currentItem;

	if (strcmp(name, "time-pos") == 0)
	{
		double s = seconds(Player.currentTime);
		if (s >= 0.0)
			Tcl_SetObjResult(ti, Tcl_NewDoubleObj(s));
	}
	else if (strcmp(name, "duration") == 0)
	{
		double s = item ? seconds(item.duration) : -1.0;	// indefinite until loaded
		if (s >= 0.0)
			Tcl_SetObjResult(ti, Tcl_NewDoubleObj(s));
	}
	else if (strcmp(name, "pause") == 0)
	{
		Tcl_SetObjResult(ti, Tcl_NewStringObj(Paused ? "yes" : "no", -1));
	}
	else if (strcmp(name, "core-idle") == 0)
	{
		bool playing = Player.timeControlStatus == AVPlayerTimeControlStatusPlaying && !Ended;
		Tcl_SetObjResult(ti, Tcl_NewStringObj(playing ? "no" : "yes", -1));
	}
	else if (strcmp(name, "eof-reached") == 0)
	{
		Tcl_SetObjResult(ti, Tcl_NewStringObj(Ended ? "yes" : "no", -1));
	}
	else if (strcmp(name, "load-error") == 0)
	{
		bool failed = !item || item.status == AVPlayerItemStatusFailed;
		Tcl_SetObjResult(ti, Tcl_NewStringObj(failed ? "yes" : "no", -1));
	}
	else if (strcmp(name, "error-text") == 0)
    {
        NSString* detail = item.error.localizedDescription;
        if (detail) Tcl_SetObjResult(ti, Tcl_NewStringObj([detail UTF8String], -1));
    }
    else if (strcmp(name, "volume") == 0)
	{
		Tcl_SetObjResult(ti, Tcl_NewDoubleObj(Player.volume*100.0));
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
			Paused = strcmp(value, "yes") == 0;
			if (Paused)
			{
				[Player pause];
			}
			else
			{
				if (Ended)	// play again from the start, as mpv does at eof
					[Player seekToTime:kCMTimeZero];
				Ended = false;
				[Player play];
			}
			ok = true;
		}
		else if (strcmp(name, "time-pos") == 0)
		{
			[Player seekToTime:CMTimeMakeWithSeconds(strtod(value, 0), 1000)
				toleranceBefore:kCMTimeZero
				 toleranceAfter:kCMTimeZero];
			Ended = false;
			ok = true;
		}
		else if (strcmp(name, "volume") == 0)
		{
			Player.volume = float(strtod(value, 0)/100.0);
			ok = true;
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
