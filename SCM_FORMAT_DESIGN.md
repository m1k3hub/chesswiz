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
| Video (embedded, board-synced) | **Tier 2 (optional `--enable-mpv`):** libmpv embedded in a Tk frame, cued to move timestamps | future, see `MEDIA_PLAYBACK_DESIGN.md` |
| Stream (URL) | hand URL to system browser/player | trivial |

UI flow:
1. User opens a game. Tcl queries `scm::MediaTable::mediaFor(gameId)`.
2. A **media pane** in the game view shows one thumbnail/button per entry:
   - Picture → render inline with Tk photo (click = full-size).
   - Audio/Video → a "▶ Play" button; click extracts (if inline) and launches
     the system player, or plays embedded (mpv tier).
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
4. **Board-sync (v2)** — the `[BoardSync "mediaId" @moveN=ts …]` grammar, so
   video can be cued to game positions (the real "Chess Media System"). Design
   the extension point now even if v1 ignores it.
5. **One `.scm` per DB vs per-game `.scm`** — one companion file is simpler
   and fine for the scale; chosen here.