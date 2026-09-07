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
delivered in presentation-time order.  Note: `CBase26.exe` contains
`ScriptActivationManager::IsStreamCrypted/GetProductId/GetCryptKey` — script
streams **can be encrypted per product**; the CBM 168 fixtures decode
cleanly and are therefore unencrypted.

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

Every four six-bit values decode to three binary bytes. A final group of two
or three values carries residual data bits followed by zero-valued transport
padding; a one-value tail is invalid. Because `?` represents zero and there is
no `=` marker, logical record framing—not the tail alone—determines how many
residual bytes are real. The decoder must unpack the residual bits and then
trim only zero bytes beyond the opcode's declared logical length. This is
similar to Base64 packing, but the source alphabet is ASCII `0x3f` through
`0x7e` and must be converted by subtracting `0x3f`; it must not be mapped to
the normal Base64 alphabet by adding an ASCII offset. Across 14,308 exported
commands, 8,090 use a three-character tail, 2,522 use a two-character tail,
and only 3,696 end on a complete four-character group.

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

The leading checkpoint schema is:

```text
u32le opcode       = 2
u32le reserved
u32le cursor_id
u32le reserved
string white_last
string white_first
string black_last
string black_first
string site
string event
u32le packed_date
```

Each string is a one-byte length followed by Windows-1252 bytes ending in NUL;
the length includes that NUL. Exactly these six identity strings parse at
offset 16 in all 5,731 exported checkpoints with no exceptions. `packed_date`
uses `(year << 9) | (month << 5) | day`; zero month/day components represent
unknown precision. The first Navara-Adams date is `2015-00-00`; a later date
field uses `0x000fbef9`, which decodes to the exact game date 2015-07-25.
Additional game metadata and the game-tree block follow this header and remain
only partially decoded.

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
encoded state payload. This is a useful oracle for packet framing and
timing, but it is not byte-identical to the sibling `.wmv` script
stream: side-by-side counts of the Mar del Plata base fixture give
identical checkpoints (73 opcode-`02` commands on both sides) but the
text export carries 23 extra transitions (99 opcode-`03` vs the `.wmv`'s
76), and the Navara-Adams text export has 87 checkpoint commands while
its `.wmv` script stream decodes 62. At playback the transport feeds
the `.wmv` stream; the export additionally reflects the interactive
replay/edit timeline. It is not a separate game notation file, and
counts taken from text exports overstate what a single base video
carries by itself.

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

The complete outer grammar of opcode `06` is now verified:

```text
u32le opcode          = 6
u32le reserved        = 0 in observed records
u16le record_count
repeat record_count times:
    u16le record_length
    u32be record_type
    u16be echoed_length
    byte payload[record_length - 6]
```

`record_length` counts the six bytes occupied by `record_type` and
`echoed_length` plus the payload, but excludes its own two-byte field. The
big-endian echoed length always equals the little-endian leading length. This
mixed-endian duplication was the source of the earlier apparent
misalignment. All 2,166 opcode-`06` commands in 234 exports parse to their
exact end with the declared record count and matching lengths; there are no
truncated or trailing records.

The observed record types are `37` (1,507 records), `4` (1,208), `5`
(1,062), `7` (531), `3` (239), `2` (90), `34` (35), and `130` (22). Type `2`
contains the long textual lesson annotations, including `would transpose to a
Shirov-Bacrot 2014 game. It's a mistake to allow the knight into c7.` Other
types contain short numeric and board/object references.

Types `4` and `5` have complete inner grammars:

```text
type 4 payload: repeat { u8 style; u8 square; }
type 5 payload: repeat { u8 style; u8 from_square; u8 to_square; }
```

All 1,208 type-`4` records have even payload lengths, yielding 1,935 square
entries. All 1,062 type-`5` records have payload lengths divisible by three,
yielding 1,639 directed square pairs. Styles are overwhelmingly `2` or `4`,
with only three style-`3` entries (type 4: `2`×1598, `4`×336, `3`×1; type 5:
`2`×1433, `4`×204, `3`×2).

Type-`4`/`5` squares are **one-based file-major** (closed 2026-08-30 to
the same convention family as the node table and opcode `04`):
`0` = "no square", `1` = `a1`, `2` = `a2`, `9` = `b1`, `64` = `h8`
(square = file×8+rank+1). Value `0` never occurs in any of the 5,214
coordinate instances, while `64` occurs 40×. Tie-breaking rank- vs
file-major within the one-based frame: piece-occupancy checks of the
77 FEN-named drill clips give **59.1 %** endpoints on occupied squares
under file-major-one-based versus 46.1 % under rank-major-one-based
(43.9/39.4 % for the zero-based frames) over 1,146 coordinate
instances, so file-major wins decisively. The 40 value-`64` occurrences
are all consistent with arrows/markers into `h8` (back-rank rays
`f8`→`h8`/`e8`→`h8` in the `CBM168Taktik` tactics lessons, file rays
`h6`→`h8`, long diagonals `d1`→`h8`), remaining corner-invariant across
both conventions.

Type `4` therefore encodes styled square markers and type `5` styled
arrows/vectors. The style values' color names (`2` = green, `3` = yellow,
`4` = red) remain a visual-oracle hypothesis. A style×move-glyph
correlation over all 3,574 style entries shows no clean good/bad split —
style `4` events join `!` symbols 143 times and `?!` 43 times — so the
color semantics, and whether style means color at all, stay unresolved.

Type `130` is text before move with a language selector, not a question
record. All 22 payloads begin with the u16be language code `0x0000` (all
languages) followed by one of `Q1`, `Q2`, `Q2a`, `Q2b`, `Q3`, `Q4`, or
`Q5a` — the interactive-question labels themselves. Type `34` is a medal
bitmask, not an enable flag: all 35 payloads are u32 `1`, setting bit 0 of
ChessBase's medal word (= the *Best Game*/brilliancy medal, same bit
numbering as the CBH index medals, scidb `Flag_Best_Game`).

### Opcode-06 record types follow the CBA annotation grammar

The type numbers are exactly the decimal images of the `.cba` annotation
types documented in `CHESSBASE_FORMAT_REFERENCES.md` §4.4 — the media
stream reuses the CBA annotation writer verbatim (`130` = 0x82 = text
before move, `34` = 0x22 = medal, `2` = 0x02 = text after move, `3` =
symbols). Byte-range checks below make this corpus-verified.

The type-`3` symbols payload validates the CBA field order across all 239
records: 171 are one byte (move glyph only), 68 two bytes (move glyph +
evaluation); the prefix byte never occurs. Index-0 values are exclusively
move glyphs — `1` (`!`)×102, `6` (`?!`)×33, `2` (`?`)×21, `3` (`!!`)×7,
`4` (`??`)×7, `5` (`!?`)×4, `0` (unset)×65. Index-1 values are exclusively
position evaluations — `0x0F` (`=/+`)×24, `0x0E` (`+/=`)×13, `0x12`
(`+-`)×10, `0x13` (`-+`)×9, `0x0B` (`=`)×9, `0x0D` (unclear)×3. The former
reading of type `3` as "an unknown scalar most commonly 1, 6, 15, 2, 14" is
fully explained: those were `!`, `?!`, `=/+`, `?`, `+/=`.

The leading u16be word of type-`2`/`130` payloads is the CBA text-comment
language code: `0x0000` all languages, `0x2A` English, `0x35` German,
`0x2B`/`0x31`/`0x46`/`0x67`/`0x75` Spanish/French/Italian/Dutch/
Portuguese. The earlier "leading `*`/`5` glyph selectors" were these
language bytes. The corpus histogram over 90 type-`2` records is
`0x0000`×68, `0x002A`×11, `0x0035`×11 — exactly the paired English/German
instructional labels. All 22 type-`130` payloads carry `0x0000`.

Type `2` is Windows-1252 lesson text. The record length supplies the
string boundary—there is no required trailing NUL. Decoding the bytes
after the language code as Windows-1252 recovers German strings such as
`weißfeldriger Läufer`. Text pairs carrying `0x002A`/`0x0035` show the
same lesson sentence in two languages; ChessBase then displays only the
one matching the UI language. Play-and-decode layers must read both.

Type `7` has the fixed payload `00 index square 00` in all 531 records. The
index ranges from 0 through 27; the square value is probably one-based like
the other graphic fields (`0` occurs only 27 times, plausibly "no square",
and observed squares `1`–`59` = `a1`–`c8`), so it associates a small
lesson/game object index with one board square. Whether that object is a
piece, selection, question target, or branch marker remains unresolved.

Type `37` is a four-byte big-endian millisecond timeline cursor. Values such
as `0x0004a6e9` become
304,873 ms; they are in the scale of their containing videos, usually first
appear shortly after that media time, and then persist in later cumulative
updates. Across 883 values unique within their export file, the median value
is 2.318 seconds behind the command carrying its first observed copy, with
248 appearing within one second. Successive changed values increase in 756 of
765 transitions (98.8%); the nine decreases occur in interactive or branch
clips where backward navigation is plausible. Larger offsets occur when an
unchanged value is carried forward and in edited/trimmed clips. The remaining
oracle question is whether this cursor names source/edit time, an annotation's
activation time, or another closely related timeline.

Corpus scanning finds several annotation classes inside `06`, including
interactive-moment labels (`7th Interactive Moment`, `16th Interactive
Moment`), instructional labels (`*Quiet move no. 1!`), speaker names
(`Dave Smerdon!`), explanatory prose, and embedded game references such as
`(70) Carlsen,M ... Nakamura,H ... Zuerich 2014`. This confirms that `06`
is a general lesson-object container, not just a move-delta stream.

**(2026-09-07) The styled square/arrow annotations are media-stream-only.**
A full-file census of the sibling `.2cba` annotation stream (863,538
records, zero parse failures) finds **zero** type-4/type-5 square-list
records: the `.2cba` sub-item inventory is exactly text (0x02, 88,741),
NAG (0x03, 64,127), move time (0x07, 14,503) and engine eval (0x21,
267).  The type-4/5 marks/arrows exist only in the WMV script stream
(opcode-06 inline collections + opcode-04 transient actions) — the
underlying database game carries none of them, so a 2CBH game import
needs no square/arrow handler and the media player cannot inherit them
from the annotation layer.

The relationship between `06` and `02` is also confirmed. Across 10
script-bearing WMVs, the final `06` delta before each
following `02` checkpoint occurs byte-for-byte inside that checkpoint in all
83 observed groups. In total, 84 of 109 individual deltas occur literally;
the remaining 25 are earlier members of multi-delta groups whose final form is
what the checkpoint retains. Thus `06` is an incremental lesson-state update
and `02` is its cumulative/checkpoint representation. They are two views of
the same state, not independent command families. A decoder can process `06`
for low-latency updates and use `02` to initialize after seeking or to verify
and repair accumulated state.

Interactive (`.cms`-attached) lessons refine this: their base `.wmv`
script stream carries no standalone opcode-`06` commands at all (the
Mar del Plata base stream = 73 checkpoints + 76 transitions and nothing
else) — all annotations live inside the checkpoint tails, per node. In
plain lectures (no `.cms`), standalone opcode-`06` deltas flow in the
base stream and the checkpoint tails embed the same bytes. Both
designs share one invariant: the opcode-`02` checkpoint is the
authoritative serialized state; the deltas are its playback-time update
channel.

### Checkpoint body structure (Navara-Adams)

Diffing the 87 consecutive opcode-`02` snapshots of the Navara-Adams base
lecture resolves the tail of the checkpoint section beyond the identity
header:

- The state value at offset 8 is a u32. Within the Navara-Adams snapshots
  its upper three bytes are always zero — fields 9–11 never change — so
  bytes 8–11 look like a lone byte there. Corpus-wide, however, the same
  field reaches `0x1af` (431) in the `CBM 168 Strategie/Strategy` base
  lectures: 337 of 5,731 checkpoint records (and 215 of 4,455 opcode-`03`
  transitions) carry upper byte `1`. The cursor is therefore genuinely
  u32le, and the Navara-Adams `0x98`/`0x99` display ids are flat
  serialized-node indices of a tree with ~154 nodes, not
  high-bit-flagged plies. Any playback implementation must read ids as
  full integers.
- Best working model after the corpus scan: ids enumerate game-tree
  nodes serially (main line plus the serialized variation forest), so
  their correlation with ply numbers holds only for linear stretches,
  and the former "bit `0x80` = variation-mode flag" hypothesis is
  inconsistent with ids beyond `0xff` and is retired — the low seven
  bits "matching" nearby ply anchors was an artifact of a small tree.
- After the six identity strings the first packed date is
  `0x000FBE00` = 2015-00-00 (year only); a second full packed date
  appears later in the body, after a length-prefixed Windows-1252
  string (the annotator/recording-agent slot: `Robot 11` for the Biel
  auto-recorded lessons; magazine games instead carry sources like
  `Mega2015 Update 36` / `Chessbase` and the annotator
  `Mihail,Marin`). The two u16le values right after that string are
  the **players' Elo ratings, white first**: corpus-verified over 218
  of 234 exports against published ratings — `2724/2740` (Navara–Adams),
  `2740/2724` (Adams–Navara round 1, confirming order), `2779/2814`
  (So–Nakamura), `2724/2733` (Navara–Wojtaszek). The 16 exceptions are
  interactive drill-clip checkpoints with a different metadata block.
  The second packed date decodes with full precision and equals the
  played game date (`0x000FBEF4` = 2015-07-20 for round 1, `0x000FBEF9`
  = 2015-07-25 for round 6, `0x000FBF1D` = 2015-08-29 for Sinquefield
  round 6).
- The remaining body is a fixed region (u16/u32 words including `df 07` =
  2015 twice, u32-length strings `FIDE` twice, and a block whose values
  `bb 80`/`0b b8`/`03 e8` read as u24be/big-endian millisecond offsets
  48,000/3,000/1,000) followed by a per-node table of 5-byte entries:
  two bytes in the square-id range `0x02`–`0x3e` plus three zero bytes.
- Opcode-`06` annotations are materialized inside this node table as
  inline collections using the exact opcode-`06` record byte grammar:
  `[u16le count][records...]`, a record being
  `[u16le length][u32be type][u16be echoed_length][payload]`. Example from
  the fixture: `01 00 0f 00 00 00 00 05 00 0f 02 27 3c 02 3c 33 02 3d 33`
  = count 1 + a type-`5` record with arrows `g5`→`d8` and `d8`→`c7`
  (one-based squares) — a queen-path diagonal into `c7`. Collections at
  empty nodes start as two zero placeholder bytes and are replaced as the
  lesson accumulates annotations; this is why diffing successive
  checkpoints shows insertions at ever-growing offsets (334, 390, 421,
  635, 736, 1126, 1217, 1456, 1477, 1479 in this lecture) plus the
  single-byte cursor updates already documented. The recorded
  `03`/`06`-before-`02` byte-equality therefore confirms the checkpoint
  embeds the same records the deltas carry.

The pair bytes in the node table are the **serialized game-tree edge
stream** (closed 2026-08-30): each entry is `[u8 from][u8 to]` plus
three zero bytes, squares encoded **file-major** (`a1` = 0, `b1` = 8,
`a2` = 1 — square = file×8+rank, the transpose of the usual rank-major
board index), edges ordered depth-first through the game tree with
variations interleaved. Verified byte-exact for the first 18 entries of
the Navara-Adams checkpoint against the published round-6 score tree:
`c2-c4` = `(17,19)`, `e7-e6` = `(38,37)`, `b1-c3` = `(8,18)`,
`d7-d5` = `(30,28)`, … ending `f6-h5` = `(45,60)` at entry 17, then
`(59,38)` = `h4×e7` (10.Bxe7) — 18/18 against python-chess. This also
explains the earlier `03`-transition id correlation: the cursor ids are
node indices into this same serialized edge stream (the max observed
cursor id ≈ the tree's edge count), so the former `0x80` "variation
flag" ids were simply deeper variation nodes. Opcode-`06` collections
are attached to the padding of the node entry they decorate (the
collection replaces padding bytes in place, so entry rhythm stays
visible), with padding 4-byte-aligned after inline record collections.
Note: a nearby small u16be word `03 4a` advances to `03 4c` while the
lesson plays, so it is a millisecond-ish counter, not a ply or node
count.

The larger Mar del Plata base checkpoint (2,534 bytes, ~70 entries)
resolves what the collections carry. Every decorated node has a
single-record collection whose record is the type-`37` ms cursor:
`[u16le count=1][len=10][type u32be 0x25=37][echo=10][u32be ms][00 00]`.
The serialized per-node field the checkpoint patches is that node's
media timestamp (values such as `0x0001623b` = 90,683 ms, `0x0000e510`
= 58,640 ms) — confirming type `37` as the per-node media time of the
serialized lesson tree, consistent with the earlier finding that such
cursors persist in cumulative deltas and first appear shortly after
their media moment. Decorated nodes also host type-`2` game-quotation
texts, e.g. `1-0 (3520) Shirov,A (2701)-Bacrot,E (2729) Bilbao 2014 CBM
163 [Krasenkow,M]` — quotation records embed the game number, both
rated players, the event, the source database (CBM 163) and the
annotator (`Krasenkow`) inline.

The node pairs still do not equal the sibling `.cms` selectors
(`x0y0`/`x24y25`/`x26y43`/`x34y43`) under decimal or hex readings; the
two tables plausibly index different layers (serialized tree nodes vs
position clips).

### Binary oracle strings

The ChessBase 26 executable contains media-related identifiers including
`ScriptItems`, `ScriptActivationManager::IsStreamCrypted`, `Extra Chess
Media`, `Chess Media System`, and `Audio Stream`. These confirm that script
items are handled by a dedicated activation/stream layer, but the executable
does not expose the private record grammar through symbols or documentation.
They provide useful search anchors for later disassembly, not proof of field
semantics.

**(2026-08-30) The August 30 corpus findings are corroborated by strings
directly inside `CBase26.exe`** — several decode-bricks in this document
now have binary-internal witnesses:

- The export-format record vocabulary sits directly next to
  `ScriptItems`: `EDITOR`, **`GA:`** (the script-command prefix decoded
  all through this document), `Timestamp`, `Action`, `Sequence`,
  **`Game Action`** — the `.txt` sidecar of each WMV is a
  `Game Action`/`Timestamp`/`Sequence` record export, exactly as parsed
  here (each `GA:` line = one timestamped action).
- The action names `V_LASTMOVE`, `V_MOVES`, `V_MAP`, `V_ZOOM` sit in the
  same cluster — the script-item action alphabet of the media viewer
  (drawing/mapping moves and camera zooms).
- `ScriptActivationManager::IsStreamCrypted`, `::GetProductId`,
  `::GetCryptKey` next to `HBStreams`/`.prot`: script streams **can be
  encrypted per product**.  The CBM 168 fixtures decode cleanly, so they
  are unencrypted — commercial/activated media may need the crypt-key
  path before a generic decoder can read them.
- The **64-byte file-major square transpose table**
  (`00 08 10 18 20 28 30 38 01 09 11 19 …`, file×8 + rank for index
  i) exists at `0x194f8d0` in the binary — direct corroboration of the
  file-major square convention the decoded checkpoint edge stream,
  opcode-`04` arrows and opcode-`06` graphics all use.
- The annotation-type registry vocabulary `V_T_*` maps one-to-one onto
  the decoded record families: `V_T_TEXT` + `V_T_IN_PB_AFTER` (type
  `0x02`, text after move) / `V_T_IN_PB_BEFORE` (type `0x82` = 130, text
  before move — *before/after is playback placement*), `V_T_SYMBOLS`
  (`0x03`), `V_T_MOVE_MEDAL` (`0x22` = 34, the found value `1` = the
  Best-Game medal), `V_T_GAME_QUOTATION` (the quotation texts with game
  number/ratings/source), `V_T_SQUARELIST` (the styled square marks and
  arrows, types 4/5), `V_T_PAWN_STRUCTURE`, `V_T_PIECE_PATH`,
  `V_T_CRITICAL_POS`, `V_T_TRAINING` (the remaining CBA annotation
  families).  `V_CB_BOARDPOINTS` names the `.cms` `x/y` selectors:
  they are **board points**.
- `dmcs`, `Traning Generator` (sic) and the `V_*` vocabulary identify
  the authoring layer ("Training Generator"; the lecture robot/mastering
  side), matching the `Robot 11` annotator strings seen in the
  checkpoints of auto-generated Biel lessons.
- The `Robot` strings in the binary (`Robot - no candidates`, `Robot
  Timeout`, `ToggleRentRobot`, `AutoRobotChat`) belong to the
  play-server robot, not the lecture annotator — no conflict with the
  checkpoint finding.

**Ghidra decompilation (CBase26, 64-bit) confirms the script-item
object model.**  The script items referenced by `ScriptItems`/`GA:`
carry `{timestamp @+0x40, action-name string @+0x30, payload
SString @+0x20}`; the exported column formatter renders the timestamp
as `item.ms / double-constant`, and for the Action column substitutes
the literal `"Game Action"` when the item's action name is `"TEXT"`.
The sequence formatter special-cases the action names `"TEXT"` and
`"GA"` — so the script items are *named actions* (`GA` = the
Game-Action payload records decoded throughout this document, `TEXT`,
and the viewer actions `V_MAP`/`V_ZOOM`/`V_LASTMOVE`/`V_MOVES`/`EDITOR`),
and the `.txt` sidecar is their timestamped export.  The annotation-dialog
wiring decompiles the full type registry: text (`V_T_TEXT`,
`V_T_IN_PB_BEFORE`/`V_T_IN_PB_AFTER`), symbols, square list, time and
date, critical position, move medal, game quotation, pawn structure,
Fritz eval, training, piece path, correspondence, variation color, eval
profile — matching the decoded opcode-`06` record families one-to-one.

**The WM-SDK delivery loop decompiles cleanly** (`FUN_1403ace20`): it
walks the ASF script-command entries through a WM-reader interface
(vtable entries 0x58 = GetCount/0x60 = Get with two out-strings), and
builds a `ScriptItem` (`FUN_1403abbe0`) per entry from the
`(name, value)` wide-char pair.  The `ScriptItem` ctor assigns the
action→type ids `"TEXT"` → 1, `"EDITOR"` → 2, `"GA"` → 3, and defaults a
missing timestamp to `10,000,000` — **100-ns units, i.e. one second** —
so the internal timeline is FILETIME-style, exporting to seconds (the
divisor seen earlier).  The dispatcher (`FUN_1403a88a0`) routes items
with action `"GA"`/`"TEXT"` into the board-side consumer (vtable
`+0x480`) and separately handles `"MA"`.  This is the exact pipeline the
static decoder in this document bypasses: ASF script stream → named
items → the `GA` payload grammar decoded above.

### Board-side dispatcher decompilation (2026-08-30, kimi)

Ghidra headless decompilation of the apply layer (probe 9, functions
`FUN_140da2160`/`FUN_140da1d70`/`FUN_1409f09c0`/`FUN_140da1650` plus 13
auxiliary functions) closes the payload-grammar questions:

**The opcode dictionary is literal in the binary** (`FUN_140da1d70` —
the record→`Sequence`-column text formatter).  Wire high-level opcodes,
verified against the decompiled switch:

| opcode | binary name | semantics |
|---:|---|---|
| 2 | `Set Game` (+ side to move) | position sync — full game/tree install |
| 15 | `Set Game` | same family (fixtures show it as the variant of 2) |
| 3 | `GotoIndex: N` | navigate the game tree to node index N (the transition ids = tree node indices, confirmed) |
| 4 | (rendered by `FUN_140b87d60`) | transient board action — see below |
| 5 | (rendered by `FUN_140d36610`) | a second board-action record (not in the CBM 168 corpus) |
| 6 | `Annotation Count=N` | opcode-06 delta container; N = record count |
| 8 | **`Promote Line`** | promotes a variation to main line — *not* a reset as earlier guessed |
| 11 | `UnAnnotate` | removes annotations |
| 12 | `Add Annotext` | annotation text channel |
| 13 | `WebOrigin` | web-origin marker |
| 14 | `Sync` | the source-time sync counter (matches the found 6 s cadence) |
| 16 | `Set Moves` | move-list install |
| 17 | `Set Header` | header install |

The apply function `FUN_140da1650` (board-object `param_2`) decodes each
case: opcode 3 = `FUN_140b7c940(board, index, 3)` (tree navigation);
opcode 4 = validate then `FUN_140b7df70(board, sq0, sq1, kind)` with
`kind` = the record's class word **and a built-in upgrade: kind `0x40`
becomes `0x80` when the position index is below the tree length**; opcode
6 = install/replace a `DirEntry` list on the board object (the
C-by-C-record annotations — matching the 8-byte-per-record count
arithmetic); opcode 7 = `FUN_140b7ac00(board)`; opcode 8 (Promote Line) =
`FUN_140b7d530(board)`; opcodes 9/10 = viewer helpers, 11 = UnAnnotate
with a `DirEntry(5)`, 12 = Add Annotext (writes into move column 7 with
a `0x20` flag), 16/17 = board/header installs.  The kernel wrapper
`FUN_1409f09c0` adds: opcodes with bit pattern `0x28002` (1, 15, 17)
force a view refresh; opcode `0x12` (18) calls the header/mode vtable
entry with `record[4]==1`; and the opcode-14 `Sync` walks the per-node
list comparing the record counter against the `+0x1c` node field — the
type-37/edge-node map observed in the checkpoints.

**Style colors, board-actions and type-7**: the per-case handlers
(`FUN_140b7df70`, `FUN_140d369f0`, `FUN_140b7ac00`, `FUN_140b7d950`,
`FUN_140b7d530`) are the visual primitives; their color/style tables
remain the only GUI-observable unknowns, but the opcode semantics above
now bound them (4/5 = styled square marks/arrows; 7 = an object
clearing/navigation case; 8 = line promotion).

### GUI observation (2026-08-30, glm vision) — BLOCKER-observed

Attempt to answer the remaining visual questions by driving ChessBase 26
under Wine against the ripped CBM 168 tree.  Result: **the observation
path is gated by the magazine's serial/abonnement wall before any
script annotation renders.**

What worked (evidence in `media-console/gui-observation/`):
- ChessBase '26 runs under Wine on a private Xvfb display
  (`Xvfb :77`, 1920×1080; `wine "C:\Program
  Files\ChessBase\CBase26\CBase26.exe"`; `WINEPREFIX=~/.wine`).
  Screenshots automatable via `ffmpeg -f x11grab -i :77` (`import`
  from ImageMagick 7.1.2 errors out); interaction via `xdotool`
  click/keys works (dialog dismissal verified).
- The whole GUI renders: database tree (ripped `168 !START` visible
  under My Databases), the Chess Media board pane initialized
  (empty board shown on the right), account chip ("Not registered" →
  "Logged in Guest").
- On load, an **"Activate data abonnement:"** dialog demands the 5×5
  DVD serial printed on the package and a captcha; `03-xvfb-launch.png`
  / `01-activation.png`.  `04-after-cancel.png`: after Cancel —
  **"Authorisation: The serial number is not valid"**, then
  **"No games found"** for the 168 magazine tree.  `05-video-node.png`:
  the Video node lists no playable entries without the serial.

Verdicts:
- Q1 (mark/arrow style bytes 2/3/4 → colors): **OPEN** — blocked by the
  serial wall before any annotation renders.  The screenshot pipeline
  and decoded event timeline (`/tmp/navara_sync2.json`: which style
  byte paints which squares at which media-ms) are prepared; only the
  valid CBM serial (or a licensed install) is missing to finish.
- Q2 (opcode-04 classes/modifiers → visual actions): **OPEN** — same
  blocker.
- Q3 (type-7 / `.cms` board points): **OPEN** — same blocker.

Re-run recipe once a serial is available: launch on Xvfb, cancel nothing,
enter the serial in the "Activate data abonnement" dialog, open
`168 !START`, play the "Biel 2015 round 06 Navara-Adams" media entry,
screenshot at the marks in `/tmp/navara_sync2.json` (t=60.642 s arrows
green?, 84.142 s class-`0x200` e1-c1, 475.181 s style-2 mark a4 …), then
map observed colors to style bytes 2/3/4 and classes to actions.

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
10 through 214 bytes. The formerly conspicuous multiples of three were an
artifact of dropping unpadded six-bit tails, not a property of the binary
grammar. Opcode `02` is variable-length and ranges from short records to
several kilobytes. This rules out a generic directory format for every opcode:
`03/04/08/0e` are fixed command structures, while only `06` and `02` need
variable-length parsers.

Opcode `04` has this stable 12-byte layout:

```text
u32 opcode       = 4
u32 action_class
u8  first_square
u8  second_square
u16 modifier
```

All 742 exported records have both square bytes in `0..63`; together they
cover that full range, and the squares are **file-major** (`a1` = 0,
`b1` = 8, `a2` = 1 — square = file×8+rank), matching the checkpoint node
table. Verified against the published game trees in tree correlations:
the Biel round-1 lecture's 14 class-`0x80` events decode to real game
edges 10/14 (vs 3/14 under a rank-major reading, and 0 reversed
mismatches); round 6 gives 4/8 + 1 reverse (vs 1/8); the misses are the
lecturer's own analysis arrows that exist only in the lesson tree. The
class-`0x80` arrows are **(from, to) move arrows**: round-6 examples
decode as `c8-e6` (= 13...Be6 ✓), `c8-f5` (= the round-1 post-mortem RAV
move 6...Bf5 ✓) and `b7-b6`; Mar del Plata shows `f3-g4`, `g5-f4`,
`f4-d3` along the thematic King's-Indian geometry. Prior rank-major
decodings (`e8-f8`, `g6-f6`, `b4-e7`) were coincidental re-readings of
the same bytes. The six little-endian action classes are `0x80` (498
records), `0` (204), `0x200` (33), `1` (4), `0x800` (2), and `2` (1).
The observed modifiers are `0` (468), `0x80` (230), `0x240` (24), `0x20`
(12), `2` (4), `1` (3), and `0x10` (1). Field boundaries and board-argument
arguments are proven; class-`0x80` = arrows, while the other classes'
visual meaning still requires an oracle observation.

Opcode `04` is not the incremental form of opcode-`06` type-`4`/type-`5`
graphics. For all 742 opcode-`04` events, the next opcode `06` within ten
seconds (when one exists) never contains the same or reversed square pair as a
type-`5` arrow; only three events share even one endpoint with a type-`4`
marker. There are 567 events with no nearby delta and 172 whose nearby delta
is unrelated. Opcode `04` therefore represents an independent, transient
board action channel, while opcode `06` updates persistent checkpoint state.
Its class/modifier mapping still needs visual identification.

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

Corpus-wide, 159 position clips carry 77 distinct `x/y/v/u` selectors:
`x` and `y` are both bounded 0–63 (e.g. `x0y0` on every drill, plus
points like `x30y21`, `x49y50`, `x33y60`), `v` ∈ {2, 3, 4} and `u` ∈
{0, 2, 5}. Their semantics remain open: decoded clip script streams
do not start at node id `x` (clips restart their own cursor ids from
zero or small values, and the Strategy drill clip `x30y44` plays ~100
transitions over ids `0x1a5`..`0x10b` of that lecture's 431-node
tree), so `x`/`y` are not node-id ranges; the base-WMV node pairs are
not equal to `.cms` coordinates either. Each interactive clip's own
script stream is a small annotated loop (2–20 commands, cursor restart
at zero) whose per-branch position is the responsibility of the base
checkpoint's per-node type-`37` media times. The inner join for
playback is therefore: the base checkpoint's per-node timestamp tells
when to switch to the clip that shows the drill at that node, while
the `.cms` maps positions to clip files.

The `.cbm` file is a media catalog/manifest and is not itself the authoritative
playback timeline.

### `.cms` binary layout (FULLY DECODED, 2026-09-02)

Header: `u32be` body length (filesize - 4), `u32le` record count,
`u32le` base-name length, base name.  The body contains exactly
`count` records; four shapes exist, discriminated by the kind field:

**kind=1 (drill/position record)** - marks chapter boundaries and the
terminal position:

```text
[kind=1 u32le]
[0 u32le]
[duration-seconds u32le]
[0 u32le]
[namelen1 u32le][FEN slash-form, namelen1 bytes]
[namelen2 u32le][base x0y0 clip name, namelen2 bytes]   (optional)
```

The clip-name pair is absent on the LAST kind=1 record in the file
(the terminal position has no clip to play after it).  This is the
"trailing short record" that broke the 5- and 6-field framings in the
earlier partial decode (commit fb3aa3d).

**kind=2 (base-video record)** - marks a base video segment:

```text
[kind=2 u32le]
[0 u32le]
[duration-seconds u32le]
[5 u32le]
[namelen u32le][base-video name, namelen bytes]   (optional)
```

The final kind=2 record omits its name: the name is implicitly the
header's base name.  Intermediate kind=2 records (base-video segments
001, 002, ...) carry their names explicitly.

**kind=4 (primary hotspot clip):**

```text
[kind=4 u32le]
[0 u32le]
[duration-seconds u32le]
[0 u32le]        <- f3 = 0 for kind=4
[0 u32le]        <- f4
[namelen u32le][clip name, namelen bytes]
```

**kind=3 (alternative hotspot clip):**

```text
[kind=3 u32le]
[0 u32le]
[duration-seconds u32le]
[2 u32le]        <- f3 = 2 for kind=3
[0 u32le]        <- f4
[namelen u32le][clip name, namelen bytes]
```

#### The x/y/v/u selectors (DECODED)

The clip name embeds the FEN (with `/` replaced by `z`) plus four
selectors: `x{X}y{Y}v{V}u{U}`.  The selectors were verified against
python-chess (109 hotspot clips across all 15 CBM168 `.cms` files):

- **x = from-square** of the lesson's key move, encoded
  **file-major 0-based** (a1=0, b1=1, ..., h1=7, a2=8, ..., h8=63).
  Verified: the from-square is occupied by a piece in 109/109 clips
  (100%).
- **y = to-square** of the key move, same encoding.  Verified: the
  x->y move is fully legal in the FEN position in 109/109 clips
  (100%, not just pseudo-legal - no king-safety violations either).
- **v, u = structural constants**, part of the filename key but not
  per-clip parameters: `(3,2)` for primary clips, `(2,5)` for
  alternative clips, `(4,0)` for base-position clips.  These probably
  encode view/priority tiers in ChessBase's Reader UI.

Example: clip `8z5k2z2P5z3Q3Kz1q6z6P1zp7z8 b - - 0 1x46y54v3u2.wmv`
= FEN `8/5k2/2P5/3Q3K/1q6/6P1/p7/8 b - - 0 1`, key move **f7-g7**
(black king steps to g7), hotspot squares f7 (from) and g7 (to).

Scidb surfaces these in `tcl/app-media.tcl`: `CmsEntries` appends the
from/to squares to each hotspot row (`CmsSquare`), `ResolveIndex`
carries them to `InteractiveFollow`, and entering a matched position
draws the hotspot move as a green board arrow via `SyncAnnotate` (the
board's own update path erases it on the next position change).
Degenerate `a1-a1` corpus hotspots (quiz positions with no single key
move) no-op in the arrow layer.

#### Verification methodology

The square encoding was tested against four candidate hypotheses
(file-major/rank-major, 0-based/1-based) across all 109 hotspot clips
in the CBM168 corpus.  Only file-major 0-based yields 100% from-square
occupancy and 100% legal moves.  The encoding matches the RE doc's
established square-encoding family (opcode-4 board actions use the
same file-major 0-based scheme; op-6 inline graphics use 1-based
file-major - the 1-based variant scores only 43/109 for from-square
occupancy, ruling it out here).

### Interactive playback model — CLOSED (2026-09-07, agy pass; task 5)

The base checkpoint tree, the per-node type-37 media times and the
`.cms` index now close the interactive playback loop. Verified
end-to-end on the Mar del Plata interactive lecture (base video
433.852 s, 221-node lesson tree with 78 media-timestamped nodes):

- The `.cms` index holds one chapter (kind=1, 433 s) whose FEN is the
  **interactive prompt position**, plus the base clip `x0y0` and three
  hotspot clips (kind 4 primary + kind 3 alternatives) whose filenames
  embed the same FEN and the answer-move selectors (`x{from}y{to}`
  file-major 0-based; all three hotspot moves verified legal in the FEN
  with python-chess).
- The chapter's prompt FEN matches **exactly one** base-tree node
  (node 124, path `main/36.v2/5`, move `Nf4/g6-f4`), whose type-37
  media time is **416.46 s** — 17.4 s before the base video's end
  (433.852 s).  That is the interactive switch point: the base lesson
  plays until the node's media time, then the player hands over to the
  hotspot clip matching the user's chosen answer move (primary clip for
  x/y, alternatives for other replies; kind 3 clips carry shorter
  durations — 61 s/37 s vs the primary's 30 s).
- Correlation statistics: 4/4 `.cms` clips matched base-tree nodes by
  exact FEN (100% FEN match rate, 100% legal hotspot moves), and the
  host node's media time validates the switch model.

Reference implementation: `media-console/nodes.py` (the base-tree
decoder: edge stream -> per-node FENs + media times, with `--summary`
and `--find-fen`) and `media-console/cms_records.py` (the `.cms`
parser/summary).  Together with `wmv2timeline.py` they complete the
static side of an authentic interactive playback engine: base-tree
positions + per-node media times + the clip mapping.  What remains for
a player is the runtime application layer (applying annotations and
switching to clips) and, for commercial media, the per-product
decrypt path.

### Rejected: an AI-fabricated "mark-style colour / opcode-04 class" table (2026-09-07)

A web-surfaced text claiming `.cms` = "Content Management / Style Map" and
`.cbm` = "Compiled Binary Mark", a four-colour "Ocean" palette (#0071BC,
#E6F1F8, #004F84, #00395E) keyed to mark styles 0x01-0x04, and an
opcode-04 class table (0x00-0x1F internal transforms, 0x20 "Concentric
Convergence", 0x40 "Dynamic Bounds Modifier", 0x60 "Bifurcated Anchor
Paths", 0x80 "Directional Arrows", 0xA0 "Loop/Recurrence Loops") is
**fabricated** and does not match the corpus:

- The 742 opcode-04 records carry six classes (0x80 x498, 0x0 x204,
  0x200 x33, 0x1 x4, 0x800 x2, 0x2 x1).  Class 0x200 (33 published
  records) and 0x800 are absent from the pasted table, while the table's
  0x3/0x4/0x5/.../0xA0 classes have never been observed.
- The opcode-06 mark-style histogram is style 2 x1598, 4 x336, 3 x1 -
  style 0x01 ("Primary Bold Line") never occurs in the corpus.
- The file-name expansions contradict ChessBase's own binary strings
  (`Chess Media System`, `Extra Chess Media`, `V_CB_BOARDPOINTS`);
  "Compiled Binary Mark" and "Content Management / Style Map" are
  backronyms.
- The colour codes are unverifiable without the visual oracle (still
  blocked by the serial wall).

Consistent with the verified state: opcode-04 = structural/vector
annotations and class 0x80 = directional arrows (proven by game-tree
correlation, not by naming).  Everything else in the text is unfounded.

### Rejected: "opcode-04 class = SyncColors key (2=green, 3=yellow, 4=red)" (2026-09-07)

A claim that the opcode-04 class field indexes a "SyncColors" table
with 2=green, 3=yellow, 4=red is a **field conflation** and is
falsified by the corpus:

- The `SyncColors {2 green 3 yellow 4 red}` table in
  `media-console/experimental-panel/app-media.tcl` is keyed by the
  **opcode-06 mark/arrow style byte**, not the opcode-04 class.  The
  opcode-06 style histogram matches its keys exactly (style 2 x1598,
  4 x336, 3 x1); the opcode-04 class histogram does not.
- The opcode-04 class histogram is 0x80 x498, 0x0 x204, 0x200 x33,
  0x1 x4, 0x800 x2, 0x2 x1 (742 records, 234 exports).  Claimed keys
  3 and 4 have **zero** corpus occurrences; key 2 occurs exactly once.
- The decoded opcode-04 layout has separate u16 class and u16 modifier
  fields; the class is not a colour/style key.
- Even the opcode-06 style -> colour mapping itself remains a
  visual-oracle hypothesis (panel code comment); the colours have
  never been verified against rendered output (serial wall).

Related code bug documented in place: lesson board events put the raw
opcode-04 class into the style slot of `SyncAnnotate`'s arrow handler
(`app-media-lesson.tcl`), so the `SyncColors` lookup never matches and
every opcode-04 arrow silently renders green.  Comments in
`app-media-lesson.tcl` and `app-media.tcl` now state this explicitly;
the fallback behaviour is unchanged pending the visual oracle.

### Internet-blocked CBase26 run (2026-09-07, this repo)

Launched CBase26 under Wine on Xvfb :78 with the Windows proxy set to
127.0.0.1:1 (ProxyEnable=1, ProxyServer=127.0.0.1:1) to block internet
access.  Passed 168!Start.cbh as a command-line argument (the working
technique from the eleventh pass).  The database loaded: window
"168 !START: 7 Games".

Results:
- The "Activate data abonnement:" dialog appeared immediately and was
  dismissed via xdotool windowclose (not keyboard — the Wine modal
  input-routing failure persists).
- An "Info" dialog followed (serial-not-valid, from the prior pass).
- The Wine log had ZERO script/media/activation/serial events: the
  activation check is LOCAL (fires immediately without a network
  round-trip), so blocking internet does NOT bypass the serial wall.
- The GUI was too minimal under Xvfb (no WM) to navigate the media
  tree after the dialog was dismissed.

Conclusion: the serial validation is offline; internet blocking has
no effect on the activation gate.

## Reader14 dynamic playback path

A second web-surfaced text claims opcode-04 sub-classes 0x00-0x3F =
square highlights (0x01 Static Full Border, 0x02 Solid Fill, 0x04
Target Reticle), 0x40 = text overlays, 0xC0+ = special markers (0xC1
X-marks, 0xC2 ghost pieces), a nibble colour palette (0x01 Green,
0x02 Red, 0x04 Yellow, 0x08 Blue), and .cms/.cbm expansions ("Chess
Media Script/System", "ChessBase Multimedia Baggage").  Corpus
falsification:

- Classes 0x200 (33 records) and 0x800 (2 records) are absent from
  the table; ~130 claimed class values (0x03-0x3F, 0xC0-0xC2, ...)
  have zero corpus occurrences in 742 records across 234 exports.
- The mark-style histogram is 2 x1598, 4 x336, 3 x1 - the claimed
  palette keys 0x01 and 0x08 never occur in 3,574 style entries.
- The file-name expansions contradict ChessBase's own binary strings
  (`Chess Media System`, `Extra Chess Media`, `V_CB_BOARDPOINTS`).
- The decoded record layout has SEPARATE u16 class and u16 modifier
  fields with distinct histograms; the pasted "class byte with a
  lower-nibble colour mask" structure does not exist.

Consistent with the verified state: opcode-04 draws arrows/colours
onto the canvas and class 0x80 = directional arrows (proven by
game-tree correlation).  The style->colour mapping and the non-arrow
class meanings remain visual-oracle-open (serial wall).

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

The linear mapping of video time to game ply that existed in
`tcl/app-media-sync.tcl` was not ChessBase-compatible. Authentic playback
now consumes the decoded stream-3 events through the
`wmv2timeline.py` → `<video>.plytimes` sidecar → `::media::sync::load-timeline`
path (see the landed state in `MEDIA_PLAYBACK_DESIGN.md` §5.5): the board
follows the lesson's own replay order with per-move media times. The
remaining abstraction gap is the annotation application layer (drawing
arrows/marks/comments during playback) and any future player that
consumes stream 3 natively at ASF presentation timestamps — the static
sidecar pre-parser removed the runtime dependency for the ply mapping.

`tkvlc` renders only the audio/video portion; nothing runtime-side needs
the ASF script-command stream while the sidecar covers playback. A
faithful in-runtime implementation would still need one of:

1. a native ASF/WMF stream reader that exposes stream 3;
2. an FFmpeg/libavformat bridge that forwards stream-3 packets to Tcl; or
3. a standalone pre-parser that builds a timestamped Scidb synchronization
   sidecar before playback.

Path 3 is the selected and landed one for ply sync (see above); the sidecar
generator is exactly option 3 as originally scoped, with the board already
consuming it. Options 1/2 remain relevant only for in-runtime annotation
playback (drawing arrows/marks live).

## Reader14 on genuine Windows — the visual oracle (2026-09-07)

ChessBase Reader 14 (free, no activation wall) was installed in a
Windows 11 VirtualBox VM (`Win11-Oracle`) and driven over
`VBoxManage guestcontrol` (PowerShell synthetic mouse + host keyboard).
The Biel 2015 fixtures were played back with synchronized script stream
and the board window screenshot-sampled at 7.2-7.9 s cadence (136 frames,
3 videos: Biel round 06, round 09, Sinquefield round 9).  Board geometry
calibrated to pixel accuracy (inner board x 48-560, y 179-691, 64 px/square
at 1024x768; verified by the round-09 a4 square mark landing exactly on
the a4 centre).  Full method + frame data: session notes
(`/tmp/vm_oracle_notes.md`, harvest in `~/sas_mirror/vm-harvest-2026-09-07/`).

### Result 1 — script-stream style bytes carry NO colour

- opcode-`06` style `2` arrows/marks render **green** (corridor tests:
  51 %/55 %/75 % of the from→to corridor green in the exact event frames;
  the 475.181 s square mark renders as a round green blob exactly on a4).
- opcode-`06` style `4` (@127.138 s mark, @222.138 s arrow in Biel 09):
  rendered **green** (127 s: a green arrow e6→e3, image-verified) or
  **nothing at all** (222 s: the c4→d3 corridor is pixel-identical to the
  clean board for 30 s).  Never red, never yellow.
- Across 136 frames: **zero** red/yellow/blue/magenta overlay pixels on
  the board.  The classic palette (2=green, 3=yellow, 4=red) is dead for
  the script stream; every script annotation renders in one green.
  Combined with the DE/EN evidence (same arrow, different class), the
  colour is a function of the authoring tool state, not of any byte in
  the stream.  scid's flatten-to-green `SyncAnnotate` fallback is
  therefore **provably correct**; the OPEN colour item closes.

### Result 2 — the renderer follows checkpoints, not deltas

The opcode-`06` delta records (type `4` marks, type `5` arrows, type `7`
index objects) are editor commands.  The rendered board follows the next
opcode-`02` SetGame checkpoint: e.g. Biel 09 @212.138 s a SetGame brings a
thick c3→h8 diagonal arrow band with **no** delta records present (the
annotation is embedded in the checkpoint's serialized game tree), and the
two-segment knight-path arrow c8→f5→d3 rendered @~266 s matches the
266.638 s checkpoint (+12 bytes = exactly one appended annotation
record), not the 261.638 s delta bytes.  This confirms the
Media-Lesson-v2 model: checkpoints are the authoritative cumulative state.

### Result 3 — timer/format operations notes

- The Reader timer is `H:MM:SS`; frames were anchored to record times by
  OCR-ing the green digits (occupancy-signature classification).
- Automation traps: double-clicking the play button toggles pause;
  `VBoxManage copyto` needs escaped backslash target paths.
- The authoring sweeps requested in `MEDIA_VM_EXPERIMENT_REQUEST.md`
  (colour/style/tool sweeps with an intent log) remain **blocked**: Reader
  14 is playback-only and CBase26 needs a valid serial (offline local
  check).  The visual-oracle question they were filed for is however
  answered above with playback evidence alone.

## Next RE tasks

1. (Closed 2026-09-07) Style/colour mapping: **solved by the Reader14 VM
   playback oracle** (§ above) — script-stream annotations always render
   green; no colour byte exists.  Remaining sub-item (non-blocking):
   opcode-`06` type-`7` object semantics and the `37`/`3` rollover
   behavior; plus the CBase26 authoring sweeps if a licensed CBase26 ever
   becomes available (only needed to probe colour paths Reader14 does not
   exercise).
2. (Closed 2026-08-30 + 2026-09-07) The checkpoint body is fully mapped:
   post-date annotator slot, white/black Elo u16le pair (white first,
   corpus-verified against published ratings), full-precision packed game
   date, the serialized game-tree edge stream with file-major squares, and
   per-node media timestamps (type-`37`) plus quotation texts in the
   padding collections. The remaining u32 words are now named (agy pass,
   2026-09-07): after the full game date (`date2`, e.g. `0x000fbef9` =
   2015-07-25) follow the round/subround words (`u16le` subround then
   round — Mar del Plata carries board/subround 4 + round 8), then a
   length-prefixed tournament/source metadata block (`u32le` length 70
   bytes for Mar del Plata, 56 for Navara-Adams; contains the event
   strings `Hangzhou`/`Heibei`, FIDE indicators, further dates), and —
   only in recorded live games, absent in magazine analysis lectures — a
   52-byte time-control block of big-endian ms values: Biel round 6
   carries 10 min base + 3 s increment, 5 min + 3 s, 90 s + 3 s, and a
   1 s delay (the digital clock configuration of the tiebreak).  The
   ms-ish counter word near the node table (`03 4a` -> `03 4c`) remains
   unnamed.
3. (Mostly closed) opcode-`04` squares are file-major and class `0x80` =
   from/to move arrows (verified by game-tree correlation, 10/14 + 4/8
   hits versus chance). The Reader14 VM run (2026-09-07) adds: opcode-`04`
   records themselves produced **no distinct rendered overlay** in any
   captured frame (class `0x200` @84 s/271 s, class `0x80` @265/279/341 s
   — all silent on screen while the checkpoint-carried annotations
   render), supporting the reading of opcode-`04` as authoring-action
   metadata (selection/publish-state) rather than a drawing primitive.
   Class semantics beyond `0x80` remain open but are not render-blocking.
4. (Closed 2026-08-30) Cursor ids above `0xff` exist corpus-wide (Strategy
   lectures reach `0x1af`), so the bit-`0x80` variation-flag hypothesis is
   retired; ids enumerate serialized tree nodes. Remaining: pin the
   node-id → host-position mapping (which decode pass assigns node
   numbers during the `06`→`02` replay).
5. Correlate `.cms` FEN branches with the decoded game-tree IDs.
6. Feed decoded timestamped events into Scidb instead of linear time-to-ply
   approximation — landed (2026-08-30):
   `media-console/wmv2timeline.py` emits the sync sidecar (`--plytimes`
   writes one media-ms per line, replay order); `tcl/media-sync.tcl`
   (`::media::sync::load-timeline`) consumes it and `drive()` maps each
   elapsed mark to one navigation step instead of linear ply mapping,
   with the existing rewind/restart and 4-plies-per-tick caps intact;
   `application::media::LoadSyncSidecar` auto-loads `<video>.plytimes`
   sidecars at playback start (the linear fallback remains when absent).
   Remaining: apply the annotation deltas (marks/arrows/comments) to the
   board during playback — the timeline drives the ply only; pixels and
   symbols need the annotation application layer (seek = start from the
   latest opcode-`02` checkpoint, then replay the opcode-`06` deltas).

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

### Checkpoint node-table grammar (WP2, 2026-09-07 — SOLVED; patch slots open)

The checkpoint decoders (`::media::decoder::parse-checkpoint` in
`media-console/experimental-panel/app-media-decode.tcl`, the python-chess
oracle `wp2_checkpoint_oracle.py`, gates `test_checkpoint_wp2.tcl`) pass
all WP2 acceptance gates on the round-08 fixture (all 79 snapshots):
the node table is consumed completely in every snapshot (walked edges ==
the u32le entry-count word: 83 in the first, 87 in the last), and the
main-line walk is 100% legal python-chess — the real MVL-Adams score.
Cross-fixture check: round 01 (Adams-Navara, plain 5-byte entries)
consumes 111/111 entries; round 06's last snapshot partially resists
its patch variant (39/76 — documented limitation, does not gate).

The opcode-`02` checkpoint body (from the identity strings onward) parses
as follows on the round-08 fixture (MVL-Adams, 2325-byte last snapshot):

- After the six identity strings: packed date (year-only), annotator
  LP-string (`Robot 11`), Elo pair u16le (white first: 2731/2740 ✓),
  second packed date (full precision), fixed words, `FIDE` u32-length
  strings ×2, ms constants `5f 90 00 00 0b b8 03 e8 03` — this
  header-tail signature locates the table in every fixture (identical
  relative position on rounds 01/06/08) — followed by the **u32le
  entry-count word** (83 first / 87 last on round 08, 111 on round 01;
  it equals the number of table entries and tracks the table growth).
  RETIRED reading: the word @0x5e (0x0087 = 135) is a CONSTANT in all
  fixtures — not a node count.
- The node table starts right after the entry-count word (0x101 on
  round 08) with entries:
  `[u8 from][u8 to][u16le collection-count][count × ([u16le len]
  [u32be type][u16be echo][payload len-6])][u8 pad=0]`
  = 5 bytes when undecorated (the plain-entry edge case), 17 bytes for
  the common single-type-7 decoration (`01 00 0a 00 00 00 00 07 00 0a
  00 <4-byte payload>`), longer with arrow/text collections.
- Edges are **file-major 0-based** (`e2`=0x21, `e4`=0x23); the stream is
  the depth-first serialized game tree with variations interleaved.
- Oracle result (python-chess 1.11.2): the **first checkpoint's** edge
  stream walks **100% legally** and reproduces the full MVL-Adams score
  (`e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 O-O c3 d5 exd5
  Nxd5 Nxe5 Nxe5 Rxe5 c6 d3 Bd6 Re1 Bf5 Qf3 Qh4 g3 Qh3 Be3 Bxd3 Nd2
  Qf5 Bd4 Rae8 Kg2 h6 a4 Qxf3+ Kxf3 Re6 axb5 axb5 Kg2 ...`), consuming
  the entire checkpoint with 4 bytes trailing.  84 nodes at t=1.5 s.
- INSERTION BLOCKS (the patch; per-item semantics open): later
  checkpoints insert blocks after node entries whose pad byte reads
  `01`/`02` instead of `00`.  Framing byte-verified across 20+
  consecutive-checkpoint diffs: the blocks grow by whole 5-byte units,
  with `[u16le count][count × 5-byte slots]` chains.  The slots carry
  (from,to) square pairs in two phase layouts — verified contents
  include type-5-style ARROWS (e.g. round 06's inline collection
  `[count 1][len 12][type 5][echo 12][02 27 23 02 23 24]` = the two
  arrows g5→d8, d8→c7 known from the 2cba grammar) AND variation
  square pairs that are legal moves at tree positions (lower bound 51
  on round 08's last snapshot: 88 main-line nodes + 51 verified
  variation slots = 139 >= the max goto cursor 114).  The exact
  per-slot semantics (annotation vs tree edge, and the two layouts'
  distinction) remain open; the decoder skips the whole patch
  structurally (strict decorated-signature resync first, plain-entry
  fallback — two fixture families).

### WP3/WP4 status (2026-09-07, glm-5.3:cloud pass)

The pure-Tcl move applier (round-08 gates) and the lesson-v2 model are
implemented and gated: 87/87 edges walk legally, the applier's 88
position FENs byte-match a python-chess replay (raw ep convention,
`fen(en_passant='fen')` on both sides), lesson::get on round 08 yields
source=sidecar, 99 timeline pairs, 108 events, cache + persist
round-trip.  The plan's "114+ positions" gate is honestly unmet at 88:
the 51 off-mainline nodes live in the patch slots above (open
semantics) so no ordered edges exist for them yet; gotos beyond the
walkable tree are a WP5 clamp/degrade concern.  Open: round 01's edge
stream dead-ends at edge 58 (h4-g5 illegal at every ancestor under
python-chess) — an upstream parse/resync or non-standard-start
question, not an applier issue; the lesson build degrades to valid=0
with a reason there.
