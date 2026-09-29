# LLM Reach Wave — Implementation Plan

**Source:** `LLM_FEATURES_RESEARCH.md` Appendix C (proposal, uncommitted draft, 2026-09).
**Scope:** turn the C1–C11 proposals into an ordered, verifiable implementation plan.
**Status:** plan only — no code changed by this document.

## Thesis

Appendix C's own diagnosis is the plan's organising constraint: *the bottleneck is
reach, not capability*. The assistant already has ~40 tools, a fact pack, a claim
checker and a report pane. The work is therefore **integration**, not new
subsystems. Every task below must reuse the existing pipeline:

```
selection/context → fact pack (::scidb::ai::text / moveFacts)
                  → prompt → provider
                  → claim check (ai-claims) → retry
                  → ::application::ai::toHtml → showReport
```

A task that introduces a second grounding path is out of scope (C.5, "One
grounding path").

## Verified integration points

Confirmed present in the tree before planning (file:line):

| Symbol | Location | Used by |
|---|---|---|
| `::application::ai::analyze` | `tcl/app-ai.tcl:157` | reference pipeline for C1/C3/C6 |
| `::application::ai::toHtml` | `tcl/app-ai.tcl:129` | all rendering |
| `::application::ai::showReport` | `tcl/app-ai.tcl:122` | report pane |
| `::ai::engine::classify` | `tcl/ai-engine.tcl:368` | C1, C3, C6 |
| `::ai::engine::evaluate` (returns `pv`) | `tcl/ai-engine.tcl:289` | C3 |
| `::scidb::ai::moveFacts` / `::scidb::ai::text` | `src/tcl/tcl_ai.cpp:38-39` | C1, C2, C3 |
| `::application::assistant::ask` | `tcl/app-assistant.tcl:362` | C8, C11 |
| `::application::assistant::runTool` | `tcl/app-assistant.tcl:558` | C10 |
| `::application::assistant::BuildQuery` | `tcl/app-assistant.tcl:1294` | C4 |
| `::application::assistant::DoSearchGames` | `tcl/app-assistant.tcl:1244` | C4 |
| `::scidb::game::update comment` | `tcl/comment.tcl:381` | C6, C7 |
| `::scidb::html::sanitize` (returns `anchors`) | `src/tcl/tcl_database.cpp:139`; dict keys at `tcl/app-ai.tcl:110` | C10 |
| AI test suites | `tests/Makefile:47` (`ai-tests`, 11 suites) | all |

## Status table

| # | Task | Effort | Risk | Depends on | Status |
|---|---|---|---|---|---|
| 1 | C1 selection → explain | S | L | — | Done |
| 2 | C4 NL search box | M | M | — | Done — superseded by `PLAIN_LANGUAGE_SEARCH.md` (adds CQL patterns) |
| 3 | C3 explain the PV | S | M | — | **Done** |
| 4 | C6 draft a comment | M | M | — | **Done** |
| 5 | C8 assistant entry points | S–M | L | C1 mapping | Planned |
| 6 | C9 missing read-only tools | S–M | L | — | Planned |
| 7 | C2 status-line hint | S | L | — | Planned |
| 8 | C5 find similar games | S–M | L | — | Planned |
| 9 | C7 explain/translate comment | S | L | C1 | Planned |
| 10 | C10 report action links | M | M | C9 | Planned |
| 11 | C11 task templates | S | L | — | Planned |

Sequencing follows Appendix C.6: highest-frequency, lowest-new-code first.

---

## Task 1 — C1: Selection → explanation

**Status: Done** (see `LLM_FEATURES_RESEARCH.md` B.27). All six steps implemented; the
three context menus are wired and verified.

**Goal.** Right-click "Explain" on a move / game row / comment produces a grounded
explanation in the report pane, using the selection as context.

**Steps.**
1. Add `::application::ai::explainSelection {kind payload}` in `tcl/app-ai.tcl`,
   dispatching on `kind` ∈ {move, game, comment}.
2. `move`: build facts via `::scidb::ai::moveFacts $san $fen` +
   `::ai::engine::classify`; reuse the `analyze` prompt/claim-check/retry body
   (factor the shared body out of `analyze` rather than copy it).
3. `game`: reuse `DoCurrentGame`'s PGN (`tcl/app-assistant.tcl:889`) +
   `position_moves`.
4. `comment`: read via `::scidb::game::query`; explain the text.
5. Wire context menus: notation pane (move), game list (row), comment editor.
6. Render through `toHtml` / `showReport`; show placeholder immediately, replace
   on completion (C.5 latency honesty).

**Guardrail.** Identical claim-check + retry as `analyze`; report pane shows the
verified/unverified verdict.

**Verify.** `make -C tests ai-claims ai-narrate`; manual: select a move, Explain,
confirm the report cites the move and flags any ungrounded claim.

---

## Task 2 — C4: Natural-language search box

**Goal.** A field above the game list accepts prose and produces the *existing*
advanced-search selector, shown for editing before it runs.

**Steps.**
1. Add the field to the database tab UI.
2. On submit, call the model to fill the fixed field dict only (never query text).
3. Reuse `BuildQuery` (`tcl/app-assistant.tcl:1294`) and the `search_games`
   validation in `CheckArgs` verbatim.
4. Render the generated criteria as editable chips; on confirm call the existing
   `::scidb::view::search` path (same as `DoSearchGames`).

**Guardrail.** Never auto-execute (P5); the model emits *fields*, not query text.

**Verify.** `make -C tests ai-tools`; manual: "Carlsen's losses as Black in the
Najdorf since 2015" → editable criteria → run → result set matches a hand-built
search.

---

## Task 3 — C3: Explain the engine's line

**Goal.** A button in each analysis pane narrates the engine's current PV in words.

**Steps.**
1. Read `pv` from `::ai::engine::evaluate` (`tcl/ai-engine.tcl:289`).
2. Feed the PV through `::scidb::ai::moveFacts --line` for per-move facts.
3. Generate narration; render in the analysis pane (not a separate report pane).
4. Cache by position hash (C.5) so repeats are free.

**Guardrail.** Narration must cite the engine's own eval and PV; the claim checker
flags any move not in the line.

**Verify.** `make -C tests ai-engine ai-narrate`; manual: run an engine, click
Explain, confirm every narrated move is in the PV.

---

## Task 4 — C6: Draft a comment in place

**Goal.** A "Draft" button in the comment editor proposes a grounded comment for
the current move; the user edits and saves.

**Steps.**
1. Add the button to `tcl/comment.tcl`.
2. Build facts via `classify` + move facts + precedent.
3. Run the claim checker before display; flag ungrounded claims inline.
4. Fill the text widget only — save stays on the existing
   `::scidb::game::update comment $key $pos $comment` path (`tcl/comment.tcl:381`).

**Guardrail.** Never auto-save; the user is the review queue (P4).

**Verify.** `make -C tests ai-claims ai-annotations`; manual: draft, edit, save,
reopen — comment persisted through the existing path.

---

## Task 5 — C8: Assistant entry points beyond the pane

**Goal.** Invoke the assistant from a global shortcut, a right-click "Ask the
assistant about this…" (pre-filled with the selection), and the CLI.

**Steps.**
1. Add a global keyboard shortcut that opens/focuses the assistant pane.
2. Add a context-menu item that builds a context preamble from the selection,
   reusing Task 1's selection→payload mapping.
3. Pass the preamble to `ask` (`tcl/app-assistant.tcl:362`), which already accepts
   a request string and `-observer`.
4. Confirm the existing `--ask` / `--chat` terminal path (`attach`, `RemoteRead`)
   still works.

**Guardrail.** Mutating tools still confirm, exactly as the chat path does.

**Verify.** `make -C tests ai-tools`; manual: right-click a game row → Ask →
pane opens pre-filled with that game as context.

---

## Task 6 — C9: Tools for the panes the assistant cannot see

**Goal.** Read-only tools for: current game's comments as structured records, the
game-list selection, the report pane contents, and the board's move history.

**Steps.**
1. Add thin `Do*` handlers in `tcl/app-assistant.tcl`, modelled on the existing
   ones (e.g. `DoCurrentGame` at line 889).
2. Read the comment store via `::scidb::game::query`; read the game-list
   selection; read the report pane's current document.
3. Register each in the tool table with read-only metadata.

**Guardrail.** Read-only only; any write stays behind the existing confirm gate.

**Verify.** `make -C tests ai-tools`; manual: ask "what does this game's comment
say" and "what is selected in the game list" — both answered.

---

## Task 7 — C2: Hover / status-line hint

**Goal.** A one-line hint for the current position or hovered move, cached by
position hash.

**Steps.**
1. Reuse `::scidb::ai::text` for the deterministic line.
2. Optionally pass through the provider for phrasing, cached by
   `hash(fen, template_version, model)`.
3. Degrade to the deterministic line when no provider is configured (P3/offline).

**Guardrail.** Must work *without* a model — the model is an enhancement, not a
dependency.

**Verify.** `make -C tests ai-facts`; manual: with no provider configured, the
status line still shows the deterministic fact-pack line.

---

## Task 8 — C5: Find games like this one

**Goal.** One click finds the most similar games in the active database and
explains *why* they are similar.

**Steps.**
1. Take the current game's positions; look them up in the precedent index
   (keyed by sha1).
2. Rank candidate games by shared-continuation overlap.
3. Generate the "why similar" text from the overlap facts only.

**Guardrail.** The rationale is generated from overlap facts, not invented.

**Verify.** `make -C tests ai-precedent`; manual: run on a known game, confirm the
listed games share the cited opening/positions.

---

## Task 9 — C7: Explain / translate a comment in place

**Goal.** Right-click a comment → "Explain" (expand a terse note) or "Translate"
(into another language slot).

**Steps.**
1. Reuse the comment read/write commands and the language slots scidb already
   stores.
2. Reuse Task 1's `explainSelection` for the "Explain" case.
3. Translation transforms existing human text — no facts invented.

**Guardrail.** Low-risk by construction (transformation, not generation).

**Verify.** `make -C tests ai-annotations`; manual: translate a comment into a
second language slot and confirm both are stored.

---

## Task 10 — C10: "Do this for me" from a report

**Goal.** Report-pane action links after an explanation: "show these games",
"start an engine here", "annotate this move".

**Steps.**
1. `::scidb::html::sanitize` already returns `anchors`; map a custom scheme
   (`ai:tool:search_games?...`) to `runTool` (`tcl/app-assistant.tcl:558`).
2. The anchor names a tool from the fixed table with checked arguments.

**Guardrail.** Same gate as the chat path; mutating tools still confirm.

**Verify.** `make -C tests ai-ui ai-tools`; manual: click "show these games" after
an explanation and confirm the search runs.

---

## Task 11 — C11: Multi-step task templates

**Goal.** Named, one-click assistant tasks that chain existing tools.

**Steps.**
1. Add a small `{label request}` table ("Prepare against the player in the game
   list", "Summarize this database", "Check my repertoire against my games").
2. Surface in the assistant pane and the Extras menu; each calls `ask $request`.

**Guardrail.** Pure prompt presets — no new code paths.

**Verify.** `make -C tests ai-tools`; manual: each template produces the same
result as typing the request by hand.

---

## Cross-cutting requirements (apply to every task)

- **Latency honesty.** Ambient features (Tasks 1, 3, 7) show a placeholder
  immediately and replace it; never block the pane the user is working in.
- **Cache by position hash.** Tasks 3 and 7 are invoked repeatedly on the same
  position; the content-addressed cache makes repeats free.
- **One grounding path.** Tasks 1, 3, 4 and 10 route through the same
  fact-pack → prompt → claim-check → retry pipeline as `analyze`.
- **Graceful absence.** With no provider configured, Task 7 falls back to the
  deterministic line; Tasks 1/3/4/10 show a "configure AI" affordance rather than
  failing.

## Verification strategy

Per task: run the narrowest relevant suite from `tests/Makefile`
(`ai-claims`, `ai-engine`, `ai-tools`, `ai-precedent`, `ai-annotations`,
`ai-narrate`, `ai-facts`, `ai-ui`) plus a manual UI check.

Before each commit: `make -C tests ai-tests` (11 suites) must stay green, and
`make -C tests tcl app-tcl` must stay green (the repo's standing gate — see
`LLM_FEATURES_RESEARCH.md:1222`).

## Out of scope (per Appendix C.7)

- No new grounding machinery.
- No new write path.
- No autonomous action.
- No model reasoning about the board.
