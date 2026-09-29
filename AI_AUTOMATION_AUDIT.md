# AI Automation Audit — what System One / LLMs can reliably automate

**Scope:** an audit of the tree for user-facing work that a **bounded classifier**
(System One / Jev-class: fixed answer set + confidence gate + rule fallback) and/or a
**grounded LLM** (fact pack → prose → claim check → retry) can automate *reliably*.
Grounded in the code that exists today; see the companion plans
(`AI_PRODUCTS_PLAN.md`, `LLM_REACH_PLAN.md`, `SYSTEM_ONE_FEATURES.md`,
`LLM_FEATURES_RESEARCH.md`, `JEV_USE_CASES.md`).

**The firewall (unchanged):** move quality, evaluations, tablebase outcomes and opening
identity come from Stockfish, the fact layer or the ECO table. A classifier ranks, buckets
and gates; an LLM narrates. Neither is ever the authority on the board.

**Reliability key**
- 🟢 **high** — deterministic decision with a fixed answer set, a threshold and a fallback
  that is today's behaviour; or read-only prose that is claim-checked.
- 🟡 **medium** — needs validation + review, or a new dependency (embedding index, ASR).
- 🔴 **low** — only behind a review gate or as an optimization; not worth it yet.

"Already shipped" is marked so the list is not re-proposed.

---

## 1. Summary table

| # | Feature | Automates (location) | Actor | Reliability |
|---|---|---|---|---|
| **A. Bounded decisions (System One)** | | | | |
| A1 | Event-type bucketing | study plan / brief mix blitz with classical (`ai-studyplan.tcl`, `ai-brief.tcl`) | System One `choice` | 🟢 *(shipped as `ai-event.tcl`; study-plan filter remains)* |
| A2 | Comment language tagging | untagged comments in the multi-language store (`comment.tcl`, `lang`) | System One `choice` | 🟢 *(shipped as `ai-language.tcl`)* |
| A3 | Comment kind facet | comment editor browse/filter (`comment.tcl`) | System One `choice` | 🟢 |
| A4 | Import doctor | raw importer error list (`app-pgn.tcl`, `import.tcl`) | System One `choice` | 🟢 *(shipped as `ai-import.tcl`)* |
| A5 | Duplicate-merge arbitration | ambiguous duplicate pairs (`app-database-maintenance.tcl`, `merge.tcl`) | System One `choice` | 🟢 |
| A6 | New-move novelty label | new move vs precedent index (`ai-precedent.tcl`, `ai-cql.tcl`) | System One `choice` | 🟢 |
| A7 | Auto-annotate ordering | which engine-flagged move gets prose first (`ai-annotate.tcl`) | System One `score` | 🟢 |
| A8 | Voice transcript gate | obviously-wrong transcripts (`app-voice.tcl`) | System One `noul` | 🟢 |
| A9 | Cloud egress gate | prompts that carry private games/comments (`ai-provider.tcl`) | System One `noul` | 🟡 |
| A10 | LLM tier routing | local-vs-cloud provider choice (`ai-provider.tcl`) | System One `score` | 🟡 |
| A11 | Free-text → search fields | natural-language search (shipped; extend pattern set) (`ai-search.tcl`) | System One + model | 🟢 *(shipped)* |
| A12 | Tool pre-routing | single-tool requests (shipped, shadow) (`app-assistant-route.tcl`) | System One `choice` | 🟢 *(shipped)* |
| A13 | Error triage | import/runtime error groups (shipped) (`app-error-triage.tcl`) | System One `choice` | 🟢 *(shipped)* |
| **B. Grounded narration (read-only)** | | | | |
| B1 | Opponent brief prose | prep stats → dossier (`ai-brief.tcl`, `PrepReport*`) | LLM | 🟢 *(shipped)* |
| B2 | Study-plan prose | mistake clusters → plan (`ai-studyplan.tcl`) | LLM | 🟢 *(shipped)* |
| B3 | Opening-report narrative | opening-prep table → article (`app-database-openingprep.tcl`, `db_tree`) | LLM | 🟢 |
| B4 | Maintenance / ECO-trend narrative | maintenance report (`app-database-maintenance.tcl` `EcoTrend`, `MaintenanceSummaryText`) | LLM | 🟢 |
| B5 | Event / crosstable report | event tables → report (`crosstable.tcl`, `eventtable.tcl`) | LLM | 🟢 |
| B6 | Explain the engine's line | PV → words in the analysis pane (`app-analysis.tcl`, `ai-engine.tcl`) | LLM | 🟢 *(shipped)* |
| B7 | Hover/status "what is this?" | deterministic fact line, optionally phrased (`ai-prompt.tcl`) | rules + LLM | 🟢 |
| B8 | Find games like this + why | overlap facts → rationale (`ai-precedent.tcl`) | LLM | 🟢 |
| B9 | Show-your-work evidence | ground each claim in the report (`app-report.tcl`, `ai-claims.tcl`) | rules | 🟢 *(shipped: the fact pack is rendered)* |
| **C. Reviewed writes** | | | | |
| C1 | Draft a comment in place | comment editor "Draft" (`comment.tcl`) | LLM + claim check | 🟡 *(shipped)* |
| C2 | Explain / translate a comment | comment transforms into a language slot (`comment.tcl`) | LLM | 🟡 |
| C3 | Auto-tagging / enrichment | bulk game labels → custom tags (`ai-annotate.tcl`) | engine + LLM, review | 🟡 |
| C4 | Media transcript + lesson outline | audio/video lessons (`app-media-lesson.tcl`, `tcl_media_extract`) | ASR + LLM | 🟡 |
| C5 | Publication / export writer | tournament report / article from a game set (`export.tcl`) | LLM + claim check | 🟡 |
| C6 | Training-set prose notes | puzzle sets (`ai-cql.tcl`) | LLM | 🟡 |
| **D. Assistant reach** | | | | |
| D1 | Entry points beyond the pane | global shortcut, context-menu "Ask about this", CLI (`app-assistant.tcl`) | wiring | 🟢 |
| D2 | Tools for unseen panes | comments/selection/report/history as records (`app-assistant.tcl`) | wiring | 🟢 |
| D3 | Report action links | "show these games", "start engine here" (`app-report.tcl`) | wiring | 🟢 |
| D4 | Named task templates | one-click chained requests (`app-assistant.tcl`) | templates | 🟢 |
| D5 | Correspondence copilot | XFCC move → 3 engine-verified candidates (`app-corr-games.tcl`, `ai-engine.tcl`) | engine + LLM | 🟡 |
| D6 | Self-repair loop | triage → issue file → agent handoff (`app-error-triage.tcl`) | wiring | 🟡 *(half)* |
| **E. Semantic layer** | | | | |
| E1 | Semantic search over comments/media | local embedding index (`ai-annotations.tcl`, `ai-precedent.tcl`) | embeddings | 🟡 |
| E2 | Model-fit + calibration battery | detect device memory, recommend quant, measure (`app-ai-models.tcl`) | rules | 🟢 |
| E3 | Threshold autotune | refit classifier gates from user overrides (`ai-systemone.tcl`) | offline | 🟡 |
| **F. Curation / data (Wave 3)** | | | | |
| F1 | Weekly digest / watchers | scheduled download → import → precedent → report (`app-download-games.tcl`) | rules + LLM | 🟢 |
| F2 | Online-game sync | batch Lichess per account → tag as mine (`app-download-games.tcl`) | rules | 🟢 |
| F3 | Import triage | bucket imported games, ECO-tag (`import.tcl`, `db_eco_table`) | System One + rules | 🟢 |
| F4 | Curation merge review | scheduled dedup, classifier arbitrates doubtful merges (`app-database-maintenance.tcl`) | System One | 🟢 |

---

## 2. Details and contracts

### A. Bounded decisions (System One)

Every item here obeys `SYSTEM_ONE_RESEARCH.md` §4: a fixed answer set, a confidence
threshold (`SCIDB_AI_*_MIN_CONFIDENCE`), and a fallback that is today's behaviour. The
classifier never decides chess truth.

- **A1 Event-type bucketing** *shipped* (`tcl/ai-event.tcl`, Extras + `event_types`
  tool) — `choice` over `{classical, rapid, blitz, bullet, correspondence, simul,
  training, unclear}` from `TimeControl` and the event words. Fallback: the rule,
  else "unclear". Note: `db::get tags` does not expose `TimeControl`, so the rule
  leans on the event words. The study plan report now *shows* the mix of the
  games it audited; a `-time` *filter* remains.
  (`SYSTEM_ONE_FEATURES.md` §2.1)
- **A2 Comment language tagging** *shipped* (`tcl/ai-language.tcl`, assistant
  `detect_language` + the comment editor's "Detect language"). — `choice` over a
  fixed language set plus `{xx, yy}`; a script rule answers Greek/Hebrew/Arabic/
  Korean/kana without the classifier. The editor carries the neutral text into
  the detected slot, so the ordinary save stores it tagged. Fallback: the rule,
  else undecided (the editor does nothing). Also feeds CQL's `:language` filter.
- **A3 Comment kind facet** — `choice` over `{opening, tactics, endgame, plan, eval,
  bio, warning, other}`. Fallback: no facet. Enables filtering a database by comment kind.
- **A4 Import doctor** *shipped* (`tcl/ai-import.tcl`; the file-import log ends with
  the rule-only doctor, the assistant `diagnose_import` uses the classifier). — a
  deterministic code→category→fix table, `choice` only for unknown codes. Fallback:
  today's raw error list. (Also fixed the log's encoding-warning filter, which read
  the wrong argument.)
- **A5 Duplicate-merge arbitration** — dedup is deterministic (`db_search` duplicate
  detection); only *ambiguous* pairs ask the classifier: `{same game, different game,
  unsure}`. Fallback: deterministic dedup. Mutations stay behind the existing confirm gate.
- **A6 New-move novelty label** — `choice` over `{novelty, side line, transposition,
  blunder}` for a move absent from `::ai::precedent`; the engine still answers
  "playable?". Fallback: no label. (Wave 2 novelty radar)
- **A7 Auto-annotate ordering** — `score` the engine-flagged moments so the best prose
  appears first / limited budgets spend on the right moves. Fallback: engine order.
- **A8 Voice transcript gate** — `noul`: is this transcript a plausible command for the
  current context? Fallback: send as today (review mode already exists).
- **A9 Cloud egress gate** — `noul`: does this outgoing prompt carry private games or
  comments? Fallback: send. Low value while the default is local-first.
- **A10 LLM tier routing** — `score` local vs cloud by request + tools touched; log the
  tier beside the provider used. Fallback: the configured provider.
- **A11 Free-text → search** *shipped* (`ai-search.tcl`): rules → model fields → classifier
  pattern id → validated by `BuildQuery` + CQL. Only the **pattern library** can grow
  (each new pattern needs a fixture game).
- **A12 Tool pre-routing** *shipped shadow-first* (`app-assistant-route.tcl`).
- **A13 Error triage** *shipped* (`app-error-triage.tcl`).

### B. Grounded narration (read-only, no writes)

Same pipeline as `::application::ai::analyze`: fact pack → prompt → provider →
`::ai::claims::check` → retry → `toHtml`/`showReport`. No mutation, so the blast radius is
a screen.

- **B3 Opening-report narrative** — feed the opening-prep rows (`db_tree`/ECO stats) to the
  provider; the numbers are already computed, so this is pure summarization.
- **B4 Maintenance / ECO-trend narrative** — `MaintenanceSummaryText`/`EcoTrend` already
  compute the trend table; narrate it. Zero new data.
- **B5 Event / crosstable report** — summarise a crosstable or an event's games (F12).
- **B6 Explain the engine's line** *shipped* — the analysis pane's line context
  menu narrates the engine's PV through the grounded pipeline; the claim checker
  is line-aware (`::ai::claims::check <fen> <text> ?line?`), so a move named from
  the line is grounded even when it is not legal in the current position.
  (`LLM_REACH_PLAN.md` C3). Caching by position hash remains.
- **B7 Hover/status "what is this?"** — `::scidb::ai::text` gives the deterministic line;
  the model only phrases it. Must work with no provider. (C2)
- **B8 Find games like this + why** — rank by shared continuations in
  `::ai::precedent`, generate the rationale from the overlap facts only. (C5)
- **B9 Show-your-work** *shipped (first cut)* — every generated report now carries a
  **Grounding facts** block with the deterministic position facts the model was given
  (`toHtml`'s new facts argument; the generation result carries them). Per-claim
  witnesses (the fact that grounds each individual phrase) remain, since the claim
  checker reports only contradictions. Also fixed the advisory notices, which were
  passed as the verdict flag and never rendered. (Wave 4)

### C. Reviewed writes (claim-checked, user confirms)

- **C1 Draft a comment** — a "Draft" button fills the editor; save stays on the existing
  `::scidb::game::update comment` path. (C6)
- **C2 Explain / translate a comment** — transformation, not generation; write into a
  language slot after review. (C7)
- **C3 Auto-tagging / enrichment** — bulk engine features + LLM labels → custom tags in a
  reviewable, reversible batch. (F13)
- **C4 Media transcript + lesson outline** — `tcl_media_extract` already extracts audio;
  add a Whisper-class ASR adapter (the voice stack already ships `stt-transcribe.py`) and
  store the transcript as searchable annotations with timestamps. (F11)
- **C5 Publication writer** — a tournament/player/opening article rendered through the
  existing HTML sanitizer and exporter; numeric claims checked against the fact pack. (F12)

### D. Assistant reach

- **D1/D2/D3/D4** are wiring, not model work: a global shortcut + context-menu "Ask about
  this"; read-only tools for the comment store, game-list selection, report pane and move
  history; report-pane action links mapped to `runTool`; named task templates. (C8–C11)
- **D5 Correspondence copilot** — XFCC move in → engine → repertoire compare → 3
  engine-verified candidates + "out of book" warning; auto-submit keeps its deterministic
  material gate. (Wave 2)
- **D6 Self-repair loop** — triage → issue file → coding-agent handoff → re-run tests;
  half shipped.

### E. Semantic layer & tuning

- **E1 Semantic search** — a local embedding index over comments/reports/transcripts
  ("games where a commentator mentions opposite-coloured bishops"). New dependency; local
  model by default. (F14)
- **E2 Model-fit battery** — detect device memory, recommend the quant, download, serve,
  run a 10-item battery, report accuracy/latency per backend. Rules, not a model.
- **E3 Threshold autotune** — record every user override of a classifier verdict and refit
  the gates offline. (Wave 4)

### F. Curation / data

- **F1 Weekly digest** — the headless `::application::download::run` already exists; add a
  timer, import, precedent check against the repertoire and a report. Deterministic counts,
  checked prose. (Wave 3)
- **F2 Online-game sync** — Lichess per-game fetch exists; batch by account and tag as
  mine. (Wave 3)
- **F3 Import triage** — bucket tournament/analysis/fragment + ECO-tag via the table. (Wave 3)
- **F4 Curation merge review** — F1 + A5 together. (Wave 3)

---

## 3. Explicit non-candidates (do not automate)

- **Move quality, "who stands better", opening names, tablebase verdicts** — Stockfish,
  the fact layer or the ECO table, never a model (`AI_PRODUCTS_PLAN.md` §0).
- **Free CQL written by a model** — only vetted pattern ids + validated fields
  (`PLAIN_LANGUAGE_SEARCH.md` §2).
- **Autonomous mutation** — every write stays behind the confirm gate.
- **Cloud by default for audio, error logs or private games.**
- **Player-name fuzzy matching as an LLM task** — the merge dialog is better served by the
  deterministic name/ID columns; a classifier only for genuinely ambiguous merges (A5).

## 4. Suggested order (highest reliability × value first)

1. **A1, A2, A4** — bounded, no new data, immediate study-plan/brief/import wins.
2. **B3, B4, B5** — pure summarization of tables the app already computes (zero new data,
   read-only).
3. **B6, B7, B9** — finish the "ambient explanation" wave already started (C2/C3/Wave 4).
4. **A5, F3, F4, F1** — curation reliability (dedup/import/digest).
5. **C1, C2** — reviewed comment writes.
6. **D1–D4** — assistant reach (wiring only).
7. **E1, C4** — the two features that need a new local dependency (embeddings, ASR).
