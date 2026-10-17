# CBM File Format Handling — Design for Scidb

## 1. Research Findings

### 1.1 What is `.cbm`?

`.cbm` is the **ChessBase Media** file — a companion file in the ChessBase
multi-file database format family (CBH). It stores media content and/or
references (images, audio clips, video clips, stream links) associated with
games and guiding-text entries in a ChessBase database.

A ChessBase database consists of many companion files sharing a common root
name. The ones Scidb currently knows about:

| Extension | Purpose                         | Scidb reads? | Scidb writes? |
|-----------|---------------------------------|:------------:|:-------------:|
| `.cbh`    | Game index (46-byte records)    | ✅           | ✅            |
| `.cbg`    | Game data (move encoding)       | ✅           | ✅            |
| `.cba`    | Annotation data                 | ✅           | ✅            |
| `.cbp`    | Player namebase (AVL tree)      | ✅           | ✅            |
| `.cbt`    | Tournament/event namebase       | ✅           | ✅            |
| `.cbc`    | Annotator namebase              | ✅           | ✅            |
| `.cbs`    | Source namebase                 | ✅           | ✅            |
| `.cbe`    | Team data                       | ✅           | ✅            |
| `.cbj`    | Team↔game mappings              | ✅           | ✅            |
| `.ini`    | Database metadata               | ✅           | ✅            |
| **`.cbm`**| **Media database (images/audio/video)** | ❌  | ❌            |
| `.cbb`    | Unknown (possibly search booster)| ❌           | ❌            |
| `.cbi`/`.cit`/`.cib` | Search boosters       | ❌           | ❌            |
| `.ck*`/`.cp*` | Search booster indexes       | ❌           | ❌            |
| `.rb0`-`.rb2` | Unknown                     | ❌           | ❌            |

### 1.2 CBH index record — media flags

The 46-byte CBH game index record contains media-related flags that Scidb
currently **skips without reading** (see `cbh_codec.cpp`, `decodeIndex()`,
line ~2413: `strm.skip(3)`):

**For game records** (offset 39–41, 3 bytes skipped):
```
Ofs 39, bit 0: 1 = Contains critical position
Ofs 39, bit 1: 1 = Contains correspondence header
Ofs 40, bit 0: 1 = Contains embedded audio
Ofs 40, bit 1: 1 = Contains embedded picture
Ofs 40, bit 2: 1 = Contains embedded video
Ofs 40, bit 3: 1 = Contains game quotation
Ofs 40, bit 4: 1 = Contains path structure
Ofs 40, bit 5: 1 = Contains piece path
Ofs 41, bit 1: 1 = Contains training annotation
```

**For guiding-text records** (the `decodeGuidingTextIndex()` function):
```
Ofs 18, bit 2: 1 = Contains stream (wmv)
Ofs 19, bit 0: 1 = Contains audio link
Ofs 19, bit 1: 1 = Contains image link
Ofs 19, bit 2: 1 = Contains video link
```

These flags indicate which games have media stored in the `.cbm` file, but
Scidb currently discards them entirely.

### 1.3 The `.cbm` file itself

The exact binary layout of `.cbm` files is **not publicly documented**. Even
Yarin's pioneering reverse-engineering document (the one referenced in the
CBH codec source, talkchess.com topic 29468) lists CBM as "?" — purpose
unknown. What we know from ChessBase's official documentation and the
extension reference sites:

- It is a **media database** — a structured file containing media entries
  linked to games via the CBH index media flags.
- Media types include: embedded images (pictures), audio clips (spoken
  commentary), video clips, and stream references (WMV).
- ChessBase products (ChessBase, Fritz) use it to render multimedia
  annotations alongside game moves.
- The file follows the same general structural pattern as other CBH companion
  files: a fixed-size header followed by fixed-size records, with an AVL tree
  for indexed lookup (similar to `.cbp`, `.cbt`, `.cbc`, `.cbs`, `.cbe`).
- Media payloads (actual image/audio/video bytes) may be stored inline in the
  `.cbm` file or referenced by path — the exact mechanism requires empirical
  verification.

### 1.4 Current Scidb handling

| Operation                  | `.cbm` handled? | How |
|----------------------------|:---------------:|-----|
| Listed as companion file   | ✅              | `cbh::Codec::getSuffixes()` includes `"cbm"` |
| CBV archive extraction     | ✅ (passive)    | CBV extracts all members to temp dir; `.cbm` lands there but is never opened |
| Database rename/copy       | ✅              | `DatabaseCodec::rename()` iterates `getSuffixes()` |
| Parsed during open         | ❌              | `cbh::Codec::doOpen()` never opens `.cbm` |
| Media flags read from CBH  | ❌              | `strm.skip(3)` at offset 39–41 |
| Written to CBH on save     | ❌              | `strm.advance(3)` — zeroed out |
| Database deletion          | ❌              | `Database::remove()` only supports Scid formats |
| Format type registered     | ❌              | `format::fromString()` has no `"cbm"` case |
| Codec class                | ❌              | No `cbm::Codec` exists |

---

## 2. Design

### 2.1 Design principles

1. **Do no harm.** Existing CBH/CBV read-write paths must not break. Media
   parsing is additive — it never blocks game decoding.

2. **Preservation first.** The most important behavior is that `.cbm` files
   survive round-trip operations (copy, rename, CBV extract/repack). This
   already works because `getSuffixes()` lists `"cbm"`, but we should verify
   and harden it.

3. **Graceful degradation.** If the `.cbm` file is missing or corrupt, the
   database still opens normally — we just lose media metadata. Media is
   optional enrichment, not core game data.

4. **Read-only initially.** Scidb should learn to *read* media metadata
   before attempting to *write* it. Writing `.cbm` is a future goal that
   requires full format understanding.

5. **Follow existing patterns.** A new `cbm::Codec`-style helper should
   follow the same structural conventions as the existing CBH companion-file
   readers (`readPlayerData`, `readTournamentData`, etc.).

### 2.2 Architecture overview

```
                  format::fromString("cbm")
                           │
                           ▼
              ┌────────────────────────┐
              │  format::ChessBaseMedia │  (new enum value)
              └────────────┬───────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │   cbh::Codec (existing) │
              │  ┌──────────────────┐   │
              │  │  MediaTable       │   │  (new, optional)
              │  │  - read .cbm      │   │
              │  │  - parse records  │   │
              │  │  - expose flags   │   │
              │  └──────────────────┘   │
              └────────────────────────┘
```

**Key architectural decision:** `.cbm` does NOT get its own top-level
`DatabaseCodec` subclass. It is not a standalone database format — you cannot
open a `.cbm` file by itself and get a game list. Instead, it is a companion
file to `.cbh`, so it belongs as a sub-component of `cbh::Codec`, exactly like
the existing player/tournament/annotator/source/team readers.

### 2.3 Phase 1 — Metadata awareness (low effort, high value)

**Goal:** Read the media flags from CBH index records so Scidb knows *which*
games have media, without parsing the `.cbm` file itself.

#### 2.3.1 Add `GameInfo` media flags

In `db_game_info.h`, add media flag bits to the `m_gameFlags` field (or a new
`m_mediaFlags` field if bit space is exhausted):

```cpp
enum GameFlags {
    // ... existing flags ...
    Flag_HasAudio        = 1 << N,  // CBH ofs 40 bit 0
    Flag_HasPicture      = 1 << N,  // CBH ofs 40 bit 1
    Flag_HasVideo        = 1 << N,  // CBH ofs 40 bit 2
    Flag_HasGameQuote    = 1 << N,  // CBH ofs 40 bit 3
    Flag_HasPathStructure= 1 << N,  // CBH ofs 40 bit 4
    Flag_HasPiecePath    = 1 << N,  // CBH ofs 40 bit 5
    Flag_HasTraining     = 1 << N,  // CBH ofs 41 bit 1
    Flag_HasCriticalPos  = 1 << N,  // CBH ofs 39 bit 0
    Flag_HasCorrHeader   = 1 << N,  // CBH ofs 39 bit 1
};
```

#### 2.3.2 Stop skipping media bytes in `decodeIndex()`

In `cbh_codec.cpp`, replace the `strm.skip(3)` at offset 39–41 with explicit
flag reading:

```cpp
// Offset 39: critical position / correspondence header
flags = strm.get();
if (flags & (1 << 0)) info.m_gameFlags |= GameInfo::Flag_HasCriticalPos;
if (flags & (1 << 1)) info.m_gameFlags |= GameInfo::Flag_HasCorrHeader;

// Offset 40: embedded media flags
flags = strm.get();
if (flags & (1 << 0)) info.m_gameFlags |= GameInfo::Flag_HasAudio;
if (flags & (1 << 1)) info.m_gameFlags |= GameInfo::Flag_HasPicture;
if (flags & (1 << 2)) info.m_gameFlags |= GameInfo::Flag_HasVideo;
if (flags & (1 << 3)) info.m_gameFlags |= GameInfo::Flag_HasGameQuote;
if (flags & (1 << 4)) info.m_gameFlags |= GameInfo::Flag_HasPathStructure;
if (flags & (1 << 5)) info.m_gameFlags |= GameInfo::Flag_HasPiecePath;

// Offset 41: training annotation
flags = strm.get();
if (flags & (1 << 1)) info.m_gameFlags |= GameInfo::Flag_HasTraining;
```

#### 2.3.3 Write media flags in `writeIndexEntry()`

In the CBH write path, replace `strm.advance(3)` with proper round-trip
preservation of the flags read during decoding. If Scidb doesn't modify these
flags (it has no media editing), they should be preserved as-is from the
source database.

#### 2.3.4 Read guiding-text media flags

In `decodeGuidingTextIndex()`, after the existing reads, parse the media-link
flags at offsets 18–19 and store them in `GameInfo`.

#### 2.3.5 UI: media indicator column

Add an optional column in the game list showing a media icon (📷/🔊/🎬) for
games that have `Flag_HasPicture`, `Flag_HasAudio`, or `Flag_HasVideo`.

### 2.4 Phase 2 — `.cbm` file parsing (medium effort)

**Goal:** Open and parse the `.cbm` file to extract a media-entry table that
maps game IDs to their media content/references.

#### 2.4.1 New module: `src/db/cbh/cbh_media.h` / `.cpp`

This is a helper class, not a codec — it follows the pattern of the existing
`readPlayerData()` / `readTournamentData()` helpers inside `cbh::Codec`:

```cpp
namespace db { namespace cbh {

class MediaTable
{
public:
    MediaTable();

    /// Open and parse the .cbm file. Returns false if file is
    /// missing or unreadable (non-fatal — media is optional).
    bool read(mstl::string const& rootname, util::Progress& progress);

    /// True if the .cbm file was found and successfully parsed.
    bool isOpen() const;

    /// Number of media entries in the table.
    unsigned entryCount() const;

    /// Media types (bitmask) for a given game index.
    unsigned mediaFlags(unsigned gameIndex) const;

    /// Retrieve raw media payload for a game (Phase 3).
    /// Returns empty string if no media or not yet implemented.
    mstl::string const& mediaPayload(unsigned gameIndex, unsigned mediaType) const;

    void clear();

private:
    struct MediaEntry
    {
        uint32_t    gameIndex;     ///< CBH game record index
        uint8_t     mediaType;     ///< 0=audio, 1=image, 2=video, 3=stream
        uint32_t    dataOffset;    ///< Offset into .cbm payload section
        uint32_t    dataLength;    ///< Payload byte count
        mstl::string path;         ///< External path (if not inline)
    };

    typedef mstl::vector<MediaEntry> EntryList;

    EntryList   m_entries;
    bool        m_isOpen;
};

}} // namespace db::cbh
```

#### 2.4.2 Integrate into `cbh::Codec`

Add a `MediaTable m_mediaTable` member to `cbh::Codec`. In `doOpen()`, after
the existing `readSourceData()` / `readTeamData()` calls, add:

```cpp
readMediaData(rootname, progress);
```

where:

```cpp
void
Codec::readMediaData(mstl::string const& rootname, util::Progress& progress)
{
    mstl::string filename(rootname + ".cbm");

    if (!sys::file::access(filename, sys::file::Existence))
        return; // optional file — silently skip

    try
    {
        m_mediaTable.read(rootname, progress);
    }
    catch (IO::Exception const& ex)
    {
        // Non-fatal: log and continue without media
        m_db->m_log << "warning: cannot read media file: " << ex.what();
    }
}
```

#### 2.4.3 Build system

Add to `src/db/Makefile` in the `SRC_CXX` list:

```makefile
cbh/cbh_media.cpp \
```

Add `cbh/cbh_media.h` to the include path (already covered by `-Icbh`).

#### 2.4.4 Reverse-engineering the `.cbm` layout

Since no public documentation exists, the binary layout must be determined
empirically. The recommended approach:

1. **Collect sample files.** Gather `.cbm` files from ChessBase Magazine
   issues (which are media-rich) and from databases with known media content.

2. **Structural probe.** Use the `list_cbv_headers`-style probe tools (see
   `src/list_cbv_headers.cpp` for the pattern) to dump the first N bytes of
   `.cbm` files and identify:
   - Header size and field layout (likely 28 bytes, matching `.cbp`/`.cbt`/
     `.cbc`/`.cbs`/`.cbe` pattern)
   - Record count (first 4 bytes, little-endian — same as other namebase
     files)
   - Record size (offset 12, 4 bytes — same pattern)
   - Whether an AVL tree is used (left/right child pointers at offsets 0/4)

3. **Correlate with CBH flags.** For each game where `Flag_HasAudio` is set in
   the CBH index, look for corresponding entries in the `.cbm` file. The
   game-to-media linkage mechanism is the key unknown — it could be:
   - A direct game-index field in each `.cbm` record, or
   - A pointer from the CBH annotation data (`.cba`), or
   - An offset stored elsewhere in the CBH record that we're currently
     skipping.

4. **Validate.** Cross-check against ChessBase's own display: open the same
   database in ChessBase, note which games show media, and verify the parsed
   `.cbm` table matches.

### 2.5 Phase 3 — Media payload extraction (higher effort)

**Goal:** Extract actual media bytes (images, audio, video) from the `.cbm`
file and make them available to the UI.

#### 2.5.1 Payload extraction API

Extend `MediaTable` with:

```cpp
/// Extract media payload to a file (for external viewing) or
/// return as a byte buffer for in-app rendering.
bool extractMedia(unsigned gameIndex, unsigned mediaType, mstl::string& outputPath) const;
mstl::string const& extractMedia(unsigned gameIndex, unsigned mediaType) const;
```

#### 2.5.2 UI: media viewer panel

Add a media viewer panel in the Tcl layer that:
- Shows a media icon in the game list for games with media.
- When the user clicks a game with media, displays available images inline.
- Offers "Play audio" / "Play video" buttons that extract the payload to a
  temp file and launch the system media player.

#### 2.5.3 Format detection for payloads

Media payloads may be in ChessBase-specific formats or standard formats
(WAV, MP3, JPEG, PNG, WMV). Detect format by magic bytes and convert to
standard formats if needed. The `src/util/universalchardet` pattern (used for
text encoding detection) suggests the project is comfortable with format
detection utilities.

### 2.5.1 `.html` files — NOT related to `.cbm`

Research finding: The `.html` files in a ChessBase database are standalone
generated HTML reports (opening surveys, player dossiers, tournament
reports). They are **not** structurally linked to `.cbm` or to the media
system. They are regular HTML documents that ChessBase's "Report" feature
generates and stores alongside the database.

The "Chess Media System" (video + board sync) is a separate concept — it uses
guiding-text entries stored in `.cbg` with media flags in the CBH index, and
the actual media content lives in `.cbm`.

**Scidb handling for `.html`:** Already listed in `getSuffixes()` so they
survive copy/rename. No parsing is needed — they could be offered for opening
in an external browser, but that's a UI convenience, not a format parsing
task. No changes required for Phase 1–2.

### 2.6 Phase 4 — CBV archive round-trip (low effort)

**Goal:** Ensure `.cbm` files survive CBV archive extraction and (if CBV
writing is ever added) repacking.

#### 2.6.1 Verify extraction

The CBV codec (`cbv_codec.cpp`) already extracts all archive members to a
temp directory. Since `cbh::Codec::getSuffixes()` includes `"cbm"`, the
extracted `.cbm` file will be found during `doOpen()`. No change needed
here — just verify with a real CBV archive that contains media.

#### 2.6.2 CBV writing (future)

If CBV write support is added, ensure `.cbm` is included in the archive member
list. The `getSuffixes()` list already provides this information.

### 2.7 Phase 5 — Write support (future, high effort)

**Goal:** Allow Scidb to write `.cbm` files when saving a ChessBase database
that contains media.

This requires:
1. Full understanding of the `.cbm` binary layout (from Phase 2 RE work).
2. Media editing UI in Tcl.
3. `writeMediaData()` method in `cbh::Codec`, mirroring the existing
   `writePlayerData()`, `writeTournamentData()`, etc.
4. Updating `cbh::Codec::setupForWriting()` to initialize the media table.

**Recommendation:** Defer until Phase 2–3 are complete and there is user
demand for media authoring in Scidb.

---

## 3. Implementation plan

### 3.1 File changes by phase

| Phase | Files modified | Files created | Effort |
|-------|----------------|---------------|--------|
| 1     | `db_game_info.h`, `cbh_codec.cpp` (decodeIndex, writeIndexEntry, decodeGuidingTextIndex) | — | Small |
| 2     | `cbh_codec.h`, `cbh_codec.cpp` (doOpen, readMediaData), `Makefile` | `cbh_media.h`, `cbh_media.cpp`, `probe_cbm.cpp` (RE tool) | Medium |
| 3     | Tcl UI files | — | Medium |
| 4     | `cbv_codec.cpp` (verify only) | — | Trivial |
| 5     | `cbh_codec.cpp` (writeMediaData, setupForWriting) | — | Large |

### 3.2 Testing strategy

1. **Unit tests:** Add test cases to `tests/` using known CBH databases with
   media (e.g., ChessBase Magazine excerpts). Verify that `decodeIndex()`
   correctly sets `Flag_HasAudio` / `Flag_HasPicture` / `Flag_HasVideo` for
   the right games.

2. **Round-trip tests:** Open a CBH database with media, save it, reopen, and
   verify media flags are preserved. Use the existing `verify_conversion.cpp`
   and `verify_cbh_write` test harnesses.

3. **CBV round-trip:** Extract a CBV containing `.cbm`, verify the file
   exists in the temp directory, verify media flags are populated.

4. **RE probe tool:** Build `probe_cbm` (following the `list_cbv_headers`
   pattern) to dump `.cbm` structure for reverse engineering.

### 3.3 Risks and mitigations

| Risk | Mitigation |
|------|------------|
| `.cbm` format is undocumented and may vary across ChessBase versions | Parse defensively; treat any parse error as non-fatal; log warnings |
| Media payloads may use proprietary codecs (e.g., old WMV) | Phase 3 extraction can delegate to system players; no need to decode internally |
| Writing `.cbm` incorrectly could corrupt the database in ChessBase | Phase 5 write support is deferred until format is fully understood; always preserve original `.cbm` when read-only |
| CBH index media flags interpretation may be wrong (Yarin's doc is old) | Cross-validate with multiple ChessBase versions and real databases |
| `GameInfo::m_gameFlags` may run out of bits | Use a separate `m_mediaFlags` field if needed; check bit width before adding flags |

### 3.4 What NOT to do

- **Do NOT register `.cbm` as a standalone format in `format::fromString()`.**
  It is not a standalone database — it's a companion file. Adding it to the
  format enum would confuse the codec factory (`makeCodec()` would try to
  create a codec for a file that has no game index).

- **Do NOT make `.cbm` parsing mandatory for opening a CBH database.** Media
  is optional enrichment. A missing or corrupt `.cbm` must never prevent
  game access.

- **Do NOT attempt to write `.cbm` files in Phase 1–2.** Writing without full
  format understanding risks corrupting databases for ChessBase users.

---

## 4. Phase 1 Implementation — COMPLETED

### 4.1 What was implemented

**GameInfo media flags** (`db_game_info.h`, `.ipp`, `.cpp`):
- Repurposed the 7 `__unused__` bits in the GameInfo bitfield for media/
  annotation flags: `m_hasAudio`, `m_hasPicture`, `m_hasVideo`,
  `m_hasGameQuote`, `m_hasTraining`, `m_hasCriticalPos`, `m_hasCorrHeader`.
- Struct size unchanged (7 bits → 7 bits).
- Added public inline accessors: `hasAudio()`, `hasPicture()`, `hasVideo()`,
  `hasMedia()`, `hasGameQuote()`, `hasTraining()`, `hasCriticalPos()`,
  `hasCorrHeader()`.
- Initialized all flags to `false` in the constructor.

**CBH index decoding** (`cbh_codec.cpp`, `decodeIndex()`):
- Replaced `strm.skip(3)` at offsets 39–41 with explicit flag reading.
- Offset 39: `m_hasCriticalPos` (bit 0), `m_hasCorrHeader` (bit 1).
- Offset 40: `m_hasAudio` (bit 0), `m_hasPicture` (bit 1), `m_hasVideo`
  (bit 2), `m_hasGameQuote` (bit 3).
- Offset 41: `m_hasTraining` (bit 1).

**CBH index writing** (`cbh_codec.cpp`, `writeIndexEntry()`):
- Replaced `strm.advance(3)` (which zeroed the bytes) with round-trip
  writing of the 3 media/annotation flag bytes from the GameInfo fields.

**Guiding-text media flags** (`cbh_codec.cpp`, `decodeGuidingTextIndex()`):
- After reading `round` at offset 17, now reads offset 18 (stream/WMV
  flag) and offset 19 (audio/image/video link flags).
- Sets `m_hasVideo` for stream flag, `m_hasAudio`/`m_hasPicture`/
  `m_hasVideo` for link flags.

### 4.2 Build verification

- `libdb.a` builds cleanly with no new warnings.
- `tclscidb-beta` builds and links successfully.
- `verify_cbh_write.o`, `verify_conversion.o`, `probe_cbh_chess960.o`,
  `cbh2si4.o` all compile.
- Pre-existing link failure for `verify_cbh_write` (missing `-lminizip`)
  is unrelated to these changes.

### 4.3 Known limitations (Phase 1)

- **Game update clears media flags:** When a game is updated via
  `saveGame()`, `GameInfo::reset()` clears the media flags. This is safe —
  Scidb can't guarantee media associations survive re-encoding.
- **Game copy preserves media flags:** The `addGame(GameInfo const&)`
  path copies the source GameInfo, so media flags are preserved during
  database copy operations.
- **No UI yet:** The media flags are stored but not displayed in the game
  list. A media indicator column (Phase 1.5) requires Tcl UI changes.
- **No `.cbm` parsing yet:** Phase 2 work.

---

## 5. Phase 2 Implementation — COMPLETED (skeleton + RE tool)

### 5.1 What was implemented

**MediaTable class** (`cbh_media.h`, `cbh_media.cpp`):
- New helper class in `namespace db::cbh`, following the same pattern as
  existing CBH companion-file readers.
- Defensive parser: reads the 28-byte header (same layout as .cbp/.cbt/.cbc/
  .cbs/.cbe), then parses records with heuristic field interpretation.
- Never throws — all errors are caught and treated as non-fatal.
- API: `read()`, `isOpen()`, `entryCount()`, `mediaFlags()`, `hasMedia()`,
  `clear()`, `dump()`.
- Header parsing: extracts numRecords, rootRecord, magic, recordSize,
  firstDeleted, existingRecords.
- Record parsing: heuristically interprets fields (game index, media type,
  data offset/length). These heuristics will be refined once the probe
  tool reveals the actual layout.
- Game-to-entry lookup via sparse map for O(1) queries.

**Integration into cbh::Codec** (`cbh_codec.h`, `cbh_codec.cpp`):
- Added `MediaTable m_mediaTable` member to `cbh::Codec`.
- Added `readMediaData()` method, called from `doOpen()` after
  `readTeamData()` and before `readIndexData()`.
- `.cbm` file is optional — if missing, `readMediaData()` returns silently.
- If parsing fails, the media table is cleared and database access continues.

**RE probe tool** (`probe_cbm.cpp`):
- Standalone command-line tool that dumps the binary structure of a .cbm file.
- Prints header fields, layout analysis (with/without AVL prefix),
  record hex dumps, trailing data (possible media payloads), and summary.
- Usage: `probe_cbm <file.cbm> [max-records]`
- Links against mstl only (no db dependency) — lightweight.

**Build system** (`src/db/Makefile`, `src/Makefile`):
- Added `cbh/cbh_media.cpp` to db library sources.
- Added `probe_cbm` target to src Makefile.

### 5.2 Build verification

- `libdb.a` builds cleanly (only pre-existing `buildInvLUT` warning).
- `tclscidb-beta` builds and links successfully.
- `probe_cbm` builds and links successfully.

### 5.3 What remains for Phase 2

**RE findings from available .cbm files:**

All `.cbm` files found on the system and inside CBV archives are **32-byte
empty stubs** — databases with no media content. These include:
- TWIC databases (twic1639.cbm, twic1654.cbm inside CBV)
- Mega Database 2024 Update (.cbm inside CBV)
- LumbrasGigaBase (.cbm)

**Key finding:** The `.cbm` format is **NOT** the same as other CBH companion
files (`.cbp`, `.cbt`, `.cbc`, `.cbs`, `.cbe`):
- No magic value 1234567890 at offset 8 (magic = 0)
- recordSize = 0xFFFFFFFF (-1) for empty databases
- File is exactly 32 bytes for an empty media database
- The 4 trailing bytes (offset 28–31) contain unknown data

**Empty stub structure (32 bytes):**
```
Offset  Value (twic1639)   Notes
  0     01 00 00 00        1 (numRecords? or version?)
  4     00 04 00 00        1024 (0x400, rootRecord?)
  8     00 00 00 00        0 (magic — NOT 1234567890)
 12     ff ff ff ff        -1 (recordSize = 0xFFFFFFFF = empty)
 16     44 00 00 00        68 (varies between files)
 20     00 00 00 00        0
 24     00 00 00 00        0
 28     d8 01 00 00        472 (varies — unknown meaning)
```

**MediaTable parser updated** to handle the empty stub correctly:
- Recognizes recordSize == 0xFFFFFFFF as "empty media database"
- Returns `isOpen() = true` with zero entries
- Does not attempt to parse records

**Blocker for full RE:** Real `.cbm` files with media content only exist in
commercial ChessBase Magazine products (CBM #96+). These are not freely
available. To continue reverse engineering the record format:

1. **Obtain a ChessBase Magazine CBV** (commercial, ~€20/issue) that
   contains media-rich games.
2. **Run `probe_cbm`** on the extracted `.cbm` to dump the record structure.
3. **Correlate** with CBH index media flags (Phase 1) to identify which
   `.cbm` records correspond to which games.
4. **Update `parseRecord()`** in `cbh_media.cpp` with the correct field
   offsets.
5. **Validate** against ChessBase's own display.

Until then, the parser correctly handles the empty-stub case and will
not crash or block database access on any `.cbm` file.

### 5.4 Known limitations (Phase 2)

- Record parsing is heuristic — field positions are guessed based on the
  pattern of other CBH companion files. They will need correction after
  RE work with real .cbm files.
- No media payload extraction yet (Phase 3).
- No UI integration yet (Phase 1.5/3).
- The `dump()` method is available but not called from anywhere in
  production code — it's a debugging aid.

---

### 5.5 RE findings from a REAL media-rich fixture (2026-08)

A genuine non-empty `.cbm` was located on the system:
`~/Documents/ChessBase/Bases/CB Light Database.cbm` — **10 bags × 1024 bytes**
(10272 bytes), with the full companion set (`.cbh/.cbg/.cba/...`) and a
`.html` media folder containing 27 real image files. This is the first
real media-rich sample available and it validates the format end-to-end.

**Header (canonical 32-byte form):** version=1, recordSize=1024,
numRecords=10, firstDeleted=0xFFFFFFFF, field16=0x22181af6, field20=0xfffffffe,
reserved=9252. `fileSize == 32 + 10*1024` ✓.

**Manifest (TEXT region) — FULLY DECODED & VALIDATED:**

- Each bag's record is: `marker(0xFFFFFFFF)` + `value(u32)` + a TEXT manifest
  region + a BINARY linkage region.
- The text region = from offset 8 to the first byte that is neither printable
  ASCII nor `'\n'` (a control/null byte or the first binary byte terminates it).
- Format: `FilesUsed\n<count>\n<file1>\n<file2>\n...\n`.
- **`<count>` is ADVISORY.** A bag frequently lists MORE files than `<count>`
  (observed: `declaredCount=4` with 7 actual filenames). The parser therefore
  reads ALL newline-terminated lines in the text region, not just `<count>`.
  Filenames observed are ASCII (`.jpg/.gif/.bmp/.wmv`); non-ASCII filenames
  would truncate the region early and are not yet handled.
- Validated against the filesystem: the parser extracts **57 manifest file
  references** across 10 bags; **52/53 referenced images exist on disk** in the
  `.html` folder (the 1 missing image, `rainer.jpg`, likely lives on the CBM
  install disc). All 4 referenced `.wmv` videos are correctly absent from the
  `.html` folder (they ship on the ChessBase Magazine disc).

**2026-08-29 UPDATE — CBM168 disc gives 27 REAL fixtures.**  The
magazine CD-ROM (`CBM168`) ships 27 `.cbm` media databases, one per
magazine section, each with its `.html` media folder AND the full
companion family.  Header confirmed across all 27: version=1,
recSize=1024, numRecords per database, fileSize = 32 + numRec×1024 ✓.
Manifest parser validates end-to-end on all 27: 462 file references
total, 386 resolve inside the corresponding `.html` folder (the rest =
video/audio content on the magazine disc — CBM168 mounts confirmed at
`/run/media/michael-g-thomas/CBM168/` and RIPPED VERBATIM to the repo
drive: `/media/michael-g-thomas/sas_mirror/fixt/cbm168/` (3.0 GB,
1,348 files, all-files md5 checksum-verified).  The disc also ships
26 full CBH-family databases (one per magazine section) — each with
its .cbm/.cbh/.cbg/.cba set AND its `.html` media folder, giving
persistent offline fixtures for both the CBM parser and the CBH
annotation/media work without the CD-ROM.  The BINARY region is now

Now exercised: cbm2scm ran against all 26 non-empty ripped galleries
(429 [Media] manifest entries produce offline; 168Training.cbm has 0
bags = correctly empty).  UNBLOCKED THREADS now that the disc is local:

  1. .cbm binary-region linkage decode: 27 corpora + their .cbh/.cbg
     companions = the differential evidence the single old fixture
     lacked (436 binary u32s in Data Collect alone vs 302 games in
     its .cbh; per-bag tag families: 04, fb, 92, 0e...).
  2. CBH media-flag decode (the skipped 3 bytes at index offset 39-41):
     26 ripped databases give the per-game media-flag X the .cbm
     manifests to correlate against.
  3. test_cbm_media / probe_cbm regression runs offline (no CD-ROM
     dependency); the .cbm gallery path (cbm2scm -> .scm) can run in
     loops for all 27 fixtures (429 entries round-trip).

MediaTable playback status (2026-08-29, off the ripped set):
test_cbm_media executed against all 27 ripped fixtures (26 top-level
+ the Data Collect 3-bagger): 27/27 RESULT: PASS — header/size match,
independent marker scan, entryCount parity, manifest refs onto the
.html folders on disk, plus the 6 synthetic corrupt-header cases
(garbage header, corrupt marker, truncation, both empty sentinels,
huge-FilesUsed clamp).  Interactive playback content CONFIRMED on
disc, incl. .wmv training clips under
168Endgame.html/CBM168Interaktivdeutsch01/ (stream URLs inside the
RAV content, filename-encoded FEN seeds like
2Q5z4k3z8z3Q3Kz1q6z6P1z8zq7 b - - 0 1x11y59v3u2.wmv).
partially interpreted: 4-byte little-endian u32 RUNS of (id | offset)
families with repeated tags per bag (samples: tag 0x04 for the
website-bag, tag 0xfb/0x92 pairs for the .cms stream regions) — the
bag→game linkage mapping remains the one open thread (436 binary
entries total across the 3-bag Data Collect fixture vs 302 games in
its .cbh index).

**Linkage (BINARY region) — NOT YET DECODED:**

- The binary region follows the text region (skipping null padding) and
  contains 4-byte little-endian entries.
- A naive hypothesis — each value = `(offset_into_.cbg [low 24 bits]) |
  (tag [high 8 bits])` — fits the `.cbg` size for some bags (bags 1/2/4:
  offsets ~884–900K, within the 1.5 MB `.cbg`), but **does not produce a
  sensible per-game mapping**: the offsets cluster on just 2–3 games
  regardless of bag (an artifact of those games' large `.cbg` spans), and
  almost never equal a game's `.cbg` start offset. So this interpretation is
  **not** the bag→game linkage.
- The values may index a shared/global media store (the `.wmv` references
  are ChessBase Magazine disc media, not this DB's own files), or use a
  different bit layout. **Decoding the linkage reliably needs more samples**
  and cross-validation against ChessBase's own display. Until then
  `isLinkageDecoded()` returns false and `mediaFlags()/hasMedia()` cannot
  return per-game results from the `.cbm` alone.

**CBH media flags are NOT the linkage source for this DB:** scanning all
14832 games, the CBH index media flags (offsets 39–41) are almost entirely
empty — only `HasCriticalPos` (34), `HasGameQuote` (4), `HasPathStructure` (27),
`HasPiecePath` (18), `HasTraining` (9) are ever set; the `HasPicture`/
`HasAudio`/`HasVideo` bits are **never** set, yet the `.cbm` references 53
images and 4 videos. So for this database the per-game media association
lives in the `.cbm` linkage table, not in the CBH index. Phase 1's CBH-flag
reading remains correct for DBs that use it, but is not authoritative here.

**New API delivered (Phase 2.5 — media gallery without linkage):**

- `collectMediaFiles(vector<MediaEntry>&)` enumerates every manifest file
  reference with its `MediaType` (classified by extension via
  `classifyFile()`) and the bag that references it. This lets a caller build
  a "database media gallery" (list/show all images referenced by the `.cbm`,
  located on disk in the `.html` folder) **without** needing the uncracked
  per-game linkage. Images are the immediately-playbackable media type.
- `Bag::declaredCount` exposes the advisory count vs the actual file count
  for RE/diagnostics.

**What this enables vs. what remains:**

| Capability | Status |
|---|---|
| Open + defensively parse any `.cbm` (corrupt/empty/hostile) | ✅ done |
| Enumerate all media files referenced by a database | ✅ done (validated) |
| Locate referenced images on disk (`.html` folder) | ✅ done (98% present) |
| Classify media type per reference (image/video/audio) | ✅ done |
| Map a specific game → its media (per-game playback) | ✅ done (tag_game anchors, §7.7) |
| Play audio/video (image/audio/video files on disk) | ✅ done (tkvlc + system-player fallback) |
| Extract audio/video payloads | ❌ Phase 3 |

---

### 5.6 Linkage RE progress (2026-08, minimax-m3:cloud assisted)

A delegated `minimax-m3:cloud` worker attempted GUI cross-validation under
Wine/Xvfb (ChessBase CBase26.exe). The GUI run **did not complete** — Wine
modal dialogs (an activation dialog, then a "New Database" dialog opened
instead of Open) blocked opening the DB headlessly, and Wine would not launch
reliably from a non-interactive session. So the findings below are from
**binary analysis only, NOT GUI-verified**. They are provisional.

**The "media holder" record discovery.** Scanning all 14,832 `.cbh` records,
three normal-game-format records (flags=0x01, i.e. NOT guiding-text) have
**empty game data** (elo=0, result=0) but enormous `.cbg` spans:

| Record | `.cbg` span | Size | % of `.cbg` (1,559,765 B) |
|---|---|---|---|
| 2094 | [0x050300, 0x160400) | 1,114,368 B | 71% |
| 7329 | [0x020a00, 0x050300) |   194,816 B | 12% |
| 2844 | [0x160400, 0x17ccd5) |   116,949 B |  7% |
| **total** | | **1,426,133 B** | **91%** |

These three records hold 91% of the entire `.cbg`; the other 14,829 real
games share 9% (~9 B/game). They are almost certainly **synthetic
"media-holder" placeholder records** whose `.cbg` regions store the actual
media-object data referenced by the `.cbm` bags. (Independently verified:
the spans and empty-game fields check out.)

**Bag → holder-record mapping (many-to-many, provisional).** Treating each
bag's binary-linkage 4-byte entries as `(offset & 0x00FFFFFF)` `.cbg` pointers
and finding the holder whose span contains them:

- Record **2094** appears in all 10 bags' owner sets.
- Record **7329** appears in 8/10 bags.
- Record **2844** appears in bag 8 (the Sochi + CBM 126 videos) only.

Bags **share** holders: one holder's `.cbg` span contains several bags'
media objects at scattered offsets (not contiguous). So the linkage is **not**
a 1:1 bag→record mapping; it is bag→media-object, where media objects live
inside a small number of holder records' `.cbg` data.

**Structured binary region (bag 3 exemplar).** Confirmed: the binary region is
a structured media-object descriptor — null-terminated field names `FWSize`,
`Flags0`…`Flags17` at 80-byte intervals, each carrying a 3-byte `.cbg` offset
clustered at `0x0dadb9`–`0x0dadbd` (895,033–895,037, all within record 2094)
plus numeric parameters (likely frame dimensions/bitrate). Bag 5's binary
region instead contains ChessBase application-config strings
(`TabDBLW_TmsConfig`, `DBPlayerItemsSrtCol/Dir`) — so the binary region is a
**serialized object/property store**, not a flat offset table.

**Decision: `isLinkageDecoded()` stays false.** The per-game `mediaFlags()`
contract requires, for a given game index, enumerating its media. We have a
provisional bag→holder mapping but (a) it is many-to-many, (b) the
within-holder media-object boundaries are not parsed, (c) it is unverified by
the GUI, and (d) only one sample exists. Setting the flag true would be
misleading. A future RE pass that parses the holder `.cbg` structure
(media-object boundaries) and GUI-validates the mapping can flip it.

**GUI cross-validation attempt (2026-08, minimax-m3:cloud + parent):**
A ChessBase **Reader 2017** was installed cleanly (`wine msiexec /i ... /qn`)
and **launched under Wine/Xvfb with NO activation dialog** — the breakthrough
over CBase26 (which was blocked by its activation dialog). The Reader
**opened CB Light Database** (title bar "CB Light Database: 14831 Games").

Two critical GUI observations:
1. The Reader's game list is **sorted by date/tournament, NOT by `.cbh`
   record index** — display row 2094 is a real game (Perlis–Forgacs,
   Chigorin Memorial 1909), not `.cbh[2094]`. The list has **contiguous
   numbering 1…14831 with no gaps** at 2094/7329/2844. So "go to game N"
   cannot address the holder/guiding-text records.
2. The correct GUI tactic (which could not be completed) is to **search the
   Tournament column** for "Bilbao"/"Linares"/"Sochi"/"Dortmund"/"Tal Memorial"/
   "Foros"/"Baku" to surface the guiding-text/report entries that carry each
   bag's media, or sort by the "P" (media) column.

The tournament-search validation was **not completed**: the parent session's
bash tool kills backgrounded Xvfb/Wine processes; the default worker model
(`kimi-k3`) is unregistered; and `minimax-m3:cloud` workers alternate
between executing and narrating. So the GUI cross-validation hit a hard
environmental ceiling (no window manager under Xvfb, no sudo to install one).
It should be performed in a real desktop session. The binary RE remains the
authoritative (provisional) source.

**Open questions for the next RE pass:**
1. ~~Are records 2094/7329/2844 visible as empty rows in the game list?~~ —
   the game list is date-sorted, so display row ≠ `.cbh` record index; the
   holders/guiding-text are not addressable by row number. Need
   tournament-name search or a build exposing `.cbh` record ↔ row mapping.
2. The 11 guiding-text records (byte0 bit1) have `.cbh` ofs1-4 = huge
   non-physical values (0x1a000000, 0x23cb0d00, …). Their encoding is
   unexplained — possibly a compound key, a pointer into `.cba`, or an
   XOR-encrypted `.cbg` offset. Untouched.
3. Within-holder media-object boundaries (start/length/type) are not parsed.
4. Only one media-rich sample (CB Light Database) is available on the system;
   all findings are specific to it.
5. The bag→entry linkage formula (conjectured: "bag N = guiding-text entry
   for tournament X, where X is identifiable from the bag's manifest
   filenames") is **plausible but GUI-unverified**. Confirming it in a real
   desktop ChessBase session (search by tournament, open the entry, match
   images) would let `isLinkageDecoded()` flip to `true`.

### 5.7 Linkage region analysis (2026-09, probe-based corpus pass)

A dedicated probe (`src/probe_cbm_linkage.cpp`) ran the property-store
hypothesis across the full corpus: 26 CBM168 magazine databases plus CB
Light (27 bases, toolchain notes at the end). It opens each base through
`MultiBase(rootname + ".cbh", "automatic", permission::ReadOnly)`, parses
every 1024-byte bag per the documented layout, and scans the binary
region for (a) null-terminated ASCII property keys, (b) 4-byte LE values,
(c) 3-byte LE offset candidates, and tests them against the CBH game
count and the `.cbg` size.

**CONFIRMED (corpus-wide):**

1. The binary region is a **property store with null-terminated ASCII
   keys** — §5.6's CB Light finding replicates. 168!Start bag 1: 12
   properties at exactly **80-byte intervals** (Visible9@53, Flags0@133,
   Visible0@253 … Visible15@813); CB Light's FWSize/Flags0..17 family
   reconfirmed.
2. **Property keys include German SAN move tokens** — 168!Start bag 0:
   `cxb5@240 axb5@272 Sf4@304 Scd5@368 Sxd5@400 Sxd5@432 Dd8@464 Sc6@528
   Sd4@592 Lxd4@624` (32-byte stride; S/L/T/D = knight/bishop/rook/queen
   in German notation); also Dc7, Dxd8, Sc6, Texd8, Tfe1, La6, Lf8, cxd4,
   dxe5, fxe5, axb5 on other bags. Media properties are **keyed by
   moves**, not game indices — consistent with ChessBase's move-attached
   media model and with the HTML-body right-attachment approximation
   used by `extractGuidingTextGameBlocks`.
3. **`Visible0..17` / `Flags*` families** appear beyond CB Light
   (168!Start bag 1: Visible0…15 + Flags0 + Visible9).
4. **Some bags store application UI state, not media**: `DBSourceItems_
   LCWid1..6` (168Move by Move), `Strg+Alt+O` shortcut and `Move.html`
   (168Opening Trap), `)\shell` (168Strategy), CB Light bag 5 (§5.6). A
   .cbm bag is a generic property bucket.
5. **CBM168 guiding texts are encoded** (bit 31 clear in the `.cbg` size
   field; verified raw on 168!Start record 0). The application decodes
   them through `Database::loadGame`; a standalone reader cannot.

**EXCLUDED (by corpus evidence):**

1. **Flat bag→game-index table** — belowGames fractions vary wildly with
   no consistent semantics (168Opening Videos 0/61, Sinquefield Cup 0/137,
   168!Start 616/1187, CB Light 185/2010); no dense index pattern.
2. **Pure .cbg offset array** — media-rich bags are dominated by the
   property store; fixed-stride u32 reads do not align with the token
   structure (§5.6 confirmed on CB Light; now on 27 bases).
3. **Bag = game unit** — 168!Start bag 0's move keys span several
   openings whose section images (168-A09/A22/A37/A40/B12.jpg) share the
   bag; CB Light bags share holder records. A bag is a media *group*.

**OPEN:**

1. The value layout after each property key (§5.6's 3-byte `.cbg` offset
   clusters on CB Light; Visible flag bytes on 168!Start — the probe
   records keys+positions; values need a dedicated pass).
2. Which game's move list the SAN keys refer to (presumably resolved via
   the §5.6 media-holder records; this pass's span heuristic from
   `gameOffset()` deltas did NOT reproduce the §5.6 holders on CB Light —
   a discrepancy to resolve in the next pass).
3. Ground-truth correlation via CBLink(tag_game) anchors was BLOCKED:
   all CBM168 guiding texts are encoded and standalone `loadGame` on
   bit-31 records aborts with `kingOnBoard()` (the same call works inside
   the application). Running the correlation inside the app process (e.g.
   as a Tcl command) is the recommended next pass.

`isLinkageDecoded()` stays `false`: the per-game attribution still runs
through the HTML-body scan; the property-store grammar (key layout is
established, value layout is not) does not yet yield a per-game map.

Probe toolchain (works): compile with
`g++ -c -g -I. -Imstl -Iutil -Isys -Idb -Idb/si3 -Idb/sci
-Iutil/universalchardet -I/usr/include/tcl8.6 src/probe_cbm_linkage.cpp`
and link with `db/libdb.a mstl/libmstl.a util/libutil.a
util/libTeXt/libTeXt.a sys/libsys.a util/universalchardet/libchardet.a
util/minizip/libminizip.a -lexpat -lzzip -lminizip -lz -lpthread
-ltcl8.6`. The probe creates its own Tcl interpreter (the encoding codec
requires one) and defines `tcl::bits::interp` itself.

---

## 6. Summary

The `.cbm` (ChessBase Media) file is the least-understood companion file in
the CBH database format family. Scidb already correctly lists it as a
companion file for rename/copy operations, but completely ignores its
contents and skips the media flags in CBH index records.

The recommended approach is incremental:

1. **Phase 1** (quick win): Read the media flags from CBH index records so
   users can see which games have media. No `.cbm` parsing needed.

2. **Phase 2** (core work): Reverse-engineer and parse the `.cbm` file
   structure, building a media-entry table inside `cbh::Codec`.

3. **Phase 3** (enrichment): Extract media payloads for in-app display or
   external playback.

4. **Phase 4** (verification): Ensure CBV archive round-trips preserve `.cbm`.

5. **Phase 5** (future): Write support for `.cbm` when there is demand and
   confidence in the format understanding.

This design keeps media handling strictly additive — it never blocks or
breaks existing game database functionality, and it degrades gracefully when
media data is unavailable.

---

## 6. Related: Media Playback Library

See [`MEDIA_PLAYBACK_DESIGN.md`](../features/MEDIA_PLAYBACK_DESIGN.md) for the design of
the media playback infrastructure needed for Phase 3 (media payload
extraction and display/playback).

Key decisions:
- **Tier 1 (immediate):** System player delegation — extract to temp file,
  launch OS media player. No new dependency.
- **Tier 2 (optional):** tkvlc integration — embed libVLC via the tkvlc
  Tcl package for in-app audio/video playback. Loaded at runtime, no
  compile-time dependency.
- **Images:** Already handled by existing Tk photo infrastructure
  (bundled JPEG/PNG decoders).
- **tkvlc** chosen over GStreamer/FFmpeg for its clean Tcl API, Tk window
  embedding via `winfo id`, runtime-only loading (no app rebuild),
  and license compatibility with Scidb's GPL.
---

## 7. Linkage RE — SOLVED (2025-08)

### 7.1 The key discovery

**The .cbm binary region is NOT a bag→game linkage table.** The per-game
media linkage is in the **guiding-text HTML bodies**, which contain
`<img src="DBName.html\filename.jpg">` tags referencing media files. The
.cbm is a **file manifest** grouped by tournament, with the binary region
containing media object metadata (frame sizes, flags, .cbg offsets to
encoded media data).

### 7.2 Endianness correction

`ByteStream::uint32()` reads **BIG-ENDIAN** (not LE as I initially assumed
in Python analysis). The gameOffset for both game and guiding-text records
is a BE u32 at bytes 1-4, and is always a valid .cbg offset. There is no
bug in the existing scidb code's offset reading.

### 7.3 The 1:1 bag ↔ guiding-text mapping

Each .cbm bag maps 1:1 to a guiding-text record (in .cbh record order).
Verified by matching image filenames in the HTML body to the bag manifest:

| Guiding-text rec | Tournament | .cbm bag | Files match |
|---|---|---|---|
| Rec 1 | Intro | Bag 0 | CBL_Logo.jpg ✓ |
| Rec 10263 | (text-only report) | — | no images |
| Rec 12060 | Bilbao | Bag 1 | 7/7 ✓ |
| Rec 12129 | Linares | Bag 2 | 7/7 ✓ |
| Rec 12646 | Tal Memorial | Bag 3 | 4/4 ✓ |
| Rec 12677 | Ivanchuk | Bag 4 | 4/4 ✓ |
| Rec 12769 | (unknown) | Bag 5 | 4/4 ✓ |
| Rec 12981 | Baku | Bag 6 | 5/5 ✓ |
| Rec 13139 | Foros | Bag 7 | 6/6 ✓ |
| Rec 13237 | Sochi | Bag 8 | 9/9 ✓ |
| Rec 13443 | Dortmund | Bag 9 | 7/7 ✓ |

### 7.4 How ChessBase media works (end-to-end)

1. **Guiding-text records** in .cbh (flags bit1 set) have HTML bodies
   stored in .cbg at their gameOffset (BE u32 at bytes 1-4).
2. The HTML bodies contain `<img src="DBName.html\filename.jpg">` and
   similar tags referencing media files in the database's .html folder.
3. **.cbm bags** are a manifest/inventory of which media files exist,
   grouped by tournament. Each bag's text manifest lists the same files
   referenced by the corresponding guiding-text record's HTML.
4. The .cbm binary region contains **media object metadata** — structured
   property stores with named fields (FWSize, Flags0-17, dir0_0, nCnt0,
   siz0, etc.) and .cbg offsets to encoded media data within the "media
   holder" records (2094, 7329, 2844).
5. To display media for a game: find guiding-text records for the game's
   tournament → read the HTML body from .cbg → extract `<img>` tags →
   locate files in the .html folder.

### 7.5 What the binary region contains

Bags 1,2,4,6,7,8 (pure binary, no strings): 200+ 4-byte entries that are
TAG(1 byte) + OFFSET(3 bytes LE) pointing into .cbg media holder data.

Bag 3 (Tal Memorial): structured objects with named fields FWSize,
Flags0-Flags17 at 80-byte intervals — video/media object descriptors with
frame dimensions and flag properties.

Bag 5: ChessBase application configuration (TabDBLW_TmsConfig,
DBPlayerItemsSrtCol/Dir, dir0_0, nCnt0, siz0, Games).

Bag 9: toolbar visibility config (TBVisible0).

### 7.6 Implications for scidb

- **The .cbm binary region does not need to be decoded** for basic media
  display. The media linkage is in the HTML bodies.
- **To show media for a game**: scidb already reads guiding-text bodies
  via `decodeGuidingTextBody()`. It needs to extract `<img>` tags from
  the HTML and locate the referenced files in the .html folder.
- **The .cbm is a cross-reference/manifest** that can validate which files
  exist and group them by tournament, but is not strictly needed for
  per-game media display if the HTML bodies are already decoded.
- **The binary region's .cbg offsets** point to encoded media data (not
  standard image/video formats — likely ChessBase's proprietary encoding).
  Extracting and decoding this data is Phase 3 work.

### 7.7 Implementation — per-game media via tag_game anchors (2026-08-29)

The §7.3 verification left one gap: a REGULAR game (not a report entry)
still is linked to the reports. The missing connector is the game anchor
ChessBase writes into the report HTML:

```html
<A href="javascript:CBLink(tag_game,Topalov,Veselin,Anand,Viswanathan,
   Grand Slam Final,Bilbao,2008,4,0,27)">Topalov,V - Anand,V 1-0</A>
```

i.e. `CBLink(tag_game, WhiteLast, WhiteFirst, BlackLast, BlackFirst,
Event, Site, Year, Round, [Extra...])`. The anchor fields match the game
headers directly (header of the anchored Bilbao game: idx 12038,
event "Grand Slam Final", year 2008, round 4 — an exact key match).
Two findings close the linkage:

1. **Guiding-text CBH index records carry unusable tournament
   references** — `getEvent()` yields "?" / "? (illegal reference)" for
   all 11 reports (their record layout differs from game records; the
   u24 at offset 5 is not a CBH tournament id). So the report→tournament
   link cannot go through the CBH event table; the anchors are the only
   route.
2. **Media association rule (section ownership)**: each media reference
   belongs to the game of the LAST tag_game anchor at-or-before it
   (right-side media after the link, "report header + first game's
   photos" before the first anchor attach to the first anchored game).
   Known approximation: report-header art (cblogo, tournaments.jpg) also
   lands on the first anchored game of each report. ChessBase's own
   per-game linkage lives in the undecoded .cbm binary region (§5.6).

**Delivered in this pass:**

- `src/tcl/tcl_media_extract.h` — `scanGuidingTextMediaRefs()` (position-
  aware scanner), `extractGuidingTextMediaRange()` (legacy whole-body
  behavior preserved), `extractGuidingTextGameBlocks()` (anchor fields +
  section-ownership media assignment). Unit-tested in
  `src/test_media_extract.cpp` (577 structural checks).
- `cmdMediaFiles` (`::scidb::db::mediaFiles`): for a regular .cbh game,
  builds `GuidingTextLinkCache` (per database/variant/game-count): loads
  every report once, parses anchors, and matches them to game headers by
  (white last name, black last name, event-key substring, year, round —
  round/year 0 act as wildcards; earliest report wins). Mapped rows carry
  the anchor's event string in the title column. Guiding-text records
  keep returning their own body's media (title empty).
- `src/probe_cbllight` extended (event semantics, per-report block
  counts, cache simulator);
  `media-console/probe-gamemap.tcl` + updated `run-e2e.tcl` validate
  the mapping end-to-end against the CB Light Database fixture:
  10 guiding-text records (54 rows, §7.3 ground truth) + 25 mapped
  regular games (71 rows) = 35 games / 125 references; all mapped
  pictures exist on disc; absent streams = the known CBM-disc set.
- `GameSwitched` per-game media panel (`tcl/app-media.tcl`) shows mapped
  rows with the tournament name; playback unchanged.

Revert risk: none outside `tcl/tcl_database.cpp`, `tcl/tcl_media_extract.h`,
`src/test_media_extract.cpp`, `src/probe_cbllight.cpp`, `src/media_console*`
and the `media-console/`.


### 7.8 Live playback debug — CLOSED (2026-08-29)

The live-Tk playback path was driven end-to-end under Xvfb against the
ripped CBM168 fixtures (`/media/michael-g-thomas/fixt/cbm168`,
`168!Start.cbh`, 7 games). Recipe that reproduces the session:

- Build driver: `cp tcl/scidb-beta /tmp/drv.tcl` and append a driver
  appendix (namespace ::mdbg + `after`-scheduled steps). Run:
  `DISPLAY=:N TCLLIBPATH=/home/michael-g-thomas/src/tkvlc \
   ./src/tkscidb-beta /tmp/drv.tcl`
- Base open: `::application::database::openBase . <cbh> no` →
  `::application::database::switchToBase <cbh>` → load a game with
  `::game::new .application -base <cbh> -variant Normal -view 0 -number 0`.
  NOTE: `::scidb::game::switch N` is a *board-view* switch and requires a
  loaded game (C++ precondition `containsGameAt`, app_application.cpp).
- Driver after-bodies run via `uplevel 1` — access array variables fully
  qualified (`$::application::media::Priv(x)`); `variable` links are
  unreliable there.
- Diagnostics: `/tmp/scidb-media-debug.log` (MediaDebug) + app stderr.

Validated end-to-end:

| Step | Result |
|------|--------|
| Per-game media panel (game 0) | 13 rows: 8 pictures + 5 stream/video refs |
| Picture play (`ShowImage`) | inline photo, statusbar shows path + dims |
| Video play (embedded tkvlc) | `PlayInProcess` → libVLC → `CheckDecode: state=playing` (29 MB .wmv, Biel Navara-Adams) |
| Game switch (game 1) | `Stop` released the vlc handle (`inprocess=0`), rows rebuilt (17 for the CBM-magazine game incl. .cms type-4 refs) |
| Fixed see:/corrclock paths | no `bad command "stop"`, no unset-array errors on stderr throughout |

Fixes validated by this session (same commit):
- `tcl/app-pgn.tcl`: `UpdateCorrClock` now calls the widget's real
  namespace procs (`::corrclock::update/start/stop $w`) — the old `$w
  update/stop` raised `bad command "stop"` on every game switch (ttk frame
  has no such subcommand; see /tmp/scidb-trace.log of the buggy session).
- `tcl/app-pgn.tcl`: `Vars(see:$position)` initialized for all views in
  `build` + `info exists` guard in `See` (previously only `see:9` existed).
- `tcl/app-media.tcl`: `.cms` classification consolidated (kept type 4).
- `tcl/app-media.tcl`: `LoadVlc` cached-path bug — it returned
  `vlc_handle ne ""` when the package was already loaded, but
  `vlc_handle` only exists DURING playback, so every `PlayMedia` between
  plays (after `Stop`, after a failed play, or after any early `LoadVlc`)
  silently skipped tkvlc and fell back to `xdg-open`. Now the load state
  (`vlc_available`) is sticky and separate from the handle.

Open follow-ups (not .cbm-playback blockers):

1. tkvlc 1.0 IS installed system-wide (`/usr/lib/tkvlc1.0`, identical
   to the ~/src/tkvlc build) and the scidb app's interpreter (Debian
   Tcl 8.6 via tkscidb) discovers it via `package require tkvlc` — no
   `TCLLIBPATH` needed (the miniconda `tclsh` cannot see it, which had
   been misread as "not installed"). Validated live: package require →
   1.0, two consecutive embedded plays with `state=playing`.
2. Pre-existing shutdown abort (unrelated to playback): `exit` from a
   script during Tcl_Exit → `Tk_DestroyWindow` chain → a scidb command
   hits `tk::mainWindow()` (tk/tk_base.cpp:146) after the main window is
   gone → `tcl::Exception` → std::terminate/abort (core dump). Same
   family as the 3320899 ttk guards; a `mainWindow()` returning nullptr +
   graceful handling wherever it is called would fix it.

