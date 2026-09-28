# System One Models: programmatic/algorithmic use cases, and what they imply for Scidb

**Status:** research note (external survey + codebase audit). No code changed.
**Companions:** `JEV_USE_CASES.md` (the decision-model contracts), `AI_PRODUCTS_PLAN.md`
(the product slate and the firewall), `LLM_REACH_PLAN.md` (grounding pipeline).
**Scope:** what a "System One" model *is*, what it is *for* programmatically, what
the independent evidence says about it, and how that maps onto — and should
constrain — what is built in this tree.

---

## 0. Method and definitions

"System One" is used in two distinct senses in the wider world, and this tree uses
the second:

1. **Kahneman's System 1** — fast, intuitive, associative judgement, as opposed to
   slow verbal reasoning (System 2). LLMs imitate System 2.
2. **The "System One model" class** (TypeSafe AI, Sept 2026) — a *decision model*
   that reads a state and answers **typed, calibrated questions** in one forward
   pass. It writes no prose. This is what `::ai::systemone` implements.

A System One model is therefore not a small chatbot and not a "fast LLM". It is a
**classifier/scorer with a wire contract**. Its three primitives are:

| Primitive | Answer | Shape |
|---|---|---|
| `choice` | one of a caller-supplied list of options (Jev: up to 255) | winning key + per-option probabilities + confidence |
| `score` | a position on an ordered 2–10 level scale | fractional score + distribution + confidence |
| `noul` | a calibrated yes/no | a single probability in [0,1]; **no `confidence` field** |

One request carries `model`, `state` and a map of `questions`; every question is
answered in the same round trip. The canonical endpoint is `POST /v1/systemone`
(`https://api.typesafe.ai/v1/systemone`), answered in ~70–500 ms.

**The codebase already commits to this class and abstracts over it.** `tcl/ai-systemone.tcl`
is a single Tcl client for four backends, all speaking the same contract:

| Backend | Where | Model | Key |
|---|---|---|---|
| `kev` (default) | `127.0.0.1:8009` | `kev-latest` (Kev-4B family) | `KEV_API_KEY` |
| `simple-jev` | `127.0.0.1:8000` | `Qwen/Qwen3.5-0.8B` | `SIMPLE_JEV_API_KEY` |
| `plumb` | `127.0.0.1:8090` | `plumb-4b-v5` (JevK5 GGUF + shim) | — |
| `jev` / `vercel` | Vercel AI Gateway | `typesafe-ai/jev` | `AI_GATEWAY_API_KEY` |

API: `::ai::systemone::evaluate` / `evaluateAsync`, `configure`, `enabled`,
`describe`, `backends`. The backend is chosen in `Extras > AI: Choose Model`
(`tcl/app-ai-models.tcl`), saved as `Settings(classifier)`, overridable by
`--ai-classifier` / `SCIDB_AI_CLASSIFIER`, with `SCIDB_AI_CLASSIFIER_URL` and
`..._MODEL` overrides. That is the correct shape for a fragmented ecosystem: 60+
open Jev-class models exist, all Jev-compatible.

---

## 1. What the ecosystem actually offers (and how good it is)

### 1.1 The reference: TypeSafe Jev

- Hosted-only, weights undisclosed; family versions `jev-1.13.0` / `jev-latest` /
  `jev-preview`. Pin in production, because a calibrated model's thresholds shift
  between releases.
- Pricing $0.042/M input tokens, output free (~$0.001/decision); rate limits
  1,200 req/min, 250k tok/s; context 64k tokens (32k for state + one question).
- Founded by Diogo Almeida with Erik Gafni and Sasha Sheng; $40M seed led by DCVC.
- Named for the **Jevons paradox** as well as System 1.

### 1.2 The independent evidence on calibration (the reason the class exists)

DecisionEval's end-to-end run of Jev 1.13.0 on 400 cases / 2,000 decisions:

| Metric | Value | Notes |
|---|---|---|
| Accuracy | 0.740 | Choice 0.738, score 0.705, noul 0.787 |
| Brier (vs gold distribution) | 0.148 | |
| ECE (10 bins) | **0.045** | the calibration number that matters |
| Latency | P50 687 ms / P95 777 ms | 5 decisions per request, network included |

And the table that actually answers "how much can I automate?":

| Confidence gate | Coverage | Accuracy within coverage |
|---|---|---|
| none | 100% | 0.740 |
| ≥ 0.7 | 57.6% | 0.864 |
| ≥ 0.9 | 24.5% | 0.937 |

This is the entire case for the architecture: **a threshold is a safety dial, and
calibration is what makes the dial meaningful.** An ECE of 0.045 means a stated
0.9 really is ~90%.

Two caveats the same source surfaces and that any integrator must internalise:

- The 0.740 averages a task with a defensible answer against one without: teachers
  agreed 0.841, disagreed 0.591. "Confidence" can be high on an ill-posed question.
- **Confidence shows how concentrated the answer is, not that it is correct.**
  A key smash scored 86% "AI-written" on a public slop demo; confident-and-wrong is
  the failure mode, not hesitant-and-wrong.

### 1.3 JevBench: the open ecosystem and the generalisation gap

JevBench v1.4.2 / v1.4.2.1 (842 decisions/system: 534 public + 308 sealed;
harmonic mean of intelligence, calibration, speed, cost):

| Rank | System | Score | Notes |
|---|---|---|---|
| 1 | **Plumb-4B** (crh225, JevK5 v0.2 + LoRA) | 65.8 | the model this tree serves via a shim |
| 1–2 | decider-4b v2 (Mapika) | 64.1 | Apache-2.0 open reproduction |
| 2–3 | Jev 1.13.0 (TypeSafe) | 63.3 | leads Intelligence + Calibration; hosted |
| 3–4 | JevK5 v0.2.0 (allebee) | 62.0 | runtime this tree's `plumb` shim uses |
| 4–5 | Cygnet (frozen Gemma-4-12B) | 61.8 | no fine-tune at all |
| ~28 | kev-4B (jaredpalmer) | 36.1 | the default backend's family |
| ~53 | kev-0.6B / ~40 jeff-400M | 24.8 / 30.6 | CPU-runnable, weak |

The published **public→sealed generalisation gap** is the sobering part: Jev
scores 86.6% on the public items and **36.7% on the 308 sealed ones** (chance
29.3%); decider-4b v2 shows the same ~49 pp gap. Independent suites corroborate
the limits: Jev *loses* Banking77 to Gemini 3.8 Flash (79.7% vs 84.6%), ties it on
PubMedQA, and on HelpSteer2 no system beats guessing the base rates. The lesson for
this tree: **a System One model is good at bounded, familiar classification and
weak at genuinely novel reasoning**, so it belongs in pre-filters and gates, never
as the last word.

### 1.4 The local backends this tree ships, characterised

- **Kev** (`jaredpalmer/kev`, Apache-2.0, ~7k stars): a LoRA + pointer head on a
  Qwen base; the *default* here is the 0.8B/4B family. Card numbers: in-distribution
  0.825 / out-of-domain 0.652 (0.8B); 0.872 / 0.797 (4B). Each checkpoint ships a
  fitted temperature (Kev-4B T=2.41), which takes confident-error rate from 8–10% to
  <1% without changing argmax. Crucially for cost planning: **coverage at a 5% error
  budget is 0.54 (Kev-4B) versus Jev's 0.70.**
- **Plumb-4B** (`crh225/plumb-4b`, Apache-2.0): a JevK5 v0.2 + LoRA rebuild, rank 1
  open system on JevBench v1.4.2.1. The tree runs it through
  `scripts/plumb-systemone-server.py`, a `/v1/systemone` shim over `llama-server`
  with the JevK5 readout (option-letter logits, temperature **2.07**, knockout passes
  for >16 options). bf16 needs ~10 GB, so the GGUF path (Q8_0 ~4.5 GB) is what fits
  an 8 GB card.
- **Simple-Jev** (`featherless-ai/simple-jev`): a tiny Qwen 0.8B served through the
  same contract; the cheapest smoke-test backend.

Known model properties that must shape integration (from the model cards):

- **Option-order sensitivity** of `choice`: flip rate is ~0 (Jev) but up to 0.08
  (Kev, JevK5). The assistant pre-router asks a 27-option `choice`; ordering is not
  neutral.
- **>16 options need a knockout runtime.** JevK5 0.2.x rejects a >16-option choice;
  ≥0.3 (and the tree's GGUF shim) does knockout passes. This is exactly why
  `app-assistant-route.tcl` documents a 27-invocation allowlist and "the local
  server needs a runtime with knockout passes."
- **Short training context.** Kev trained on states ≤384 tokens; long states degrade.
  The tree truncates state aggressively for this reason (`routeState` 2000 chars,
  `rhetoric::state` 4000 chars, brief prep 3000 chars).
- **Knowledge is set by the base**, not the decision head; MMLU-style questions are
  the weakest axis. Do not route knowledge questions to a System One model.

---

## 2. Programmatic/algorithmic use cases (a taxonomy)

Vendor material and independent write-ups converge on the same short list. Each
maps cleanly onto one of the primitives and onto a *placement* in a program:

| Use case | Primitive | Placement | What the code does with it |
|---|---|---|---|
| **Route/classify** a request to a handler | `choice` | in front of a dispatch | run handler / tool |
| **Score/prioritise** (risk, urgency, quality, fit) | `score` | before a queue or ordering | threshold + sort |
| **Gate/guardrail** (allow / hold / escalate) | `noul` | before an action | act if p ≥ t else fallback |
| **Pre-filter** for an expensive model | `choice`/`noul` | before an LLM call | skip the LLM when confident |
| **Second opinion** on generated text | `choice` | after a deterministic checker | add an advisory badge |
| **Arbitrate** between mechanical outcomes | `choice` | before a merge/dedupe | pick a category, low-confidence → human |
| **Label** a deterministic finding | `choice` | after facts are computed | human-readable category |

Named patterns from the ecosystem that are worth knowing by name:

- **The fuzzy `if`**: too fuzzy for a hand-written rule, too small for a frontier
  LLM. This is the class's whole lane.
- **Model routing**: grade a request's complexity and send it to fast/balanced/frontier.
- **Guardrail tool calls**: score command risk before an agent runs it (Kev/decider
  behaviour probes literally measure "command risk" and "touches-outside-project").
- **Context compaction**: decide keep/truncate/drop for each stale tool result —
  verbatim, no lossy rewrite.

### 2.1 What is *not* a System One use case

The vendors and the tree's own `JEV_USE_CASES.md` §4 agree, and stating it is as
important as the positive list:

- **Generation of any kind.** No prose, no extraction of values, no invention.
- **Anything with ground truth already cheaper and exact.** Chess: move quality,
  "who is better", opening names, tablebase verdicts. Those are Stockfish / the C++
  fact layer / the ECO table. This is the tree's **firewall** (`AI_PRODUCTS_PLAN.md`
  §0), and the external evidence supports it: a text classifier reading a FEN would
  be guessing against a signal the engine already computes exactly.
- **Knowledge-heavy questions** on a small local model.
- **Anything the deterministic checker already does.** A classifier second-guessing
  `::ai::claims::check` is less reliable, not more.

---

## 3. What is built in this tree (audit)

Every System One integration point, with the question type, the gate, the fallback,
and where it sits.

### 3.1 The client — `tcl/ai-systemone.tcl`
Single pluggable client; `evaluateAsync` is non-blocking and the callers treat any
`ok 0` as "no classifier". Config is never hard-coded into logic.

### 3.2 Error triage — `tcl/app-error-triage.tcl` (the proof point)
- **Question:** one `choice` per error group over `{bug, environment, user, noise}`.
- **Gate:** `MinConfidence = 0.6` (`SCIDB_AI_CLASSIFIER_MIN_CONFIDENCE`).
- **Fallback:** groups the classifier does not settle go to the language model,
  which also writes the issue file. **Only non-bug verdicts are settled by the
  classifier**; a confident-wrong "non-bug" merely delays a bug (the LLM pass still
  runs), it cannot hide one.
- **Why it is safe:** bounded output, confidence-gated, fallback = status quo, and
  **no chess facts are at stake** (the state is an error report).

### 3.3 Assistant tool pre-routing — `tcl/app-assistant-route.tcl` (+ `JEV_USE_CASES.md` §3.A, §7)
- **Problem:** the assistant routes every request through an LLM tool loop (seconds);
  a bounded classification is ~0.5 s locally.
- **Two gates, both must pass** (a second-opinion correction, §7):
  1. `route` — `choice` over an allowlist **derived at call time from the Actions
     table** (bare tools, all-optional tools at defaults, single-required-enum tools
     expanded per value → 27 invocations), plus an `existing_assistant` sentinel.
  2. `satisfied` — `noul`: "names one simple action and contains no specific values."
     ("show twenty continuations" fails this even though `position_moves` is right.)
- **Thresholds:** route ≥ 0.7 (`SCIDB_AI_ROUTE_MIN_CONFIDENCE`), satisfied ≥ 0.4
  (`SCIDB_AI_ROUTE_MIN_SATISFIED`) — different scales, because `noul` has no
  confidence and distributions differ. Calibrated on a 10-request battery against
  plumb-4B (positives ≥0.50, negatives ≤0.26).
- **Modes (default `shadow`):** `shadow` logs the prediction against what the model
  actually did (`route-shadow.log`) with behaviour unchanged; `active` runs the tool
  through the ordinary `runTool` path (so `CheckArgs`, the confirm gate and the tool
  log all still run) and falls back to the LLM loop if the tool errors; `off`
  disables it. A **watchdog** (`SCIDB_AI_ROUTE_TIMEOUT_MS`, 4000) starts the model
  loop rather than let a slow server stall the request.
- **Why it is safe:** bounded enum (cannot invent a tool), two independent gates,
  validate-the-shape before acting, additive (the LLM loop is the fallback), and
  every mutating zero-arg tool still hits the confirm gate.

### 3.4 Advisory rhetoric + coverage gate — `tcl/ai-rhetoric.tcl` (JEV §3.B + §3.F)
- **Problem:** `::ai::claims::check` is deterministic and structurally cannot see
  *rhetoric* ("a stroke of genius" at −1.2) or a *substantive non-answer*
  (fluent, claim-check-passing prose that does not do the task).
- **Questions:** one `choice` over `{ordinary, emphatic_certainty, promotional_hype,
  unclear}` and one over `{addresses_request, generic_nonanswer, refusal_or_deferral,
  unrelated, unclear}` — **both in a single call**.
- **Gate:** rhetoric 0.6 (`SCIDB_AI_RHETORIC_MIN_CONFIDENCE`), coverage 0.7
  (`SCIDB_AI_COVERAGE_MIN_CONFIDENCE`).
- **Output:** a **fixed, application-owned notice string** — the model only picks a
  label, so it cannot inject text. Advisory only: it never changes `grounded`, never
  suppresses a report, never triggers an unbounded regeneration loop.
- **Placement:** after the claim checker passes, inside `::ai::generate::deliver`
  (`tcl/ai-generate.tcl`), merging `notices` into the payload.

### 3.5 Study-plan pattern label — `tcl/ai-studyplan.tcl`
- **Question:** `choice` over `{tactical, opening, endgame, kingsafety, positional}`,
  reading the engine verdict plus the position-fact JSON.
- **Gate:** 0.6; **fallback is a deterministic rule** (`pattern`) over the same facts,
  so the classifier only ever *labels*, never invents. The engine owns what happened.

### 3.6 Opponent-brief stance — `tcl/ai-brief.tcl`
- **Question:** `choice` over a fixed set of strategic stances, reading the
  preparation facts. Gate 0.6; deterministic `ruleStance` fallback; the LLM may only
  restate numbers from the report.

### 3.7 The model chooser — `tcl/app-ai-models.tcl`
Lists the four backends from `::ai::systemone::backends`, with notes on which are
local and what key they need; `Extras > AI: Choose Model`.

### 3.8 Summary table

| Feature | File | Type | Gate | Fallback |
|---|---|---|---|---|
| Error triage | `app-error-triage.tcl` | `choice` | 0.6 | LLM takes the group |
| Tool pre-route (route) | `app-assistant-route.tcl` | `choice` (27) | 0.7 | LLM tool loop |
| Tool pre-route (sufficiency) | `app-assistant-route.tcl` | `noul` | 0.4 | LLM tool loop |
| Rhetoric | `ai-rhetoric.tcl` | `choice` | 0.6 | no badge |
| Coverage | `ai-rhetoric.tcl` | `choice` | 0.7 | no badge |
| Study-plan pattern | `ai-studyplan.tcl` | `choice` | 0.6 | deterministic rules |
| Brief stance | `ai-brief.tcl` | `choice` | 0.6 | deterministic rules |

Tests: `tests/test_app_systemone.tcl`, `test_app_assistant_route.tcl`,
`test_ai_rhetoric.tcl`, `test_app_error_triage.tcl` (mock `/v1/systemone` server +
stub provider).

---

## 4. The architecture this implies (and the tree already encodes)

The external evidence and `JEV_USE_CASES.md` §6 converge on one **shared reliability
contract**. Every shipped integration obeys it; it should be treated as the rule for
any future one:

1. **Bounded output.** The options are a fixed enum/list/level set the caller
   supplies. The model cannot invent a category. Validate the returned label against
   the offered set anyway (`Answers` does not enforce it).
2. **Confidence-gated.** A threshold decides act-vs-fallback, it is an env var, it
   starts conservative, and it is *calibrated on your own data* — because ECE and
   the confidence distribution are model-specific (Jev ECE 0.045; Kev ships
   T≈2.4 and still has 0.54 coverage at 5% error vs Jev's 0.70).
3. **The ground truth still runs.** Stockfish, `::ai::claims::check` and the C++
   fact layer are never replaced. The classifier is a pre-filter or a second opinion
   on *text*, never the authority on the board.
4. **The fallback is the status quo.** No server / timeout / malformed reply /
   unknown label ⇒ exactly today's behaviour. A missing classifier can only cost
   speed or a badge, never correctness.
5. **Pluggable, never hard-coded.** No model, backend, engine or port in logic —
   the four-backend client plus env overrides.
6. **Graceful absence + fit the machine.** The features hide/disable/degrade; the
   GGUF/fp16 paths target 8 GB cards and CPU; startup survives a poisoned settings
   file.
7. **Local-first.** Decisions about private text stay on the machine unless the user
   chose a cloud backend.
8. **Auditable + bounded blast radius.** "Show your work" where a claim is made;
   mutations confirm; a wrong classification costs a screen, not data.
9. **Shadow-first evaluation.** Ship the classifier predicting alongside the status
   quo (`shadow`), log prediction-vs-actual, and only then turn on `active`. This is
   the mechanism the external calibration literature demands and the tree implements.

### 4.1 How the *shape* of the model dictates the *placement*

This is the central "informs what is built" point:

- Because it is **typed**, its output can be branched on directly — no parsing, no
  regex, no malformed-response handling beyond shape validation. Hence "route",
  "gate", "label".
- Because it is **calibrated**, a threshold is a *safety* device, not a heuristic.
  Hence the two-gate route, the separate rhetoric/coverage thresholds, and the
  insistence on the conservative start.
- Because it is **one-pass and text-only**, it cannot touch the board. Hence the
  firewall: the classifier ranks/gates/labels, the engine decides, the LLM narrates.
- Because it is **fast and cheap**, it can sit *in front of* the expensive path
  (LLM tool loop, triage escalation) rather than beside it. Hence "pre-filter" is
  the dominant pattern in this tree.
- Because it can be **confidently wrong**, every call site needs a non-model
  fallback. Hence every shipped feature has one.

---

## 5. Gaps and opportunities, grounded in the research

These are not commitments; they are the places where the external survey suggests
the tree is under-using the class.

### 5.1 The `score` primitive is unused
The client supports `score`; every shipped feature uses `choice` or `noul`. Ordered
levels are the natural fit for several things already on the roadmap:
- **Repertoire-gap urgency** (`AI_PRODUCTS_PLAN.md` Wave 2: "classifier scores
  urgency") — `score` over `{rarely faced, occasional, critical}`, engine verifies
  playability.
- **Rhetoric calibration** — JEV §3.B originally proposed `score` for
  Calm/Measured/Overstated before it shipped as `choice`; an ordered level maps more
  directly to "add a badge".
- **Novelty radar** severity, **import triage** confidence, **curation merge**
  doubt. All of these are "ordering", not "one of a set", and `score` is a better
  fit than an ad-hoc `choice`.

### 5.2 Batch questions in one call
Jev's own guidance is to batch. `ai-rhetoric.tcl` already asks two questions in one
round trip; the pattern could extend to bundling independent decisions (e.g. an
assistant route that also asks "is this a question or a command?"), paying the state
cost once.

### 5.3 Guardrail on mutating tool calls (JEV candidate G — deferred)
The external ecosystem has this as a first-class use case ("score risk before an
agent runs a shell command"; Kev/decider ship command-risk behaviour probes at
~0.9). The tree defers it because the **confirm gate is already the authority**.
That remains a defensible call — but the research suggests the right time to revisit
is *not* to add a second gate over the confirm dialog, but to catch the specific
failure "a question phrased as a command" ("How would I start a new game?" →
`new_game`), which is a `choice` over
`{explicitly_requested, hypothetical_or_negated, different_action, unclear}` and can
run *instead of* the confirm dialog only when the classifier is confident it was a
question. Low blast radius, real coverage gain.

### 5.4 Loop-termination scoring (JEV candidate E — deferred)
The ecosystem names "is another tool call needed?" as a meta-decision classifiers
are good at. The tree correctly defers until real conversation traces exist; the
`shadow` log is the right way to collect them.

### 5.5 Context compaction for long assistant sessions
Not in the tree at all. As the assistant's `Priv(maxRounds)` tool loop grows, a
`choice` over `{keep, truncate, drop}` per stale tool result is exactly the class's
lane ("verbatim, no lossy rewrite"). This is a genuine, currently-missing capability
that the external research supports and the tree's own "fit the machine" requirement
(8 GB cards, constrained hardware) makes valuable.

### 5.6 Calibration battery + threshold autotune (Wave 4, unbuilt)
The tree has thresholds and a shadow log but no automated way to (a) measure
coverage-at-error-budget for the *user's* backend and (b) refit thresholds from
observed overrides. The external evidence is emphatic: **calibrate on your own
labels**; a temperature/threshold fitted elsewhere does not transfer (JevBench's
public→sealed gap; Kev's "a temperature fitted in distribution does not transfer").
Wave 4 already lists this; the research raises its priority.

### 5.7 Model-fit / quant recommendation
The client documents `KEV_DTYPE=fp16` on Turing/Pascal and the plumb GGUF Q4_K_M path
for small cards, but the chooser does not *detect* the device and recommend a
backend/quant. Wave 4 lists "detect device memory → recommend the quant → download →
serve → battery → suggest thresholds". This is the highest-leverage unbuilt item for
"fit the machine".

---

## 6. Risks and anti-patterns to keep in view

1. **Confident-and-wrong is the failure mode.** Never read confidence as
   correctness; the slop-detector counterexample (86% on a key smash) is the
   cautionary tale. Every use here is consequently reversible or advisory.
2. **Thresholds are per-model.** `plumb` T=2.07; Kev T=2.41 with a different
   confidence formula; Jev ECE 0.045. The tree's env overrides and "retune via the
   env var" comments are correct — but the *defaults* are plumb-calibrated, so a user
   who selects `kev` (the default backend!) is running plumb's thresholds on Kev's
   distribution. This is the single sharpest mismatch in the current integration and
   the strongest argument for the calibration battery.
3. **Option-order sensitivity.** ~0 for Jev, up to 0.08 for Kev/JevK5; a 27-option
   route question is a large `choice`. Rotation-averaging (as Kev does at inference)
   would multiply latency; the shadow log is the cheap mitigation.
4. **>16 options need the right runtime.** The tree documents this, but a user
   running an old JevK5/kev server silently loses the router. The `describe` /
   `backends` surface should keep surfacing the caveat.
5. **Small local models are much weaker out of domain.** kev-0.8B transfer 0.65 vs
   Jev 0.86. Choosing the local default is a privacy/cost decision that *is* also an
   accuracy decision, and the confirm gate + fallbacks must carry that weight (they
   do).
6. **Long states degrade.** Keep states short and structured (the tree already
   truncates); the "state is facts, not prose" convention is a feature.
7. **Do not let the classifier become the authority.** The firewall
   (`AI_PRODUCTS_PLAN.md` §0) is the guardrail; every new integration must restate it.

---

## 7. Bottom line

- A System One model is a **typed, calibrated, one-pass decision model**: route,
  score, gate, label, pre-filter, second-opinion. It is not a fast chatbot and not a
  chess authority.
- Its **shape** — typed output, calibrated confidence, text-only, fast, fallible —
  dictates where it may be used, and this tree's `JEV_USE_CASES.md` +
  `AI_PRODUCTS_PLAN.md` firewall + reliability contract are a faithful restatement
  of that logic, arrived at independently and largely matching the ecosystem's own
  guidance.
- The tree's integrations (triage, pre-route, rhetoric/coverage, study-plan label,
  brief stance) are all correctly placed: pre-filter or second opinion, never the
  authority, always with a status-quo fallback and an env-tunable gate.
- The **under-used** surfaces are `score` (ordered levels), question batching,
  context compaction, and — most importantly — **per-backend calibration /
  threshold autotuning**, because the defaults are plumb-calibrated while the default
  *backend* is kev, and the external evidence is unambiguous that thresholds do not
  transfer between models.

---

## 8. Sources

**In-repo:** `tcl/ai-systemone.tcl`, `tcl/app-assistant-route.tcl`,
`tcl/ai-rhetoric.tcl`, `tcl/ai-studyplan.tcl`, `tcl/ai-brief.tcl`,
`tcl/app-error-triage.tcl`, `tcl/ai-generate.tcl`, `tcl/app-ai-models.tcl`,
`tcl/app-ai.tcl`, `scripts/plumb-systemone-server.py`, `JEV_USE_CASES.md`,
`AI_PRODUCTS_PLAN.md`, `tests/test_app_systemone.tcl`.

**External (checked for this note):**
- TypeSafe Jev: `jevtypesafeai.com/{,how-to-use,jev/models,jev/system-one}`; API
  reference and models docs; DecisionEval `decisioneval.dev/models/typesafe-jev`.
- JevBench: `benchmarkheaven.com/jev-models/{open-source-jev,alternatives,jev-vs-plumb}`,
  `jev-ai.pro/jevbench`, `jevbench.dev`, HN thread 49800574.
- Kev: `github.com/jaredpalmer/kev` (README, PLAN.md), `huggingface.co/jaredpalmer/kev-{0.8b,4b}`.
- JevK5: `huggingface.co/alibiserikbay/JevK5`; Plumb: `huggingface.co/crh225/plumb-4b{-GGUF}`.
- decider: `huggingface.co/Mapika/decider-4b`.
