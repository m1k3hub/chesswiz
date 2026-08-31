# Media Lesson v2 — Implementation Plan

**Status: PLANNED — implementation deferred (approved architecture, not yet built).**

Derived from: `CHESSBASE_MEDIA_RE.md` (corpus-verified RE), the Biel 2015
fixture set, and the v1 implementation (commits `b39ad57`, `0b17b25`).
Everything marked *verified* below was confirmed empirically against the
round-08 fixture on 2026-08-31.

---

## 1. Why v2 is needed (v1's proven failure modes)

v1 ("coupled media-lesson datatype") works end-to-end for the *linear*
stretch of a lecture — user-confirmed 2026-08-31. Its model is still wrong:

| v1 assumption | Ground truth (sidecar) | Consequence |
|---|---|---|
| `gotoIndex` ≈ main-line ply; board advances via `BoardForward` | goto ids are **flat node indices into the serialized game-tree edge stream** (RE: "the 0x80 variation-flag hypothesis is retired"); round-08 gotos are non-monotonic: `…44 → 88 → 89 → 96 → rewind to 44 → 45…51 → 84 → back to 51 → 52…` | board desyncs and stalls through every variation/rewind |
| ffprobe stream-2 decode is the event source | the `.txt` sidecar is the official export (CBase26 strings: `EDITOR`, `GA:`, `Timestamp`, `Action`, `Sequence`, `Game Action`). Round 08 census: sidecar = **380 packets, 99 gotos, range 1..114**; ffprobe path = 98 packets, 37 gotos, max id 75, ms shifted ~2 s (goto5: 16.1 s vs 14.1 s) | 60% of navigation events lost, timing wrong |
| embedded game never decoded | opcode-2 checkpoints are **cumulative snapshots** (RE doc: "its cumulative/checkpoint representation"): round 08 carries 79 of them, 46 distinct decoded sizes growing **1672 → 2325 bytes** as annotations accumulate | the authoritative position table was discarded |

The board can only follow the lecture when all three are fixed together.

## 2. Ground truth inventory (fixture: `fixt/cbm168/Festival Biel 2015.html/`)

### 2.1 The `.txt` sidecar — primary event source (verified)

- One event per two lines: `H:MM:SS.d:` timestamp line, then `GA:` + six-bit
  transport payload (chars `?`..`~` = 0x3F..0x7E, 6 bits each, MSB-first,
  4 chars → 3 bytes).
- Decoded record: `[opcode u32le][payload…]`.
- Round-08 census (380 packets): op 2 (Set Game) ×79 — **cumulative
  snapshots** (46 distinct decoded sizes, 1672 → 2325 bytes: identical for
  the first ~6, then growing as annotations accumulate — keep the
  **last/largest**); op 3 (GotoIndex) ×99 — `[u32le 3][u32le cursor]`,
  8-byte records, cursors 1..114, non-monotonic; op 4 (Board Action) ×108;
  op 6 (Annotation) ×14; op 8 (Promote Line) ×1; op 14 (Sync) ×79.
- Timestamps are media-exact (10ths of a second field, `0:00:12.5` = 12500 ms).
- Not every WMV has a sidecar → keep the existing ffprobe decode as fallback
  (accepting its known losses; document the degradation).

### 2.2 The checkpoint (opcode 2) — the embedded game (header verified)

```
[u32le opcode=2]
[12 zero bytes]                         (fields 9–11; RE: "never change")
6 × [u8 length][chars…\0]               identity strings — round 08:
                                        "Vachier-Lagrave" "Maxime" "Adams"
                                        "Michael" "Biel" "48th Biel Festival 2015"
[u32be packed date]                     0x000FBE00 = 2015 (year-only, first date)
… second date, Windows-1252 annotator slot ("Robot 11" family),
[u16le Elo white][u16le Elo black]      (RE: verified corpus-wide, 218/234)
fixed region: u16/u32 words, "FIDE" strings ×2, u24be ms offsets
(48000/3000/1000 = bb 80/0b b8/03 e8)
node table (tail): per-node entries + inline annotation collections
```

- Node table grammar per the RE doc: 5-byte entries `[u8 from][u8 to]` +
  3 padding bytes; padding hosts inline op-6 collections
  (`[u16le count][u16le len][u32be type][u16be echo][payload]`) and is
  patched with **type-37 per-node media timestamps** (e.g. `0x0001623b` =
  90683 ms). Insertions at growing offsets (334…1479) as annotations
  accumulate.
- **Round-08 observation (new, needs pinning in WP2):** this checkpoint's
  tail shows a regular ~18-byte rhythm
  (`07 00 0a 00 | XX YY 00 00 ZZ WW | 01 00 | 0a 00 00 00 00`) — i.e. most
  nodes are already *decorated*; the "plain 5-byte entry" picture is the
  empty-checkpoint edge case. The alignment of `[from][to]` inside this
  rhythm is WP2's first deliverable, resolved against the python-chess oracle.

### 2.3 Square encodings — one family, two offsets (per the RE doc's closure)

| Layer | Encoding | Evidence |
|---|---|---|
| Edge stream (moves), opcode-4 board actions | **file-major, 0-based** (`a1`=0, `b1`=8, `a2`=1; `c2`=17) | RE: 18/18 vs python-chess (Navara-Adams round 6); the RE opcode-04 section closes op-4 squares as file-major 0-based — "prior rank-major decodings (e8-f8, g6-f6, b4-e7) were coincidental re-readings of the same bytes". The v1 `sq0` (file=v>>3, rank=v&7) is already correct — keep it |
| Op-6 inline graphics (type-4/5 records) | **1-based file-major** (subtract 1, then file-major) | RE doc opcode-06 section; the 64-byte file-major transpose table in CBase26 corroborates file-major throughout |

No rank-major decoding anywhere — earlier rank-major readings were retired
as coincidental. Both layers use the same file-major scheme, differing only
by a 0/1 offset. (Verified numerically: `c2`=17=0x11, `c4`=19=0x13 in the
edge stream.)

### 2.4 Out of scope (tracked, deferred)

- `.cms` binary hotspot format (FEN + `z`-FEN + `x/y/v/u` selectors): the
  position-matched *drill-clip* layer. Current `CmsEntries` regex hack stays.
- `.scm`/`.cms` `[BoardSync]` **persistence** of decoded lessons (write-side
  of this model — a later phase; the RE doc already specifies the section).
- Encrypted script streams (`ScriptActivationManager::IsStreamCrypted`) —
  CBM 168 fixtures are unencrypted; commercial locked media is not covered.
- `.plytimes`/interactive `.smv` sidecars: keep existing behavior.

## 3. Target architecture

```
::media::decoder (tcl/app-media-decode.tcl)
  sidecar-parse <file.txt>        → event list (goto/action/annotation/sync
                                    + checkpoint payloads)
  decode-checkpoint <bytes>       → {header edges nodeTimes annotations}
  decode-wmv <file>               → fallback (existing ffprobe path)

::media::lesson (tcl/app-media-lesson.tcl)
  lesson dict v2 = {valid reason video
                    edges        serialized tree: list of {from to flags}
                    positions    per-node FEN list (index 0 = start)
                    timeline     goto events {mediaMs nodeIndex} ascending
                    events       board actions {ms arrow from to class mod}
                    nodeTimes    {nodeIndex mediaMs} (type-37, optional)}
  get/flush cache as today; source preference: .txt sidecar → WMV fallback

::media::sync (tcl/app-media-sync.tcl)
  load-timeline {ms nodeIndex} pairs; drive(timeMs):
    goal = node index of last pair ≤ timeMs
    if goal != currentNode → BoardGoto goal      (replaces BoardForward stepping)
    rewind (goal < lastGoal) = the same call + annotation reset

::application::media (tcl/app-media.tcl)
  BoardGoto nodeIndex → [::scidb::game::go <slot> position $positions(nodeIndex)]
                        (variation-native; browser.tcl:379 is the precedent)
  PlayLesson: unchanged strict coupling; loads lesson v2 + positions
```

Board driving via FEN-position goto removes the ply/variation problem
entirely: ScidB resolves the tree node; depth-first interleaving,
variation jumps and rewinds all reduce to "go to this position".

## 4. Work packages

**WP1 — Sidecar parser (decoder v2).**
Files: `tcl/app-media-decode.tcl` (rewrite).
Scope: `H:MM:SS.d:` + `GA:` parsing; six-bit decode (char-direct, not hex —
the sidecar payload is the transport itself); record dispatch; checkpoint
extraction (keep the **last/largest** cumulative snapshot, note the count
and the growth curve).
Acceptance (in-repo assertions, no external reference dump): round-08
sidecar decodes to exactly 380 events; 99 gotos with cursors 1..114 in the
known sequence (first 12 monotonic, then the non-monotonic pattern
including 44→88→96 and the ~94.9 s rewind to 44); 108 board actions; ms
values exact (12500 for goto 1, …); checkpoint census 79 records with the
last being the largest. Harness: tclsh, no app dependencies.

**WP2 — Checkpoint decoder (RE package, oracle-driven).**
Files: `tcl/app-media-decode.tcl`.
Scope: header parse (op, 12 zeros, 6 LP-strings, dates, Elo) on the **last**
snapshot; node-table entry alignment for decorated checkpoints; edge
extraction (file-major 0-based); inline collection extraction (op-6
grammar); type-37 per-node times. **Path B fallback (OPEN QUESTION, not a
confirmed escape hatch):** derive `edges/positions` from the loaded .cbh
game's tree via a depth-first walk — the API surface is plausible
(`::scidb::game::move/next/lines/query/fen`) but unverified for a full DFS
with variations; timebox the attempt — if the decorated-entry alignment
resists RE, path B becomes primary and checkpoint decode degrades to
header-only.
Acceptance (HARD GATES): the edge stream walks **100% legally** from the
standard start under python-chess (`python-chess 1.11.2` installed); the
walk's move list matches the MVL-Adams game in `168!Start.cbh`; **node
count ≥ max goto id (114)** — if edge count < max cursor the parse is
wrong, do not proceed; per-node times (if extracted) within video duration.

**WP3 — Pure-Tcl move applier.**
Files: `tcl/app-media-lesson.tcl` (new proc set).
Scope: apply `[from][to]` edges from the start FEN (standard unless WP2 finds
a header FEN); handle castling (king two squares), en passant, promotion
(flag byte from edge padding — pin empirically in WP2; MVL-Adams may not
contain one, Navara-Adams round-6 end `f6-h5`/`h4xe7` suggests none either —
if unresolvable, mark promotion lessons degraded, log, continue); produce
`positions` = per-node FENs in ScidB FEN format.
Acceptance: positions[N] FENs byte-match a python-chess replay of the same
edges for all N — **and** are in ScidB's FEN dialect (R-new2): the applier
must emit FENs that `::scidb::game::go -1 position $fen` accepts and
resolves to real tree nodes of the loaded game.

**WP4 — Lesson v2 model.**
Files: `tcl/app-media-lesson.tcl`.
Scope: lesson dict v2 (above); timeline = goto events sorted by ms;
`source` field (sidecar|wmv) for diagnostics; cache keyed as today;
graceful degradation when only the WMV exists (v1 behavior, documented).
Acceptance: `lesson::get` on round 08 yields valid=1, ≥ 99 timeline pairs,
114+ positions, events in `{ms arrow from to class mod}` order (rank-major
squares transposed to algebraic); cache stable; invalid paths give reasons.

**WP5 — Sync v2 (node-goal model).**
Files: `tcl/app-media-sync.tcl`, `tcl/app-media.tcl` (delegates only).
Scope: `drive` applies node-index goals via a `BoardGoto` delegate; **the
`min(goal, len-1)` ply clamp must NOT apply to node-index goals** (len is a
main-line ply count; node ids exceed it — clamping silently caps variation
navigation); keep legacy bare-int marks (count model) for `.plytimes`
compat; rewind = goto + `BoardClearAnnotations`; **`BoardGoto` is a no-op
when target node == current node**; **re-sync `lastgoal` on manual board
navigation** (a manual move during follow must not trigger a spurious
rewind/reset on the next tick); **verify the `driving?` guard covers the
transport-coupling path** (`::media::sync::step` currently calls
`Transport pause` without a `driving?` check — BoardGoto fires board
subscriptions → step → potential self-pausing feedback loop); **debounce
mpv seek-bar drags** (position bursts → many gotos; same-node no-op plus
jump coalescing).
Acceptance: harness with stub delegates: `drive 12500` → goto 1;
`drive 50800` → goto 88; `drive 94900` → goto 44 (rewind fires reset);
**goto 114 with a 40-node main line is NOT clamped**; annotation events
fire in-window (existing `_fire_events` unchanged); no Transport pause is
triggered by a driving goto.

**WP6 — Panel wiring.**
Files: `tcl/app-media.tcl`.
Scope: `BoardGoto` delegate → `::scidb::game::go **-1** position $fen`
(slot **-1** = the main board game, matching `SyncBoardForward`'s
`::scidb::game::go -1 1`; browser.tcl:379 and ecotable.tcl:441 are the
precedents). **First verify the node-matching semantics on a scratch
harness**: `go position` must resolve to an existing tree node of the loaded
game — if the FEN does not match a node exactly, ScidB may create a
scratch/analysis position and silently detach from the game (breaking
PlayLesson's strict-coupling invariant). Define behavior for the lesson
start FEN (may not be a tree node — the game's initial position). Emit
ScidB-dialect FENs (R-new2); PlayLesson loads v2 lesson; FollowTick/mpv
transport unchanged (working); statusbar shows node/ply context; MediaDebug
lines for goto jumps (throttled).
Acceptance: in-app click test: board follows through the variation section
(~50–95 s: jumps 44→88→96, rewind to 44) and arrows render at their
timecodes; the owning game remains attached after gotos (verify via the
app's game index/debug log, not just visual).

**WP7 — Build, integration, verification pipeline.**
Scope: monolith rebuild (`make -C tcl`), app restart, debug-log trace check,
user click test; commits per repo style; update `CHESSBASE_MEDIA_RE.md`
with the checkpoint tail-grammar findings from WP2 (docs are first-class
here); optionally update `SCM_FORMAT_DESIGN.md` §[BoardSync] to the
node-index model.

## 5. Validation strategy (before any GUI trust)

1. **Oracle walk** (WP2/WP3): python-chess replay of the full edge stream;
   legality of every edge; comparison against the .cbh game score.
2. **Timestamp reconciliation**: sidecar goto ms vs type-37 per-node ms
   where both exist (RE says they agree for Navara-Adams; verify round 08).
3. **Arrow sanity**: for a sample of op-4 actions, the arrow endpoints must
   be occupied by pieces (or plausible empty squares for ideas/moves-to)
   at the goto position active at that ms.
4. **FEN dialect reconciliation**: emit positions in ScidB's FEN format and
   verify `::scidb::game::go -1 position $fen` lands on real tree nodes for
   a sample of positions from the loaded fixture game (scratch harness
   before any app wiring).
4. **Unit harnesses** in `/tmp` (tclsh, stubbed delegates) for every WP.
5. **Integration**: monolith greps, app restart, `PrebuildLessons` logs the
   v2 census, click test through the variation section.

## 6. Risks / open questions

| # | Risk / unknown | Mitigation |
|---|---|---|
| R1 | Checkpoint node-table alignment for *decorated* checkpoints (18-byte rhythm) not yet pinned | WP2 is oracle-driven with HARD GATE node-count ≥ max goto id; path B fallback (open question) |
| R2 | Promotion encoding in edge padding unpinned (no promotion in current fixtures) | degrade gracefully + log; revisit when a fixture with promotion exists |
| R3 | Start position assumed standard (no header FEN found yet) | WP2 checks header; Biel games are standard-start; type-15 variant flagged |
| R4 | `go position $fen` node-matching: python-chess FEN ≠ ScidB FEN dialect; a non-matching FEN may create a scratch position and silently detach the game (breaks strict coupling) | WP6 scratch-harness verification FIRST; emit ScidB-dialect FENs; define start-FEN behavior |
| R5 | Sidecar-less media keep v1 behavior (lossy) | documented degradation; `source` field in lesson |
| R6 | drive() ply clamp (`min(goal, len-1)`) applied to node goals would cap variation navigation (node ids ≫ main-line length) | clamp REMOVED for node-index goals; harness asserts goto 114 unclamped |
| R7 | Transport-coupling feedback loop: `::media::sync::step` calls `Transport pause` without a `driving?` guard; BoardGoto fires board subscriptions → step → self-pausing | verify/extend the driving guard to cover `step`; harness asserts no Transport pause from a driving goto |
| R8 | Manual board moves during follow: `lastgoal` not re-synced → spurious rewind/annotation-reset on next tick | re-sync `lastgoal` to the current node on manual navigation |
| R9 | mpv seek-bar drag bursts → many BoardGoto calls per second | same-node no-op + jump coalescing; drive tick stays at 250 ms |
| R10 | ffprobe fallback now second-class | keep, but mark `source=wmv` lessons degraded in statusbar |

## 7. Sequencing

```
M1: WP1 + WP2 (+WP3)   — decode + oracle proof   (no app changes)
M2: WP4                — lesson v2 available to Tcl consumers
M3: WP5 + WP6          — sync/panel rework (app changes, gated on M1/M2)
M4: WP7                — build, integration, click test, commits, docs
```

M1–M2 are pure engine-side and independently demoable via tclsh harnesses.
M3 touches the app only after the oracle proof. Estimated scope: one
subagent pipeline (architect validation → 4 workers → verifier with
python-chess oracle → fix loop → integration → commits), same shape as v1.

## 8. Deferred (explicit)

- `.cms` binary hotspot parser RE (separate workstream)
- `[BoardSync]` persistence into `.cms`/`.scm` (write-side)
- Encrypted script streams
- Annotation text rendering (op-6 payloads beyond arrows — type-2 game
  quotations etc. are already parsed by WP2 but not yet displayed)