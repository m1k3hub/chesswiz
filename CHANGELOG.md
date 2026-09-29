# Changelog

## Unreleased — three more audit features (A6 novelty, B4 database trends, C4 media transcript)

- **A6 — move novelty** (`tcl/ai-novelty.tcl`): label a move against master
  practice, grounded in the precedent index. A position the index knows is
  `known` without the classifier; otherwise the bounded classifier decides
  `novelty`/`side_line`/`transposition` (an unsettled move stays `unknown`).
  Firewall kept: `blunder` is deliberately *not* a label — move quality is
  Stockfish's, never a model's. Surfaces: assistant tool `novelty_label`.
- **B4 — database trends** (`tcl/ai-trend.tcl`): a read-only narrative of the
  active database's opening trends from Scidb's own counts
  (`::scidb::db::count`/`ecoStats`), through the ordinary grounded pipeline
  (fact block → prompt → claim check → one retry); with no model or on a
  provider error the deterministic facts are the report. Surfaces: *Extras →
  AI: Database Trends* and assistant tool `database_trend`.
- **C4 — media transcript** (`tcl/ai-transcript.tcl`): the speech of an audio
  lesson as text, using the same local speech-to-text the voice assistant uses
  (`scripts/stt-transcribe.py`, or an `SCIDB_AI_STT` template), with a
  deterministic summary. Nothing is stored; the media player is untouched.
  Surfaces: assistant tool `transcribe_media`. A failing engine's stderr is the
  error detail; an exit status the event loop already reaped is no longer
  mistaken for failure when there is stdout to return.
- Tests: `tests/test_app_novelty.tcl`, `tests/test_app_ai_trend.tcl`,
  `tests/test_app_transcript.tcl`. App suite 356/356; `make -C tests ai-tests`,
  Tcl and C++ suites green.

## Unreleased — AI: auto-annotate priority (A7)

- Auto-annotation now asks the classifier (the `score` primitive) how much each
  engine-flagged moment deserves a comment (low/medium/high) before drafting it.
  The score orders the run and, with `minImportance` set, drops the routine
  moments (`::ai::annotate::configure -minImportance high`). With no classifier
  the fallback is "high", so today's behaviour is unchanged.
- Tests: `tests/test_app_annotate.tcl` (`annotate-rank`, `annotate-priority-skip`,
  `annotate-priority-keeps`). App suite, `make -C tests ai-tests`, Tcl and C++
  suites green.

## Unreleased — System One: the score primitive

- The `score` question type (a position on an ordered level scale) is handled
  end to end. `::ai::systemone::valid` accepted only `choice`/`noul`, so any
  `score` question silently fell back; it now validates the `score`/`confidence`
  shape, and `::ai::systemone::Decided` maps the score to the ordered level
  (`criteria` is the low-to-high level list) and gates on confidence. This
  closes the "the score primitive is unused" gap (`SYSTEM_ONE_RESEARCH.md` §5.1)
  and unblocks the ordering uses (annotate priority, tier routing).
- Tests: `tests/test_app_systemone.tcl` (`systemone-score-valid`,
  `systemone-score-level`, `systemone-score-gate`). App suite, `make -C tests
  ai-tests`, Tcl and C++ suites green.

## Unreleased — AI: comment kind (A3)

- New `tcl/ai-comment.tcl`: what a comment is about — opening theory, a tactic,
  the endgame, a plan, an evaluation, a warning or something else. A deterministic
  keyword rule answers the obvious cases; the bounded classifier (`::ai::decide`,
  choice, gate 0.6) the rest. Read-only.
- Surfaces: the assistant tool `comment_kind {text}`, and *Classify comment* in
  the comment editor's context menu.
- Tests: `tests/test_app_systemone.tcl` (`systemone-comment-rule`, `-classifier`,
  `-rulepath`, `-assistant`). App suite, `make -C tests ai-tests`, Tcl and C++
  suites green.

## Unreleased — AI: voice transcript gate (A8)

- After transcription, before the transcript becomes an assistant request, a
  bounded `noul` classifier asks "is this a plausible request to Scidb?". An
  implausible transcript ("gibberish words") is held in the entry for the user to
  correct rather than sent; a plausible one, or an undecided one, is sent exactly
  as before. With no classifier the gate is skipped (`SCIDB_AI_VOICE_GATE=0`
  disables it, `SCIDB_AI_VOICE_GATE_MIN_CONFIDENCE` sets the gate).
- Tests: `tests/test_app_voice.tcl` (`voice-gate-holds`, `voice-gate-sends`,
  `voice-gate-undecided`). App suite, `make -C tests ai-tests`, Tcl and C++
  suites green.

## Unreleased — AI: translate a comment into a language slot (C2 / C7)

- The comment editor's context menu gains **"Translate comment to"** with a
  language submenu: it translates the comment through the grounded pipeline and
  puts the result into the target language's slot for review. The transformation
  preserves every move and fact; nothing is saved until the user accepts.
  ("Explain this comment" already shipped, so this completes C2/C7.)
- Tests: `tests/test_app_comment_draft.tcl` (`comment-translate-inserts`,
  `comment-translate-ignores-failure`). App suite, `make -C tests ai-tests`,
  Tcl and C++ suites green.

## Unreleased — AI: draft a comment in place (C1 / LLM_REACH_PLAN C6)

- The comment editor's context menu gains **"Draft a comment"**: it runs the
  ordinary grounded pipeline for the current position and puts the drafted text
  into the editor for review. Nothing is saved — the editor's Accept is still the
  user's decision, and the claim checker has already audited the text.
- The grounded generation gains an `-observer` hook (`::application::ai::generate`),
  so a caller can also use the produced text, not just the report.
- Tests: `tests/test_app_comment_draft.tcl` (inserts, appends, ignores a failed
  generation or an empty answer). App suite 313/313; `make -C tests ai-tests`,
  Tcl and C++ suites green.

## Unreleased — AI: show your work (B9)

- Every generated report now carries a **Grounding facts** block: the
  deterministic position facts (`::scidb::ai::text`) the model was given, so a
  reader can see what it was working from beside the assessment. The generation
  result carries them (`::ai::generate`) and `toHtml` renders them.
- Fixed while doing it: `onResult` passed the advisory notices where `toHtml`
  expects the verdict flag, so the System One advisory notices never rendered
  (and a non-empty notice list silently acted as the verdict).
- Tests: `tests/test_ai_ui.tcl` (facts rendered / omitted, advisory notices
  rendered). App suite, `make -C tests ai-tests`, Tcl and C++ suites green.

## Unreleased — AI: explain the engine's line (C3 / audit B6)

- "Explain this line" in the engine analysis pane's line context menu narrates
  the engine's principal variation through the ordinary grounded pipeline (fact
  pack → prompt → claim check → report pane). The line is handed to the claim
  checker, so a move the model names from the engine's line is grounded even when
  it is not legal in the current position: `::ai::claims::check <fen> <text>
  ?<line>?` and `::ai::generate::positionToolsAsync ?-line?`.
- Tests: `tests/test_ai_claims.tcl` (a later move in the line is grounded; the
  same move without the line is flagged; a move outside the line is flagged).
  App suite, `make -C tests ai-tests`, Tcl and C++ suites all green.

## Unreleased — AI: import doctor (System One, A4)

- New `tcl/ai-import.tcl`: turn the importer's error/warning codes into a cause
  and a fix. A deterministic table maps Scidb's PGN reader codes to a category
  (encoding, not-PGN, truncated, bad FEN, illegal moves, missing tags, bad tags,
  variant) with a concrete fix; the bounded classifier is asked only when a code
  is not in the table. The file-import log now ends with the rule-only doctor
  (`Import doctor:` grouped by cause); the assistant tool `diagnose_import`
  uses the classifier too.
- Fixed while wiring it: the import log's "show only encoding warnings" filter
  compared the wrong argument (the empty message slot instead of the code), so
  it never filtered; it now reads the code.
- Tests: `tests/test_app_systemone.tcl` (`systemone-import-rule`, `-text`,
  `-diagnose`, `-rulepath`, `-assistant`). App suite 309/309; Tcl and C++
  suites stay green.

## Unreleased — AI: comment language tagging (System One, A2)

- New `tcl/ai-language.tcl`: the language of a chess comment. A deterministic
  rule answers the scripts a Latin heuristic cannot see (Greek, Hebrew, Arabic,
  Korean, Japanese kana) and leaves Cyrillic/Han/Latin to the bounded
  classifier (`::ai::decide`, choice, gate 0.6) over a fixed set
  (English, German, French, ... plus `xx` language-independent and `yy`
  another language). Read-only.
- Surfaces: the assistant tool `detect_language {text}`, and *Detect language*
  in the comment editor's context menu, which carries the neutral (`xx`) text
  into the detected language slot so the ordinary save path stores it tagged.
- Tests: `tests/test_app_systemone.tcl` (`systemone-language-rule`,
  `-detect`, `-rulepath`, `-assistant`). App suite 304/304; Tcl and C++
  suites stay green.

## Unreleased — AI: event-type bucketing (System One)

- New `tcl/ai-event.tcl`: a game's kind of time control (classical, rapid,
  blitz, bullet, correspondence, simul, training) from its PGN tags. A
  deterministic rule reads the `TimeControl` value and the event words first;
  the bounded classifier (`::ai::decide`, choice, gate 0.6) settles the games
  the rule cannot place, asked once per distinct event. Exposed as
  *Extras → AI: Time Controls* and the assistant tool `event_types`.
  Read-only; with no classifier the rule alone answers and the rest is
  "unclear", so it degrades to a deterministic report.
- Note: scidb does not expose the `TimeControl` tag through `db::get tags`, so
  in practice the rule leans on the event words and the classifier. The study
  plan report now also shows the mix of the games it audited, so the
  blitz/classical mixing the audit warned about is visible.
- Also fixed: `::application::assistant::Resolve` is now safe when no request
  is pending (an asynchronous tool could resolve after its call ended).
- Tests: `tests/test_app_systemone.tcl` (`systemone-event-rule-unit`,
  `-rule`, `-classifier`, `-assistant`). App suite 299/299; Tcl and C++
  suites stay green.

## Unreleased — CQL tagging (:forany / :tagmatch / $tag)

- The CQL tagging system is implemented: `:forany <tag> <designator>` in a
  match list, `:tagmatch <tag> <designator>` and `$tag[squares]` designators in
  position lists. Each piece of the start position gets a mark that travels
  with it (promotion keeps the mark, a capture destroys it); the query is run
  once per binding of the tags to candidate marks (no two tags share a mark),
  and a tag may only take a mark whose piece matches the designator. Up to two
  tags, mainline only. Candidate marks use the start position's piece IDs, so a
  pawn that only *promotes* to the designator's piece is not a candidate (a
  documented narrowing).
- Fixed while doing it: the default `:matchcount` was `1 1`, so a position that
  matched more than once failed the final-position check; the default is now
  "at least once" and an explicit range is enforced only when the game ends.
- Tests: `tests/test_app_cqlfeatures.tcl` (`cqlf-tags` — the "same rook visits
  all four corners" example, plus `:tagmatch` and `:movefrom $tag`). App suite
  295/295, Tcl and C++ suites green.

## Unreleased — CQL :exclude

- `:exclude` is implemented (`src/db/cql/cql_position.cpp`, `cql_match.cpp`,
  `cql_game_matcher.cpp`): with an argument, the game is excluded when the
  sub-position list matches anywhere; without one, the game is excluded when
  the containing position list matches. It never influences the containing
  position's own result. The game walker keeps going after a hit while an
  exclude is pending, and rejects the game at the end.
- Tests: `tests/test_app_cqlfeatures.tcl` (`cqlf-exclude`); app suite 294/294,
  Tcl and C++ suites green.

## Unreleased — CQL accumulator extension

- The CQL-S accumulator keywords are implemented (`src/db/cql/cql_position.cpp`):
  `:accumulate <name>` counts the transformations of the position list that
  match, `:sumrange <name> <range>` matches only when the accumulated value is
  in range, and `:reset <name>` clears the accumulator. The map is cleared when
  a new board position is reached and is shared by nested position lists, so the
  documented "count the passed pawns" and "at least three white and two black
  passers" forms work.
- Tests: `tests/test_app_cqlfeatures.tcl` (`cqlf-accumulate`); app suite
  293/293, Tcl and C++ suites green.

## Unreleased — CQL transformation keywords (flips and shifts)

- The spatial flip and translation keywords are implemented
  (`src/db/cql/cql_position.cpp`, `cql_designator.cpp`):
  `:flip`/`:flipdihedral`, `:fliphorizontal`, `:flipvertical`, `:flipdiagonal`,
  `:flipoffdiagonal`, `:shift`, `:shifthorizontal`, `:shiftvertical`,
  `:shiftmaindiagonal`, `:shiftoffdiagonal`, `:shiftdiagonal`. Each names a
  transformation set (identity included), and multiple keywords compose.
  - The flips are bijections, so they are applied to the board: a pattern D
    transformed by F matches board B iff D matches F(B). All square-based
    conditions (designators, `:piececount`, `:attackcount`, rays, ...) are
    covered uniformly, and move filters are transformed with the move.
  - The shifts are not bijections (CQL's edges smear), so they are applied to
    the designators through an active-shift view (`Designator::view`); nested
    position lists compose with the surrounding shift.
- Tests: `tests/test_app_cqlfeatures.tcl` (`cqlf-flips`, `cqlf-shifts`); the
  app suite passes 292/292, Tcl and C++ suites stay green.

## Unreleased — CQL variations and square-colour designators

- CQL's `:variations` and `:variationsonly` position keywords are implemented
  (`src/db/cql/cql_game_matcher.cpp`, `cql_position.cpp`): the game consumer walks
  the variations when a position list asks for them and tags the positions with
  `IsInsideVariation`; the position list decides whether to accept the main line,
  the variations, or both. A query without either keyword is unchanged (main line
  only). This clears the "Main line only" limit in `CQL_FEATURES.md`.
- CQL's special square-colour designators are implemented in the matcher
  (`src/db/cql/cql_designator.cpp`): `L` selects the light squares and `D` the
  dark squares, in the bracketed (`[L?]`, `[D1]`) and bare (`BL?`, `b[D?]`)
  forms. `L`/`D` may designate the files or the ranks, but not both; using both
  is refused with a new `Square_Colour_Not_Allowed` parse error. This removes a
  `Not_Implemented` blocker named in `PLAIN_LANGUAGE_SEARCH.md`, and the
  `opposite_bishops` pattern now uses `BL?`/`bD?` instead of enumerating all
  32 light and dark squares.
- Tests: `tests/test_app_cql.tcl` (`cql-variations`),
  `tests/test_app_cqlfeatures.tcl` (`cqlf-squarecolour`, `cqlf-colour-error`).

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
- v3 — GL reliability: piece display lists are tracked per GL context
  (each Togl window has its own) and validated with glIsList — a global
  compiled-flag had made every view but the one created first silently
  draw NO pieces.  The optional trailing photo argument of
  glboard_render reads the rendered frame back into a Tk photo
  (glReadPixels from the back buffer, rows flipped manually), which the
  tests use to pixel-verify pieces in both contexts.  Text marks now
  render on the GL surface too (baked pixel font as flat quads —
  glXUseXFont proved to corrupt the GL context on some stacks; negative-
  pitch Tk_PhotoPutBlock corrupts the heap and is also avoided).
  New ::scidb::tk::glboard_info reports {renderer vendor version} of a
  view's GL context, so anyone can check whether they are on hardware
  (GPU name) or software (llvmpipe).
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