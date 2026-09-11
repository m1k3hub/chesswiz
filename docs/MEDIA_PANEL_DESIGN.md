# Media Panel Design (tcl/app-media*.tcl)

Status: written after implementation (reverse-spec), reviewed against the
code. Companion documents: `MEDIA_PLAYBACK_DESIGN.md` (backend selection),
`MEDIA_LESSON_V2_PLAN.md` (lessons), `SCM_FORMAT_DESIGN.md` (manifest
format), `CBM_FORMAT_DESIGN.md` (ChessBase media system).

## 1. Module map

| File | Namespace | Responsibility |
|---|---|---|
| `tcl/app-media.tcl` | `::application::media` | Panel UI (ChessBase-style transport bar, viewer, collapsible tree, status), media resolution, playback orchestration, sync wiring |
| `tcl/app-media-mpv.tcl` | `::media::mpv` | mpv JSON-IPC transport (Tier-2b backend) |
| `tcl/app-media-decode.tcl` | `::media::decoder` | ChessBase script-stream (WMV stream 2) decoder |
| `tcl/app-media-lesson.tcl` | `::media::lesson` | Lesson cache: timeline + board events per video, persisted to sidecars |
| `tcl/app-media-sync.tcl` | `::media::sync` + `::mediasync` | UI-free sync state machine (transport/follow/annotation delegates) |

C++ boundary: `::scidb::db::mediaFiles` (per-game media),
`::scidb::db::mediaGallery` (database-level gallery), `::scidb::game::link?`,
`::scidb::game::fen`, `::scidb::game::ply`, `::scidb::game::go`,
`::game::new`. See `src/tcl/tcl_database.cpp` for the type-id contract
(§3.1). Board rendering: `::board::diagram::{drawAlternative,hilite,
clearMarks,canvas}`.

## 2. Media type ids (wire contract)

Both C++ commands document the SAME encoding (`tcl_database.cpp`,
`cmdMediaFiles`/`cmdMediaGallery` comment):

```
0 = none    1 = picture    2 = audio    3 = video    4 = stream
```

Tcl-side mapping to panel sections (`TypeNumber`, `Sections`):

| Id / label | Section |
|---|---|
| `1` | picture |
| `2` | audio |
| `3` | video |
| `0`, `4`, unrecognized string | other |
| string naming a known section (e.g. `"reports"`) | passes through as that section |

The `.cbm` bitflag encoding (1=audio, 2=picture, 4=video, 8=stream,
`cbh_media.h`) is normalized to the ids above inside the C++ commands;
Tcl code MUST NOT re-interpret raw `.cbm` flags.

## 3. Data flow

### 3.1 Resolution (Update)

`Update(position)` runs on game switch (debounced via `after 1`) and on
database switch. Order:

1. `Stop` any playing media, clear the tree.
2. **Independent mode** (`position < 0 || position == 9`, no game on
   board): fall back to the last opened base's gallery
   (`mediaGallery`), keeping entries playable without a game.
3. Otherwise: `::scidb::game::link?` resolves the owning base, then
   `mediaFiles` returns per-game entries; rows are inserted via
   `InsertEntry` (grouped under section headers).
4. `.cms` files among the entries are collected as interactive indexes.

`InsertEntry(typeLabel, title, path, index)` groups by section
(`TypeNumber` maps ids/labels → section keys; missing sections are
created lazily).

### 3.2 Playback selection (PlaySelected)

Re-classifies by file extension (`ClassifyFile`: 1 picture, 2 audio,
3 video, 4 stream/.cms) and dispatches:

- **Pictures** → inline Tk photo, scaled to fit (`ShowImage`).
- **`.cms` index** → `ResolveIndex` (§3.3), then lesson/plain playback.
- **Media owned by a game** (`type in {2 3}` with `galleryIndex >= 0`) →
  **coupled lesson** (`PlayLesson`): the owning game is loaded first
  (`::game::new` + `after idle`), media plays embedded only, sync
  timeline/events load together. Never falls back to an external player.
- **Plain media** → `PlayMedia`: clear sync state, try embedded
  (mpv → tkvlc); video (`ClassifyFile == 3`) refuses the external
  fallback (it would lose board coupling); other types fall back to
  `LaunchExternal` (xdg-open/open/start).

### 3.3 Interactive video (.cms / .smv)

Two index formats resolve to position-keyed clips:

- **`.cms`** (ChessBase, CBM_FORMAT_DESIGN §7): sibling clip directory,
  FEN-seeded filenames (`/` → `z`), hotspot squares encoded in
  `x{X}y{Y}v{V}u{U}` (`CmsSquare`: file-major 0-based, a1=0). Verified
  corpus: 109/109 legal moves.
- **`.smv`** (scidb manifest, SCM_FORMAT_DESIGN §1.5): `[Media]` /
  `[Interactive]` sections; `Kind: clip` (own file) or `Kind: range`
  (referenced `[Media]` id + Start/End seconds).

Resolution order in `ResolveIndex`: `.smv` entries (position match →
interactive), `.smv` baseline, then `.cms` entries, `.cms` baseline.
FEN matching uses `FenKey` (`<board with 'z' separators> <side>`).

Three interactive sources, checked in `InteractiveFollow` order:
user manifest (`~/.scidb-beta.../media/interactive.scm`), database
manifest (`<root>.scm` via `LoadDbInteractive`), then the game's own
`.cms` indexes. A matched clip plays once per position key
(`Priv(interactive:played:<key>)`) and draws the `.cms` hotspot arrow.

## 4. Playback backends (tiered)

1. **Tier-2b: mpv** (`::media::mpv::launch`, JSON-IPC Unix socket):
   preferred when `mpv` is in PATH. Position/duration are cached by IPC
   property-push events; `CheckDecode` verifies liveness 800 ms after
   launch.
2. **Tier-2a: tkvlc** (libVLC embedded via window id): fallback when
   mpv is absent. `CheckDecode` inspects player state; one retry for
   demux pre-fill hiccups (`Priv(vlcretry)`).
3. **External** (`LaunchExternal`): pictures/audio/non-coupled media
   only — never game-coupled video (spec §3.2).

Invariants:

- **One player at a time.** `Stop` (or `DestroyVlcHandle`) releases the
  previous backend before a new launch. `Stop` cancels all deferred
  timers (`checkid`, `rangeid`, `seekid`, follow tick).
- **Range entries** (`startMs`/`endMs`) seek on start and arm a
  stop-at-End timer for both backends.
- **Lifecycle:** playback stops when the panel is unmapped
  (`activate`/`setActive`) or destroyed (`closed`).

## 5. Sync state machine (`::media::sync`)

UI-free; the panel wires delegates at `build` time
(`SyncTransport`, `SyncBoardForward/Start/Length/Ply`, `SyncAnnotate`,
`SyncClearAnnotations`). Two coupled modes:

- **Transport sync** (board autoplay drives media; manual navigation
  pauses media) — `::media::sync::autoplay`/`step` from board code.
- **Follow mode** ("board follows video"): `FollowTick` every 100 ms
  feeds `(time, duration)` to `::media::sync::drive`, which maps media
  time to nodes — via the decoded per-move timeline when a lesson
  sidecar/timeline exists; without one the board is left at the game
  position (no guessed timing) — and invokes the
  board delegates. mpv branch must be checked before tkvlc (no vlc
  handle exists while mpv is active).
- **Main-line projection:** the lesson timeline is projected onto the
  main-line position table by `::media::lesson::_mainline-timeline`
  before it is persisted. The raw opcode-03 cursors address the
  authoring tree including variation patch slots, which the position
  table does not carry; keeping them made the board jump to unrelated
  main-line plies during a variation. Out-of-range cursors and
  variation detours (a jump of >2 plies that the next cursor rewinds)
  are dropped, so the board holds the last main-line position through a
  variation and resumes afterwards. Cache signature is v4.
- **Board → media:** `BoardUpdated` (called from
  `application::board::update`) defers to idle → `PlySeek` (seek the
  media to the board's node unless the sync machine is `driving?`) and
  150 ms → `InteractiveFollow` (jump to a position-matched clip).

```
                 ┌─────────────────────┐
                 │  Transport sync     │  board autoplay/step
                 │  (board drives)     │  → ::media::sync::autoplay/step
                 └─────────┬───────────┘
                           │
      board manual nav ────┴──── pauses media
                           │
┌──────────────┐   idle debounce    ┌──────────────┐
│ board::update │ ───────────────►  │   PlySeek    │  seek media to node
│ (BoardUpdated)│    150ms debounce │ (skipped if  │  (unless driving?)
│               │ ───────────────►  │  driving?)   │
└──────────────┘                    └──────────────┘
        │
        └──────────────────────────► InteractiveFollow
                                      (jump to position-matched clip)

┌──────────────┐  every 100ms   ┌──────────────┐   maps time→node via
│  FollowTick  │ ─────────────► │ sync::drive  │   lesson timeline (no
│ (mpv/tkvlc)  │  (time,dur)    │ "board       │   guessed timing when
└──────────────┘                │  follows     │   absent) ──────────►
                                 │  video" mode │   board delegates
                                 └──────────────┘   (Goto/Forward/
                                                      Start/Length/Ply)
```

Transport sync and Follow mode are mutually exclusive directions of
control (board→media vs. media→board); `driving?` is the flag that
lets `PlySeek` know Follow mode currently owns the ply so it doesn't
fight it.

Timeline source precedence: lesson cache (`::media::lesson::get`, which
decodes the WMV script stream via `::media::decoder` and persists a
`.plytimes` sidecar) → `.plytimes` sidecar → empty (no board navigation).
Annotation events come from `.events` sidecars (`ms kind payload`),
fired as `SyncAnnotate` calls: `arrow`/`mark` (board diagram overlay,
rendered green — visual-oracle-verified in Reader14 on Windows,
2026-09-07: the style/class byte carries no colour and every script
annotation renders one green; see CHESSBASE_MEDIA_RE.md), `comment`
(status bar), `symbol` (logged).

## 6. Known gaps / follow-ups

- Variation positions are not followed: the checkpoint patch slots that
  carry off-main-line moves still have open per-slot semantics
  (`CHESSBASE_MEDIA_RE.md`), so the board holds the main-line position
  while the video explores a variation.
- No unit tests for the panel itself; `tests/test_app_media_sync.tcl`
  covers only the sync state machine (with injected stubs).
- Inline (base64) media entries are listed but not playable (status-bar
  notice); extraction is future work.
- `LoadSyncEvents`/`LoadSyncSidecar` are only wired on some paths;
  `PlayLesson` uses the lesson cache instead. Consolidate.
- `ShowImage` recreates `Priv(img)` twice (once inside `catch` for
  probing, once for real) — harmless but wasteful.
- `Update` clears `interactive:played:*` only in independent mode;
  switching games within a base retains played-keys (deliberate:
  re-entering a position does not replay), but a database switch should
  arguably clear them too.
- Debug log goes to `/tmp/scidb-media-debug.log` unconditionally.

## 7. Panel layout (ChessBase-style, 2026-09-11)

The pane mirrors the Chess Media System control strip (ChessBase help,
"Chess Media System"): the video/viewer fills the pane, and a single
transport bar sits directly beneath it with

- a round blue play/pause button (canvas glyph reflects `MediaState`),
- a black LCD read-out showing `current / total` in green digits,
- round chapter prev/next buttons (`ChapterStep`, walking the gallery),
- the seek slider, and
- a volume indicator (mouse-wheel to change, click to mute).

The transport canvas is drawn by `application::media::_drawControlBar`
and hit-tested by `_controlBarClick`; `Priv(seeklabel)` is traced so the
LCD follows `SeekTick`/`Stop`. The media list (treeview) sits below the
transport and is collapsed with the footer's *Media list* button
(`ToggleList`); the *View report* / *Open externally* actions live in
the list header. `Priv(seekbar)` remains a `ttk::scale`, so the
seek/scrub logic is unchanged.
