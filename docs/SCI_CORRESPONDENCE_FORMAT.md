# SCI correspondence-duration format (v4, joint final draft)

Status: draft under joint review by Claude (reviewer) and Codex (original
author). This revision supersedes the original memo and incorporates Codex's
v2 review findings. It is intended to be an implementable specification, not
just a design note.

## 1. Problem

`%cclk` (correspondence clock) and `%cemt` (correspondence elapsed) move-info
annotations are parsed from PGN (`MoveInfo::parseCorrespondenceClock` /
`parseCorrespondenceElapsed`, `db_move_info.cpp:312/361`) but cannot be
serialized to SCI files:

- The three-bit move-info type namespace in the current `Mark` record encoding
  is exhausted (`MoveInfo::type()` extracts 3 bits; record lengths come from a
  fixed type switch, not a length prefix — `db_move_info.cpp:80`).
- The encoder's correspondence cases are a **no-op** behind a stale
  "6-byte encoding" comment (`db_move_info.cpp:815-823`).

### 1.1 Existing bug (independent of this proposal — file separately)

`Consumer::sendMoveInfo()` (`sci_consumer.cpp:329`) and
`Encoder::encodeNote()` (`sci_encoder.cpp:497`) emit the `token::Mark` stream
token **unconditionally**, then call `MoveInfo::encode()` which emits nothing
for correspondence types. Writing a game containing `%cclk`/`%cemt` to SCI
today can therefore emit a `Mark` token with no corresponding data record,
corrupting the stream. This must be fixed regardless of v96 (see §7).

## 2. Version lineage

- The current unversioned codec **is version 95**: `FileVersion = 95`
  (`sci_codec.cpp:339`); `readIndexHeader()` accepts 94 (24-bit game count) and
  95 (32-bit game count). The `v91`/`v92`/`v93` directories are historical
  codecs only.
- Versions 94 and 95 are therefore **not free**; they are the current format.
- **96 is the next version number** and is allocated by this proposal.

## 3. Compatibility policy

Shipped readers cannot skip unknown extensions: `Mark` dispatches on the
payload's high bit and record lengths are resolved by a fixed type switch, so
there is no length prefix for a legacy reader to skip. Consequently:

- **Readers that do not understand v96 must reject the file version.** This is
  unavoidable, not a design choice. Partial tolerance cannot be retrofitted
  into already-shipped readers.
- **Writing v96 is the default for newly created databases; existing
  databases are never silently changed.** Two write modes exist:
  - **v96 (default for new databases):** correspondence durations are
    stored as native binary records per §5.
  - **Legacy v95 (opt-in at creation, or via conversion):** `%cclk`/`%cemt`
    are preserved as PGN-style comments in the SCI comment stream.
- A database's storage version is fixed once games exist; conversion
  between versions goes through export/import or the copy-based converter
  (§8).

## 4. Wire format (v96)

### 4.1 Extended move-info envelope

The 3-bit type namespace is exhausted (`MoveInfo::Type` values 1–8 map to
`0x80 | (type-1)<<4`; `CorrespondenceClock`/`CorrespondenceElapsed` are 9/10
and unrepre­sentable — `db_move_info.h:40-56`). Every data-stream byte
`0x80..0xFF` already dispatches as a legacy move-info type (`isMoveInfo()`
tests bit 7 only, `db_move_info.ipp:174`), and move-stream bytes ≥
`token::Special_Move` are moves (`sci_decoder.cpp:399`). **No free tag value
or free move-stream token exists.** The v96 escape therefore reuses the
existing `Mark` dispatch point (`sci_decoder.cpp:464`) with a reserved
first-byte sentinel:

```
extended move-info record (data stream, after a token::Mark token):
  byte 0:  0x00                     // escape sentinel
  byte 1:  info-type (8 bits, full byte)
  byte 2:  payload-length (8 bits)
  bytes 3..: payload
```

- **Escape validity and the zero byte:** byte `0x00` is reserved as the
  extended-record sentinel. Legacy semantics of `0x00` are **not** unused:
  it is a valid empty mark (`mark::None == 0`, `db_common.h:1055`;
  `Mark::decode`/`skip` accept it, `db_mark.cpp:542/589/613`), and the
  exclusion of empty marks in `Mark::encode()` is an `M_REQUIRE` that can
  compile away. Therefore:
  - v94/v95 semantics are unchanged: `Mark` + `0x00` remains an empty mark.
  - In v96, `Mark` + `0x00` is the extended envelope. This is unambiguous
    because only v96 writers produce v96 files, and v96 writers MUST exclude
    empty marks **at runtime** (not solely via `M_REQUIRE`), including
    suppression of the corresponding `token::Mark` token itself.
  - Code paths that copy or transcode records between databases (including
    legacy → v96 conversion) MUST validate the sentinel invariant: a
    zero-first-byte legacy `Mark` record encountered in a v96 context is
    either transcoded to the v96 rules or rejected — never copied raw.
- The full-byte `info-type` retires the 3-bit namespace for new types;
  legacy types keep their existing encoding and MUST NOT be re-emitted in the
  extended envelope.
- `payload-length` makes the record skippable **for v96 readers**; it is not
  retro-compatible with pre-96 readers (see §3).
- A v96 reader encountering an unknown `info-type` MUST skip the record using
  `payload-length` (forward compatibility within v96+).
- **Truncation/corruption (cursor-relative):** after the `Mark` token the
  cursor must hold at least 1 byte. If that byte is `0x00`, the cursor must
  hold at least 2 further bytes (info-type, payload-length); after reading
  payload-length, at least exactly `payload-length` bytes must remain — fewer
  is **corruption: reject the file**. No heuristic recovery.
- **Known-type length check:** for info-types 0x01 and 0x02 (§4.2) the
  payload-length MUST be exactly 5. Any other length for a known type is
  corruption: reject.

### 4.2 Correspondence-duration payload (info-type 0x01)

Value body, 5 bytes, big-endian / network order:

```
  bytes 0-1:  unsigned 16-bit days
  byte 2:     unsigned hours   (0..255)
  byte 3:     unsigned minutes (0..255)
  byte 4:     unsigned seconds (0..255)
```

- Stored component bounds match the existing *stored* representation: days
  ≤ 65535, all other components ≤ 255 (`parseCorrespondenceClock`,
  `db_move_info.cpp:312`). **No normalization** (e.g. 90 minutes stays 1h30m
  only if the source said so); round-trip fidelity beats canonical form.
- **Two info-types: 0x01 = correspondence clock, 0x02 = correspondence
  elapsed**, each with the 5-byte body above.
- **Binary bounds:** textual overflow is clamped at PGN import (existing
  behavior, `db_move_info.cpp:330/333/345/348`), so in-memory values are
  always within the stored bounds and every possible 5-byte body is a valid
  encoding; no runtime bounds check is needed on the binary path.
- All five bytes are unsigned; the only possible failure on the binary path
  is the length check (§4.1).

### 4.3 Stream placement

Two placements, both defined:

1. **Per-node move-info** (all placements, mainline included): the extended
   record appears in the data stream in the same position/order as a legacy
   `Mark` record; the move stream carries the ordinary `token::Mark` token
   exactly as today. The move-stream token encoding is unchanged in v96.
2. **Mainline time-table values:** **deferred.** v96 does NOT add
correspondence columns to the time table. All correspondence durations are
stored as per-node extended records per §4.1, including on the mainline.
This keeps the table format (column identification, entry encoding, missing
entries, skip/strip via `MoveInfo::length`, `sci_decoder.cpp:1324`) untouched
in v96; a table representation may be proposed in a later version if size
demands it. The time-table code changes required for v96 are therefore
limited to §5 enforcement (not accepting correspondence types).

`TimeTableSection` (flag `1 << 12`) asserts the section exists. It does NOT
imply the presence of correspondence annotations.

**Terminology:** throughout this document, "correspondence types" means
exactly `CorrespondenceClock` and `CorrespondenceElapsed`. It does NOT
include `CorrespondenceChessSent`, which already has a working legacy binary
encoding (`db_move_info.cpp:752`) and is unaffected by this proposal.

## 5. Interim behavior (until v96 ships)

One shared version-aware eligibility policy — a single predicate consulted
at every emission point — governs, for each move-info value, whether it is
emitted as a token, a table column, or demoted to a comment. The policy is
implemented once and enforced at these points:

- `Consumer::sendMoveInfo()` (`sci_consumer.cpp:333`) and
  `Encoder::encodeNote()` (`sci_encoder.cpp:503`) MUST NOT emit a `Mark`
  token for any type the encoder will not encode. This fixes the §1.1 bug
  for all unencodable types, not just correspondence.
- `Consumer::preparseComment()` correspondence-derived table insertions AND
  their subsequent clearing (`sci_consumer.cpp:377`) MUST follow the same
  policy: rejected entries become comments before removal, and affected
  counts/flags are recomputed.
- Existing tables handed to `Encoder::encodeTimeTableSection()`
  (`sci_encoder.cpp:682`) MUST be filtered by the same policy before the
  table section and its token-suppression decisions (`sci_encoder.cpp:503`)
  are finalized.
- `MoveInfoSet` PGN extraction (`db_move_info_set.cpp:342`) MUST preserve
  unsupported directives rather than drop them.
- The Tcl `moveinfo` command (`tcl_game.cpp:3640`) MUST preserve
  `%cclk`/`%cemt` as comments in interim mode and verify full parser
  consumption before accepting values.
- Time-table population MUST NOT accept correspondence types until the v96
  column allocation exists.
- Do **not** "fix" this by changing the general-purpose
  `MoveInfoSet::count()`; verification goes through both entry paths
  (consumer and encoder) and both SCI writers.

## 6. Test plan

1. **Round-trip:** `%cclk`, `%cemt`, both together, omitted zero components,
   days = 65535, components at 255, values beyond legacy centisecond range.
   Mainline and variation placements, including the coexistence of
   correspondence records with ordinary move-info, comments, and
   nonempty marks in the same game.
2. **Corruption:** truncation at every byte boundary of the extended record
   (sentinel, info-type, length, payload), wrong payload-length for known
   types (4 and 6-byte variants must reject), `0x00` sentinel, unknown
   info-type (must skip), malformed table counts.
3. **Skip/strip:** selective strip and skip/recovery with following moves,
   ordinary move-info, comments, and variations; assert stream alignment and
   retained content.
4. **Interim mode:** PGN import with `%cclk`/`%cemt` → Tcl insertion → SCI
   save (v95) → reopen → PGN export; assert annotation preservation, zero
   correspondence binary records, correct table counts and flags.
5. **Compatibility:** legacy-mode output opens in a v95 reader unchanged;
   a v95 reader rejects a v96 file with a clear version error (fixture-based).

## 8. Notes for older readers (pre-v96)

This section records what pre-v96 readers do — and cannot do — with the
formats described here, for maintainers of legacy SCI tooling:

- **Version rejection is mandatory and total.** A pre-96 reader cannot skip
  an unknown extended record: every data-stream byte `0x80..0xFF` already
  dispatches as a legacy move-info type (`isMoveInfo()` tests bit 7 only),
  record lengths come from a fixed type switch with no length prefix, and
  move-stream bytes ≥ `token::Special_Move` are moves. There is no free tag,
  no free token, and no skippable framing to exploit. A v96 file passed to a
  v95 reader must be rejected at `checkFileVersion()` — attempting to read
  past the rejection point risks misinterpreting a `0x00` envelope sentinel
  as an empty mark and desynchronizing the stream.
- **The `0x00` sentinel is the sharpest edge.** In v95, `Mark` + `0x00` is a
  valid empty mark. Legacy readers/writers that copy raw `Mark` records
  between databases can silently transmute v96 envelopes into empty marks or
  vice versa. Legacy tools SHOULD refuse to copy records out of v96 files
  entirely rather than attempt partial interpretation.
- **Interim files are safe.** Databases saved in legacy mode (§3) remain
  version 95; correspondence annotations live in the comment stream and are
  invisible to the binary move-info paths. Old readers see ordinary comments
  and need no changes. They will simply not display the durations as
  structured move-info.
- **Mixed-version fleets.** Deployments mixing v95 and v96 tooling must
  treat v96 as write-once-read-never for old tools. There is no downgrade
  path in place; converting v96 → v95 requires a new-version converter that
  demotes correspondence records back to comments (per §3 legacy mode),
  re-running the §5 eligibility predicate at the target version.

## 9. Change list

1. Fix the §1.1 Mark-without-payload bug as an independent change (v95-safe).
2. Implement interim enforcement (§5) + tests 4.
3. Implement v96: envelope (§4.1), payload (§4.2), per-node placement
   (§4.3), FileVersion bump, reader rejection path, runtime empty-mark
   exclusion, migration/transcoding validation.
4. Tests 1, 2, 3, 5.

Open item (deferred by design, not a prerequisite): a correspondence
time-table representation (column identification, entry encoding,
missing-entry handling) may be proposed in a future version; v96 uses
per-node records only.

Follow-ups required when the v96 opt-in path is first exercised (v96 is
currently dormant — no in-repo caller of `Codec::setSciVersion`):

- Raw same-format copy: `Database::exportGame` → `DatabaseCodec::addGame`
  copies record bytes verbatim with no storage-version/sentinel-invariant
  check; gate or transcode when v96 files exist (spec §4.1, §8).
- `Codec::setSciVersion` rebuilds the cached game magic but not an
  already-constructed BlockFile's copy; rebuild at creation time before
  BlockFile construction, or verify block-0 coherence at open.
- Codec-level strip/consumer integration tests (§6.3/§6.5) once a v96
  creation path exists.
