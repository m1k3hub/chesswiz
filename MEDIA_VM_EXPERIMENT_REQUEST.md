# REQUESTED: controlled CBase26 VM experiment — opcode-04 class/modifier oracle

Filed 2026-09-07 by the scid-code session, for the VM instance doing
ChessBase RE (CBase26 in the Windows VM).  This closes task 3 in
CHESSBASE_MEDIA_RE.md ("a visual oracle for classes 0x200/0/1/0x800/2
and the modifier bits") and the mirrored OPEN item in
../scid-code/DONE_TODO.md.

## What is already known (do not re-derive)

- opcode-04 board-action record, 12 bytes:
  `u32le opcode=4, u32le class, u8 from_sq, u8 to_sq, u16le modifier`
  (probe_chessmedia.py:174-181, app-media-decode.tcl:297-306).
- Census over the CBM168 corpus (742 records, 259 files):
  - class: 0x80 (498), 0x0 (204), 0x200 (33), 0x1 (4), 0x2 (1), 0x800 (2)
  - modifier: 0x0 (468), 0x80 (230), 0x240 (24), 0x20 (12), 0x2 (4), 0x1 (3), 0x10 (1)
  - every observed record has from != to (arrow-shaped)
- DE/EN parallel takes of the same lesson (Projekt02/Project02) carry
  DIFFERENT class values for the same arrow (g5-h5: class 0x800/mod 0x80
  in DE vs class 0x0/mod 0x80 in EN).  Therefore class is NOT a color
  index — it tracks the authoring action or tool state.  Falsified: the
  classic .cba palette (2=green, 3=yellow, 4=red) appearing as opcode-04
  class values (no 3 or 4 ever occurs).
- scid's current renderer (this repo's media-console SyncAnnotate)
  looks up SyncColors("80") -> missing -> every script-stream arrow
  falls back to green.

## The controlled experiment (in the VM)

In ChessBase 26 (or whatever CBase build runs; Reader 14 is the known
fallback for activation), create a MEDIA lesson / training board whose
annotations are saved into the WMV script stream, then:

1. **Color sweep.** During recording, draw the SAME arrow (e.g. g1->f3)
   once in every color the GUI offers (green, yellow, red, and any
   others), pausing between draws so each lands as its own record.
   Save/export the media file.
2. **Style sweep.** If the GUI offers thickness / solid-dash / arrowhead
   options, repeat the same arrow once per style, color constant.
3. **Tool sweep.** Draw the same arrow via different authoring gestures:
   mouse freehand drag vs. keyboard/toolbar shortcut, and (if available)
   once before and once after a recording pause.  This tests the
   class = authoring-action hypothesis directly: class should vary
   while the visible arrow is identical.
4. **Square mark attempt.** Try to mark a single SQUARE (no from->to)
   in the same media context.  Question: does opcode-04 ever carry
   from == to, or do squares go to a different opcode/record?
5. **Keep an intent log.** For each draw, note: intended color, tool,
   thickness, gesture, timestamp.  The dump is useless without it.

## What to deliver back

- The raw media file(s) (or at minimum the extracted script stream
  bytes) plus the intent log, per draw.
- A dump using the existing tooling (probe_chessmedia.py /
  app-media-decode.tcl) showing each draw as: intent -> opcode,
  class, from, to, modifier (and any neighboring opcode-06 records in
  the same stream — those carry the decimal 2/3/4 classes that
  SyncColors understands; we need to know whether script-stream arrows
  EVER carry color, or always render the default green).

## Why it matters

- If color appears (class or modifier bits or an opcode-06 companion
  record), the scid/scidb media panel can render real colors.
- If not, the current flatten-everything-to-green fallback is provably
  correct and the mystery closes as "no color data in this stream".
- Either way the class-bit meaning (publish-state? layer? snap mode?)
  gets pinned by the tool/gesture sweeps.