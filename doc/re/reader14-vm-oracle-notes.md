# VM visual-oracle session — working notes (2026-09-07)

## Environment
- Win11-Oracle VirtualBox VM, CBReader14 (Reader 2017, 14.17), no activation wall
- Playback driven via guestcontrol PowerShell mouse clicks + host keyboardputscancode (Space)
- Play button at native (637,369); single click = play. DOUBLE-CLICK TOGGLES PAUSE (cost us 20 min)
- Board calibration (1024x768 screen): board inner x 48..560, y 179..691, pitch 64
  (verified: round-9 a4 square-mark blob lands exactly on a4 centre)

## Biel 2015 round 06 (Navara-Adams) — 70 frames @7.9s
Records (probe_chessmedia.py, full list incl. non-sidecar records):
- 60.642 OP6 delta arrows=[green:e7-h4, green:h4-g3]        → RENDERED (corridor 51%, cap_04)
- 84.142 OP4 class=0x200 a5,a3 mod=0x1                      → NOTHING VISIBLE (frames 7-12 baseline)
- 170.642 OP6 arrows=[green:c1-b3, green:b3-c5]             → NOT FOUND on corridors (caps 17-24)!
- 265.142 OP4 class=0x80 g2,f2 mod=0x0                      → bursts at cap_31/33 (diagonals near e4/e6?)
- 279.142 OP4 class=0x80 d5,c7 mod=0x0                      → cap_33/34 burst (g3 vertical n=51)
- 343.142 OP6 [good-move symbol; arrow green d6-g6]         → RENDERED (corridor 55%, cap_40/41)
- 467.7/468.7 OP4 class=0x80 (d5,b4)(c3,b4) mod=0x80        → cap_50/52-53 bursts?
- 475.181 OP6 arrows=[green d2-d1, green a4-d1] + mark a4   → RENDERED (75%, cap_57/58) + round green blob EXACTLY a4 (n=451)
- Green last-move wedges = the ~135px baseline in every frame
- Arrow green over dark squares ≈ RGB(70-100, 155-185, 34-75); wedge green similar hue

## Sinquefield Cup round 9 — 10 frames
- r9cap_036/039 (t≈41-45): NO b1-b5 arrows (34.763 event) — arrows already gone or never drew
- r9cap_217 (t≈223): BIG green diagonal band c3..g5 (n=568, rgb(92,175,69)) — c1→g5 (record 100.763) persisted ~120s?
- r9cap_220-232: green gone; **style-4 "red" d2→c3 @222.138 drew NOTHING** — d2-c3 corridor pixel-identical to clean board
- No red/yellow/blue/magenta overlay anywhere in the board interior in ANY frame
- Clearing happened t≈224-226, i.e. ~2-4s AFTER the 222.138 record — either a delayed clear, an unlisted clear, or arrow lifetime

## Working hypotheses
1. opcode-6 style 2 = draw GREEN arrow — CONFIRMED (3 independent corridor hits + square mark on a4)
2. opcode-6 style 4 = NOT a red arrow in Reader14 — drew nothing visible (corridor 0 px diff). Either:
   a) style 4 = clear-annotations action, or
   b) style 4 renders something invisible/subtle, or
   c) style 4 arrows render briefly (<1s)
   Need round 8 (red e1-e4 @735.271) as the second style-4 data point.
3. opcode-4 records (class 0x80/0x200): no clean corridor match yet; square decode in probe may be
   file-major-distorted; rendered bursts exist (cap_31/33/46 etc.) — geometry unresolved pending scout eyes.
4. Arrow persistence is inconsistent (Biel E1 <8s? round-9 c1-g5 ~120s) — maybe cleared by the NEXT
   opcode-6/4 record with different latency, or animation-dependent.

## Harvested from VM (Track 2)
- /tmp/vm_harvest/: Chess32.dll, CBReader14.exe (+strings), ChessBaseAdminTool.exe, Eco.cbcod (4.2MB),
  EcoMoves.cod, World.cbw, WorldEx.cbw
- Registry: HKCU\Software\ChessBase (CBReader14 settings/recent), HKLM WOW6432Node Install_CBReader_RC
- Reader14 media stack: native WMCreateSyncReader; strings ScriptItems/SetGames/GotoIndex:/HeumasFlags
- No CB databases anywhere in VM; no CBase26 installed (serial-wall product); .cms/.cbm authoring not
  available in Reader14 (playback only) — the MEDIA_VM_EXPERIMENT_REQUEST.md sweeps need CBase26 + serial

## Pending
- scout 1 (ac52de7a): 9 board crops description — arrows geometry for unexplained bursts
- scout 2 (17cc59e4): timer readings for r9cap frames — pins playback t0
- Then: round 8 style-4 second datapoint @735s if needed
- Then: sync colours are STILL only style-2-proven; SyncColors stays hypothesis for 3/4
## LATE FINDINGS (2026-09-07 evening) — Biel round 09 deep-dive

### CRITICAL BUG FOUND: probe_chessmedia.py square decode is FILE-MAJOR, the reader is RANK-MAJOR
- Raw op-6 item @127.138: t4 value=[04 2c] -> probe says "red:f4"; byte 0x2c=44 in RANK-MAJOR = **e6**
- The rendered overlay (image read) = GREEN ARROW e6->e3 — tail at e6 ✓✓ byte 44 = e6 confirmed
- So probe's square_name() must be changed to rank*8+file, and every corpus square derived from it
  re-checked (the "d2-c3" @222.138 is really c4->d3: bytes 0x1a=26=c4, 0x13=19=d3 rank-major)

### opcode-6 record types (raw-verified)
- type=4, len=8, value=[style u8, square u8]  (2 bytes) — rendered as ARROW e6->e3 at 127s (style byte 4!)
  -> but an arrow needs from+to; [4,44] has one square + style. Either the t7 item carries the second
     square, or type-4 implies a direction. t7 @127s = [index=0, 06, 00].
- type=5, len=9, value=[style, from, to] (3 bytes) — @222.138 = [04, 26, 19] = c4->d3 (rank-major)
- type=7, len=10, value=[index u16, square u8, flag u8] — appears alongside every delta
  (@127: idx0/06/00, @222: idx3/0x33/00, @261: idx2/0x34/00)
- The .events sidecar styles (2/3/4) = these type-4/5 style bytes. Style 4 in corpus x336.

### RENDERED COLOURS (decisive observations)
- opcode-6 style 2 arrows/marks: GREEN (multiple corridor hits 51-75% + a4 mark blob exactly a4)
- opcode-6 style 4 @127s (t4 [4,44=e6]): rendered GREEN arrow e6->e3 — NOT red!
- opcode-6 style 4 @222s (t5 [4,c4,d3]): NOTHING visible in the c4-d3 corridor across 5 frames (30s)
- No red/yellow/blue/magenta overlay found anywhere in 136 frames across 3 videos
- => **the script-stream style byte does NOT carry colour in Reader14** (or maps 4->green too).
   The flatten-to-green fallback in scid's SyncAnnotate is CORRECT for script-stream arrows.
- Caveat: Reader14's palette could differ from CBase26's; the DE/EN class!=colour evidence + this
  suggests colour is decided by the AUTHORING TOOL STATE, not stored per-record.

### Checkpoints carry annotations
- Round 09 @212.138 SetGame(len 1410) -> thick diagonal band c3..h5 appears (no delta records!)
- Round 9 @220.263 SetGame(3198B, Nakamura-Grischuk) -> identical band at 229s
- The band = annotation embedded in the checkpoint's serialized game tree (arrow saved earlier)
- Delta at 222.138 + checkpoint @224.138 grew by exactly 12 bytes = one annotation record appended
- opcode-6 t7 item = [index u16][square u8][flag u8] looks like "attach at node index, square" (goto+annotate?)

### Timer OCR (cracked, no OCR lib needed)
- Timer format H:MM:SS (green 7px digits, occupancy signatures: 0=4742474, 3=53386, 4=2333991, 9=1753571, 5=65355)
- Frame->elapsed mapping now exact; Biel09 frames: c9_18=~131s, c9_29=~212-221s, c9_36=~266s

### VM automation lessons
- Double-click on play toggles pause; single click plays
- copyto needs double-backslash target paths; --target-dir unsupported on this VBox version
- The deepseek-v4-flash scout model cannot view images (returned "counsel..." spam) — use pixel analysis or larger models

### Format-coverage harvest (files in /tmp/vm_harvest/, to be archived in the repo)
Chess32.dll, CBReader14.exe (+strings: WMCreateSyncReader, ScriptItems, SetGames, GotoIndex:, HeumasFlags,
ScriptActivationManager::{IsStreamCrypted,GetProductId,GetCryptKey}), ChessBaseAdminTool.exe,
Eco.cbcod (4.2MB), EcoMoves.cod, World.cbw, WorldEx.cbw, registry keys (HKCU ChessBase settings/recent)
