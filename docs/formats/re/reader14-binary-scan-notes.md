# Static binary scan — annotation-color tractability (2026-09-07)

Quick handoff note from the scid-code session, after the Reader14 oracle
closed the script-stream color question (green-only).  This records what
the harvested binaries do and do not support for any future static pass
on the remaining style-3/4 visual semantics (needs a licensed CBase26
or CBReader14.exe disassembly; corpus playback showed style 4 renders
green-or-nothing, style 3 has one unverified corpus occurrence).

## Chess32.dll — RULED OUT as renderer (do not re-scan)

- Only 4 imports total: KERNEL32 Sleep, USER32 PostMessageA,
  SHELL32 SHGetPathFromIDListA, ole32 CoTaskMemFree.
- No GDI/GDI+ imports at all; it is a small integration/COM helper,
  not the board/annotation renderer.
- COLORREF byte-pattern hits are noise: the 8 hits for standard green
  (0x00800000) are all inside `.rsrc` (icon/bitmask palettes, file
  offsets 0x29a1d-0x29a62 within `.rsrc` 0x29a00); the yellow/red
  "hits" in `.text` are mid-instruction byte soup (e.g. file 0x51fb
  falls inside `or $0x40,%cl` sequences — overlapping FF/00 patterns,
  not immediates).

## CBReader14.exe — the actual renderer, needs a real plan

- Imports GDI color APIs: SetTextColor (IAT 0x00adf8f8),
  CreateSolidBrush (0x00adf95c); 18 MB PE — a serious disassembly
  project (Ghidra/radare), not a strings/byte-grep pass.
- Tractable anchors for such a pass: cross-reference
  CreateSolidBrush/SetTextColor call sites for a palette table
  (look for a 3-5 entry COLORREF array near the annotation draw path —
  the VM corridor-measured arrow green is approx RGB(50-100, 155-185,
  34-80), i.e. COLORREF ~0x0050AA32 .. 0x80B9AA22-family, likely
  0x00AA32-ish if a single constant).
- Expected payoff is bounded: the VM oracle already proves script-stream
  style bytes carry no color; static analysis can only pin the
  .cba-style classic palette and style 3/4 edge behavior, which is
  optional polish now that flatten-to-green is proven correct.

## Harvest contents (for reference)

`~/sas_mirror/vm-harvest-2026-09-07/`: CBReader14.exe (18 MB, renderer,
imports GDI), Chess32.dll (192 KB, ruled out above), ChessBaseAdminTool.exe,
Eco.cbcod / EcoMoves.cod / World.cbw / WorldEx.cbw (data), cbread_strings.txt
(pre-extracted CBReader14 strings).