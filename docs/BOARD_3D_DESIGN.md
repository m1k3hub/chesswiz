# 3D Chessboard — Design and Plan

Status: **implemented (v3, Classic Woodcraft themes, 3D Vector Pieces,
hardware-accelerated OpenGL view and WebGL viewer)**

## 1. Goal

Render the current board as an aesthetic perspective (3D) chessboard that the user can
orbit, tilt and zoom, and which stays in sync with the main board.  This is a
third presentation of the same position, next to the 2D board widget and the
piece/textual views.

Features:
* Handcrafted 3D woodworking themes (**Classic Woodcraft**, Rosewood & Boxwood, Walnut & Maple, Ebony & Ivory, Tournament Green).
* Triple piece rendering engines:
  - **Vector 3D Pieces**: Geometrically sculpted lathe-profile revolution solids (Pawns, Rooks, Knights, Bishops, Queens, Kings) with green baize felt bases, directional Lambertian shading, specular highlights, and architectural finials.
  - **Realistic 3D Pieces**: Blender-rendered photo pieces from `img/pieces_3d/` (provenance: `models_3d/`, `scripts/build_3d_chess_blender.py`).
  - **Billboard Piece Photos / Glyphs**: Scaled photo piece sets with graceful Unicode fallback.
* Interactive viewer toolbar with live theme switching and piece style selection.
* **Hardware-accelerated 3D view**: a Togl OpenGL widget renders the board
  and sculpted mesh pieces (`src/tk/tk_glboard.cpp`) with two-lamp lighting;
  click-to-select picks through the same projection (`glboard_pick`).
  Available as a separate viewer window and embedded directly in the main
  board window (2D ⇄ 3D switch).
* **WebGL viewer** (`web3d/`): a three.js front end served by
  `web3d/server.py` on port 8899, kept in sync with the main board via a
  local HTTP API (`Extras → Open WebGL Real 3D Board`).

## 2. Why a separate renderer

The existing renderer (`tcl/board-stuff.tcl`, namespace `::board::diagram`)
is a Tk canvas of axis-aligned images.  Every interaction (drag, marks,
arrows, promotion signs, animation) keys off `[$canvas coords square:$sq]`
returning the single top-left corner of an axis-aligned square.  Projecting
those squares would break that contract in many places.

Instead the 3D board lives in its own namespace, `::board3d`, and *mirrors*
the board string that the 2D renderer already publishes.  It has:

* a **pure math core** (camera, projection, unprojection, hit-testing) that
  has no Tk dependency and is unit-tested headless;
* a **canvas renderer** that draws a perspective board slab, shaded tiles,
  coordinate labels, marks and depth-scaled pieces;
* a **viewer window** with orbit/tilt/zoom bindings and view presets.

The main board pushes its current 64-character board string to the viewer via
a single hook in `application::board::update`; nothing else in the board code
changes.

## 3. Geometry and camera

World space: the board top surface is the plane `z = 0`, centred on the
origin, spanning `[-4, 4]` in `x` (files) and `y` (ranks).  A square
`(file, rank)` has centre `(file - 3.5, rank - 3.5, 0)` and corners
`(file - 4 .. file - 3, rank - 4 .. rank - 3)`.  White's first rank is at
`y = -3.5` (near the default camera).  The slab has a configurable thickness
(`z = -thickness`).

Camera: an orbit camera that always looks at the board centre.

```
cam     = d * ( cos(pitch) sin(yaw), -cos(pitch) cos(yaw), sin(pitch) )
forward = normalize(-cam)
right   = normalize(forward x worldUp)      # worldUp = (0, 0, 1)
up      = right x forward
```

`pitch` is clamped away from ±90° so `right` never degenerates.

Projection of a world point `p`:

```
v  = p - cam
xc = v . right ; yc = v . up ; zc = v . forward      # zc = view depth
sx = cx + focal * xc / zc
sy = cy - focal * yc / zc
```

`focal`, `cx`, `cy` are computed once per canvas size by `::board3d::fit`
(see below) and cached in the viewer state, so hit-testing uses exactly the
same transform as drawing.

### 3.1 Auto-fit

Changing `focal` scales the screen offset `(sx-cx, sy-cy)` linearly
(`zc` does not depend on `focal`), so the board can be fitted exactly without
iteration:

1. project the eight extreme slab points (four top corners + four bottom
   corners) with `focal = 1`, recording `ux = xc/zc`, `uy = -yc/zc`;
2. `focal = min(availW / (maxUx-minUx), availH / (maxUy-minUy))`;
3. `cx = W/2 - focal*(minUx+maxUx)/2`, likewise for `cy`.

This keeps the whole slab inside the canvas with a margin for any orbit
angle.

### 3.2 Unprojection / hit-testing

Screen point `(sx, sy)` → ray from the camera:

```
ux = (sx-cx)/focal ; uy = -(sy-cy)/focal
ray = normalize(right*ux + up*uy + forward)
t   = -cam.z / ray.z            # intersect z = 0
world = cam + t*ray
```

`file = floor(world.x + 4)`, `rank = floor(world.y + 4)`, clamped to `0..7`;
`square = rank*8 + file`.  This is the same indexing `::board::diagram`,
`::scidb::pos` and `::move` use, and the same order as the board string
`::board::diagram::data` returns: **a1 = 0, h8 = 63, row 0 = rank 1**
(white's home rank sits near the default camera).

## 4. Rendering

Painter's algorithm, far to near.  Draw order:

1. a soft drop shadow quad under the slab;
2. the four slab sides (darker shade of the board colour);
3. the 64 tiles, sorted by camera depth descending, with a lit/shaded fill so
   the two square colours read correctly; a thin darker outline gives the
   grid;
4. coordinate labels (`a..h`, `1..8`) just outside the slab;
5. pieces on occupied squares, far to near: a ground-shadow ellipse at the
   square centre plus the piece image drawn as a billboard whose height is
   the projected distance between the square centre and a point
   `pieceHeight` above it.  Images are scaled through
   `::scidb::tk::image copy` and cached by `(piece, height)`;
6. marks / last-move highlight / selection outline;
7. a small heads-up line (view name, FEN side to move).

Colors default to a maple/walnut pair; if the board theme's
`photo_Square(lite,$size)` / `photo_Square(dark,$size)` images exist their
top-left pixel is sampled so the 3D board matches the configured theme.

Piece photos come from the existing piece sets (`photo_Piece($piece,$size)`).
If they are not available (headless / no theme loaded) the renderer falls
back to Unicode chess glyphs scaled by depth, so the feature degrades
gracefully.

## 5. Interaction

| Binding | Action |
|---------|--------|
| `<Button-1>` drag | orbit (yaw/pitch) |
| `<Shift-Button-1>` drag | pan |
| `<Button-4/5>` / `<MouseWheel>` | zoom (distance) |
| `<Left>/<Right>` | rotate 15° |
| `<Up>/<Down>` | tilt 5° |
| `<Home>` | reset to default view |
| `<Button-1>` click | select a square (highlight + coordinate readout) |

View presets: `white` (default), `black`, `side`, `top`, `free`.

## 6. Integration

* `tcl/board-3d.tcl` — the module (`::board3d`).
* `tcl/board-stuff.tcl` — add `::board::diagram::data {w}` accessor.
* `tcl/app-board.tcl` — after each diagram update, call
  `::board3d::PositionChanged` when it exists (mirrors the existing media
  hook).
* `tcl/menu.tcl` — *Extras → 3D Board* menu entry.
* `tcl/Makefile` — add the module to `SOURCES`.

### 6.1 Hardware-accelerated OpenGL view

`src/tk/tk_glboard.cpp` registers two Tcl commands,
`::scidb::tk::glboard_render` and `::scidb::tk::glboard_pick`, implemented
against the Togl 2.0 ABI (functions resolved at runtime with `dlsym`; no
link-time dependency on libTogl — the binary only links `-lGL -lGLU`).
The system Togl package (`libtogl2`/`libtogl-dev` on Debian) is the
supported runtime dependency; a fallback copy can be placed at
`lib/togl/libTogl.so` (not tracked — the repo ignores `*.so`).

**GL contexts are per window.** Each Togl widget has its own GL context,
and display lists exist per context: the piece lists are therefore
tracked per widget and validated with `glIsList` for the current context
before drawing (a single global set would silently draw *no* pieces in
every view but the one that compiled it).

`::scidb::tk::glboard_info <togl>` reports the GL implementation of a
view's context as `{renderer vendor version}` — `llvmpipe` in the
renderer means software rendering (e.g. under Xvfb), a GPU name means
hardware acceleration.
The viewer creates a `togl` widget when `lib/togl/libTogl.so` (or a system
Togl) can be loaded and packs it in place of the Tk canvas; the "3D Hardware"
toolbar button toggles between the two views at any time.  Piece meshes live
in `src/tk/gl_piece_data.h` (triangles with normals, exported from the
Blender models in `models_3d/`).

`glboard_pick` unprojects the click through the same `gluPerspective`/
`gluLookAt` matrices the renderer used, intersects the ray with the tile
plane and returns the square in board-string indexing — so click-to-select
(`::board3d::pickSquare`) behaves identically in both views.

**Pitfall — duplicate libTogl instances.**  Tcl's `load` opens extension
libraries `RTLD_LOCAL`, so they are invisible to `dlsym(RTLD_DEFAULT)`.
Naively `dlopen`ing a *system* libTogl when Tcl already loaded the *vendored*
copy creates a second instance whose Tcl stubs table was never initialized
(`Togl_Init` never ran for it) — the first call into it dereferences a NULL
stubs pointer and segfaults.  `loadToglSymbols` therefore resolves the exact
file Tcl loaded (`info loaded`) and re-opens that path (which hands back the
already-loaded object); only when no Togl was ever loaded does it open a
system library and run its `Togl_Init` itself.

### 6.2 Embedded hardware 3D pane (main window)

The embedded pane and viewer share a compact camera bar (View, rotate,
zoom, Fit). The embedded viewport requests only 240×240 pixels so it can
compose with the docking layout; switching presentations preserves the
original packing options and sibling order. Viewer appearance settings
live in a secondary menu rather than a wide row of selectors.

The GL renderer and picker share `setupCamera`: it fits the slab and a
1.4-unit piece-height envelope to the actual viewport and orbit. Distance
12 is the fitted view; zooming in can intentionally crop the board, and
Fit restores that view without changing orientation. Togl's display
callback repaints after buffer allocation, including the first frame after
a resize. Coalesced redraw timers are per widget and canceled on destroy,
so resizing one view cannot cancel another view's repaint.

*Extras → 3D Board in Main Window* swaps the 2D diagram of the board pane
for the hardware OpenGL view *inside the main window* — no separate
window.  `::application::board::show3D` owns the pane geometry (packs
`::board3d::embed`'s container frame in place of the 2D canvas and
repacks the canvas on the way back); `::board3d::embed` creates the Togl
widget inside the pane.  The camera starts from the 2D board's
orientation; the menu checkbutton state lives in
`::board3d::State(embed)`.

While embedded, the 3D pane is **playable**: pressing a piece of the
side to move starts a 3D drag — the piece is lifted over the board and
follows the cursor, legal target squares light up blue
(`glboard_render`'s `suggested` argument) — and releasing on a target
plays the move through `::move::AddMove`, so legality, promotion
dialogs, sounds, engine updates and game navigation behave exactly as
on the 2D board.  Shift-drag allows illegal moves like the 2D board;
press-release-press completes a move click-click; pressing empty squares
or button-3 orbits the camera; the wheel zooms; plain keys are forwarded
to the hidden 2D board.  Square indices are the `::board::diagram`
convention everywhere (`a1 = 0`, `h8 = 63`, board string row 0 = rank 1).

The game's `%draw` annotations (marks) reach the 3D views too:
`application::board::updateMarks` pushes them to `::board3d::setMarks`,
which parses scidb's `cmd,type,sq,sq2,color` strings (square names,
named colors) into the internal form.  The canvas renderer draws full/
square marks as stippled polygons, circles and disks as outlines, arrows
as projected canvas lines with arrowheads and text marks as canvas text;
the GL renderer draws flat translucent overlays and flat arrows on the
board plane, and text marks with a baked pixel font (`gl_text_font.h`,
flat quads — `glXUseXFont` proved to corrupt the GL context on some
stacks).  Rotating the 2D board re-aims white/black preset cameras live
(`::board3d::syncOrientation`); free camera angles are left alone.

`glboard_render` accepts an optional trailing photo name: the rendered
frame is read back with `glReadPixels` (from the back buffer, rows
flipped manually) into that Tk photo, which the tests use to verify
pixel content across contexts.

Limitations: the board pane is a singleton in scidb's twm (only the
analysis panes multiply), so there is exactly one embedded view to
manage.

### 6.3 WebGL viewer

`web3d/index.html` (three.js + `OrbitControls`) renders the board and
sculpted pieces in the browser; `web3d/server.py` serves it and exposes a
`/api/board` GET/POST API.  `::board3d::openWebGLViewer` starts the server
(python3, reused if already running), pushes the current position and opens
the system browser (`SCIDB_WEB3D_NO_BROWSER=1` suppresses that, used by
tests).  Afterwards every `PositionChanged` POSTs the new board; the page
polls every 400ms and rebuilds the pieces.

## 7. Test plan

* `tests/test_board3d.tcl` (headless): projection ↔ unprojection round trip
  on the board plane, `squareAt` returns every square from its own projected
  centre, depth ordering matches camera distance, `fit` keeps the projected
  slab inside the canvas, camera basis is orthonormal, presets are sane,
  theme/piece-style switching, vector-piece drawing, `pickSquare` canvas
  fallback, WebGL URL/JSON helpers.
* `tests/test_app_board3d.tcl` (app-backed, xvfb): the module loads, the
  viewer toplevel opens with a populated canvas, rotation/preset/reset update
  it, `PositionChanged` redraws a different position, click selection works
  in *both* the canvas and the hardware OpenGL view (via `glboard_pick`),
  the embedded 3D pane swaps into the main board window (Togl-gated),
  dragging pieces in the 3D pane plays moves through the move machinery
  (drag, click-click, illegal rejection; Togl-gated), the WebGL server
  starts/serves/syncs the board (python3-gated), and close destroys the
  window.

## 8. Phases

1. Math core + headless tests.
2. Canvas renderer.
3. Viewer window + interaction.
4. App integration (accessor, hook, menu) + app test.
5. Docs/changelog.
6. v2: woodcraft themes, vector pieces, realistic Blender renders, toolbar.
7. v3: hardware OpenGL view (Togl) with click picking, WebGL viewer.

All phases are implemented.

## 9. Pitfalls found while implementing

* **`<Configure>` bind substitutions.** The resize handler needs the widget,
  width and height, so the binding must be `%W %w %h` (`%W` is the window
  path, `%w`/`%h` are its size).  Passing only `%w %h` calls a 3-argument
  proc with 2 arguments; the resulting `wrong # args` background error is
  shown by Scidb in a **modal error dialog**, which looks exactly like the
  event loop hanging (both `update idletasks` and `vwait` stop returning).
  When chasing a Tcl/Tk "hang" in this app, check for background-error
  dialogs before suspecting a geometry loop.
* **Command substitution in image names.** `"...[ $piece ]..."` evaluates
  the piece name as a Tcl command; use `${piece}`.
* **Toplevel sizing.** The viewer is created with `wm withdraw`, built,
  placed and sized explicitly, then deiconified.  A toplevel that is mapped
  without an explicit size while carrying a `<Configure>` binding can also
  spin under a window-manager-less X server (`::util::place` only sets the
  *position*).
* **`[info script]` is empty in event callbacks.**  Menu and toolbar
  commands run from the event loop after the startup script finished
  evaluating, so `[info script]` returns `""` there — and any path built
  from it collapses to something relative to the *current working
  directory* (the app once failed to find `web3d/server.py` this way and
  reported "could not be started").  Paths to assets must be resolved once
  at *load time* (`::board3d::LibRoot`, captured in the `namespace eval`
  while the module is being sourced) and reused from runtime procs.  Tests
  sourced from a file never see the empty `[info script]`, so this can only
  be caught by calling the entry points from an `after` callback that runs
  after the startup script returns.

* **GL display lists are per context; Tk photos must never see negative
  pitch; glXUseXFont can poison the context.**  Three hard-won GL/Tk
  lessons, each found by pixel-verifying frames instead of trusting
  return codes:
  - a *global* "lists compiled" flag made every Togl window but the
    first silently draw no pieces (the lists only existed in the context
    that compiled them) — track list bases per widget and validate with
    `glIsList` for the current context;
  - passing a `Tk_PhotoImageBlock` with **negative pitch** (to un-flip a
    bottom-up GL read) walks out of bounds inside Tk and corrupts the
    heap, breaking rendering in unrelated (even later-created) GL
    contexts — flip the rows yourself and keep the pitch positive;
  - `glXUseXFont` aborted display-list compilation on this stack
    (Mesa/llvmpipe under Xvfb), leaving a phantom open list that
    swallowed all further drawing in the context — text marks use a
    baked pixel font (`gl_text_font.h`) drawn as flat quads instead.
