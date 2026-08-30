# SCM — a scidb-native Media Format + Playback Design

**Status:** proposal (greenfield). Authored 2026-08-20, after the ChessBase
`.cbm` reverse-engineering effort (see `CBM_FORMAT_DESIGN.md`). The RE proved
that a *text manifest* + *stable-ID linkage* + *external payloads* would have
avoided every hard problem we hit with ChessBase's opaque binary `.cbm`. This
design starts from that conclusion.

## 0. Design goals (and anti-goals)

**Goals**
1. Associate media (image/audio/video/stream) with games and guiding-text
   entries in a scidb database.
2. **Authorable and debuggable** — a human can read/edit the manifest in a
   text editor and `diff` it. (ChessBase `.cbm` fails this hard.)
3. **Portable** — copy the database folder, media travels with it.
4. **Graceful degradation** — missing/corrupt media never blocks opening the
   database; you just lose enrichment. (Same principle as the `.cbm` parser.)
5. **No duplication** — a media file referenced by 1000 games is stored once.
6. **Stable linkage** — reordering/sorting/deleting games does not break
   media associations. (ChessBase couples linkage to `.cbg` offsets / row
   numbers — we could not even crack it.)
7. **Playable in scidb today** — images via existing Tk; audio/video via
   system-player delegation, with an optional embedded path later.

**Anti-goals (v1)**
- Not binary/compact. Media DBs are small; text is fine and wins on every
  other axis. A binary table is explicitly rejected (it is the `.cbm` mistake).
- Not a media *container* (we do not invent a video codec). Payloads are
  standard files (JPEG/PNG/MP3/MP4/…).
- Not board-synced "Chess Media System" in v1 (video cued to moves). That is a
  v2 extension point, designed-in but not built.

## 1. Format: `.scm` companion manifest

A `.scm` (scidb media) file is a **UTF-8 text manifest** that is a *companion*
to a scidb database (e.g. alongside `MyBase.si4`). Payloads live as ordinary
files in a sibling folder `MyBase.media/`. Both are optional; deleting either
leaves a fully functional game database.

### 1.1 Why text + external payloads (and not the alternatives)

| Option | Verdict |
|---|---|
| **A. Text manifest + external payload folder** | ✅ chosen. Debuggable, diffable, VCS-friendly, no duplication, portable, large-media-friendly, trivial to author/convert. |
| B. Binary table (CBH/CBM-style) | ❌ rejected. Opaque, hard to author/debug — the exact thing that made `.cbm` RE take days. Compactness is irrelevant at this scale. |
| C. Embed media in the game/annotation record | ❌ rejected. Media is not annotation; bloats game data; shared media would duplicate; ties media lifetime to a single game. |

### 1.2 Grammar (line-oriented, PGN-ish, forgiving)

```
# scidb media manifest
# version 1

[Database "MyBase"]          # rootname this manifest companions (advisory)
[MediaDir "MyBase.media"]    # payload folder, relative to the .scm file
[Encoding "utf-8"]

# --- media library: one block per physical media file ---
[Media "M01"]
Type: picture
Path: images/bilbao_topalov_anand.jpg
Title: "Bilbao 2008: Topalov-Anand"
[Media "M02"]
Type: video
Path: videos/cbm126_aronian_grischuk.mp4
Title: "CBM 126: Aronian-Grischuk"
[Media "M03"]
Type: audio
Path: audio/lasker_commentary.mp3
[Media "M04"]
Type: inline-picture            # payload embedded inline (small/standalone)
Inline: base64,<iVBORw0KGgoAAAANSUhEUgAA...>
Title: "Thumbnail"

# --- linkage: stable game id -> media ids ---
# Game is referenced by the scidb stable game id (NOT a row/position number).
[Game "42"]
Media: M01, M02
[Game "108"]
Media: M01, M03
[Game "108"]                   # duplicate block => appended (multi-section ok)
Media: M04
```

Key rules:
- **Comments** with `#` (full-line only).
- **Media ids** (`M01`…) are local handles; `Path` is relative to `MediaDir`.
  The same media id may be referenced by many games (no duplication).
- **Game ids** are the scidb **stable game id** (see §2). Not list-row numbers.
- **Inline** payloads (base64) for small self-contained media; external `Path`
  is the default and preferred for anything large.
- Unknown sections/keys are **ignored** (forward-compatible). A parser that
  does not understand `[BoardSync …]` (v2) skips it and still works.
- Line continuations, quoting, and escapes follow PGN conventions (so existing
  PGN tooling/lexers can be reused).

### 1.3 File layout

### 1.5 `[Interactive]` — position-keyed video (v1.1)

Interactive video: media segments attached to *positions* rather than
whole games. While a game is played through on the board, the media panel
jumps to the segment that owns the current position (ChessBase "Media
System" `.cms` semantics — see CBM_FORMAT_DESIGN.md §7 — implemented
natively). Two segment kinds:

```
[Media "V0"]
Type: video
Path: videos/mardelplata_lecture.mp4

# Kind: clip — the segment is its own file (what a .cms import yields)
[Interactive "V1"]
Fen: r1bq2k1/ppp2r2/3p1n1b/3n4/P1pP1N2/2N1P2P/2Q2PP1/1R1R2K1 b
Kind: clip
Clip: videos/mardelplata_x0y0v4u0.wmv
Label: "hotspot x0 y0"

# Kind: range — the segment is a time range of a [Media] video
[Interactive "V2"]
Media: V0
Fen: r1bq1rk1/2p1bppp/p1np1n2/... w
Kind: range
Start: 84.0
End: 160.0
Label: "Aronian explains the plan"
```

Key rules:
- `Fen` comparison uses board + side to move only (castling/move counters
  are ignored, so transposed lines and differing headers match).
  For clip filenames scidb keeps the ChessBase convention: '/' → 'z'.
- `Kind: clip` — `Clip` (and `Label`) present; playback plays the file.
- `Kind: range` — `Media`, `Start`, `End` (seconds, float); playback
  seeks to `Start` in the referenced video and stops at `End`.
- Referencing from `[Game]` uses the plain `Media:` key; position-keyed
  segments may also sit standalone in an `.smv` manifest with no
  `[Game]` blocks (then any game of the companion DB can use them).
- A sibling `<name>.smv` next to a ChessBase `<name>.cms` **overrides**
  the .cms parse (author once, keeps the .cbm-era binary out of the loop).
  `media-console/cms2smv.tcl` ports a .cms into this grammar.

```
MyBase/
  ├── MyBase.si4          # the games
  ├── MyBase.scm          # this manifest (text)
  └── MyBase.media/       # payloads
      ├── images/
      │   └── bilbao_topalov_anand.jpg
      ├── videos/
      │   └── cbm126_aronian_grischuk.mp4
      └── audio/
          └── lasker_commentary.mp3
```

### 1.6 `[BoardSync]` — lecture timelines + board events (v1.2, from the WMV RE)

The ChessBase WMV reverse engineering (`CHESSBASE_MEDIA_RE.md`) proved
that Chess Media lectures are not just audio/video: the ASF script
stream carries a **serialized game-tree replay** (per-step media
timestamps), from/to move arrows, styled square marks, positional symbol
lights and multilingual pre/post comments — all keyed to the video
timeline. The `[BoardSync]` section gives `.scm` the same capability
without any of ChessBase's encoding hazards:

```
[Media "V05"]
Type: video
Path: videos/biel_r6_marin.wmv
Title: "Biel 2015 round 6 — Marin"
Title-lang de: "Biel 2015 Runde 6 — Marin"

[Game <fingerprint>]
Media: V05

[BoardSync "V05"]
# navigation timeline: one Step per replay step — media-ms, ascending,
# in the lecture's own navigation order (depth-first through the game
# tree, variations interleaved).  The board advances one step per
# elapsed mark.
Step: 30642
Step: 37142
Step: 51142

# transient board events: <media-ms>, <kind>, payload (one per line)
Arrow: 45200, green, c8-e6
Mark: 46000, green, h8
Comment: 51000, post, , "would transpose to a Shirov-Bacrot 2014 game"
Symbols: 51000, 1, 1
Comment: 90200, pre, de, "Der Läufer nach c7 verliert"
Reset: 63000
```

Key rules — each settles a trap the ChessBase binary left us:

- **Time base**: integer media-ms in the referenced video, ascending.
  `Step` marks follow the lecture's own navigation order, which is
  depth-first through the game tree with variations interleaved.
- **Squares are algebraic** (`c8`, `e6`), never numeric board indices.
  The decoded ChessBase stream uses file-major square bytes (`a1` = 0,
  `b1` = 8, `a2` = 1; graphics one-based) — an encoding trap that took a
  full RE round to pin down; `.scm` stores what a human and scidb's core
  already speak.  An omitted index (ChessBase `0`) means "none".
- **Styles** are free short tags (`green`, `yellow`, `red`, …).
  ChessBase media uses numeric style bytes (2/3/4; colors still
  unverified against the GUI) — `.scm` never stores those numbers, only
  the author's intent.
- **`Comment`**: `post` (after the move; ChessBase type `0x02`) or
  `pre` (before; type `0x82`), then the language code (empty = all
  languages), then the quoted text.  Imports transcode from
  Windows-1252 to UTF-8; script records carry per-language copies, and
  the UI shows only the active locale's copy when present.
- **`Symbols`**: scidb NAG numbers (the decoded symbol records are
  move glyphs / position evaluations / prefix glyphs — standard NAG
  territory, not worth re-inventing).
- **`Reset`** clears transient overlays at that time (the ancestor
  opcode-`08` boundary).
- Unknown event kinds are ignored — like every other section.
- **`Step`-only sections** are the flat case consumed today:
  `wmv2timeline.py --plytimes` writes the one-mark-per-line form, and
  an `.scm` `[BoardSync]` with only `Step:` lines is its in-manifest
  generalization.  Event-carrying sections cover the full decoded WMV
  record set (types 2/3/4/5/8/14).

Consumption: the panel feeds the `Step:` marks to
`::media::sync::load-timeline` (the ply driver) and queues the events
for the annotation layer when playback reaches them (§4 tier-2, future).
The `Step`-only form is the v1.2 ship set; events ride along whenever an
importer produced them.

## 2. Linkage: stable game id (the central design decision)

This is where ChessBase's `.cbm` failed us: its linkage couples media to `.cbg`
*byte offsets* and to record/row positions, so (a) we could not decode it and
(b) even the GUI's own row numbers ≠ `.cbh` record indices (the list is
date-sorted). A scidb format must not repeat this.

**Rule: link media to a game's content fingerprint, never to a position.**

Confirmed against the codebase: scidb games are **index-addressed** with no
stable per-game id (`Database::gameInfo(unsigned index)`, `computeChecksum(index)`).
So SCM uses a **normalized header fingerprint** as the primary key — it is stable
across sort/reorder/re-index (reordering doesn't change game content) and is
cheap (no move decode).

- `[Game "<hex-fingerprint>"]` where the fingerprint = FNV-1a-64 of the
  normalized string `"white|black|event|date|round|result"` (lowercased,
  trimmed). Computed by `scm::fingerprint(normHeader)`.
- At database-open time the loader fingerprints each game (header only) and builds
  `fingerprint -> vector<Entry>`.
- A game edit changes its fingerprint → its `[Game]` block becomes an orphan
  (dropped on maintenance, or re-attached by the authoring tool). Identical games
  share media (acceptable semantic).
- This single rule removes the entire class of "row vs record vs offset"
  confusion that made `.cbm` uncrackable, and it is the only stable key scidb
  offers.

## 3. C++ core API

```cpp
namespace db { namespace scm {

class MediaTable
{
public:
    enum Type { None, Picture, Audio, Video, Stream };

    struct Entry {
        mstl::string  mediaId;    // "M01"
        Type          type;
        mstl::string  path;       // relative to media dir (or inline)
        mstl::string  title;
        bool          inlineData; // payload is base64 in `path`
    };

    bool read(mstl::string const& scmPath);        // never throws
    bool isOpen() const;
    unsigned mediaCount() const;                   // library size
    unsigned gameCount() const;                    // games with media

    // per-game access — the primary query used by playback
    void mediaFor(unsigned gameId, mstl::vector<Entry>& out) const;

    // resolve a relative path to an absolute one in the media dir
    mstl::string resolvePath(Entry const& e) const;

    // gallery (no linkage needed): all media in the database
    void collectAll(mstl::vector<Entry>& out) const;

    void clear();
    void dump() const;                             // RE/debug aid
private:
    // id -> entries   (a game can map to several entries)
    mstl::map<unsigned, mstl::vector<Entry>> m_byGame;
    mstl::vector<Entry>                     m_library;
    mstl::string                             m_mediaDir;
    bool                                     m_isOpen;
};

}} // namespace db::scm
```

Notes:
- `read()` is **defensive by construction** (lessons from the `.cbm` parser):
  try/catch around all I/O, a sane size cap, ignore-unknown-sections for
  forward compatibility, and a missing/corrupt `.scm` or `.media/` folder
  yields `isOpen()==false` and zero entries — the database still opens.
- Integration mirrors the existing `cbh::MediaTable`: a `scm::MediaTable`
  member on the scidb codec, loaded in `doOpen()` after the game index, inside
  a `try/catch(...)` that clears on failure (exactly the `readMediaData()`
  pattern already used for `.cbm`).

## 4. Playback architecture

Playback is **UI work**; the core only hands the UI a `vector<Entry>` for the
opened game. scidb is Tcl/Tk, so:

| Media type | Renderer | Status |
|---|---|---|
| Picture (jpg/png/gif/bmp) | **Tk `image create photo`** with scidb's bundled JPEG/PNG/GIF decoders | available now |
| Audio (mp3/wav/ogg) | **Tier 1:** extract inline→temp, launch system player (`xdg-open`/platform) | no new dep |
| Video (mp4/wmv/…) | **Tier 1:** same system-player delegation | no new dep |
| Video (embedded, board-synced) | **Tier 2 (optional tkvlc):** libVLC embedded in a Tk frame, cued to move timestamps | future, see `MEDIA_PLAYBACK_DESIGN.md` |
| Stream (URL) | hand URL to system browser/player | trivial |

UI flow:
1. User opens a game. Tcl queries `scm::MediaTable::mediaFor(gameId)`.
2. A **media pane** in the game view shows one thumbnail/button per entry:
   - Picture → render inline with Tk photo (click = full-size).
   - Audio/Video → a "▶ Play" button; click extracts (if inline) and launches
     the system player, or plays embedded (tkvlc tier).
3. Missing payload file → the entry shows a "media missing" placeholder, not
   an error (graceful degradation).

This reuses everything scidb already has (Tk photo, the `MEDIA_PLAYBACK_DESIGN`
tiers) — no new core dependency for v1.

## 5. Authoring + round-trip

- **Add media to game:** UI "Add media…" → pick a file → copied into
  `<db>.media/<type>/<slug>.<ext>` → a `[Media]` block + a `[Game]` block are
  appended to the `.scm`. Round-trips: re-open shows the media.
- **Shared media:** picking an already-indexed media file just adds its id to
  the game's `Media:` line (no second copy on disk).
- **Import from ChessBase `.cbm`:** the existing `cbh::MediaTable` already
  cracks the manifest (57 refs, 98% present on disk). A converter copies the
  `.html` images into `.media/images/` and emits `.scm` `[Media]`/`[Game]`
  blocks. The *linkage* conversion (bag→game) is the one piece still gated on
  the `.cbm` RE — but the *gallery* (all images, no per-game mapping) converts
  today as a `[Game "*"]` fallback or a database-level gallery.

## 6. Why this beats ChessBase's `.cbm` (the lessons, applied)

| Problem we hit with `.cbm` | SCM fix |
|---|---|
| Opaque binary; RE took days | Text manifest; readable in any editor |
| Linkage = `.cbg` byte offsets / row numbers; uncrackable | Stable game id (+ optional fingerprint); positions never matter |
| `FilesUsed` count is advisory/buggy (declares 4, lists 7) | No count field — sections are self-delimiting |
| Media blobs interleaved with binary linkage table | Payloads are plain files in a sibling folder |
| One media-rich sample; no format spec | Open spec here; any sample is self-describing |
| GUI list is date-sorted, row ≠ record | Linkage is by id, not row, so this is a non-issue |

## 7. Build / integration plan

1. `src/db/scm/scm_media.{h,cpp}` — the `MediaTable` parser + `mediaFor()`.
   Defensive (try/catch, size cap, ignore-unknown).
2. Hook into the scidb codec's `doOpen()` (mirror `cbh::readMediaData()`).
3. `src/db/Makefile`: add `scm/scm_media.cpp`.
4. Tcl: `::scidb::db::mediaFiles <db> <gameId>` subcommand (follow the
   `cmdEcoStats` pattern in `tcl_database.cpp`) returning `{filename type
   mediaId title}` rows — the bridge the UI needs.
5. Tcl UI: media pane in the game view (images via Tk photo; a/v via system
   player).
6. Tests: a `test_scm_media.cpp` modeled on `test_cbm_media.cpp` — independent
   header/size check, parse cross-check, synthetic corrupt-manifest cases,
   missing-media-folder degradation, and a stable-id-after-reorder test (the
   case `.cbm` could not satisfy).
7. Converter: `cbm2scm` tool using `cbh::MediaTable::collectMediaFiles()`.

## 8. Open design decisions (worth a quick consensus before building)

1. **Stable id vs content fingerprint as primary key** — depends on what
   scidb's native format actually guarantees (confirm against `Database` API).
2. **Inline base64 cap** — small enough to keep the manifest readable (e.g.
   ≤64 KiB), above which external is required.
3. **Tombstones on game delete** — keep `[Game]` blocks as records vs prune.
4. **Board-sync (v2)** — DESIGNED (2026-08-30): §1.6 `[BoardSync]` gives
   the grammar lecture timelines (`Step:` marks) and board events
   (arrows/marks/comments/symbols, algebraic squares, NAGs), informed by
   the decoded ChessBase script stream (`CHESSBASE_MEDIA_RE.md`).  The
   `Step`-only form ships with the landed `wmv2timeline.py` +
   `::media::sync::load-timeline` path; the event form awaits the
   annotation application layer.  Open sub-question: whether event-heavy
   lectures should inline their events in the `.scm` or reference an
   external `V05.sync` payload (§1.2's inline-cap rule applies).
5. **One `.scm` per DB vs per-game `.scm`** — one companion file is simpler
   and fine for the scale; chosen here.