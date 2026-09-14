# Changelog

## Unreleased — 3D Chessboard Viewer (v2/v3: themes, vector pieces, hardware OpenGL, WebGL)

- New `tcl/board-3d.tcl` (`::board3d`) renders the current position as a
  perspective board that can be orbited, tilted and zoomed:
  - a pure-Tcl orbit camera with exact auto-fit (the board slab always fits
    the canvas) and screen→square unprojection for hit-testing;
  - a canvas renderer drawing a board slab, shaded tiles, coordinates,
    marks and pieces as depth-scaled billboards of the configured piece
    set (Unicode-glyph fallback when no piece set is loaded);
  - a viewer window with White/Black/Side/Top presets, rotate/tilt/zoom
    (drag, wheel, arrow keys, Home) and click-to-select.
- v2 — presentation upgrade: five handcrafted woodworking themes
  (Classic Woodcraft, Rosewood & Boxwood, Walnut & Maple, Ebony & Ivory,
  Tournament Green) selectable live from the new toolbar, plus three piece
  styles: *realistic3d* (Blender-rendered pieces, `img/pieces_3d/`, built
  from `models_3d/` via `scripts/build_3d_chess_blender.py`), *vector*
  (lathe-profile revolution solids with felt bases and architectural
  finials) and the existing *photos*/*glyphs* billboards.
- v3 — hardware-accelerated view: `src/tk/tk_glboard.cpp` embeds an OpenGL
  renderer (board slab, 64 shaded tiles, mesh pieces from
  `src/tk/gl_piece_data.h`, two-lamp lighting) behind
  `::scidb::tk::glboard_render`, loaded through the Togl 2.0 ABI at runtime
  (`lib/togl/libTogl.so` vendored, system Togl as fallback; the binary only
  gains `-lGL -lGLU`).  The "3D Hardware" button toggles between the OpenGL
  widget and the Tk canvas; clicking a square resolves through the *active*
  view (`glboard_pick` unprojects with the same matrices the renderer used).
  Loading guards against the duplicate-libTogl segfault: the exact library
  file Tcl `load`ed is re-opened (same object, stubs table initialized by
  its `Togl_Init`); a fresh system copy is only opened — and initialized —
  when no Togl was loaded at all.
- v3 — embedded hardware 3D pane: *Extras → 3D Board in Main Window*
  swaps the board pane's 2D diagram for the hardware OpenGL view inside
  the main window (same `glboard_render` engine, orbit/zoom on the mouse,
  click-to-select through `glboard_pick`).  The pane is *playable*:
  dragging a piece of the side to move lifts it over the board (it
  follows the pick ray, legal targets highlight blue) and dropping it on
  a square plays the move through `::move::AddMove` — legality,
  promotion dialogs, sounds and engine updates behave exactly as on the
  2D board; Shift-drag permits illegal moves, press-release-press
  completes moves click-click.  While embedded, the pane takes the focus
  and forwards plain keys to the hidden 2D board, so game navigation
  keeps working.  The 2D diagram and all its bindings are preserved and
  restored when toggling back.
- v3 — marks and orientation sync on the 3D views: the game's %draw
  annotations (%draw full/disk/circle/arrow/text) now reach the canvas
  viewer and the embedded GL pane — `application::board::updateMarks`
  pushes them through `::board3d::setMarks`, which parses scidb's
  `cmd,type,sq,sq2,color` strings; the canvas renderer draws stippled
  polygons, outlines, projected arrow lines and text, the GL renderer
  draws flat translucent overlays and flat arrows on the board plane
  (`glboard_render`'s new marks argument).  Rotating the 2D board
  re-aims white/black preset cameras live (free camera angles are
  untouched); the earlier documented limitation is gone.
- v3 — GL board orientation and indexing fixes: the OpenGL renderer now
  uses the `::board::diagram` square convention everywhere
  (a1 = 0, h8 = 63, board string row 0 = rank 1 at the near edge of the
  white camera); previously pieces were drawn transposed across ranks
  relative to the board colours (the board appeared upside down with
  pieces on the wrong squares) and picks returned mirrored indices.
  `glboard_pick` optionally returns the ray's world intersection
  (`{square worldX worldY}`) and `glboard_render` accepts `suggested`-
  square and dragged-piece arguments used by the 3D move input.
- v3 — WebGL viewer: `Extras → Open WebGL Real 3D Board` starts
  `web3d/server.py` (local three.js viewer on port 8899, polling
  `/api/board`), pushes the current position and opens the browser;
  every position change keeps it in sync.  `SCIDB_WEB3D_NO_BROWSER=1`
  suppresses the browser launch (used by tests).  Asset paths resolve
  through the load-time-captured `::board3d::LibRoot` — `[info script]`
  is empty in menu/toolbar callbacks, which previously collapsed the
  `web3d/` path to a cwd-relative location and made the server fail to
  start with a misleading "make sure python3 is installed" message;
  failures now report the concrete reason.
- Wired into the app: `Extras → 3D Board` opens the viewer; the main board
  pushes its position through `::board3d::PositionChanged` from
  `application::board::update` (via a new `::board::diagram::data`
  accessor), so the 3D view mirrors play live.  Design and plan in
  `docs/BOARD_3D_DESIGN.md`.
- Tests: `tests/test_board3d.tcl` (headless camera/projection/hit-test
  math, themes/styles, vector pieces, pick fallback, WebGL helpers) and
  `tests/test_app_board3d.tcl` (viewer open/draw/preset/sync/click-select
  in both views/WebGL round-trip/close under X).
- Test infra: `tests/run_app_tests.tcl` exits through the real `exit` after
  the summary, avoiding the post-suite abort when the application has
  redefined `exit`.

## Unreleased — Media Pane Layout-Menu Crash Fix

- The media pane was registered in `PaneOptions`/`BoardLayout` but had no
  `::application::twm::mc::Pane(media)` label, so building the settings
  menu (`BuildSettingsMenu` → `makeLayoutMenu`) raised
  `can't read "mc::Pane(media)"` whenever the media pane was in the
  active layout.  Added the default label in `app-twm.tcl` and to all
  language files, and made `makeLayoutMenu` fall back to the pane uid so
  an unlabeled pane can never break the layout/window menu again.
- Tests: `tests/test_app_no_media.tcl` (label exists; uid fallback).

## Unreleased — Reversible Board ⇄ Video Sync

- Board navigation and video playback stay synchronized forwards and
  backwards:
  - `::media::sync::ms-for-ply` takes the current media time and picks
    the occurrence *nearest* to it, so stepping one move back to a ply
    the lecture revisited seeks to the nearby mention instead of jumping
    to the ply's first mention minutes earlier.
  - An explicit seek (`::media::sync::seek`, e.g. a slider scrub) drives
    the board even while the transport is paused (`drive` gained a
    `force` flag).
  - A 50 ms `reach` tolerance stops a seek that lands a few ms short of
    a timeline mark from snapping the board onto the previous move.
  - Legacy `.plytimes` count timelines now invert exactly: a ply maps to
    its own mark rather than any later mark, so a board-driven seek on a
    legacy lesson no longer jumps to a future ply's timecode.
  - `PlySeek` passes the video's current position to the nearest-occurrence
    lookup.
- Tests: `tests/test_media_sync.tcl` (nearest occurrence, paused tick,
  paused seek, reach tolerance); a round trip over the Biel round-08
  fixture matches all 89 marks with no drift.

## Unreleased — Build & Test Hygiene

- `make cpp` (hence `make all`/`make test`) now also builds and runs the
  self-contained C++ unit tests that live in `src/`
  (`test_html_core`, `test_scm_media`, `test_scriptstream`,
  `test_media_extract`, `test_corr_moveinfo`, `test_sci_result`) via the
  new `cpp-src` target, with a `PASS:`/`FAIL:` summary per binary.
- `src/Makefile`: `test_media_extract` now links the libraries it
  actually needs (`sys`/Tcl), and `test_corr_moveinfo` has a build rule
  — both targets previously failed to build.
- `test_media_extract` installs a live Tcl interpreter (the path
  resolver reaches `sys::file` through Tcl's filesystem layer); it
  previously segfaulted at startup.
- `test_scriptstream` rebuilds its synthetic checkpoint record with the
  verified 5-byte tree-edge grammar, restoring the exact
  `c2-c4`/`e7-e6` assertion (was 50/51; now 51/51).
- Removed a stray debug `fprintf(stderr, "[tail: …]")` from the script-stream
  checkpoint parser.
- `tests/tmp/` is ignored.

## Unreleased — System-wide Database Discovery

- New `tcl/app-database-discover.tcl`: a *Discover Databases…* dialog
  (Database tab toolbar magnifier + main menu → Extras) that walks the
  machine for every supported chess database format
  (`.sci`/`.si4`/`.si3`, `.cbh`/`.cbf`/`.cbv`/`.2cbh`, `.scv`,
  `.pgn`/`.pgn.gz`/`.bpgn`/`.bpgn.gz`) and lists the primary index/header
  files with their game count and size.
- Companion files (`.scg`, `.cbg`, `.sg4`, …) are never listed; binary
  formats are confirmed by magic bytes; the walk is incremental (150
  directories per event-loop tick) and cancellable, and skips
  pseudo-filesystems, VCS dirs, caches and trash.
- *Open* loads the selected databases; *Add to switcher* registers them
  without changing the current base.
- Tests: `tests/test_database_discover.tcl` (8 headless) and
  `tests/test_app_discover.tcl` (4 app-backed); design in
  `docs/DATABASE_DISCOVERY.md`.

## Unreleased — ChessBase (.cbh) Per-Game Media via tag_game Anchors

### Overview

`::scidb::db::mediaFiles` now maps a REGULAR game of a ChessBase `.cbh`
database onto its tournament report's media, closing the last open row of
the CBM capability table (CBM_FORMAT_DESIGN.md §7.7).

### Details
- Reports (guiding-text entries) anchor games in their HTML bodies via
  `CBLink(tag_game,White,Black,Event,Site,Year,Round,…)`; anchors match
  game headers on (lastname, lastname, event-key, year, round) — fixture:
  Topalov–Anand/Bilbao 2008 r4 = game 12038, exact match
- Guiding-text CBH index records carry no usable tournament reference
  ("? (illegal reference)" for all 11 reports) — the anchors are the only
  per-game route (so the CBH event table cannot link them)
- Media association = section ownership: each reference belongs to the
  game of the last anchor at-or-before it (report-header art lands on the
  first anchored game — documented approximation)
- New: `tcl_media::scanGuidingTextMediaRefs/extractGuidingTextMediaRange/
  extractGuidingTextGameBlocks` + `GuidingTextLinkCache` in `cmdMediaFiles`
- `tcl_media_extract` unit tests extended to 577 structural checks
- E2E (CB Light Database): 35 games carry media (10 reports + 25 mapped),
  125 refs, all mapped pictures on disc; probe-gamemap + run-e2e PASS
- `src/probe_cbllight` extended: event semantics, per-report block counts,
  cache simulator (dev tool)

## Unreleased — ChessBase 17+ (2CBH) Move Decoding

### Overview

The ChessBase 17+ `.2cbg` move encoding (used by Mega Database 2026,
Corr Database 2024 and LumbrasGigaBase) is fully reverse engineered and
decoded in scidb.  Full `cb2::Codec` integration is the next step.

### Details
- The move data is plaintext 16-bit "Move16" codes (not encrypted)
- The runtime-built ChessBase decode table was extracted from a live
  CBase26 process under Wine, packed and embedded in `src/db/2cbh/`
- Validated on 200,000 games of the LumbrasGigaBase fixture: 100% of
  mainlines decode, replay legally, and carry the correct player names
  (the .2lid namebase mapping: player ID == namebase slot ordinal)
- The game result decoded: index byte 0x58 low 2 bits (0 = 0-1,
  1 = draw, 2 = 1-0), validated on 2,748 games with zero mismatches
- `2cbh2pgn` converts complete databases to PGN (names included), now
  with full nested RAV variations and .2cba comments in position
  (2026-09-07): emission goes through `db::cb2::walkGameRaw` +
  `db::PgnWriter` instead of a duplicated flat mainline walk; UTF-8
  output; two-pass per game so a desync never truncates a game
- Standalone validation tool `2cbh_probe`; reproducible table-dump
  script in `scripts/`
- Media RE: the script-stream colour question closed by a Reader14 VM
  playback oracle (2026-09-07) — annotations render green regardless of
  style/class byte (136 frames, 3 videos, pixel-correlated); the
  renderer follows opcode-02 checkpoints, not opcode-06 deltas.  See
  `CHESSBASE_MEDIA_RE.md` "Reader14 on genuine Windows"
- See `2CBH_FORMAT_DESIGN.md` section 3.8

## Unreleased — Correspondence Chess Support

### Overview

Full correspondence chess support added to scidb-beta, including live
clock display, automatic move timestamps, a game manager panel, and
ICCF XFCC server integration.

### Features

#### Correspondence Clock Widget
- Live countdown display showing remaining time as `28d 12h 30m`
- Parses `WhiteTimeLeft` / `BlackTimeLeft` PGN tags (ISO 8601 durations)
- Side-to-move player's clock ticks down in real time
- Active player highlighted with bold font and accent color
- Auto-shows in the gamebar area when a correspondence game is loaded
- Auto-hides for non-correspondence games

#### Automatic ccsnt Timestamps
- When a move is entered in a correspondence game (TimeMode = `corr`),
  the move is automatically stamped with `[%ccsnt YYYY.MM.DD, HH:MM:SS]`
- New C++ Tcl subcommand: `::scidb::game::update moveinfo <key> <type> <value>`
  supports `ccsnt`, `cclk`, and `cemt` move info types
- New `Game::addMoveInfo()` C++ method with full undo tracking

#### Correspondence Game Manager Panel
- Accessible via **Tools → Correspondence Games...**
- Lists all correspondence games from the current database
- 10 columns: #, White, Black, ICCF ID, Status, White Time, Black Time,
  Last Move, Event, Result
- Filter by status (All / Ongoing / Finished)
- Detail area shows ICCF ID, status, and remaining time for selected game
- Double-click to open a game in the editor

#### ICCF XFCC Server Integration
- Full SOAP client for the ICCF XFCC Basic web service
- Endpoint: `https://www.iccf.com/XfccBasic.asmx`
- Operations: `GetMyGames`, `MakeAMove`, `MakeAMove2`
- **Tools → ICCF Settings...** — configure username and password
- **Sync** button in the game manager — fetches games from ICCF server
- **Auto-submit** — when a move is entered in a game with an `ICCFGameID`
  tag, the move is automatically submitted to the ICCF server
- Credentials stored in the options file with simple obfuscation
- TLS 1.8.0 required (auto-loaded from system package paths)

#### PGN Format Support
- `[%cclk P28DT12H30M]` — correspondence clock (remaining time)
- `[%cemt P2DT4H30M]` — correspondence elapsed move time
- `[%ccsnt 2024.01.15, 14:30:00]` — correspondence chess sent timestamp
  (pre-existing, now with auto-timestamping)
- `TimeControl` tag auto-exported from `TimeMode` for PGN compatibility
- ICCF ratings (`WhiteICCF` / `BlackICCF`) always exported alongside Elo
- Move info display menu includes cclk and cemt (enabled by default)

#### CCG Format Design
- `CCG_FORMAT_DESIGN.md` — design spec for `.ccg` (Correspondence Chess
  Game) files, a PGN superset with complete correspondence metadata

### Technical Details

- **C++ changes**: `MoveInfo` class extended with `CorrespondenceClock`
  and `CorrespondenceElapsed` types, `CorrDuration` struct
  (days+hours+minutes+seconds), ISO 8601 duration parser, PGN printer
  with proper `[%cclk]` / `[%cemt]` annotation format
- **Tcl changes**: 4 new Tcl files (`corrclock.tcl`, `app-corr-games.tcl`,
  `iccf-xfcc.tcl`, `test_corr_moveinfo.cpp`), modifications to `move.tcl`,
  `app-pgn.tcl`, `menu.tcl`, `pgn-setup.tcl`, `app-database.tcl`
- **Build**: 3 new files registered in `tcl/Makefile` SOURCES list
- **Tests**: 29 C++ unit tests (parsing, printing, roundtrip),
  111 Tcl tests, 335 Python tests, 220 frontend tests — all pass

### Files Added

| File | Lines | Description |
|------|-------|-------------|
| `tcl/widgets/corrclock.tcl` | 307 | Live correspondence clock widget |
| `tcl/app-corr-games.tcl` | 417 | Game manager panel |
| `tcl/iccf-xfcc.tcl` | 560 | ICCF XFCC SOAP client |
| `src/test_corr_moveinfo.cpp` | 130 | C++ unit test for MoveInfo parsing |
| `CCG_FORMAT_DESIGN.md` | 210 | CCG format specification |
| `ICCF_XFCC_DESIGN.md` | 210 | XFCC integration design document |

### Files Modified

| File | Description |
|------|-------------|
| `src/db/db_move_info.h` | `CorrespondenceClock`/`Elapsed` types, `CorrDuration` struct, public accessor |
| `src/db/db_move_info.cpp` | ISO 8601 parser, PGN printer (fixed double-`]` bug), encode/decode |
| `src/db/db_move_info_set.cpp` | `[%cclk]` / `[%cemt]` extraction from PGN comments |
| `src/db/db_game.h` | `addMoveInfo()` method, `AddMoveInfo` undo command |
| `src/db/db_game.cpp` | `addMoveInfo()` implementation with undo tracking |
| `src/db/db_writer.cpp` | `TimeControl` auto-export, ICCF rating export |
| `src/db/db_common.h` | `moveinfo::CorrClock` / `CorrElapsed` flags |
| `src/tcl/tcl_game.cpp` | `moveinfo` subcommand, `getMoveInfoTypes` cclk/cemt, `AddMoveInfo` toString |
| `tcl/move.tcl` | Auto-ccsnt timestamp + auto-submit to ICCF |
| `tcl/app-pgn.tcl` | Corrclock widget in gamebar, `UpdateCorrClock` proc |
| `tcl/menu.tcl` | Tools menu entries for corr games and ICCF settings |
| `tcl/pgn-setup.tcl` | cclk/cemt in ShowMoveInfo defaults |
| `tcl/app-database.tcl` | corrClock/corrElapsed in move info display |
| `tcl/Makefile` | 3 new source files in SOURCES list |

### Getting Started with ICCF Integration

1. Register at [iccf.com](https://www.iccf.com) if you haven't already
2. In your ICCF player settings, set an API password (separate from your
   web login password)
3. In scidb-beta, go to **Tools → ICCF Settings...**
4. Enter your ICCF username and API password
5. Go to **Tools → Correspondence Games...**
6. Click **Sync** to fetch your games from the ICCF server
7. Open a game, make a move — it will be auto-timestamped and
   auto-submitted to the ICCF server