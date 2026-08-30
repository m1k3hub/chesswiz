# ChessBase WMV/WMA Synchronization RE Notes

Status: active reverse engineering, updated 2026-08-30.

This document records observations from the locally available CBM168 media
fixtures. It deliberately distinguishes facts observed from hypotheses that
still require validation against ChessBase/Fritz.

## Confirmed container structure

The sampled `.wmv` files are ASF containers with three streams:

| ASF stream | Type | Observed format |
|---:|---|---|
| 1 | video | WMV3 or VC-1/WVC1 |
| 2 | audio | WMA2 (`wmav2`) |
| 3 | script/data | ASF script-command media type |

The stream-3 type GUID is:

```text
59dacfc0-59e6-11d0-a3ac-00a0c90348f6
```

This is not an arbitrary unknown binary stream. It is an ASF script-command
stream. Microsoft documents script streams as timestamped type/argument pairs
delivered in presentation-time order.

The sampled base file `02 Mar del Plata000.wmv` is 433.852 seconds long. Its
stream 3 contains 149 packets and 389,574 bytes. Packet timestamps run across
the complete media duration. It has 76 packets of exactly 30 bytes and larger
packets ranging from approximately 4.3 KiB to 6.8 KiB.

## ChessBase payload encoding

The stream-3 packet payload is represented as UTF-16LE-shaped characters. The
first three code units are consistently:

```text
G A NUL
```

The remaining printable code units use a custom 64-character alphabet:

```text
'?' = 0, '@' = 1, 'A' = 2, ..., '~' = 63
```

Every four six-bit values decode to three binary bytes. This is similar to
Base64 packing, but the source alphabet is ASCII `0x3f` through `0x7e` and
must be converted by subtracting `0x3f`; it must not be mapped to the normal
Base64 alphabet by adding an ASCII offset.

After this decoding, the payload is structured binary data containing plain
ASCII strings and integers. The first decoded byte is significant; it is not
part of the six-bit transport header.

## Decoded large records

Large packets decode to records beginning with:

```text
02 00 00 00
```

They contain game/header state. A representative
decoded record includes:

```text
Lysyj
Igor
Wan
Yunguo
China
CHN-chT
Mega2015 Update 36
Chessbase
Mihail,Marin
Hangzhou
Heibei
FIDE
```

The observed string convention is a one-byte length followed by a
null-terminated ASCII string. The exact integer-field layout is not yet
fully identified.

## Decoded compact records

### Stream census

The probe was run over all 259 local `.wmv` fixtures. It decoded 6,368
script packets. The observed leading opcodes were:

```text
02  3294 packets  large state/checkpoint records
03  1293 packets  compact state transitions
04   432 packets  additional record family, not yet identified
06   779 packets  additional record family, not yet identified
08     3 packets  additional record family, not yet identified
0e   567 packets  additional record family, not yet identified
```

This is important: `02` and `03` are not the whole ChessBase command
language. The decoder currently preserves and reports the other families but
does not assign semantics to them. A playback implementation that handles
only `02`/`03` would therefore be incomplete, even if it works for the
representative lecture.

Initial examples of the other families are now captured. They are compact
binary records rather than six-bit text payloads after transport decoding:

```text
04 00 00 00 00 02 00 00 20 10 01 00   (12 bytes)
06 00 00 00 00 00 00 00 01 00 0c 00
   00 00 00 05 00 0c 02 27 3c 02 3c 33 (24 bytes)
08 00 00 00 00 00                     (6 bytes)
0e 00 00 00 0e 00                     (6 bytes)
```

The `06` example occurs at 60.642 seconds and the `04` example at 84.142
seconds in the Biel 2015 lesson. The `08` example occurs in an endgame lesson;
the `0e` example occurs at 0.642 seconds in the Biel lesson. Their lengths
and fields differ from the `03` transition, so they must be decoded as
separate record types. Their semantics are still unknown.

The `0e` record is a periodic source-time counter, not a state selector. Its
little-endian `u16` value advances by one about every six seconds. In the Biel
round-6 stream it runs from 14 at 0.642 seconds to 99 at 511.681 seconds:
85 increments over 511.039 seconds, or 6.012 seconds per increment. Nine
distinct lecture files produce ratios between 6.012 and 6.028 seconds per
increment. Initial values vary by file (including 0, 2, 10, 11, 14, and 1582),
so the value is not simply elapsed time within the current WMV; it is consistent
with a counter inherited from the source recording or edit timeline. It is
independent of the large-record state id and must not be treated as a direct
state lookup.

The Biel lesson also shows that the `06` and `04` records are sparse relative
to the `0e` sequence. `06` appears at 60.642, 170.642, and 343.142 seconds
with payloads containing repeated structural fields (`...01 00 0c 00...` or
`...02 00 07 00...`) followed by short value pairs. `04` appears at 84.142,
265.142, 279.142, 467.681, and 468.681 seconds. The latter two records are
adjacent, showing that `04` is not merely a periodic checkpoint. These are
strong candidates for board/annotation actions, but the current evidence is
not sufficient to name individual fields or map them to squares.

Large records in this same lesson are cumulative snapshots: their decoded
length grows from 1311 bytes to 1509 bytes as the lesson progresses. Some
snapshots differ only at offset 8, while others append or modify sizeable
regions beginning around offsets 334, 378, 421, 635, 715, 1101, and 1217.
This pattern is consistent with a serialized lesson state accumulating
annotations or board objects, not with a fixed-size move tuple. The value at
offset 8 should consequently be treated as a snapshot selector, while the
rest of the record must be parsed before deriving board state.

Some fixtures also include a same-basename `.txt` export. It contains
timestamped `GA:` commands such as `0:00:01.5: GA:B_...` followed by the
encoded state payload. This is a useful oracle for packet framing and timing:
the text export preserves the original command timestamps, while the ASF
stream carries the same information as script packets. It is not a separate
game notation file.

Across 234 text exports, six command prefixes occur immediately after `GA:`:

```text
?_  5731
?o  4455
@_  2166
B_  1210
@?   742
A?     4
```

This is a better candidate for the command dispatch table than the decoded
leading integer alone. The prefix is part of the outer text/export encoding;
the binary opcode is produced only after decoding the command payload. The
counts also explain why a decoder built from one `.wmv` will miss substantial
parts of the format.

### Verified prefix-to-opcode dispatch

The outer encoding is the same six-bit packing used by the ASF probe, but the
text export omits the UTF-16LE-shaped `GA` wrapper. Decoding the characters
after `GA:` immediately produces the binary record header. Verified samples
establish this dispatch table:

```text
?_  -> 02 00 00 00   large state/checkpoint record
?o  -> 03 00 00 00   compact transition record
@?  -> 04 00 00 00   12-byte action record
@_  -> 06 00 00 00   variable-length action record
A?  -> 08 00 00 00   6-byte record
B_  -> 0e 00 00 00   6-byte source-time counter record
```

This is now verified rather than inferred from frequency: for example,
`GA:B_????w????` decodes to `0e0000000e00`, `GA:?o????C????` decodes to
`030000000100`, and `GA:@?.......` samples decode with opcode `04`.
The remaining work is the field grammar and semantics of each binary record,
not the outer transport or opcode dispatch.

### Opcode `06` container grammar

The `06` family is not a single fixed-size record. After its eight-byte
header, single-field records contain a subrecord with this verified shape:

```text
u16 tag
u16 length
byte payload[length]
```

For example, a 24-byte record contains tag `1`, length `12`, and a 12-byte
payload. Longer records appear to contain several related subrecords, but
applying the same four-byte framing naively after every field misaligns some
samples. Some payloads include
plain UTF-8 text, including lesson annotations such as `Quiet move no. 1!`,
`Stilller Zug Nr 3!`, and explanatory English sentences. Other payloads end in
short numeric pairs such as `02 1e 36`, consistent with board/object
references. The first-level container boundary is understood, but the
multi-field framing variant and tag-specific payload semantics remain to be
mapped.

A decoded text-bearing sample starts with `tag=3, length=0x61`; its payload
contains the annotation text `would transpose to a Shirov-Bacrot 2014 game.
It's a mistake to allow the knight into c7.` This confirms that at least tag
`3` represents a textual lesson annotation. The payload also has a short
binary preamble and a terminator before subsequent records, so the length is
not simply the length of the visible UTF-8 string.

Corpus scanning finds several annotation classes inside `06`, including
interactive-moment labels (`7th Interactive Moment`, `16th Interactive
Moment`), instructional labels (`*Quiet move no. 1!`), speaker names
(`Dave Smerdon!`), explanatory prose, and embedded game references such as
`(70) Carlsen,M ... Nakamura,H ... Zuerich 2014`. This confirms that `06`
is a general lesson-object container, not just a move-delta stream.

The proposed multi-record interpretation was tested against the corpus. The
first `u16` after the eight-byte `06` header is `1` in the 24-byte sample and
`2` in several longer samples, so it is a credible record-count candidate.
However, the remaining bytes do not fit a simple directory of `(offset,
length)` pairs followed by a raw block: the candidate lengths leave
inconsistent residual bytes and no stable alignment. The count hypothesis is
therefore retained as a lead, while the directory grammar remains unverified.

The relationship between `06` and `02` is now confirmed even though the inner
grammar is not. Across 10 script-bearing WMVs, the final `06` delta before each
following `02` checkpoint occurs byte-for-byte inside that checkpoint in all
83 observed groups. In total, 89 of 109 individual deltas occur literally;
the remaining 20 are earlier members of multi-delta groups whose final form is
what the checkpoint retains. Thus `06` is an incremental lesson-state update
and `02` is its cumulative/checkpoint representation. They are two views of
the same state, not independent command families. A decoder can process `06`
for low-latency updates and use `02` to initialize after seeking or to verify
and repair accumulated state.

### Game-tree cursor IDs

In the Navara-Adams fixture, ordinary opcode `03` transition IDs and the state
ID at offset 8 of opcode `02` track the game's main-line ply number. This is
confirmed against the published 74-ply score: the stream reaches IDs through
74 while the lecturer navigates the game. IDs with bit `0x80` set occur while
annotated side variations are shown; their low seven bits repeatedly match the
nearby branch anchor (for example `0x98`/`0x99` around plies 24/25). Treating
the high bit as a variation-mode flag is a strong working hypothesis, but it
still needs validation on games or trees exceeding 127 plies.

### Binary oracle strings

The ChessBase 26 executable contains media-related identifiers including
`ScriptItems`, `ScriptActivationManager::IsStreamCrypted`, `Extra Chess
Media`, `Chess Media System`, and `Audio Stream`. These confirm that script
items are handled by a dedicated activation/stream layer, but the executable
does not expose the private record grammar through symbols or documentation.
They provide useful search anchors for later disassembly, not proof of field
semantics.

The raw PE RTTI cluster around the callback names also contains
`IWMStatusCallback`, `IWMReaderCallback`, and `IWMReaderCallbackAdvanced`
descriptors. This confirms ChessBase links the legacy Windows Media reader
callback family as a group. The names are adjacent metadata, not direct call
sites; locating the implementing vtable remains necessary before assigning a
callback method to script-packet decoding.

The ChessBase 26 binary imports Media Foundation's
`MFCreateSourceReaderFromURL` from `MFReadWrite.dll` and contains RTTI for
`IWMReaderCallback`/`IWMReaderCallbackAdvanced`. This indicates the modern
reader has both a Media Foundation path and legacy Windows Media callback
support. A faithful Scidb implementation should therefore not assume that
the old WMP callback API is the only way ChessBase consumes script streams.

Corpus-wide decoding of all 234 text exports provides a stronger length
profile: opcode `03` is always 6 bytes (4,455 records), opcode `04` is
always 12 bytes (742), opcode `08` is always 6 bytes (4), and opcode `0e` is
always 6 bytes (1,210). Opcode `06` is variable but its observed lengths are
mostly 18, 21, 24, 30, 33, 36, 39, 42, 45, 48, 54, and larger; these are
consistent with records built from three-byte-packed substructures. Opcode
`02` is variable-length and ranges from short records to several kilobytes.
This rules out a generic directory format for every opcode: `03/04/08/0e`
are fixed command structures, while only `06` and `02` need variable-length
parsers.

Opcode `04` has this stable 12-byte layout:

```text
u32 opcode       = 4
u32 action_class
u8  first_square
u8  second_square
u16 modifier
```

All 742 exported records have both square bytes in `0..63`; together they
cover that full range. Interpreting `0` as `a1`, increasing by file and then
rank, yields plausible pairs such as `e8-f8`, `g6-f6`, and `b4-e7`. The six
little-endian action classes are `0x80` (498 records), `0` (204), `0x200`
(33), `1` (4), `0x800` (2), and `2` (1). The observed modifiers are `0`
(468), `0x80` (230), `0x240` (24), `0x20` (12), `2` (4), `1` (3), and
`0x10` (1). This proves the field boundaries and board-square arguments.
Whether each class draws an arrow, highlights a square, or performs another
board action still requires an oracle observation.

Opcode `08` occurs only four times in all 234 exports and is always the same
six-byte value, `08 00 00 00 00 00`. Every occurrence lies at a board-context
boundary: it follows an `04`, `06`, or `03` event and is followed by a new
checkpoint or a new cluster of `04` board actions. One occurrence clears the
context after a rare class-`0x800` action on `h1-g1`, immediately before two
new class-`0x80` actions. With no varying argument and this placement, `08` is
very likely a reset/clear-transient-board-state command. The affected layer
(graphical arrows/highlights, selection, or a broader interaction state) still
needs visual oracle confirmation.

The 30-byte stream packets decode to six-byte records with this recurring
shape:

```text
03 00 00 00 XX XX
```

Examples include:

```text
03 00 00 00 17 00
03 00 00 00 18 00
03 00 00 00 d6 00
03 00 00 00 d7 00
03 00 00 00 d8 00
```

These records are timestamped independently by ASF. Their value is a
little-endian 16-bit field. In the observed lecture, compact values precede
large records carrying the same state value at offset 8. For example, the
stream contains compact `d6`, compact `d7`, then a large record with state
value `d7`; later it contains compact `d8`, followed by large records with
state value `d8`. The same pattern occurs for the `18`, `19`, `1a`, `1b`, and
subsequent values.

This establishes a state-transition/checkpoint relationship. It is stronger
than the earlier hypothesis that these were arbitrary event IDs, although the
contents of each state and the exact meaning of the transition opcode `03`
remain to be decoded.

## Role of `.cms`

The `.cms` files are separate indexes associated with a media directory. They
contain a base media name and FEN-like position records whose names include
values such as:

```text
x0y0v4u0
x24y25v3u2
x26y43v3u2
x34y43v2u5
```

The sibling directory contains a base video (usually `*000.wmv`) and
position-specific WMV clips. The evidence supports this division:

```text
.cms  -> selects/locates lesson branches and position clips
.wmv  -> carries audio, video, and timestamped ChessBase script commands
```

The `.cbm` file is a media catalog/manifest and is not itself the authoritative
playback timeline.

## Reader14 dynamic playback path

Opening a fixture WMV directly with ChessBase Reader 14 under Wine produced
two decisive runtime events:

1. Reader14 instantiated the Windows Media Player ActiveX control,
   CLSID `{6BF52A52-394A-11D3-B153-00C04F79FAA6}`.
2. During control initialization, Wine's `wmvcore` implementation logged
   `WMReaderAdvanced_SetManualStreamSelection(..., TRUE)`.

The first event directly establishes that Reader14 uses the Windows Media
Player control for this playback path. The second establishes that the
resulting Wine playback stack requests manual Windows Media stream selection,
which is the mechanism needed to select non-audio/video ASF streams. The trace
does not identify whether Reader14 or Wine's WMP-control implementation made
that call, nor did it show a subsequent script-sample callback. Therefore
explicit selection of stream 3 and delivery of its commands to ChessBase remain
to be demonstrated. Wine reports the manual-selection call as an unimplemented
(`fixme`) operation, making it a concrete compatibility suspect.

A dedicated `+wmvcore` trace separates two reader passes and exposes an even
earlier failure:

1. Reader14 calls `WMCreateReader`, opens the fixture, queries
   `IWMProfile`, obtains the profile stream count, and requests stream index 0.
2. It obtains that stream's number and queries its media-properties interface.
3. Wine logs `stream_props_GetType(..., major_type, stub!)`; Reader14 then
   immediately closes and releases that reader without examining stream index
   1 or 2.
4. A second reader pass (the WMP control) queries duration, enables a
   user-provided clock, requests manual stream selection, and closes.

Thus the first demonstrated compatibility blocker is Wine's stubbed
`IWMMediaProps::GetType`, not merely manual selection. Reader14 appears to
enumerate stream types itself, but cannot get past the first stream under this
Wine implementation. The underlying GStreamer trace likewise creates only
audio and video pads; it creates no pad for ASF script stream 3. These are two
independent reasons the Windows playback stack cannot currently deliver the
ChessBase command stream under Wine. This behavior is a Wine limitation, not
evidence that the WMV lacks synchronization data—the static extractor reads
that data directly from the same fixture.

### `.cbm` catalog structure

The beginning of `168Endgame.cbm` is a compact little-endian binary header,
followed by readable sections. The first section is introduced by the ASCII
marker `FilesUsed`, a decimal count, and newline-delimited filenames. The list
includes images, `.cms` indexes, and the corresponding language-specific WMV
files, for example `CBM168Interaktivenglisch01.cms` and
`CBM 168 Mueller - Endgame1.wmv`. This establishes `.cbm` as the authoritative
file inventory/manifest for a media package, while the WMV script stream
remains authoritative for synchronized playback events.

## Implications for Scidb

The current linear mapping of video time to game ply in
`tcl/app-media-sync.tcl` is not ChessBase-compatible. Authentic playback must
consume stream 3 and apply its commands at ASF presentation timestamps.

`tkvlc` currently renders the audio/video portion but does not expose the ASF
script-command stream to Tcl. A faithful implementation therefore needs one of:

1. a native ASF/WMF stream reader that exposes stream 3;
2. an FFmpeg/libavformat bridge that forwards stream-3 packets to Tcl; or
3. a standalone pre-parser that builds a timestamped Scidb synchronization
   sidecar before playback.

No one of these implementation paths has been selected yet.

## Next RE tasks

1. Recover the exact six-bit decoder and packet framing as a reusable probe.
2. Parse all large records and identify their integer/string field boundaries.
3. Diff consecutive records at adjacent timestamps.
4. Correlate compact records with the `.cms` FEN sequence and known game moves.
5. Validate the decoded event sequence against ChessBase/Fritz playback.
6. Only then replace the current approximation in Scidb.

## Evidence and references

Local evidence comes from the CBM168 fixtures under
`/media/michael-g-thomas/sas_mirror/fixt/cbm168/`, inspected with `ffprobe` and
byte-level decoding.

Public documentation confirms that ChessBase embeds board actions and
annotations in the multimedia stream and synchronizes them during playback:

- https://help.chessbase.com/CBase/16/Eng/chess_media_system.htm
- https://help.chessbase.com/Fritz/19/Eng/chess_media_system.htm

The published score used to correlate the Navara-Adams cursor IDs is at:

- https://en.chessbase.com/post/biel-06-three-at-the-top

Microsoft's ASF documentation confirms the script-stream model:

- https://learn.microsoft.com/en-us/windows/win32/wmformat/to-use-a-script-stream
- https://learn.microsoft.com/en-us/windows/win32/medfound/mf-pd-asf-script-attribute
