# Jev-type Models in Scidb — Use-Case Research

**Scope:** where the System One decision models now selectable in Extras > AI:
Choose Model (`kev`, `simple-jev`, `plumb`, `jev`) can *reliably* enhance the
user experience, beyond the error log they already triage. This is a design
note, not a build plan; each candidate carries its integration point, its
reliability contract, and an honest call on whether it earns its keep.

## 1. What a Jev-type model is, and is not

A System One model reads a *state* and answers *typed questions* with a
calibrated probability per option in one forward pass — `choice` (one of named
options), `noul` (yes/no probability), `score` (an ordered level). It writes no
prose. The wire contract and the Tcl client live in `tcl/ai-systemone.tcl`
(`::ai::systemone::evaluate` / `evaluateAsync`).

That shape dictates everything below:

- **It is a classifier/scorer, not a generator.** It cannot extract "Najdorf"
  from a sentence, cannot write an explanation, cannot invent a move. Any
  use-case that needs produced text stays with the language model
  (`tcl/ai-provider.tcl`, Ollama).
- **It has no chess board understanding.** It reads a FEN or PGN as *text*.
  It is the wrong tool for anything that depends on the position itself —
  move quality, opening themes, "who is better here". Those are already
  grounded by the engine (`tcl/ai-engine.tcl`) and the C++ fact layer
  (`::scidb::ai::moveFacts`, `::scidb::ai::claimFor`), which are the ground
  truth and must stay so.
- **Its strength is bounded decisions with a confidence.** The reliability
  pattern, established by error triage (§2), is: the model picks from a fixed
  enum, a confidence gate decides whether to act on it, and on low confidence
  or an absent server the existing path runs unchanged. It can be wrong *with
  low confidence* and the system is unaffected; it can be wrong *with high
  confidence* only into a category the existing validation already catches.

## 2. The proof-point: error triage (already shipped)

`tcl/app-error-triage.tcl` asks the classifier one `choice` question per error
group — verdict over `{bug, environment, user, noise}` — and settles anything
the model calls non-bug above `MinConfidence` (0.6); the rest goes to the
language model, which also writes the issue file for every bug. The integration
is `::application::triage::Classify` → `::ai::systemone::evaluateAsync` →
`OnClassifiedImpl`, with `::application::triage::Escalate` as the fallback.

Why it is reliable, and why it is the template for every candidate below:

1. **Bounded output.** The model can only answer one of four labels; it cannot
   invent a fifth and cannot free-associate.
2. **Confidence-gated.** `confidence < MinConfidence` ⇒ advise only; the
   language model takes the group anyway. A confident wrong answer is the only
   risk, and…
3. **The fallback is the status quo.** …a confident wrong non-bug verdict is
   caught by the language-model pass that follows for exactly those groups, so
   a classifier mistake delays a bug, it does not hide one (bugs are never
   settled by the classifier alone — only non-bugs are).
4. **No chess facts are at stake.** The state is an error report, not a
   position; the engine and the claim checker are not involved, so the
   classifier cannot contradict ground truth.

Every candidate below is measured against these four points.

## 3. Candidate use-cases

Each entry: **state** (what the model reads), **questions** (typed), **integration
point** (existing proc it slots into), **fallback**, **reliability**, **verdict**.

### A. Assistant tool pre-routing — *build first*

**Problem.** The assistant (`tcl/app-assistant.tcl`) picks a tool by running
the language model with a tool schema every round (`Step` → `OnReplyImpl` →
`RunCalls`). For the common, argument-free requests — "explain this", "new
game", "switch to the database tab", "what engines do I have", "summarize the
database", "triage the errors" — the language model is doing nothing the
classifier cannot do faster and cheaper, and on constrained hardware that round
is 2–10 s versus ~0.5 s for the classifier.

**State.** The user's request text, plus the selection context preamble that
`::application::assistant::ask` already builds for the language model.

**Questions.** One `choice` over the *zero-argument* tools plus two sentinel
options:

```
{explain_position, new_game, switch_tab_board, switch_tab_database,
 list_open_databases, discover_databases, export_database,
 install_player_photos, install_chessbase_fonts, current_game,
 database_summary, show_search, clear_search, list_engines, app_state,
 triage_errors, list_issues, needs_clarification, conversation}
```

`switch_tab` is split by its enum value so the classifier picks the destination
directly. `needs_clarification` and `conversation` route back to the language
model tool-loop (the existing path).

**Integration point.** A new `::application::assistant::preRoute $request`
called at the top of `Step`, before `::ai::provider::chatAsync`. On a hit
(confidence ≥ threshold, say 0.7) it calls `RunTool $name {}` directly — for a
zero-arg tool `CheckArgs` returns the empty dict and the handler runs; the
reply is fed back through `ToolReply` exactly as if the language model had
called it. On a miss (low confidence, `needs_clarification`, `conversation`,
no server) `Step` continues unchanged.

**Fallback.** No classifier / low confidence / unknown option ⇒ the existing
language-model tool-loop, byte for byte.

**Reliability.** *Bounded* (fixed enum, cannot invent a tool), *validatable*
(`CheckArgs` still runs; a wrong zero-arg tool either no-ops or errors back to
the model, which self-corrects next round), *gated* (confidence threshold), and
*additive* (the language-model path is the fallback, not the victim). The only
new failure is a confident misroute to a zero-arg read-only tool, which at
worst shows the wrong pane — the user says "no, I meant…" and the conversation
continues; no data is changed without the existing confirm gate
(`Priv(reqconfirm)`), because every mutating zero-arg tool (`new_game`,
`show_search`, `clear_search`, `install_*`) still passes through `RunTool`'s
confirm branch.

**Verdict.** **Build first.** It is the highest-volume assistant path, the
latency win on constrained hardware is real, and it is strictly safer than the
status quo because the language model is still the authority on anything
ambiguous. Effort: S (one proc, one classifier call, a threshold).

### B. Comment rhetoric gate — *build second*

**Problem.** The drafted-comment path (the C6 plan in `LLM_REACH_PLAN.md`,
wired through `tcl/comment.tcl`) runs the language model, then
`::ai::claims::check` to catch chess-factual errors (illegal moves, wrong
piece placements, a claimed "isolated pawn" that isn't there). `claims::check`
is deterministic and regex-based; it structurally *cannot* see rhetoric —
"this move is a stroke of genius", "Black is completely lost" at −1.2, "could
lead to a winning attack". The user gets over-claiming the fact checker passes.

**State.** The drafted comment, the fact-pack evidence `::scidb::ai::text`
returned, and the engine eval line — the same inputs the claim checker already
has.

**Questions.**

- `noul`: "Does the comment make a claim the evidence does not support?"
- `choice` tone: `{instructive, measured, hype, speculative}`
- `score` calibration: `Calm / Measured / Overstated` (ordered levels)

**Integration point.** After `::ai::claims::check` passes, before the comment
is shown to the user (`::application::ai::toHtml` / the comment editor's
insert). A flag on `noul`-true or `tone=hype` above threshold marks the comment
"unverified — the model over-claimed; review", or triggers one re-generation
prompt with "make it more measured" (the same retry shape `ai-generate` already
uses for failed claim checks).

**Fallback.** No classifier ⇒ show the comment as today. Low confidence ⇒ no
flag.

**Reliability.** *Bounded*, *additive* (the deterministic checker still runs
and still decides chess facts; the classifier only scores rhetoric), *gated*.
The honest caveat: a text-trained classifier generalizing to chess commentary
tone is unproven, so the threshold should start high (e.g. 0.8) and the flag
should be advisory, not blocking, until it earns trust on real comments. It
cannot make the comment worse — at worst it adds a cautionary badge.

**Verdict.** **Build second.** It adds a capability the deterministic checker
structurally lacks, in the safest possible position (second opinion, advisory,
after the ground-truth check). Effort: S–M.

### C. Find-similar rationale label — *build if/when C5 ships*

**Problem.** The find-similar-games plan (C5) ranks games by shared-continuation
overlap from the precedent index (`tcl/ai-precedent.tcl`) and explains the
"why" from the overlap facts. The explanation is currently a list of facts;
a labelled rationale ("same opening line", "same player", "same tactical motif")
is nicer UX and is a classification, not a generation.

**State.** The overlap facts the explanation already uses (shared plies,
shared player, shared event, shared material hash) as a compact text block.

**Questions.** One `choice` over `{same_opening_line, same_player,
same_event, same_material_structure, same_tactical_motive, same_ending}` — or a
`noul` per label if several can apply.

**Integration point.** `::application::ai::explainSelection` (the game case)
or the C5 handler, rendering alongside the fact list in `toHtml`.

**Fallback.** No classifier ⇒ show the fact list as today (no label).

**Reliability.** *Bounded*, *fact-grounded* (the state *is* the overlap data, so
the model is labelling facts, not inventing them), *gated*, *additive*. A wrong
label is a cosmetic annoyance, not a wrong game — the ranking is the precedent
index's, untouched.

**Verdict.** Build only when C5 itself ships; it is a polish on a feature that
does not yet exist. Effort: S.

### D. Search-intent field set (C4) — *probably not worth it*

**Problem.** The natural-language search box (C4 plan) has the language model
fill a fixed field dict (`BuildQuery` in `tcl/app-assistant.tcl`). Which
fields are present is a classification; the *values* ("Najdorf", "2015") are
generation.

**State.** The user's search sentence.

**Questions.** One `noul` per field in the fixed schema ("is a player
constraint stated?", "is a date range stated?", …).

**Integration point.** Before `BuildQuery`, to pre-select which fields the
language model must fill — narrowing the prompt.

**Fallback.** No classifier ⇒ the language model fills the whole dict as today.

**Reliability.** Bounded and additive, yes. But the language model already
does field selection and value extraction in one pass; splitting it saves at
most a few tokens and adds a round-trip. The win is marginal and the C4 path
is not shipped.

**Verdict.** **Skip** unless profiling shows field selection is a real cost.
The classifier's niche is routing and gating, not pre-digesting prompts the
language model handles in one shot.

### E. Assistant loop-termination scoring — *maybe*

**Problem.** The assistant runs up to `Priv(maxRounds)` tool rounds. Sometimes
the language model stops too early (it thinks it has enough) or too late (it
calls a tool it did not need). A second opinion on "is another tool call
needed?" could terminate earlier or extend by one.

**State.** The conversation so far (user request + tool replies) as text.

**Questions.** `noul`: "Another tool call is needed before answering the
user."

**Integration point.** In `OnReplyImpl`, when the language model returns *no*
`tool_calls` (it is about to finish), consult the classifier; high
`noul`-true ⇒ inject a "you have tools, use one if needed" system nudge and
`Step` again; high `noul`-false ⇒ finish as today. When the language model
*does* return tool calls, leave the loop alone.

**Fallback.** No classifier ⇒ the language model's own judgement, as today.

**Reliability.** Bounded and gated. The risk is the classifier extending the
loop with a spurious extra round — a latency cost, not a correctness cost, and
bounded by `maxRounds`. The benefit (catching premature stop) is real but
unproven.

**Verdict.** **Maybe, later.** It is the kind of meta-decision classifiers are
good at, but it needs real conversation traces to tune the threshold and
prove the win. Not now.

## 4. Anti-use-cases (do not build)

Stating these explicitly, because the classifier's calm boundedness invites
misapplication:

- **Move-quality labelling** (`Best`/`Excellent`/`Good`/`Inaccuracy`/`Mistake`/`Blunder`).
  `::ai::engine::classify` already does this from a real search (cpLoss,
  winPercent, the only-move gap). A text classifier reading the FEN would be
  guessing against a ground-truth signal that is already cheaper and exact.
  Use the engine.
- **Opening-theme or game-role tagging** ("miniature", "king attack",
  "endgame technique"). This needs chess understanding the classifier does
  not have; the fact layer and the engine are the only honest basis, and a
  language model narrating from *those facts* is the right shape, not a
  classifier labelling raw text.
- **Search value extraction.** Generation, not classification (§3.D).
- **Anything the deterministic claim checker already does.** `::ai::claims::check`
  is the ground truth for chess-factual claims; a classifier second-guessing
  it would be less reliable, not more. The classifier's place is the rhetoric
  the checker cannot see (§3.B).

## 5. Prioritization

| # | Use-case | Value | Reliability | Effort | Build? |
|---|---|---|---|:---:|:---:|
| A | Assistant tool pre-routing | high (every request, latency on constrained HW) | high | S | **first** |
| B | Comment rhetoric gate | medium-high (closes a real gap) | high (advisory, additive) | S–M | **second** |
| C | Find-similar rationale | medium (polish) | high | S | with C5 |
| E | Loop-termination scoring | medium (meta) | medium | S | later, if traced |
| D | Search-intent field set | low (marginal) | high | S | skip |

## 6. The shared reliability contract

Every build-worthy candidate above satisfies the same four points that make
error triage safe, and they are worth restating as the rule for any future
Jev-type integration in Scidb:

1. **Bounded output.** The question's options are a fixed enum/list/level
   set the caller supplies. The model cannot invent a category.
2. **Confidence-gated.** A threshold decides act-vs-fallback; below it, the
   existing path runs unchanged. The threshold is the safety dial and starts
   conservative.
3. **The existing ground truth still runs.** The engine, `::ai::claims::check`,
   and the fact layer are never replaced by the classifier; it is a pre-filter
   or a second opinion on text, never the authority on the board.
4. **The fallback is the status quo.** No classifier server, a network error,
   or an unknown answer ⇒ exactly today's behaviour. The classifier can only
   make things faster or add a bounded flag; it cannot make them wrong in a
   way the status quo would not also be wrong.

## 7. Corrections from a second opinion (Codex / GPT-6 Astra)

The analysis above was put to a second model. It changed three things and
added one candidate:

### A — narrow it (two gates, not one)

Choosing a *relevant* tool is weaker than deciding its output *satisfies* the
request. "Show the current PGN" and "Summarize this game" both select
`current_game`; only the first is satisfied by returning PGN. "Show twenty
continuations" must not silently run `position_moves` at its default limit.

**Fix:** add a second `noul` question — `fully_satisfied_by_default_invocation`.
Both routing *and* sufficiency must pass their thresholds before the shortcut
fires. Two gates, not one.

Three implementation details it caught that A must heed:
- `player_stats` requires `name`, `opening_score` requires `eco` — they are
  **not** zero-argument despite being read-only. The fast path must exclude
  them (the "no required properties" schema check handles this).
- `explain_position` still runs the Report-pane generation pipeline; A saves
  the *assistant orchestration* (the tool loop), not the explanation
  generation itself. Don't expect it to skip the LLM for that one.
- `Finish` with empty content produces "(no answer)"; a routed tool needs a
  deliberate response renderer, not an empty finish.

### B — promote to now (C6 is not needed)

C1 (Explain) is already shipped, and `analyze`/`explainSelection` already
render generated prose in the Report pane via `::application::ai::onResult`.
That prose can over-claim *today*. The rhetoric gate can pilot on the
existing Explain reports right now — the seam is `onResult` in
`tcl/app-ai.tcl`, not the unbuilt C6 Draft button.

### F — request–answer coverage advisory (new)

The existing `noAnswer` helper catches *empty* text. It structurally cannot
catch a **substantive non-answer** — fluent, claim-check-passing prose that
does not perform the requested communicative task. "I'll explain that in a
moment" or generic chess advice when asked to explain a specific comment.

- **State:** original task instruction + final prose + task kind
  `{position, move, game, comment}`.
- **Questions:** `choice` over `{addresses_request, generic_nonanswer,
  refusal_or_deferral, unrelated, unclear}`.
- **Integration:** after final generation checks, the same Report-pane advisory
  hook as B.
- **Reliability:** bounded, gated, additive, advisory. The classifier judges
  *language against an explicit request* — it does not assess chess
  correctness (the claim checker owns that) and cannot invent a category.
- **Verdict: build now**, pilot alongside B. Obvious linguistic non-answers
  are in scope; "strategically insightful" is not.

A fixed notice — "This response may not address the selected request" — can
accompany a user-triggered retry. Do not automatically discard the report or
add an unbounded regeneration loop.

### G — mutation intent-match notice (new, defer)

Before the existing confirm gate for mutating tools, a `choice` over
`{explicitly_requested, hypothetical_or_negated, different_action, unclear}`
— catching "How would I start a new game?" (a question) being executed as
`new_game` (a command). Good idea, but it adds latency to a path *already
protected by user confirmation*. The confirm gate is the authority; this
would be a second opinion on top of an existing safety layer. Build only if
traces show mistaken proposals are common.

### Two implementation observations (apply to every candidate)

1. `::ai::systemone::enabled` checks *configuration*, not *server
   reachability*. A configured-but-down backend reports `enabled=1`; callers
   must handle the `ok 0` fallback (the triage code already does).
2. `Answers` does not enforce per-answer enum/probability constraints —
   callers should validate the response shape, not trust it.

## 8. Revised prioritization

| # | Use-case | Value | Reliability | Effort | Build? |
|---|---|:---:|:---:|:---:|:---:|
| A | Assistant tool pre-routing (narrowed) | high | high (two gates) | S–M | **after shadow eval** |
| B | Rhetoric caution on Explain reports | medium-high | high (advisory) | S | **now** |
| F | Request–answer coverage advisory | medium-high | high (advisory) | S | **now** |
| C | Find-similar rationale | medium | high | S | with C5 |
| G | Mutation intent-match notice | medium | high | S | defer (behind confirm gate) |
| E | Loop-termination | medium | medium | S | defer (needs traces) |
| D | Search-intent field set | low | high | S | skip |

B and F share one Report-pane advisory hook: both gate *already-rendered*
prose with a fixed advisory badge, both are post-engine and post-claim-checker,
and both fall back to today's report on any abstention. They are the
smallest-consequence, highest-readiness pair, and they are buildable now
against the live `onResult` path.

Build B and F now; shadow-evaluate A (narrowed) against real assistant
traces; defer the rest until the features they polish exist or the traces to
tune them are in hand.
