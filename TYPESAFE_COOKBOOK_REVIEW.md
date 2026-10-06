# TypeSafe cookbook review — applicable refactors for Scidb

**Method:** read the cookbooks index (`https://console.typesafe.ai/docs/cookbooks`)
and the cookbooks below, then matched each against Scidb's fragile or complex
code. Each entry names the cookbook, the code, the fragility, the refactor, and
whether the firewall allows it.

The firewall is unchanged: nothing here lets a model decide move quality,
evaluations, tablebase verdicts or opening identity. The classifier *selects
among candidates code produced*; code still owns every value.

## Prioritized map

| # | Cookbook | Scidb code | Fragility it removes | Firewall |
|---|---|---|---|---|
| 1 | [Entity alignment](https://docs.typesafe.ai/cookbooks/entity_alignment.md) | `merge.tcl`, duplicate groups (A5) | header-only key false-positives -> deterministic move compare, **not** a model | measured: no |
| 2 | [Pre-parsed value extraction](https://docs.typesafe.ai/cookbooks/pre_parsed_value_extraction_cookbook.md) | `app-assistant.tcl::ResolvePlayer`, `ai-search.tcl::extract`, `iccf-xfcc.tcl` | ambiguity → error + LLM retry; regex/emitted values | safe (copies a candidate) |
| 3 | [Re-ranking](https://docs.typesafe.ai/cookbooks/rerank_typesafe.md) | `ai-precedent.tcl`, `ai-annotations.tcl` | retrieval returns overlap/keyword order, not relevance order | safe (read-only) |
| 4 | [Function calling](https://docs.typesafe.ai/cookbooks/function_calling.md) | `app-assistant-args.tcl` (shipped) | the LLM emits JSON args; enum values can be wrong | safe (code runs the tool) |
| 5 | [Structure recovery](https://docs.typesafe.ai/cookbooks/autoformat.md) | `scripts/annotation_extract.py::is_prose` | multilingual regex + bracket-depth scanner | safe (offline corpus) |
| 6 | [Date extraction](https://docs.typesafe.ai/cookbooks/date_extraction_cookbook.md) | `ai-search.tcl` date fields | regex years; relative dates ("last year") unsupported | safe (field, then validated) |
| 7 | [Line-by-line search](https://docs.typesafe.ai/cookbooks/semantic_find.md) / [RAG passages](https://docs.typesafe.ai/cookbooks/classifying_rag_passages.md) | comment/annotation search | keyword search misses paraphrase | safe (read-only) |
| 8 | [Guardrails for LLMs](https://docs.typesafe.ai/cookbooks/llm_guardrails.md) | `ai-provider.tcl` egress (A9), `RunTool` | privacy leaks; malformed tool calls | safe (gates) |
| 9 | [Parallel questions](https://docs.typesafe.ai/cookbooks/parallel_questions.md) | `ai-batch.tcl`, `ai-rhetoric.tcl` | already done — the cookbook confirms the shape | safe |
| 10 | [Classification using confidence](https://docs.typesafe.ai/cookbooks/classification_using_confidence.md) | `app-error-triage.tcl` classifier gate | top-label confidence when the decision is bug / not bug | safe (shipped) |
| 11 | [Skill suggestion](https://docs.typesafe.ai/cookbooks/skill_suggestion.md) / [Hierarchical classification](https://docs.typesafe.ai/cookbooks/hierarchical_classification.md) | `app-assistant-route.tcl` flat route choice | probability spreads over similar actions as the catalog grows | safe (deferred) |
| — | [Self-consistency](https://docs.typesafe.ai/cookbooks/consistency_choice_cookbook.md), [Citation check](https://docs.typesafe.ai/cookbooks/citation_check.md) | `ai-claims.tcl`, `ai-factcheck.tcl` | **walled** — the chess-fact trust boundary stays deterministic | — |

## 1. Entity alignment → duplicate/merge arbitration (A5)

**Cookbook shape:** one `Score` over `{different, related-but-maybe-same,
same}` plus companion `Noul`s per compared field; the middle level routes to a
curator; no threshold to fit. Merging is the expensive error, so the third
outcome is essential.

**Scidb today:** the duplicate key is **headers only** --
`GameInfo::computeChecksum` covers event/site/players/ratings/date/ECO/result
and *explicitly excludes move data*, and `DatabaseCodec::computeChecksum`
returns that crc unchanged. So a flagged group can hold different games (same
headers, different moves); the merge dialog has no arbitration (A5 audited 🟢
but unshipped).

**Refactor:** in `tcl/ai-merge.tcl`, send `{game_a, game_b}` and ask
`Score {different | related | same}` + `Noul` per field. Code calls
`merge`/`markDeleted` only on the confident ends and queues the middle.

**Measured -- not shipped.** On 8 pairs that share headers by construction
(5 same-game, 5 with different moves): a classifier given only the shared
headers made **4/8 errors** (no signal), and given the move text made 0/8 --
but so does the one-line deterministic comparison `game_a.moves == game_b.moves`
(0/8), which is exact, free and offline. A classifier cannot beat that, and
the real gap (near-duplicates whose headers *differ* -- ratings, ECO, site
spelling) needs fuzzy candidate generation, a different feature with its own
labels. The right fix for the false positives is deterministic: compare the
mainline move checksum when resolving a group (or include it in the key), not
a model.

**Why less fragile:** removing the binary "is this a duplicate" decision and
tuned field weights; the model reads the pair, code keeps every write behind
confirmation.

## 2. Pre-parsed value extraction → player resolution (the strongest small fix)

**Cookbook shape:** a recall-tuned regex (or roster) finds candidate spans;
TypeSafe `Choice`s the intended span; code copies it verbatim, so the value
cannot be invented or transposed.

**Scidb today:** `ResolvePlayer` (`tcl/app-assistant.tcl:1799`) already calls
`::scidb::db::findPlayers` — the roster is there — but on ambiguity it
**errors** and asks the language model to retry with an exact name. That is a
fragile multi-turn dance, and `ai-search.tcl::extract` lets the model *emit*
player/event/ECO values (generation, therefore hallucinable).

**Refactor:** when `findPlayers` returns 2–10 candidates, send the user's text
and the candidate list as a `Choice` (options = the candidates, plus `none`),
copy the chosen name; only error when `none`. The same pattern replaces the
emitted-value fields in `ai-search` (`player`, `event`, `eco`) and the free-text
`myMessage` in `tcl/iccf-xfcc.tcl` (candidates from the DB's legal moves/ids).

**Shipped (player half).** `::ai::systemone::chooseSync` (a bounded, synchronous
single-question selector in `tcl/ai-systemone.tcl`) plus
`::application::assistant::SelectPlayer` and the rewritten `ResolvePlayer`
(`tcl/app-assistant.tcl`). The candidate names ARE the choice options, so the
return is always a real database row; on any abstention (no classifier, timeout,
low confidence, `none`) `ResolvePlayer` falls back to the old error. Tests:
`systemone-player-select` / `-none` / `-lowconfidence` / `-threshold` / `-off`.

**Evaluation (is it reliably better than the error-and-retry it replaced?).**
On 12 disambiguating queries and 8 ambiguous bare surnames, at gate 0.6 the
classifier committed on 2/8 ambiguous names (a confident guess the old code
never made); at **0.75** both plumb and Jev commit **0/8** ambiguous and the
disambiguating picks are **100% correct** (Jev 12/12, plumb 11/12; the one
abstention falls back to the old error). The gate is therefore 0.75, not 0.6 —
without that change the refactor was not reliably better and would have been
reverted. Still open: the `event` field (a substring filter today, no
error/retry, so lower value) and the `iccf-xfcc` message.

**Why less fragile:** the returned value is always a real database entry, so it
cannot invent a player, and the ambiguity is one request instead of a retry
loop. This is the cookbook's core guarantee: *the value is one of the spans the
regex/roster found*.

## 3. Re-ranking → precedent and annotation retrieval

**Cookbook shape:** fast search (BM25) builds a shortlist; one `Noul` per
query-candidate pair scores relevance; sort by the noul. Top-1 5% → 18%,
top-10 38% → 62%.

**Scidb today:** `ai-precedent.tcl::lookup` runs the SQLite index and returns
the top-N by shared-continuation overlap (`--limit`); `ai-annotations.tcl` does
the same for exemplars. The order is the index's, not relevance to the current
question.

**Refactor:** keep the SQLite index as fast search (raise the shortlist to
~20), then one `Noul` per candidate — "does this continuation/exemplar answer
the current question?" — and sort. The narrator then sees the best evidence
first. Batch the questions with `ai-batch` and cache by `(fen, candidate)`.

**Why less fragile:** retrieval quality stops depending on string overlap; the
shortlist guarantees the answer is available, and re-ranking only reorders what
is already there.

## 4. Function calling → assistant tool arguments

**Cookbook shape:** for each argument with a closed set, a `Choice`; a `bool`
becomes a flag; a `stated` `noul` decides whether the request mentions the
argument at all, so omitted arguments keep the function's defaults. One request
carries the route plus every argument; the call's confidence is the weakest
argument's.

**Scidb today:** the assistant asks the LLM for JSON tool arguments
(`RunCalls` → `CheckArgs` → `BuildQuery`). `app-assistant-route.tcl` already
routes *zero-argument* tools via a gate; arguments are still generated text
that `CheckArgs` can reject, costing a round trip.

**Refactor:** extend the router to fill arguments from closed sets the schema
already declares (a `choice` per enum argument, a `noul` per optional
argument's presence). Code passes the chosen values to `CheckArgs` unchanged.
The `stated` question is the key part: it prevents a confident guess for an
argument the user never mentioned.

**Shipped + measured.** `tcl/app-assistant-args.tcl` + `correctArgs` (called
from `RunCalls`) correct the closed-set arguments of a tool call before it
runs; `::ai::systemone::chooseManySync` asks one `Choice` per enum arg in one
request, gated at 0.7, and anything unfilled keeps the model's value. Modes
`SCIDB_AI_ARGS=off|shadow|active` (default shadow). Measured on 26 enum-arg
slots across six tools: the LLM made errors **granite4.2:8b 4-8%**,
**granite4.2:3b 8-12%**, **deepseek-v4.1-flash 12%** (a systematic `opponent`
colour inversion), while TypeSafe was **0/26** every run, and its answer is
always a schema value. Tests: `tests/test_app_assistant_args.tcl`.

**Re-measured (2026-09-29).** 45 hand-labelled requests over nine tools (38
stated enum slots, 32 unstated), granite4.2:8b as the model, the real
`correctArgs` as the classifier path. With the original wording ("the request
means color=white") the classifier answered the *user's* colour for "I'm
playing white against X" and fixed nothing (`off` 34/38, `active` 34/38, both
Plumb-4B and Jev). With the schema's argument description as the question and
in each option ("the colour the opponent will play is white") the result is:

| classifier | `off` (model) | `active` | fixed | broken | invented values |
|---|---|---|---|---|---|
| Jev (`typesafe`) | 34/38 | **37/38** | 3 | 0 | 0/32 |
| Plumb-4B (local) | 34/38 | 36/38 | 2 | 0 | 0/32 |

The remaining miss is "I'm black against Ding, write a brief" (classifier
abstains below 0.7, so the model's value stands). One model, one labelled set
written by the author, two classifiers: enough to say the description matters,
not enough to call the 4-12% error rate general. The default stays `shadow`
until a real-usage comparison from `args-shadow.log` agrees. (Not tried:
granite4.2:3b, deepseek.)

**Why less fragile:** arguments can only take values the tool accepts, and
"not mentioned" is an explicit answer rather than an invented default.

## 5. Structure recovery → annotation/prose extraction

**Cookbook shape:** pass 1 stitches hard-wrapped lines (one `Noul` per adjacent
pair); pass 2 classifies every block (`Choice` over heading/paragraph/list/
code/callout) with companion questions asked up front. Direct evidence
(punctuation, blank lines) stays in code.

**Scidb today:** `scripts/annotation_extract.py::is_prose` is a chain of
multilingual regexes (clock, `(CBH payload:`, `medal:`, `<xx>` glossary,
`[A-Za-z]{3,}` counts) and `clean_comment` hand-scans bracket depth "because a
regex cannot recurse". These decide which comments become narrator exemplars.

**Refactor:** keep `clean_comment`'s directive stripper in code; replace
`is_prose` with a `Choice` over `{prose, machine}` per comment, batched and
cached. This is the same job `tcl/ai-comment.tcl` already does for
`comment_kind`.

**Shipped + measured.** `scripts/annotation_extract.py` gains an opt-in
`--classifier` (env `SCIDB_ANNOTATIONS_CLASSIFIER`, `_URL`, `_MODEL`,
`_API_KEY`/`TYPESAFE_API_KEY`, `_CACHE`): it sends up to 32 comments per
request as one state with one `Choice` per comment, caches verdicts by text
hash, and falls back to `is_prose` on any error. Opt-in because the comments
may be private. Measured on a 39-case labelled battery: **regex 13/39 wrong
(33%) vs Jev 0/39 (0%)** — the regex structurally drops every non-Latin prose
comment and passes clock/engine lines. Test
`tests/test_annotation_extract.py::main_classifier` (mock `/v1/systemone`,
asserts batching and the dead-endpoint fallback).

**Why less fragile:** the multilingual/format-specific regex set is replaced by
one bounded question; the output is a fixed label the caller can branch on.

## 6. Date extraction → plain-language search dates

**Cookbook shape:** read the date's *parts* (`mode` absolute/relative/none,
month, day, year, weekday, week offset) with `Choice`s; resolve to a `date` and
take the weakest part's confidence; flag or drop on low confidence.

**Scidb today:** `ai-search.tcl::extract` matches a handful of year regexes
(`since/after/before/in/of`) and cannot express "last year", "this decade",
"the 90s".

**Refactor:** ask for the parts and resolve in code (today's date is known),
keeping the existing regex as the fallback. Reuse `::scidb::view::search`'s
date-range fields.

**Why less fragile:** relative phrasing is handled by the model reading the
words, while all calendar arithmetic (which the model is bad at) stays in code.

## 7. Line-by-line search / RAG passage classification → comment search

**Cookbook shape:** tag lines/blocks with ids, ask one `Choice` per id against a
plain-language query (plus a `Noul` "does the document answer this at all?");
code filters by probability.

**Scidb today:** comment/media search is keyword-based; `ai-annotations` only
looks up one position.

**Refactor:** give comments stable ids and score them against the query in one
request (batched), then filter in code. This is the semantic layer
(`AI_AUTOMATION_AUDIT` E1) without an embedding index.

**Why less fragile:** no separate embedding store to keep in sync, and the
query is applied by meaning rather than by the words in the comment.

## 8. Guardrails → egress and tool-call validation

**Cookbook shape:** screen every input and output with one request, threshold
hazard probabilities and severity to pass/review/block.

**Scidb today:** the cloud egress gate (A9) is planned but unbuilt;
`ai-provider.tcl` sends prompts to cloud providers without a privacy check.

**Refactor:** before a non-local provider request, one `Noul` ("does this
prompt carry personal data, private games or local paths?") plus a severity
`Score`; warn (never block) and remember the session answer. Also validate a
mutating tool call's intent in `RunTool` (the deferred candidate G).

**Why less fragile:** the check is a fixed question with a threshold and the
status-quo fallback, same contract as every other `::ai::decide` gate.

## 10. Classification using confidence → error triage gate

**Cookbook shape:** when the action depends on a broader grouping than the
labels, add up the fine labels' probabilities and decide on the group.

**Scidb before:** `OnClassifiedImpl` settled a group only when the top label
was not `bug` *and* its own confidence was >= `MinConfidence` (0.6). An answer
of environment 0.45 / noise 0.40 / bug 0.15 went to the language model, though
the classifier was 85% sure it was no bug.

**Shipped.** The gate settles on `1 - P(bug) >= MinConfidence`, using the
`probabilities` the client already returns. If bug is the top label but not
the majority, the likeliest non-bug class is recorded as the verdict. When
the answer has no usable `P(bug)`, the old top-label rule applies. Test:
`systemone-triage-not-bug` in `tests/test_app_systemone.tcl`.

**Open:** `ai-calibrate.tcl` measures top-label accuracy against top-label
confidence. `qualified triage` therefore still gates the feature on a slightly
different quantity than the one the threshold now compares. Re-measure the
0.6 against P(not bug) on the triage gold set before trusting it in the cloud
backend.

## 11. Skill suggestion / hierarchical classification → assistant router

**Cookbook shape:** a large catalog is picked in two stages -- a group, then
an item within it -- so probability is not split among near-synonyms.

**Scidb today:** `routeInvocations` gives one flat `Choice` over every
non-debug action, one entry per small enum value, descriptions cut to 110
characters, plus a "needs the language model" sentinel. The confidence gate
can fail because several actions look alike, not because the request is
unclear.

**Deferred.** Two stages (board / database / search / player / ... then the
action) with the sentinel at both levels. Do this only when the corpus shows
flat routing accuracy dropping as actions are added. `satisfied` runs in
parallel with `route`, so it judges whether the request is generic. It must
not be used to confirm the chosen action.

**Not applicable:** SDE cascade (argument filling already is the extraction
step), autoresearch feature discovery (no labeled outcomes collected);
confidence-gated and intent routing are already the triage and router shapes.

## Wall

**Self-consistency** and **citation checking** are the cookbooks closest to
`ai-claims.tcl` / `ai-factcheck.tcl`, and they are **deliberately not applied**:
those modules are the trust boundary for chess facts, and a model placed
between prose and the fact layer can only turn a caught claim into an uncaught
one (see `JEV_USE_CASES.md §4` and the `event_type` lesson in
`TYPESAFE_API_EXPERIMENT.md`). The deterministic checker stays authoritative.

## Recommended order

1. **#2 player/value extraction** — smallest change, removes a retry loop and a
   generation path, reuses the roster already in the DB.
2. **#3 re-ranking** — improves every grounded report, read-only, batched with
   the existing helper.
3. **#1 entity alignment** — the audited A5 feature, with the cookbook's
   three-outcome `Score` and curator middle.
4. **#4 function calling** — extends the shipped router to arguments.
5. **#5, #6, #7, #8** — follow as the features above land.

All cloud use stays opt-in (`typesafe` backend + `TYPESAFE_API_KEY`); local
plumb keeps working with no key.
