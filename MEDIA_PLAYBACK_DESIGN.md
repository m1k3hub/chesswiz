# Media Playback Library Design for Scidb

## 1. Context

Scidb needs media playback to support the ChessBase Media System — images,
audio commentary, and video clips stored in `.cbm` companion files alongside
CBH databases (see `CBM_FORMAT_DESIGN.md`).

### 1.1 What Scidb already has

| Capability | Status | How |
|------------|--------|-----|
| **Image display** | ✅ Built-in | Tk `image create photo -data [binary]` + bundled JPEG decoder (`src/tk/jpeg/`) + PNG support (`tk_png.cpp`) |
| **Audio playback** | ✅ Via tkvlc (libVLC) | `tcl/app-media.tcl` — `package require tkvlc`; falls back to system player |
| **Video playback** | ✅ Via tkvlc (libVLC) | Embedded in Tk canvas via `::tkvlc::init HANDLE [winfo id $canvas]` |
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

### 2.2 tkvlc (embedded libVLC as Tcl package)

[tkvlc](https://github.com/ray2501/tkvlc) is a Tcl extension that wraps
[libVLC](https://wiki.videolan.org/LibVLC/) and embeds VLC video playback
into a Tk frame widget.

**Integration method:**

Pass a Tk widget's window ID (via `winfo id`) to `::tkvlc::init`, which
creates a VLC media player bound to that window. VLC handles video
rendering directly into the Tk widget.

**Tcl API (tkvlc commands):**

```tcl
::tkvlc::init HANDLE ?HWND|photo?   ;# create a player handle
HANDLE open filename                 ;# load a media file
HANDLE openurl url                   ;# load a media URL
HANDLE play                          ;# start playback
HANDLE pause                         ;# pause / resume
HANDLE stop                          ;# stop playback
HANDLE isplaying                     ;# -> 1 if playing
HANDLE volume ?value?                ;# get/set volume
HANDLE duration                      ;# -> duration in seconds
HANDLE time ?value?                  ;# get/set position in seconds
HANDLE position ?value?              ;# get/set position (0.0–1.0)
HANDLE isseekable                    ;# -> 1 if seekable
HANDLE state                         ;# -> idle|opening|buffering|playing|paused|stopped|ended|error
HANDLE rate ?value?                  ;# get/set playback speed
HANDLE repeat ?flag?                 ;# get/set repeat flag
HANDLE event ?cmd?                   ;# get/set event callback
HANDLE info                          ;# -> array of player info
HANDLE destroy                       ;# release the player
```

| Pros | Cons |
|------|------|
| In-app audio + video playback | New optional dependency (libVLC + tkvlc extension) |
| Handles all common formats (WMV, MP4, MP3, WAV) | Must build/install tkvlc Tcl extension |
| Clean Tcl API, no C++ compilation needed | X11 window-embedding focus-stealing issues (as with any wid approach) |
| Audio-only and video-only both supported | |
| MIT licensed, actively maintained | |
| Pure Tcl-loadable (`package require tkvlc`) — no app rebuild needed | |

**License:** tkvlc is MIT. libVLC is GPLv2+ (compatible with Scidb's GPL).

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
- This is the fallback when tkvlc is not available.

### Tier 2 — tkvlc (optional, loaded at runtime via `package require`)

**Implemented.** Optional dependency loaded at runtime via Tcl's
`package require tkvlc`. No compile-time dependency, no app rebuild.

- Embed VLC video window in a Tk frame via `::tkvlc::init HANDLE [winfo id $w]`.
- Play audio-only files through VLC's audio output (no video window needed).
- Provide play/pause/stop/seek controls in Tcl via the tkvlc handle commands.
- If tkvlc is not installed, gracefully falls back to Tier 1 (system player).

### Tier 3 — OpenGL render API (future, advanced)

**Deferred.** Use libVLC's render API to render video into a Tk OpenGL
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
│  │  │ Image display  │  │ Video (tkvlc)   │    │    │
│  │  │ (Tk photo)     │  │ (or system player)│   │    │
│  │  └───────────────┘  └──────────────────┘    │    │
│  └─────────────────────────────────────────────┘    │
└──────────────────┬───────────────────────────────────┘
                   │
┌──────────────────┴───────────────────────────────────┐
│              C++ Media Module (stub)               │
│                                                       │
│  src/tcl/tcl_media.cpp (no-op init)                │
│  Playback is handled entirely in Tcl via tkvlc.   │
└──────────────────┬───────────────────────────────────┘
                   │
        ┌──────────┴──────────┐
        │                      │
┌───────┴──────┐      ┌───────┴──────┐
│  tkvlc       │      │  System      │
│  (optional)  │      │  fallback    │
│  - libVLC    │      │  - exec      │
│  - in-app    │      │  - xdg-open  │
└──────────────┘      └──────────────┘
```

---

## 5. Implementation plan

### 5.1 Phase A — System player delegation (no dependency)

**Status: Implemented** in `tcl/app-media.tcl` (`LaunchExternal` proc).

**Files:**
| File | Description |
|------|-------------|
| `tcl/app-media.tcl` | Media panel UI + system player fallback (`LaunchExternal`) |

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

### 5.2 Phase B — tkvlc integration (optional, runtime)

**Files:**
| File | Description |
|------|-------------|
| `tcl/app-media.tcl` (modified) | Media panel UI using tkvlc for playback |
| `src/tcl/tcl_media.cpp` (stub) | No-op `media::init`; playback is pure Tcl |
| `tcl/app-media-sync.tcl` | Board ⇄ media synchronization state machine (§5.5) |

**No build system changes needed.** tkvlc is loaded at runtime via
`package require tkvlc`. If the package is not installed, the media
panel falls back to the system player (Tier 1).

**Tcl usage** (see `tcl/app-media.tcl`):
```tcl
# Load tkvlc (lazy, on first playback)
package require tkvlc

# Create a VLC player bound to a Tk canvas window id
::tkvlc::init scidb_vlc [winfo id $canvas]

# Open and play
scidb_vlc open [file nativename $path]
scidb_vlc play

# Check state
set state [scidb_vlc state]   ;# playing|paused|stopped|ended|error|...

# Stop and release
scidb_vlc stop
scidb_vlc destroy
```

### 5.3 Phase C — Tcl UI media panel

**Status: Implemented** in `tcl/app-media.tcl` (`build`, `PlaySelected`, `ShowImage`, `PlayMedia`).

**Media panel features:**
- Shows image thumbnails for games with `hasPicture()`
- "Play audio" button for games with `hasAudio()`
- "Play video" button for games with `hasVideo()`
- If tkvlc available: embedded video in panel
- If not: launches system player
- Media indicator column in game list (📷 🔊 🎬)

### 5.4 Phase D — Custom stream callbacks

**Goal:** Play media directly from `.cbm` file data without extracting
to a temp file.

Deferred — would require a custom libVLC media callback or a temporary
file approach. Not currently implemented.

---

## 5.5 Phase B+ — Board ⇄ media synchronization

**Implemented (2026-08-29)** in `tcl/app-media-sync.tcl` (state machine,
UI-free) + `tcl/app-media.tcl` (panel wiring). Board code reports
playback events; the media panel controls the transport:

| Direction | Event | Action (sync enabled) |
|-----------|-------|----------------------|
| board → media | browser/pane autoplay starts | media plays |
| board → media | autoplay stops/pauses | media pauses |
| board → media | manual position navigation | media pauses |
| media → board | video plays with "Board follows video" | main board advances per the loaded sync sidecar: one navigation step per elapsed transition mark (verified ChessBase per-move timecodes, see §5.6); without a sidecar the mapping degrades to linear over the video duration (4 plies/tick max; a media rewind restarts the game) |

State machine: `::media::sync` (see `tcl/app-media-sync.tcl`); the media
panel registers delegates (`SyncTransport`, `SyncBoard*`) so the machine
never touches tkvlc or the game API directly. Tests with stub delegates:
`tests/test_app_media_sync.tcl` (run inside the app:
`xvfb-run -a ./src/tkscidb-beta tests/run_app_tests.tcl -match mediasync*`).

Per-move timecodes ("board follows video" follows the actual ChessBase
lesson replay): the ChessBase script stream inside the WMV carries the
authoritative per-step media times — reverse-engineered and documented in
`CHESSBASE_MEDIA_RE.md` (checkpoint game-tree stream + opcode-`03`
transitions; `CBM_FORMAT_DESIGN.md` §7.8 superseded the linear
assumption). Generate the sidecar with
`media-console/wmv2timeline.py <base>.wmv --plytimes <video>.plytimes`
(one media-ms per line, replay order); `tcl/app-media.tcl`
(`LoadSyncSidecar`) auto-loads it at playback start and
`::media::sync::load-timeline` feeds the state machine — one board step
per elapsed mark, rewind-safe, linear fallback when absent. Headless
tests: `tests/test_app_media_sync.tcl` (case prefix `mediasync-`,
run via `./src/tkscidb-beta tests/run_app_tests.tcl -match mediasync*`).

Remaining scope limits: the timeline drives the board ply only —
applying the decoded board annotations (arrows/marks/comments, file-major
squares per `CHESSBASE_MEDIA_RE.md`) to the board during playback is
future work; the sync couples to the main board (position −1) and any
browser dialog's autoplay; per-game media switching still stops playback
(the panel rebuilds per game as before).

---

## 6. Build system integration

**No build system changes needed.** tkvlc is a standard Tcl package
loaded at runtime. The C++ `tcl_media.cpp` is a no-op stub; no
compile-time dependency on libVLC or tkvlc is required.

To install tkvlc:
```
# Install libVLC development files
sudo apt-get install libvlc-dev   # Debian/Ubuntu
sudo zypper in vlc-devel          # openSUSE

# Build and install tkvlc
git clone https://github.com/ray2501/tkvlc
cd tkvlc
./configure --prefix=/opt/tcl
make && make install
```

In Tcl, detection is runtime-only:
```tcl
if {![catch { package require tkvlc }]} {
    # tkvlc is available
    set ::media::backend "vlc"
} else {
    set ::media::backend "system"
}
```

---

## 7. License considerations

| Component | License | Compatible with Scidb (GPL)? |
|-----------|--------|------------------------------|
| tkvlc | MIT | ✅ |
| libVLC | GPLv2+ | ✅ |

No license conflict. Scidb is GPL, libVLC is GPLv2+, both are compatible.

---

## 8. Summary

| Phase | What | Dependency | Effort |
|-------|------|------------|--------|
| **A** | System player delegation | None | Small |
| **B** | tkvlc integration | Optional tkvlc (runtime) | Small |
| **C** | Tcl UI media panel | A or B | Medium |
| **D** | Custom stream callbacks (in-memory playback) | B | Deferred |

**Implemented path:** Phase A (system player fallback, always available)
and Phase B (tkvlc for embedded playback, loaded at runtime) are both
implemented in `tcl/app-media.tcl`.

The key insight is that **tkvlc** is the right embedded playback choice
because:
1. It handles all ChessBase media formats (WMV, MP4, MP3, WAV)
2. It has a clean Tcl API — no C++ compilation or app rebuild needed
3. It can embed in Tk windows via `winfo id`
4. Its license (MIT) is compatible with Scidb
5. It wraps libVLC, which is actively maintained and widely used

The system player fallback ensures media works even without tkvlc
installed — it just opens in an external window instead of embedded.