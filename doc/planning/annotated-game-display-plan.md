# Plan: Display Annotated Chess Games

Status: Phases 1-4 complete (2026-09-06) — Phases 3-4 mostly corrected premises

## Phase 4 results (2026-09-06)

**Corrected finding, again: browser.tcl is deliberately minimal, not a
missing-parity gap.** Read `browser.tcl`'s own layout renderer (`UpdatePGN`,
`browser.tcl:1075` — a separate implementation from `app-pgn.tcl`'s
`DoLayout`, not a shared one as an earlier note assumed) before touching
anything:
- Comments, NAGs, and marks are explicitly, deliberately skipped in the
  browser's move rendering (`annotation - marks { # skip }`,
  `browser.tcl:1135`).
- `setupStyle`'s `browser` branch hard-codes `showDiagrams no`,
  `showEmoticons no`, `showVariationNumbers no`, `paragraphSpacing no`
  regardless of any option (`pgn-setup.tcl:485-490`) — diagrams and
  annotation display are intentionally off for this context, not
  unimplemented.

This is coherent given what the browser pane actually is: a small,
transient game-preview popup with its own live board widget already
showing the position — not a second full annotated-game viewer. Bringing
it to full parity with the editor (inline diagrams, marks-on-preview-board,
comment/NAG text) would be a real, unrequested feature addition changing
the character of an intentionally lean widget, not a bug fix — not done.

**One genuine, narrow bug found and fixed**: `browser::open`
(`browser.tcl:114`) never called `::pgn::setup::setupStyle browser
<position>` / `::pgn::setup::setupNags browser` at pane-creation time
(unlike the editor's `build`, `app-pgn.tcl:342`). Both calls exist and are
correctly invoked later — on `refresh` (`browser.tcl:476`) and on the setup
dialog's close handler (`pgn-setup.tcl:740-741`) — but never on first open.
Net effect: a freshly opened browser window (before the user ever visits
its own setup dialog in that session) rendered with whatever column-style/
NAG-symbol choice some other context (typically the editor) last set
globally, ignoring the browser's own persisted preferences. Fixed by adding
both calls right after `position` is allocated in `open`, before any
widget or layout work. Both are pure C++ state setters with no Tk
dependency, so this is safe to call before the pane's widgets exist.

Verified: full app suite 32/32; headless startup smoke test passes (exit
134 — the pre-existing, Makefile-tolerated teardown-on-destroy artifact
seen throughout this session's probes, not a regression).

## Phase 3 results (2026-09-06)

## Phase 3 results (2026-09-06)

**Corrected finding: the Phase 1 gap analysis was wrong here too.** Variation
folding — Fold All / Unfold All / Fold All But Current Line — is already
fully implemented, wired to both the toolbar and the context menu, and has
been all along. No new engineering was needed; this phase reduces to source
verification of already-shipped code, not a build.

- `Game::setFolded(bool)` (`db_game.cpp:4529`): `setFolded(true)` calls
  `m_startNode->fold(true)` (recursively marks every variation at every
  level as folded via `MoveNode::fold`, `db_move_node.cpp:878`), then walks
  up from `m_currentNode` via `getLineStart()`/`prev()` unfolding each
  ancestor variation's line start (`MoveNode::unfold`, `db_move_node.cpp:1093`
  clears `IsFolded` on `getLineStart()`). That combination *is* "fold
  everything except the path to the current move" — exactly ChessBase's
  "Fold All But Current Line", already implemented as a side effect of what
  the code names "fold on". `setFolded(false)` unfolds everything (the same
  up-walk is harmlessly redundant when nothing is folded) — "Unfold All".
- Both already exposed: context menu "Collapse Variations"/"Expand
  Variations" (`app-pgn.tcl:2748-2758`, bound to `variation fold on|off`)
  and matching toolbar buttons (`app-pgn.tcl:299-307`,
  `Vars(button:fold-variations)`/`Vars(button:expand-variations)`, via
  `FoldVariations` at `app-pgn.tcl:3038`).
- Auto-unfold-to-current-move on navigation — also already implemented:
  `ProcessGoto` (`app-pgn.tcl:1441`) calls `::scidb::game::variation unfold`
  (no `-force`) whenever the current key changes, which maps to
  `Game::unfold()` (`db_game.cpp:4441`) — walks up from `m_currentNode`
  unfolding each folded ancestor, i.e. exactly "reveal the path to wherever
  you just navigated."
- Per-node click-to-toggle-fold (single variation, not all) also predates
  this plan: `ToggleFold`/`m:fold`/`m:expand` tags (`app-pgn.tcl:2159-2296`).

Not added: a genuine regression test locking this behavior in. A headless
probe via `::scidb::game::variation folded? <key>` kept hitting
`isValidKey` precondition failures on the key values inferred from the raw
edit-node layout stream (the "begin" node's second field is not the key
`folded?`/`isFolded` expects) — the real, supported entry point is a Tk
text-mark lookup (`FindKey` in `app-pgn.tcl:609`, used by the live click
handler), which needs the actual rendered widget rather than raw layout
introspection. Given this is pre-existing, unmodified code (not a change
made in this session), verification was done by direct source reading
(cited above) rather than by fighting an unfamiliar key format for
additional confidence — a real end-to-end regression test (driving the
actual `pgn::editor` Tk widget headlessly) is a reasonable follow-up but
was not force-fit into this session.

## Phase 2 results (2026-09-06)

Implemented `$220`/`$221` (ChessBase-standard diagram NAGs) as an opt-in PGN
export option, off by default (existing `$155`/`$156` output unchanged —
regression test `annotated-diagram-04` still passes as-is).

Corrected two premises from the Phase 1 audit before implementing:
- The claim "`nag::fromChessPad` has zero callers, therefore dead" was wrong —
  it's composed into `nag::map` (`db_common.ipp:496`), which the PGN reader's
  `parseNag` already calls. **Import already correctly maps `$220`→`Diagram`**
  (verified with a round-trip probe, not just re-reading the diff).
- Writer/PgnWriter's 32-bit flags word is **fully exhausted** (bits 0-31 all
  claimed: `Flag_Write_Any_Rating_As_ELO=1<<30` is `Flag_LAST`, and
  `PgnWriter::Flag_Append_Games = Flag_LAST << 1` already claims bit 31). No
  room for a new bitmask flag without a breaking type change, so the new
  option is a plain `PgnWriter::setUseChessPadDiagramNag(bool)` member
  (default false) instead — additive, no existing call site needs to change.

Changes: `db_annotation.h` (`Flag_Use_ChessPad_Diagram_Nag`, a small
independent flags namespace unrelated to Writer's exhausted one),
`db_annotation.cpp` (`print()` emits `$220`/`$221` when the flag is set;
also fixed `DiagramFromBlack` having no dedicated case at all before —
previously always fell through to a bare `$156`), `db_pgn_writer.{h,cpp}`,
`app_application.{h,cpp}` (new trailing `useChessPadDiagramNag` param,
default false), `tcl_game.cpp` (new `-chesspad-diagram-nag` option on
`::scidb::game::toPGN`).

Verified: manual round-trip probe (`$220` in → `Diagram` internally →
`$220` out with the flag set; `$155` unchanged without it); new regression
test `annotated-diagram-nag-export-04b`; full app suite 32/32;
`verify_cbh_write` round-trip passed.

## Phase 1 results (2026-09-06)

New: `tests/corpus/annotated_games.tcl` (adversarial annotated PGN corpus),
`tests/test_app_annotated_display.tcl` (10 layout-pipeline tests, all passing;
runs in the app harness via `make app-tcl`), `tests/annotated_layout_probe.tcl`
(manual edit-node dump tool). Full app suite: 31/31 passed.

Audit findings — the pipeline is healthier than the gap table assumed:
- `[%csl]/[%cal]`, Scid `[%draw]/[%mark]/[%arrow]`, `[%clk]/[%emt]/[%eval]`
  are all stripped from displayed comment text; csl/cal and Scid syntaxes both
  become marks (`MarkSet::extractFromComment`, `db_mark_set.cpp:97`).
- Marks are position-scoped: `::scidb::game::query <pos> marks` returns them
  only when the annotated node is current — already the best-practice behavior.
- ChessBase `$220` is mapped to internal `$155` **on import** (also bare `D`
  comments, `db_pgn_reader.cpp:3735`). Export still emits `$155`/`D`
  (`Annotation::print`, `db_annotation.cpp`), so Phase 2 reduces to the
  writer direction only: emit `$220/$221` (config-gated).
- NAG grouping (prefix/infix/suffix), 7-NAG pile-up, depth-4 nested RAVs,
  multibyte comments all round-trip through the layout stream correctly.
- Test-harness gotchas: `::scidb::game::new <slot>` errors if the slot exists
  (guard with catch; import replaces content); the app boot script clobbers
  common global vars (`pgn`, `dir`) — compute paths before sourcing it.

## Background

Scidb already ships a complete annotated-game display pipeline — this feature is a
gap-closing and polish effort, not a greenfield build.

- C++ core builds a display AST (`edit::Node` tree, `src/db/db_edit_node.h`) from
  `MoveNode` (`src/db/db_move_node.h`: comments Ante/Post, up to 7 NAGs
  (`db_annotation.h`), marks (`db_mark.h`), variations).
- `src/tcl/tcl_game.cpp` serializes the AST to Tcl node lists
  (`edit::Visitor` subclass at :385, subscriber push at :1130).
- `tcl/app-pgn.tcl` renders it: `DoLayout` :1206, `InsertMove` :1539,
  `PrintComment` :1839, `PrintNumericalAnnotation` :1977, `InsertDiagram` :1715
  (NAGs 155/156), marks, `[%clk]/[%emt]` move info, multi-language comments,
  incremental updates, click navigation, middle-click position preview.
- `tcl/browser.tcl` is the read-only viewer sharing the same engine
  (contexts: editor / browser / merge).
- NAG glyphs: `tcl/fonts.tcl` (`splitAnnotation` :1741, `mapNagToUtfSymbol` :1733).
- ChessBase mark syntax parser exists: `Mark::parseChessBaseMark`
  (`db_mark.cpp` :359) for `[%csl]`/`[%cal]`.

## Gap analysis (vs. ChessBase / SCID vs PC / ChessX / lichess research)

| Capability | scidb today | Benchmark | Verdict |
|---|---|---|---|
| Comments, NAG glyphs, variations, indent | full | SCID/ChessBase parity | audit only |
| Inline diagrams in notation | NAGs 155/156 + `InsertDiagram` | only ChessBase does this | keep; fix interop |
| Diagram NAG interop `$220/$221`, `D`/`#` | Scidb-private 155/156 | ChessBase standard `$220/$221` | gap |
| `[%csl]/[%cal]` display | parser + `updateMarks` board overlay | show only at annotated position | verify |
| Variation folding | fold markers + `ToggleFold` per node, **plus already-implemented Fold All / Unfold All / auto-unfold-on-navigate (see Phase 3 results)** | fold all / unfold all / fold all but current line (top Scid-family request) | none — already implemented |
| `[%eval]` | not surfaced | ChessBase eval-profile strip | gap (optional) |
| Machine tags hidden from text | clk/emt handled | hide raw `%csl/%cal/%eval`, render effects | verify |

## Phases

### Phase 1 — Audit & harden the existing display (baseline)
1. Adversarial annotated PGN corpus under `tests/`: deep nested RAVs, pre+post
   comments, multi-language, all NAG classes, `[%csl][%cal][%clk][%emt][%eval]`,
   ChessBase and Scid `[%draw]` mark syntaxes, diagram NAGs.
2. Load each through browser and editor panes; verify comment styling, NAG glyph
   mapping, variation indent per depth, marks shown only at the annotated node,
   raw command tags never leaking into displayed text.
3. Fix defects; add a headless smoke test (style of `tests/test_app_no_media.tcl`);
   new Tcl must pass the merged-script syntax check.

### Phase 2 — Diagram NAG interoperability
Map incoming `$220/$221` → internal 155/156 (and accept trailing `D`/`#`) in the
PGN reader; emit `$220/$221` (config-gated) in `db_pgn_writer` for ChessBase
round-tripping. Contained change: `db_common.h` nag mapping + reader/writer.

### Phase 3 — Variation folding, ChessBase-grade — DONE, pre-existing
Turned out to already be fully implemented (`Game::setFolded`/`unfold`,
context menu, toolbar, `ProcessGoto` auto-unfold) — see "Phase 3 results"
above. No engineering needed; verified by source audit.

### Phase 4 — Read-only viewer polish (browser pane) — DONE, narrower than planned
Browser is a deliberately minimal preview widget, not a second annotated
viewer missing parity — see "Phase 4 results" above. Fixed the one real
bug (setupStyle/setupNags never applied at pane-open time); did not add
diagrams/marks/annotation display, since that would change the widget's
intentional character rather than close a gap.

### Phase 5 (optional) — Evaluation profile
Parse `[%eval]` in `db_move_info_set.cpp` (alongside `%clk/%emt`), surface
per-ply evals through the edit AST move-info path, draw a bar strip under the
notation pane (Tk canvas); click a bar to navigate.

## Ordering & risk
- Phases 1–4 done. Phase 5 separable/droppable, and optional — evaluate
  whether it's still wanted before starting, given how much of the
  original gap analysis (Phases 3 and 4, and part of Phase 2) turned out
  to already exist or to rest on a false premise once actually checked
  against the code.
- Hazards: new panes need `activate`/`closed` procs and the correct grid master
  (see 4d7e2a4, 53227b7); never reintroduce anything named `gamemedia`
  (`tests/test_app_no_media.tcl` asserts absence); chmod 644 touched files
  before committing.
