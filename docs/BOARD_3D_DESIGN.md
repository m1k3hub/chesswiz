# 3D Chessboard — Design and Plan

Status: **implemented (v1, view-only 3D board window)**

## 1. Goal

Render the current board as a perspective (3D) chessboard that the user can
orbit, tilt and zoom, and which stays in sync with the main board.  This is a
third presentation of the same position, next to the 2D board widget and the
piece/textual views.

Non-goals for v1:

* making the 3D view the *play* surface (legal-move input, promotion,
  variations) — the 2D board remains the input surface;
* mesh/shader rendering of pieces — pieces are depth-scaled billboards of the
  existing piece-set photos, with a Unicode-glyph fallback.

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
`square = (7 - rank)*8 + file` (the same `row*8+col` indexing the 2D board
uses, row 0 = rank 8).

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

## 7. Test plan

* `tests/test_board3d.tcl` (headless): projection ↔ unprojection round trip
  on the board plane, `squareAt` returns every square from its own projected
  centre, depth ordering matches camera distance, `fit` keeps the projected
  slab inside the canvas, camera basis is orthonormal, presets are sane.
* `tests/test_app_board3d.tcl` (app-backed, xvfb): the module loads, the
  viewer toplevel opens with a populated canvas, rotation/preset/reset update
  it, `PositionChanged` redraws a different position, and close destroys it.

## 8. Phases

1. Math core + headless tests.
2. Canvas renderer.
3. Viewer window + interaction.
4. App integration (accessor, hook, menu) + app test.
5. Docs/changelog.

All five phases are implemented.

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

