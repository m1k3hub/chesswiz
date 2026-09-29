# System One Features — what the classifier integration makes possible

**Status:** design proposal. No code has been changed by this document.
**Companions:** `SYSTEM_ONE_RESEARCH.md` (what the model class is, plus the reliability
contract in §4), `JEV_USE_CASES.md` (the decision-model contracts), `AI_PRODUCTS_PLAN.md`
(the product slate and the firewall), `LLM_REACH_PLAN.md` (C1–C11).

---

## 0. Why now

With `auto` discovery (`tcl/ai-systemone.tcl`: `autostart` → `discover` → `Reachable`),
the classifier is **on by default** whenever any local server answers (`kev`, `simple-jev`,
`plumb`). Until now it was used for internal decisions: error triage, tool pre-routing,
rhetoric/coverage badges, study-plan and brief labels. The features below give it
user-facing jobs.

This document leaves out items the companion docs already cover: context compaction,
the question-vs-command gate (research §5.3), threshold autotune, novelty radar, import
triage, curation merges.

Every feature obeys `SYSTEM_ONE_RESEARCH.md` §4:

- a fixed set of answers
- a confidence threshold set by an environment variable
- the fallback is today's behaviour
- it never decides move quality, evaluations or tablebase results (the firewall,
  `AI_PRODUCTS_PLAN.md` §0)

---

## 1. Slate

| # | Feature | Question type | What it reads | Fallback | Effort |
|---|---|---|---|---|---|
| 1 | Event-type bucketing | `choice` | Event/Site/Round tags plus the TimeControl tag | TimeControl parse, otherwise `unknown` | S |
| 2 | Comment language tagging | `choice` | the text of an untagged comment | leave it untagged | S |
| 3 | Comment kind facet | `choice` | the text of a comment | no facet | S–M |
| 4 | Cloud egress gate | `noul` | the outgoing LLM prompt | send without a warning (today) | S |
| 5 | LLM tier routing | `score` | the request plus the tools it touched | the configured provider | S–M |
| 6 | Import doctor | `choice` | a group of import errors | today's error list | S |
| 7 | Voice check before sending | `noul` | the speech-to-text transcript | send as today | S |
| 8 | Ordering auto-annotate moments | `score` | the engine verdict plus the fact JSON of moments already flagged by the engine gate | the engine gate's order | S |
| 9 | Follow-up buttons on reports | `choice` | the request plus the report's headline | no buttons | S |

**Suggested order:** foundations (§3) → 1, 2 → 4 → 6, 7 → 3 → 9 → 5 (after its
shadow logs exist) → 8.

---

## 2. Feature contracts

### 2.1 Event-type bucketing

- **Problem:** the study plan (`ai-studyplan.tcl`) and the opponent brief (`ai-brief.tcl`)
  sample games from every time control, so blitz and classical games are mixed together.
- **Decision:** *deterministic, rule-only* (`tcl/ai-event.tcl`). The rule reads the
  `TimeControl` tag, then the `Event`/`Site`/`Round` words; anything it cannot place is
  `unclear`. A classifier is deliberately **not** consulted: the rule resolves every tag
  that carries the information, and the residual's honest answer is `unclear` — naming an
  event's time control from its name alone is world-knowledge recall, and both plumb-4b
  and hosted Jev scored only 10/17 on exactly those inputs
  (`TYPESAFE_API_EXPERIMENT.md`).
- **Consumers:** the study plan and brief (a `bucket` filter, default classical + rapid),
  the Extras → AI: Time Controls report, and the assistant `event_types` tool.
- **Blast radius:** metadata only. A wrong bucket costs a filter miss, never a chess claim;
  the feature has no model dependency at all.

### 2.2 Comment language tagging

- **Problem:** Scidb stores multilingual comments (`tcl/comment.tcl`, "Add language… /
  Switch language"), but imported comments arrive untagged (`xx`). Switching languages
  therefore does nothing for most games.
- **Question:** `choice` over the languages in `::mc` plus `other`.
- **Action:** propose a language tag. Applying it is a reviewable batch edit. For a single
  game, the comment editor shows the proposal as a pre-selected tag.
- **Threshold:** `SCIDB_AI_LANG_MIN_CONFIDENCE`, default 0.8. The threshold is high
  because this writes to the database.
- **Fallback:** the comment stays untagged, as today.

### 2.3 Comment kind facet

- **Question:** `choice` over `{explanation, plan, anecdote, source_citation, engine_dump,
  clock_note, question, unclear}`.
- **Unlocks:**
  - searching for "games with human prose annotations"
  - "strip engine dumps", which is a confirmed batch edit with a preview
  - a cleaner annotation input for `ai-factcheck.tcl`, which can skip `engine_dump`
    comments
- **Threshold:** `SCIDB_AI_COMMENTKIND_MIN_CONFIDENCE`, default 0.7.
- **Firewall:** the classifier reads text only and says nothing about whether the comment
  is correct. Correctness stays with the fact checker.

### 2.4 Cloud egress gate

- **Problem:** the local-first rule (research §4.7). When the configured LLM provider is a
  cloud provider, prompts can carry names of private individuals, email addresses and
  local paths.
- **Question:** `noul` "does this contain personal data (email addresses, names of
  private individuals, local file paths)?"
- **Placement:** in `ai-provider.tcl`, before a request to a non-local provider. It is
  skipped when the classifier backend is itself a cloud backend: sending the prompt to
  that backend for the check would already defeat the purpose.
- **Action:** a one-time warning dialog showing what would be sent: "Send anyway /
  Cancel / Don't ask for this session". It warns and never blocks.
- **Threshold:** `SCIDB_AI_EGRESS_MIN_P`, default 0.6.
- **Timeout:** 1500 ms, after which the request is sent as today.

### 2.5 LLM tier routing

- **Question:** `score` over `{simple, normal, hard}` for the request's complexity.
- **Action:**
  - `simple` → the local Ollama model (`::ai::provider::ollamaModels`)
  - `hard` → the configured frontier provider
  - `normal` → the default provider
- **Rollout:** follow the same path as `app-assistant-route.tcl`. `shadow` (the default)
  logs the tier next to the provider actually used and whether the claim checker had to
  retry. Only then turn on `active`.
- **Safety:** `::ai::claims::check` still runs on every output. If the local model fails
  the check twice, the request is escalated to the next tier.
- **Settings:** `SCIDB_AI_TIER_MODE` (`off|shadow|active`) and
  `SCIDB_AI_TIER_MIN_CONFIDENCE` (0.7).

### 2.6 Import doctor

- **Pattern:** error triage (`app-error-triage.tcl`) applied to PGN/CBH import logs.
- **Question:** `choice` per error group over `{encoding, truncated, illegal_move,
  junk_header, duplicate, other}`.
- **Action:** each label maps to one fixed, deterministic fix, offered as a button:

  | Label | Fix |
  |---|---|
  | `encoding` | re-import with a different encoding |
  | `truncated` | skip the tail |
  | `junk_header` | strip the header |
  | `illegal_move` | open the game at that ply |

  The user confirms every fix.
- **Threshold:** 0.6. Below it, the group is shown as today.

### 2.7 Voice check before sending

- **Question:** `noul` "is this transcript a coherent request to a chess assistant?"
- **Placement:** in `app-voice.tcl`, between speech-to-text and `ask`.
- **Action:** if p < `SCIDB_AI_VOICE_MIN_P` (default 0.3, deliberately low), show
  "Didn't catch that — repeat?" instead of starting an LLM round trip.
- **Worst case:** the user repeats the utterance once.

### 2.8 Ordering auto-annotate moments

- **Precondition:** the engine gate in `ai-annotate.tcl` has already chosen which moves
  are worth comments. The classifier never adds or removes a moment.
- **Question:** `score` over 4 levels for "how instructive is this moment to a club
  player?"
- **Use:** only when the user caps comments per game (new setting,
  `annotate.maxComments`). The classifier decides which N of the engine-flagged moments
  get prose.
- **Fallback:** the engine's order (the size of the centipawn loss).

### 2.9 Follow-up buttons on reports

- **Question:** `choice` over the C10 report actions (`LLM_REACH_PLAN.md`: explain the
  PV, find similar games, draft a comment, open the position, …) plus `none`. Take the
  top 2 above the threshold.
- **Cost:** batched into the existing rhetoric/coverage call in `ai-rhetoric.tcl`, so no
  extra round trip (research §5.2).
- **Safety:** the actions come from a fixed list, so the classifier can't invent one.
  Clicking a button runs `runTool`, so argument checks and the confirm gate still apply.
- **Depends on:** C10.

---

## 3. Foundations to build first

1. **Check returned labels.** `::ai::systemone::Answers` should reject a label that isn't
   in the offered set and treat it as `ok 0`. Features 1–3 and 6 write to the database,
   so an unexpected label must never be stored.
2. **Thresholds per backend.** Add `::ai::systemone::threshold <feature>`, which looks up
   `(feature, backend)` in a table and falls back to the environment variable. Why: under
   `auto` the resolved backend is often `kev`, while the current defaults were calibrated
   on plumb (research §6.2).

   **Shipped** (`::ai::systemone::loadThresholds`, auto-loaded from
   `SCIDB_AI_THRESHOLDS` or `tcl/ai-thresholds.tsv`). The table is filled
   by `scripts/calibrate-systemone.tcl` from a labelled battery
   (`tests/fixtures/systemone-battery.tcl`, math in `tcl/ai-calibrate.tcl`,
   tests in `tests/test_ai_calibrate.tcl`): it measures a backend on the
   *production* question, sweeps the confidence threshold, and writes the
   most-coverage threshold that meets a target accuracy. A feature that
   cannot meet the target is **not** written, so a calibration can never
   loosen a gate. Live runs (2026): on `plumb-4b-v5`, `comment_kind`
   → 0.85 (coverage 0.57, accuracy 0.94) and `language` → 0.75
   (coverage 0.84, accuracy 0.94); on hosted `typesafe` (jev-latest),
   `comment_kind` → 0.0 (1.00 / 0.967) and `language` → 0.0
   (1.00 / 1.000). `event_type` is not calibrated because it is now
   rule-only (§2.1, `TYPESAFE_API_EXPERIMENT.md`).
3. **Batch helper.** Features 1–3 run over whole databases (100k+ games). They need:
   - a queue with limited concurrency over `evaluateAsync`
   - de-duplication by state hash
   - a progress bar
   - resuming after interruption from a sidecar cache
   - dropping silently to the fallback when `enabled` turns false partway through

   **Shipped** (`tcl/ai-batch.tcl`, `::ai::batch::run`, tests in
   `tests/test_ai_batch.tcl`). It is policy-free: each item yields its raw
   answer (`{ok 1 answer A source classifier|cache}`) or an error
   (`{ok 0 error E}`), and the caller applies `::ai::systemone::valid` and
   its own threshold, exactly as `::ai::decide` would. The cache is
   append-only and keyed by (endpoint, model, question, state), so a changed
   backend or question never reuses a stale answer and a crashed run resumes
   from the last persisted answer.
4. **Override log.** Every time the user rejects a proposed label or tag, record it. This
   feeds the Wave 4 threshold autotune with real labels.

   **Shipped** (`tcl/ai-journal.tcl`, tests in `tests/test_ai_journal.tcl`).
   The *decision* half is wired: `::ai::decide` installs
   `::ai::journal::logged` in front of every caller's script, so turning on
   `SCIDB_AI_JOURNAL=<file>` records every gate's `(feature, state, label,
   confidence, source)`. The *override* half is the exposed
   `::ai::journal::override <feature> <state> <proposed> <corrected>` API;
   the UI accept/reject hooks (e.g. the comment language slot) call it.

---

## 3a. Primitives

### Layer A — one gated decision (implemented)

In `tcl/ai-systemone.tcl`:

```tcl
::ai::decide <feature> <state> <question> <script> ?-fallback CMD? ?-threshold T?
# script gets {ok 1 label L confidence C source classifier}
#          or {ok 1 label L confidence {} source rules}   (CMD's result)
#          or {ok 0}                                       (no CMD)
::ai::systemone::valid     <question> <answer>   ;# shape + offered label + [0,1]
::ai::systemone::threshold <feature> <default>   ;# env, then per-backend table, then default
```

- The threshold is looked up in this order: `SCIDB_AI_<FEATURE>_MIN_CONFIDENCE`, then
  `::ai::systemone::Thresholds {feature {backend T}}`, then the default. The table is
  empty until thresholds are calibrated per backend.
- For a `noul` question, the label is 1 or 0 (p ≥ threshold) and the confidence is p.
- `score` is not supported yet: the wire shape of its answer hasn't been verified
  against a server.
- **Callers moved over:**
  - study-plan pattern (feature `pattern`) and brief stance (feature `stance`): these
    now go through `::ai::decide`
  - rhetoric: its `validAnswer` now calls `valid`
  - error triage: now uses `valid`, so a label that wasn't offered no longer settles a
    group

### Layer B — primitives typed by database object (planned)

These go in a new `::ai::db` namespace. Each builds a short state from a Scidb object and
calls `::ai::decide`.

| Primitive | What it classifies | Question type | Cached per |
|---|---|---|---|
| `label event/site BASE IDX LABELS` | an event or site table entry | `choice` | entry |
| `label comment POS KEY LABELS` | the text of one comment | `choice` | text hash |
| `label header BASE GAME LABELS` | the game's tags only | `choice` | game |
| `label facts FACTS LABELS` | the fact JSON only (FEN/PGN is refused) | `choice` | fact hash |
| `match player/event/site BASE A B` | a pair of entries | `noul` | pair |
| `rank ITEMS QUESTION LEVELS` | a list of short states | `score` | item hash |
| `sweep VIEW PRIMITIVE` | every entry in a view: limited concurrency, resumable | — | via the cache |

- **Cache key:** `(base, object type, id, hash of the state, backend/model)`, stored in a
  sidecar file next to the database.
- **`match` never merges anything itself.** It returns a probability; merging is still a
  step the user confirms.
- **Open question:** filtering a view by label needs `customFlags` or a search over a
  list of game numbers. Check the `::scidb::view::search` API first.

### CQL

CQL (`src/db/cql/`, `src/app/app_cql_engine.*`) is exact position-pattern matching, so it
sits on the **ground-truth** side of the firewall, next to Stockfish and the fact layer.
It is reachable from Tcl as `::scidb::cql::parse|match|search`
(`src/tcl/tcl_cql.cpp`, tests in `tests/test_app_cql.tcl`). It also filters the game
list as a `cql <script>` search term (`::scidb::view::search … {cql …}`), combinable with
the header terms. `flipcolor` is implemented. Keywords that aren't built yet (the other
flips and `shift*`, `accumulate`/`sumrange`, `following`/`preceding`, `variations`,
comment filters) are refused with `Not_Implemented`. Plain-language search
(`PLAIN_LANGUAGE_SEARCH.md`) uses the classifier as the last of three ways to pick a
vetted CQL pattern.

- **The classifier never judges whether a game matches.** CQL decides that.
- **CQL can be a fact source for the classifier.** Motifs CQL can express become fields
  in the state that `label facts` reads, so rules replace guesses.
- **The classifier fits in front of CQL** as a pre-router: a `choice` over a library of
  vetted CQL templates, the same pattern as tool pre-routing. The parser validates the
  query and the user confirms before it runs.

---

## 4. Reliability summary

| Feature | Writes data? | Needs user confirmation? | What a wrong answer costs |
|---|---|---|---|
| 1 Event bucket | sidecar metadata | no (can be re-run) | a filter miss |
| 2 Language tag | comments | yes (batch review) | one wrong tag, which can be undone |
| 3 Comment kind | facet; stripping only if confirmed | yes, to strip | a search miss |
| 4 Egress gate | no | — | an extra dialog, or a missed warning |
| 5 Tier routing | no | — | a slower answer, or an escalation after the check fails |
| 6 Import doctor | only when a fix is applied | yes | a wrong suggested fix, which the user declines |
| 7 Voice check | no | — | one repeated utterance |
| 8 Moment order | the comments that get written | the game is left modified, unsaved | a less instructive moment gets prose |
| 9 Follow-ups | no | the tool's own gate | an irrelevant button |

None of these features lets the classifier decide move quality, an evaluation or a
result. None fails differently when no server is running: without a classifier, each
behaves exactly as the app does today.

---

## 5. Tests

- Extend the mock `/v1/systemone` server in `tests/test_app_systemone.tcl` so each feature
  can check:
  - the gate taken on a confident answer
  - the fallback on a low-confidence answer, a malformed reply, an unknown label, a
    timeout, and no server at all
- Add a new `tests/test_ai_batch.tcl` for the batch helper: concurrency cap, dedupe,
  resume, and a server that disappears partway through.
- Register the new suites in `tests/Makefile` `ai-tests`.
