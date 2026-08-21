# Media Playback Library Design for Scidb

## 1. Context

Scidb needs media playback to support the ChessBase Media System — images,
audio commentary, and video clips stored in `.cbm` companion files alongside
CBH databases (see `CBM_FORMAT_DESIGN.md`).

### 1.1 What Scidb already has

| Capability | Status | How |
|------------|--------|-----|
| **Image display** | ✅ Built-in | Tk `image create photo -data [binary]` + bundled JPEG decoder (`src/tk/jpeg/`) + PNG support (`tk_png.cpp`) |
| **Audio playback** | ❌ None | — |
| **Video playback** | ❌ None | — |
| **Player photos** | ✅ Built-in | `tcl/utils/player-photos.tcl` — downloads and displays player photos using Tk photo images |
| **External process launch** | ✅ Tcl `exec` | Used for engine subprocesses, photo download subprocess |

### 1.2 Media formats in ChessBase databases

ChessBase Magazine and multimedia databases use:

| Type | Formats found | Notes |
|------|---------------|-------|
| Images | JPEG, PNG, BMP, GIF | All decodable by existing Tk infrastructure |
| Audio | WAV, MP3 | Spoken commentary |
| Video | WMV (older), MP4 (CBM #180+) | Chess Media System: video + board synchronization |

### 1.3 Key constraint

Scidb is a **Tcl/Tk + C++** application. The media library must integrate
with the Tk event loop and windowing system. Any embedded video player
must be able to render into a Tk widget.

---

## 2. Options evaluated

### 2.1 System player delegation (no new dependency)

Extract media payload from `.cbm` to a temp file, then launch the OS
default media player:

- **Linux**: `xdg-open <tempfile>`
- **macOS**: `open <tempfile>`
- **Windows**: `start <tempfile>`

| Pros | Cons |
|------|------|
| Zero new dependencies | No in-app integration (external window) |
| Supports any format the OS can play | No board synchronization |
| Trivial to implement | Requires temp file extraction |
| Cross-platform via Tcl `exec` | User experience is jarring |

### 2.2 libmpv (embedded mpv as library)

[libmpv](https://mpv.io/manual/master/#embedding-into-other-programs-libmpv)
is the C API for embedding the mpv media player as a playback backend.

**Integration methods:**

1. **Native window embedding** (`wid` option) — pass a Tk widget's
   window ID to mpv, it renders video inside that widget. Simple, works
   on X11/win32/macOS.

2. **Render API** (OpenGL) — create an OpenGL context, use
   `mpv_render_context_render()` to draw video frames. More control,
   can overlay UI, but requires OpenGL integration with Tk.

3. **Custom stream callbacks** — register a protocol handler so mpv
   reads directly from in-memory `.cbm` data (no temp file needed).

| Pros | Cons |
|------|------|
| In-app audio + video playback | New optional dependency (~5-15 MB) |
| Handles all common formats (WMV, MP4, MP3, WAV) | Requires OpenGL for render API |
| Can read from memory via stream callbacks | GPL license consideration (see below) |
| Clean C API, well-documented | X11 focus-stealing issues with `wid` |
| Audio-only and video-only both supported | |
| Used by many projects (Qt, SDL, wxWidgets examples) | |

**License:** libmpv C API is ISC. mpv core is GPLv2+ by default, or
LGPLv2.1+ when built with `-Dgpl=false`. Scidb is GPL, so GPLv2+ mpv
is compatible.

### 2.3 GStreamer

Full multimedia framework, pipeline-based.

| Pros | Cons |
|------|------|
| Very flexible pipeline architecture | Heavy dependency (~50+ MB with plugins) |
| Can do complex processing | Complex API (GObject introspection) |
| Plugin ecosystem | Overkill for simple playback |
| | No simple "play this file" API |

### 2.4 FFmpeg / libav directly

Low-level codec library.

| Pros | Cons |
|------|------|
| Maximum control | You must build the entire player yourself |
| No player overhead | Audio/video sync, buffering, rendering — all DIY |
| | Enormous effort for minimal benefit |

### 2.5 Tcl media extensions (Snack, tkvideo)

| Extension | Pros | Cons |
|-----------|------|------|
| **Snack** (audio) | Tcl-native, simple API | Unmaintained, limited formats, no video |
| **tkvideo** | Tcl-native video | Unmaintained, WMV only, no audio |
| **vlc-tcl** | VLC backend | Unmaintained wrapper |

---

## 3. Recommendation: Tiered design

### Tier 1 — System player delegation (always available, no dependency)

**Implement first.** This gives immediate media access with zero new
dependencies.

- Images: Display in-app using existing Tk photo infrastructure
  (`image create photo -data [payload]`).
- Audio/Video: Extract to temp file, launch system player via Tcl `exec`.
- This is the fallback when libmpv is not available.

### Tier 2 — libmpv (optional, `--enable-mpv`)

**Implement second.** Optional dependency detected at configure time,
following the existing `--enable-fam` pattern.

- Embed mpv video window in a Tk frame via the `wid` option.
- Play audio-only files through mpv's audio output (no video window needed).
- Use custom stream callbacks to play from `.cbm` in-memory data.
- Provide play/pause/stop/seek controls in Tcl via a new `::media` namespace.

### Tier 3 — OpenGL render API (future, advanced)

**Deferred.** Use libmpv's render API to render video into a Tk OpenGL
widget for tight integration (overlay chess board, custom OSD). This
requires a Tk OpenGL widget (e.g., `tkogl` or `togl`) and is significantly
more complex.

---

## 4. Architecture

```
┌──────────────────────────────────────────────────────┐
│                    Tcl UI Layer                       │
│                                                       │
│  ::media::play $gameIndex $mediaType                 │
│  ::media::stop                                      │
│  ::media::isAvailable                               │
│  ┌─────────────────────────────────────────────┐    │
│  │ Media Panel (Tk frame)                        │    │
│  │  ┌───────────────┐  ┌──────────────────┐    │    │
│  │  │ Image display  │  │ Video (mpv wid)  │    │    │
│  │  │ (Tk photo)     │  │ (or system player)│   │    │
│  │  └───────────────┘  └──────────────────┘    │    │
│  └─────────────────────────────────────────────┘    │
└──────────────────┬───────────────────────────────────┘
                   │
┌──────────────────┴───────────────────────────────────┐
│              C++ Media Player Module                  │
│                                                       │
│  src/media/media_player.h                             │
│  src/media/media_player.cpp                           │
│                                                       │
│  class MediaPlayer {                                   │
│      bool isAvailable();      // libmpv present?      │
│      bool play(path);        // play audio/video      │
│      bool play(data, size);  // play from memory      │
│      void stop();                                    │
│      void pause(bool);                               │
│      void seek(double seconds);                      │
│      double position() const;                         │
│      double duration() const;                        │
│      void setWindowHandle(uint64_t wid);             │
│      // event callback for position updates          │
│  };                                                   │
└──────────────────┬───────────────────────────────────┘
                   │
        ┌──────────┴──────────┐
        │                      │
┌───────┴──────┐      ┌───────┴──────┐
│  libmpv      │      │  System      │
│  (optional)  │      │  fallback    │
│  - embedded  │      │  - exec      │
│  - in-app    │      │  - xdg-open  │
└──────────────┘      └──────────────┘
```

---

## 5. Implementation plan

### 5.1 Phase A — System player delegation (no dependency)

**Files:**
| File | Description |
|------|-------------|
| `tcl/utils/media.tcl` (new) | Tcl `::media` namespace — play/stop/available |
| `tcl/utils/media-player.tcl` (new) | System player delegation: extract + exec |

**Tcl API:**
```tcl
# Check if media playback is available (always true for system player)
::media::isAvailable

# Play media for a game
::media::play $db $gameIndex ?$mediaType?

# Stop playback
::media::stop

# Show image inline (uses Tk photo)
::media::showImage $w $db $gameIndex
```

**System player detection:**
```tcl
proc ::media::systemPlayer {} {
    foreach cmd {xdg-open open start} {
        if {![catch {exec which $cmd}]} { return $cmd }
    }
    return ""
}
```

### 5.2 Phase B — libmpv integration (optional)

**Files:**
| File | Description |
|------|-------------|
| `src/media/media_player.h` (new) | C++ MediaPlayer class wrapping libmpv |
| `src/media/media_player.cpp` (new) | Implementation |
| `src/media/Makefile` (new) | Build rules |
| `src/tcl/tcl_media.cpp` (new) | Tcl command bindings (`::media::mpv`) |
| `configure` (modified) | Add `--enable-mpv` check, like `checkFAM` |
| `Makefile.in` (modified) | Add `MPV_INC`, `MPV_LIB` variables |

**Configure check** (following the `checkFAM` pattern):
```tcl
proc checkMPV {} {
    global feature
    if {$feature(mpv)} {
        puts -nonewline "    Checking if your system has libmpv: "
        flush stdout
        if {[SystemHasMPV]} { puts "yes." } else { puts "no" }
    }
}
```

**C++ MediaPlayer class:**
```cpp
namespace media {

class MediaPlayer
{
public:
    /// Returns true if libmpv is linked at compile time.
    static bool isAvailable();

    MediaPlayer();
    ~MediaPlayer();

    /// Set the parent window handle for video embedding.
    /// On X11: pass the Tk widget's window ID.
    void setWindowHandle(uint64_t wid);

    /// Play a file from path.
    bool playFile(mstl::string const& path);

    /// Play from in-memory data (using mpv stream callbacks).
    bool playData(unsigned char const* data, size_t size);

    void stop();
    void pause(bool flag);
    void seek(double seconds);
    double position() const;
    double duration() const;

    /// Callback for position updates (called from mpv event thread).
    typedef void (*PositionCallback)(void* ctx, double pos);
    void setPositionCallback(PositionCallback cb, void* ctx);

private:
    mpv_handle* m_mpv;
    PositionCallback m_posCallback;
    void* m_posCtx;
};

} // namespace media
```

**Tcl bindings** (`tcl_media.cpp`):
```cpp
// ::media::mpv play $path
// ::media::mpv playData $data
// ::media::mpv stop
// ::media::mpv pause $bool
// ::media::mpv seek $seconds
// ::media::mpv position
// ::media::mpv duration
// ::media::mpv setWindow $wid
// ::media::mpv available
```

### 5.3 Phase C — Tcl UI media panel

**Files:**
| File | Description |
|------|-------------|
| `tcl/utils/media-panel.tcl` (new) | Media viewer panel widget |
| `tcl/app-database.tcl` (modified) | Add media column to game list |

**Media panel features:**
- Shows image thumbnails for games with `hasPicture()`
- "Play audio" button for games with `hasAudio()`
- "Play video" button for games with `hasVideo()`
- If libmpv available: embedded video in panel
- If not: launches system player
- Media indicator column in game list (📷 🔊 🎬)

### 5.4 Phase D — Custom stream callbacks

**Goal:** Play media directly from `.cbm` file data without extracting
to a temp file.

Uses libmpv's `mpv_stream_cb_add_ro()` to register a custom protocol
(e.g., `cbm://game=123;type=video`) that reads from the MediaTable's
in-memory data.

This eliminates temp file I/O and is cleaner for large media files.

---

## 6. Build system integration

### 6.1 configure changes (following the FAM pattern)

```tcl
# In configure:
set feature(mpv) no
# ...
puts "  --enable-mpv               build with libmpv media support [default=$feature(mpv)]"
# ...
proc checkMPV {} {
    global feature
    if {$feature(mpv)} {
        puts -nonewline "    Checking if your system has libmpv: "
        flush stdout
        if {[SystemHasMPV]} { puts "yes." } else { puts "no" }
    }
}
```

### 6.2 Makefile.in changes

```makefile
MPV_INC          =
MPV_LIB          =
HAVE_LIBMPV     =
```

When `--enable-mpv` is used:
```makefile
HAVE_LIBMPV     = -DHAVE_LIBMPV=1
MPV_LIB         = -lmpv
```

### 6.3 Conditional compilation

In C++ code:
```cpp
#if HAVE_LIBMPV
#  include <mpv/client.h>
#endif
```

In Tcl:
```tcl
if {[info commands ::media::mpv] ne ""} {
    # libmpv is available
    set ::media::backend "mpv"
} else {
    set ::media::backend "system"
}
```

---

## 7. License considerations

| Component | License | Compatible with Scidb (GPL)? |
|-----------|--------|------------------------------|
| libmpv C API | ISC | ✅ |
| mpv core (default) | GPLv2+ | ✅ |
| mpv core (`-Dgpl=false`) | LGPLv2.1+ | ✅ |
| FFmpeg (mpv dependency) | LGPL/GPL | ✅ (typically LGPL build) |

No license conflict. Scidb is GPL, mpv is GPLv2+, both are compatible.

---

## 8. Summary

| Phase | What | Dependency | Effort |
|-------|------|------------|--------|
| **A** | System player delegation | None | Small |
| **B** | libmpv integration | Optional libmpv | Medium |
| **C** | Tcl UI media panel | A or B | Medium |
| **D** | Custom stream callbacks (in-memory playback) | B | Small |

**Recommended path:** Implement Phase A first (immediate, no dependency),
then Phase B (libmpv) as an optional enhancement, then Phase C (UI), then
Phase D (stream callbacks) for polish.

The key insight is that **libmpv** is the right embedded library choice
because:
1. It handles all ChessBase media formats (WMV, MP4, MP3, WAV)
2. It has a clean C API that integrates well with C++/Tcl
3. It can embed in Tk windows via the `wid` option
4. It supports custom stream callbacks for in-memory playback
5. Its license is compatible with Scidb
6. It's actively maintained and widely used

The system player fallback ensures media works even without libmpv
installed — it just opens in an external window instead of embedded.