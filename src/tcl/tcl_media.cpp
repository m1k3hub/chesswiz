// ======================================================================
// tcl_media.cpp — media playback init (backend removed).
//
// Previously this file implemented an in-process libmpv backend that
// provided the `::media::mpv` Tcl command for embedded video/audio
// playback.  libmpv did not work reliably with Tk's X11 windows (GPU/EGL
// binding issues, BadMatch crashes during teardown), so it has been
// removed.
//
// Media playback is now handled entirely in Tcl via the `tkvlc` package
// (a Tcl binding to libVLC that embeds video into Tk frames).  See
// tcl/app-media.tcl for the integration.  No C++ command is needed.
//
// This file retains only the `media::init` stub so that tcl_base.cpp's
// call site does not need changing.  It is a no-op.
// ======================================================================

#include "tcl_base.h"

using namespace tcl;

namespace tcl {
namespace media {

void
init(Tcl_Interp* /* ti */)
{
	// No-op.  Media playback is handled in Tcl via `package require tkvlc`.
}

} // namespace media
} // namespace tcl

// vi:set ts=3 sw=3:
