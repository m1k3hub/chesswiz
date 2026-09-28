# LLM Features for Scidb — Research & Proposal

Status: research / proposal, not committed scope
Author: agent research pass
Date: 2026-09 (draft)

---

## 1. Executive summary

Scidb already owns every deterministic ingredient an LLM feature needs: a UCI/WinBoard
engine layer, CQL pattern search, ECO/opening-tree statistics, player-prep and
opponent-dossier reports, a multi-language annotation/comment store, an HTML report
viewer with a hardened sanitizer, a media/lesson panel, and a working HTTPS client
pattern. What it lacks is a language layer that turns those structured results into
prose and turns prose requests into structured queries.

The competitive picture (ChessBase '26 "Consult AI", plus open-source Stockfish+LLM
annotators) shows the winning pattern and the failure mode:

- **Winning pattern:** decouple *facts* (engine/statistics, deterministic) from
  *wording* (LLM). Projects such as `kibitz`, `chessbeast`, and `chess-narrator`
  all enforce a "truth layer" that the LLM may describe but never invent.
- **Failure mode:** ChessBase's own reviewers noted the AI assistant's statements
  "were rated only slightly better by the AI, whereas Stockfish clearly rated a
  position as +2" and "seemed generic." Ungrounded generation loses trust fast.

**Recommendation:** build a small, local-first **grounded language layer** — a fact-pack
builder plus a provider-agnostic client — and ship features in order of
value-to-risk: explanation and summarization first (read-only), then natural-language
search, then reviewed annotation writing. Never let the LLM reason about the board.

The single highest-value feature is **natural-language → validated structured query**
(NL → scidb advanced search or CQL), because the LLM emits only a query string that
deterministic scidb code validates and executes. The single highest-parity feature is
**grounded position explanation** ("Consult AI") rendered in the existing HTML report
pane.

---

## 2. What the codebase already gives us

| Capability | Where | Role in an LLM feature |
|---|---|---|
| UCI/WinBoard engine, multipv, eval, PV | `src/app/app_engine.{h,cpp}`, `app_uci_engine.*`, `src/tcl/tcl_engine.cpp` | Fact source: eval, best move, PV, classification |
| CQL engine | `src/app/app_cql_engine.h`, `src/db/cql/` | Target for NL→query; deterministic search |
| ECO table, opening tree/stats | `src/db/db_eco*.cpp`, `db_tree*.cpp`, `tcl/app-tree*.tcl` | Opening stats, move frequencies, Elo bands |
| Player prep / opponent dossier | `tcl/app-db-players.tcl` (`PrepReport*`, `OpponentDossier*`) | Structured stats ready to narrate |
| Opening prep report | `tcl/app-database-openingprep.tcl` | Stats → prose scouting report |
| Player card, crosstable | `tcl/player-card.tcl`, `::scidb::db::playerCard` | Bio/prep context (ChessBase uses ChatGPT here) |
| Multi-language comments + NAGs | `src/db/db_annotation.*`, `db_comment.*`, `tcl/comment.tcl` | Write target for generated annotation |
| HTML report viewer + sanitizer | `tcl/app-report.tcl`, `src/html/html_sanitize.h` | Render Markdown→sanitized HTML output |
| Media panel / lessons | `tcl/app-media*.tcl`, `media-console/` | ASR/translation/summarization target |
| HTTPS client pattern | `tcl/iccf-xfcc.tcl` (`http::register https` + `tls::socket`) | Template for LLM API client |
| Async threads, multi-cursor | `src/app/app_thread.*`, `app_multi_cursor.*` | Background generation without UI stalls |
| Options persistence | `tcl/options.tcl`, `.options` files | AI settings page |
| Tcl command registration | `src/tcl/tcl_base.h::createCommand`, `tcl_database.cpp` | Expose `::scidb::ai::*` commands |

Two structural facts matter:

1. **Tcl already has `http` + `tls`.** The ICCF client proves an outbound HTTPS JSON
   client is feasible with no new C++ networking (the older `util::Http`/`tcl::Http`
   layers are HTTP-only and not needed).
2. **Engine analysis is already asynchronous.** Generated commentary can ride the same
   worker/progress/cancel machinery as engine analysis.

---

## 3. Design principles (non-negotiable)

**P1 — The LLM never reasons about the board.** Every chess fact (evaluation, best
move, PV, material, pawn structure, motif, opening, result statistic) must be produced
by Stockfish or deterministic scidb code. The model's only freedom is *which* facts to
mention, in what order, and in what words. This makes errors localizable: a wrong fact
is a fact-pack bug, a badly-worded correct fact is a prompt bug.

**P2 — Ground, then verify.** Build an explicit, versioned **fact-pack** for every
request, and run a **claim checker** on the output that flags any move/eval/number not
present in the fact-pack. Ungrounded claims are highlighted, not silently shown.

**P3 — Local-first, private by default.** Support a local runtime (Ollama / llama.cpp /
OpenAI-compatible localhost) as the default provider. Cloud providers are opt-in per
feature. Professional opening prep is confidential; the product must not require
uploading a private database.

**P4 — No silent mutation.** Any generated text that would modify a database
(comments, annotations, tags) goes to a **review queue** with per-item accept/reject,
not a direct write.

**P5 — Read-only before write, explain before act.** Ship features that only read the
database first. Query generation is previewed and user-confirmed before execution.

**P6 — Cost and latency are first-class.** Token budgets per operation, prompt caching,
content-addressed response caching, batched/cancellable jobs, and a visible cost
estimate before a run.

**P7 — Stay a database/preparation tool.** The README explicitly excludes automatic
game analysis, training, and engine play. LLM features should be framed as *database
preparation and explanation assistance* (scouting, summarizing, querying, annotating
for review), not as a coach that plays or trains.

---

## 4. Enabling infrastructure (Phase 0)

### F1 — LLM provider abstraction

- **What:** A Tcl module `::scidb::ai::provider` with a common interface
  (`complete`, `stream`, `embed`, `models`, `cost`). Adapters:
  - OpenAI-compatible `/chat/completions` (covers OpenAI, Azure, OpenRouter, vLLM,
    LM Studio, llama.cpp server, Ollama's OpenAI shim).
  - Anthropic Messages API.
  - Local Ollama native API (better streaming/model discovery).
  - Optional CLI adapter (`claude`, `llm`) for users already authenticated.
- **Why:** avoids vendor lock-in; enables the local-first default; lets tests use a
  stub provider.
- **How:** model on `tcl/iccf-xfcc.tcl` (`initTls`, header list, `::http::geturl`,
  error mapping). Key storage via environment variable or a `0600` config file;
  optional OS keyring later.
- **Risk:** low. Effort: small–medium.

### F2 — Grounded fact-pack builder ("position/game dossier')

**Status: position anatomy implemented** — `src/db/db_chess_facts.{h,cpp}`, probe
`src/probe_chess_facts.cpp`, regression test `tests/test_chess_facts.py`
(`make -C tests chess-facts`). See Appendix B for the schema and the chess-native
prompt/claim-check design.

- **What:** A C++ Tcl command `::scidb::ai::facts` that compiles deterministic facts
  into a compact JSON payload. Proposed schema:
  - position: FEN, side to move, castling, material balance, piece activity,
    pawn structure signature, king safety heuristics, motif flags (pin/fork/
    discovered/hanging), space, open files;
  - engine: eval (cp/mate), best move, multipv PVs at a chosen depth, eval deltas
    per move for a game;
  - game: move list SAN, clock annotations if present, ECO, result, players/ratings;
  - reference: N similar/continuation games, opening-tree move frequencies and
    score %, Elo-band splits;
  - player: prep stats (openings split by colour, results, rating range, trends).
- **Why:** this *is* the anti-hallucination mechanism (P1/P2). It also lets the same
  fact-pack feed multiple features and be cached/hashed.
- **How:** new `src/tcl/tcl_ai.cpp` registering `::scidb::ai::*`; reuse `app::Engine`,
  `db_board`, `db_tree`, `db_eco_table`, existing prep-report data sources. Most
  fields already exist internally; the work is exposing them as one serializable
  structure.
- **Risk:** medium (new public command surface). Effort: medium.

### F3 — Async AI job queue, cache, and cost ledger

- **What:** `::scidb::ai::job` built on the existing progress/cancel pattern: submit,
  poll, cancel, stream partial output; content-addressed cache keyed on
  `hash(fact_pack, prompt_template_version, model, params)`; per-session token/cost
  accounting; rate-limit/backoff.
- **Why:** generation is slow and costs money; the UI must stay responsive and
  repeat runs must be free.
- **How:** mirror `src/app/app_thread.*` and the progress reporting used by searches.
  Cache under the scidb config dir.
- **Risk:** low–medium. Effort: medium.

### F4 — Settings page + model registry

- **What:** an "AI" page in the options dialog: provider, endpoint, key, model,
  temperature, max tokens, token budget, privacy mode (local-only / cloud-allowed),
  default audience level, prompt language, and a "test connection" button. Store in
  the existing options file.
- **Why:** necessary for F1–F3 to be usable; also gives a single place to enforce P3.
- **Risk:** low. Effort: small.

---

## 5. Feature proposals

Value/effort/risk keyed: ⭐ value, E effort (S/M/L), R risk (L/M/H). All features
assume F1–F4.

### Tier 1 — Read-only, high value, fits the prep mission

#### F5 — Grounded position explanation ("Consult AI") ⭐⭐⭐ E:M R:M
- **What:** For the current board, produce a natural-language plan summary: pawn
  structure, long-term plans, piece coordination, weaknesses, and concrete
  candidate continuations — each tied to engine PVs and reference-game statistics.
  Rendered in the existing HTML report pane (`tcl/app-report.tcl`).
- **Why:** direct ChessBase '26 parity, and fixes its documented weakness by grounding
  every claim in multipv + stats.
- **How:** `::scidb::ai::facts position` → prompt template → response cached by
  position hash. Offer "explain this PV" and "explain both sides" variants.
- **Guardrail:** if engine eval and text disagree, the claim checker flags it.

#### F6 — Opponent / player prep narrative ⭐⭐⭐ E:S R:L
- **What:** Turn the existing structured `PrepReport*` stats into a prose dossier:
  preferred openings by colour, score vs common first moves, rating-band behaviour,
  time-control tendencies, recurring weaknesses. Optionally seed with public bio
  facts (ChessBase's ChatGPT-in-player-card feature).
- **Why:** scidb already computes every number; this is pure summarization, the
  lowest-risk, highest-perceived-value LLM feature. Zero database writes.
- **How:** feed the prep-report rows to the provider; render in the report pane or
  append to the dossier dialog. Add a "copy as scouting brief" export.

#### F7 — Opening report narrative ⭐⭐ E:S–M R:L
- **What:** From tree/ECO statistics, generate a readable scouting report: typical
  plans, popular deviations, success by Elo band, transposition notes, "pioneer"
  players.
- **Why:** complements the existing opening-prep report; ChessBase '26's biggest
  release feature is exactly an enriched opening report.
- **How:** same fact-pack route as F6, sourced from `db_tree`/`db_eco_table`.

#### F8 — Natural-language → validated search ⭐⭐⭐ E:M R:M
- **What:** A search box that accepts "games where White sacrificed a bishop on h7 and
  won" and emits either (a) the existing advanced-search selector or (b) CQL. Show the
  generated query, let the user edit it, and require confirmation before running.
- **Why:** **highest-value database feature.** It makes the whole DB queryable in plain
  language while keeping execution deterministic and reviewable. The LLM never touches
  the database — it only proposes a query string that scidb validates.
- **How:** fact-pack includes the search schema / CQL grammar and a few few-shot
  examples; response is constrained to a query object, validated by the CQL parser or
  search builder, with a retry-on-parse-error loop. Never auto-execute.
- **Risk:** medium — prompt/grammar drift. Mitigate with a strict schema, validation,
  and a visible "edit query" affordance.

### Tier 2 — Annotate, translate, enrich (reviewed writes)

#### F9 — Generated game annotation / commentary ⭐⭐⭐ E:M–L R:M
- **What:** Generate per-move comments grounded in eval deltas, move classification,
  motifs, and opening theory, at a chosen **audience** (beginner/club/expert),
  **perspective** (neutral/white/black), and **density** (sparse/normal/verbose).
  Write into scidb's multi-language comment store via the existing
  `::scidb::game::update comment` path, through a **review dialog** with per-move
  accept/reject (P4).
- **Why:** core database-preparation value; scidb's annotation store and NAGs already
  support it. This is what the open-source annotators do, but integrated into a real
  database with review.
- **How:** engine analysis pass → fact-pack per move → batched generation (cache hit
  for repeat runs) → diff/review UI → write. Add an "annotate whole game" and
  "annotate selected moves" entry point.
- **Guardrail:** claim checker must pass or claims are flagged inline.

#### F10 — Comment / annotation translation ⭐⭐ E:S R:L
- **What:** Translate existing comments into another language slot, preserving
  structure. scidb already stores comments per language.
- **Why:** high utility for the international database corpus (ChessBase magazines,
  TWIC); low risk because it transforms existing human text rather than inventing
  facts.
- **How:** reuse the comment read/write commands; add a language picker.

#### F11 — Media summarization & transcription ⭐⭐ E:M R:M
- **What:** ASR (Whisper-class, local) for audio/video lessons plus translation and
  summary; summarize magazine articles/HTML reports; generate a lesson outline with
  timestamps that link to the existing media panel.
- **Why:** scidb has a mature media/lesson stack; transcription makes media content
  searchable and translatable, a capability no chess DB ships well.
- **How:** media extraction already exists (`tcl_media_extract.h`); add an ASR
  adapter and store transcripts as searchable annotations.

#### F12 — Publication/export writer ⭐⭐ E:S–M R:L
- **What:** Generate a tournament report, player profile, or opening article from a
  game set, crosstable, or report; render through the existing HTML sanitizer and
  exporter (whole view or single game).
- **Why:** turns scidb's data into publishable output; reuses the HTML pipeline.
- **Guardrail:** numeric claims verified against the fact-pack.

#### F13 — Auto-tagging / database enrichment ⭐⭐ E:M–L R:M
- **What:** Bulk-classify games (tactical/positional, brilliancy, opening novelty,
  endgame type) using deterministic engine features + LLM labels, written to custom
  tags/annotations in a reviewable batch.
- **Why:** makes large databases navigable; complements maintenance tooling.
- **Risk:** bulk writes — always reviewable and reversible.

### Tier 3 — Assistant / semantic layer (higher risk, later)

#### F14 — Semantic search over annotations & media ⭐⭐ E:L R:M
- **What:** Local embedding index over comments, reports, and transcripts, enabling
  "find games where a commentator mentions opposite-coloured bishops." Local
  embedding model by default (P3).
- **Why:** unlocks qualitative search that metadata/CQL cannot express.

#### F15 — Conversational database assistant ⭐⭐ E:L R:H
- **What:** A chat surface over the DB that orchestrates deterministic scidb tools
  (search, tree, playercard, prep) via tool calls: "how does my opponent handle the
  endgame?", "build me a repertoire against them."
- **Why:** long-term vision. High risk (tool-call reliability, trust); only after the
  grounding layer is proven. Each answer must expose the underlying tool results.

#### F16 — Correspondence / variant assistance ⭐ E:M R:M
- **What:** Explain engine suggestions for ICCF/XFCC correspondence games (the game
  manager already exists) and Chess960/variant positions, grounded in engine lines.
- **Why:** niche but aligned with existing correspondence features.

---

## 6. Cross-cutting concerns

- **Claim checker (differentiator).** A post-processor that extracts every move, eval,
  and number from the generated text and verifies it against the fact-pack. Flagged
  claims are shown with a warning; optionally auto-retry with the discrepancy appended.
  This is what makes the feature trustworthy and debuggable (P1/P2).
- **Prompt versioning.** Templates are versioned files; the cache key includes the
  template version so prompt changes invalidate cleanly.
- **Evaluation harness.** Small fixed corpus (positions, games, prep reports) with
  expected facts; regression-test grounding and claim-check pass rates offline with a
  stub provider.
- **i18n.** Generated text should respect the app's language setting; translation is
  itself a feature (F10).
- **Security/privacy.** Never send a database or game list to a cloud provider without
  an explicit per-feature, remembered consent; local provider is the default. Redact
  API keys from logs.
- **Offline behavior.** Every feature must degrade gracefully: with no provider
  configured, buttons show a clear "configure AI" affordance rather than failing.

---

## 7. Suggested sequencing

| Phase | Scope | Rationale |
|---|---|---|
| 0 | F1, F2, F3, F4 | Infrastructure; nothing ships without it |
| 1 | F6, F7, F5 | Read-only summarization/explanation; highest value, lowest risk |
| 2 | F8, F9, F10 | Query generation + reviewed annotation; the core DB workflow |
| 3 | F11, F12, F13 | Media, publishing, enrichment |
| 4 | F14, F15, F16 | Semantic/assistant layer once grounding is proven |

---

## 8. Explicit non-goals

- LLM as an engine or arbiter of best moves (only Stockfish decides).
- LLM-generated moves played or auto-submitted (except the existing correspondence
  flow, which stays engine/clock driven).
- Silent bulk database mutation.
- Cloud-required operation for any feature.
- Training/puzzle modes — out of scidb's stated scope.

---

## 9. Open questions

1. Is an in-Tcl client acceptable long-term, or should the provider layer live in C++
   for streaming/performance? (Tcl is faster to ship and already has TLS.)
2. Which local runtime is the supported default — Ollama, llama.cpp server, or both
   via the OpenAI shim?
3. Should the fact-pack be a stable, documented, user-visible format (shareable,
   inspectable) or an internal detail?
4. How much generated content may be persisted in the database versus regenerated on
   demand? (Affects `.sci` schema expectations — comments are fine; tags need a plan.)
5. Do we ship a default prompt/model pair, or require user configuration?

---

## Appendix A — Reference points from the landscape

- **ChessBase '26 "Consult AI" / AI plan descriptions** — validates demand for
  natural-language explanations, but reviewers flagged inconsistency with engine
  evaluations and generic output. Grounding + claim checking is the differentiator.
- **ChessBase 18 ChatGPT player card** — validates bio/prep narration (maps to F6).
- **`kibitz` (Rust)** — the "LLM never reasons about the board; every fact from
  Stockfish/deterministic code" rule is the clearest statement of P1.
- **`chessbeast`** — rating-aware annotation, critical-moment detection, token
  budgets, reasoning-effort controls; good UX reference for F9.
- **`chess-narrator`** — three-layer truth/teacher/delivery architecture; good
  reference for separating fact-pack, prompt, and rendering.
- **`KibitzAI`** — structured intermediate tokens (quality/phase/tactical event)
  before generation; useful schema inspiration for the fact-pack, and a cautionary
  data point that LLM "insightfulness" is a real ceiling.
- **ChessBase '26 opening report / Elo-band stats / Monte Carlo** — competitive
  bar for F7; scidb already has most of the statistics.

---

## Appendix B — The chess-pilled grounding layer (implemented)

The difference between a useful chess LLM feature and a hollow one is not the prompt
wording — it is whether the model is handed *chess anatomy* or just a FEN. A generic
"here is a FEN, explain the position" request invites a language model to hallucinate
piece locations and evaluations. The implemented layer computes the anatomy first.

**Code:** `src/db/db_chess_facts.{h,cpp}` (extractor), `src/probe_chess_facts.cpp`
(CLI), `tests/test_chess_facts.py` (regression).
**Run:** `make -C src probe_chess_facts && ./src/probe_chess_facts "<FEN>"`, or
`make -C tests chess-facts`.

### B.1 What it computes

Every fact below is derived from scidb's own bitboards and precomputed masks — no
model is involved. This is the source of truth the language layer may describe.

| Chess concept | Definition used | Backing primitive |
|---|---|---|
| Material / balance | per-side K,Q,R,B,N,P counts and centipawn value | `Board::material(color)` |
| Bishop pair | two or more bishops | bishop bitboard count |
| Opposite-coloured bishops | one side only light, the other only dark | square-colour test |
| Pawn islands | groups of adjacent occupied files | per-file pawn counts |
| Doubled pawns | extra pawns on a file | per-file counts |
| Isolated pawn | no friendly pawn on either adjacent file | `board::MaskIsolatedPawn` |
| Backward pawn | not isolated/passed, unsupported, stop square covered by an enemy pawn | `board::PawnAttacks`, rank masks |
| Passed pawn | no enemy pawn on same/adjacent file ahead | `board::MaskPassedPawn` |
| Protected / connected pawns | defended by a friendly pawn / phalanx | `board::PawnAttacks`, `MaskDuoPawn` |
| IQP | isolated d-pawn | file occupancy |
| Hanging pawns | c+d pawns with no b/e pawn | file+rank masks |
| Pawn majority | queenside (a–d) vs kingside (e–h) counts | per-file counts |
| Open / semi-open files | no pawns at all / no own pawns | file masks |
| Bad bishop | ≥3 committed (non-home-rank) own pawns on its colour | bishop + pawn bitboards |
| Knight outpost | 4th–6th rank, no enemy pawn can cover it | `board::MaskNoAttacks` |
| Rook on open / semi-open / 7th | file and rank tests | file/rank masks |
| Development | minor pieces off the home rank | knight+bishop bitboards |
| Mobility | pseudo-legal move count, excluding own-occupied squares | manual ray attacks + attack tables |
| King shield | own pawns on the three files around the king, two ranks ahead | file+rank masks |
| King safety | enemy attackers vs own defenders of the king zone | `Board::attacks`, `attacksOf` |
| Castled | king on c/g home file | king square |
| Pins | exactly one own piece between king and an enemy slider | ray walk |
| Checkers | enemy pieces attacking the side-to-move king | `Board::attacks` |
| Undefended pieces | attacked and not defended | `Board::attacks` |
| En prise | attacked by a cheaper piece | `Board::attacks` + piece values |
| Forks | one piece attacking two or more enemy non-pawn units | `attacksOf` + piece bitboards |
| Skewers | slider attacking a more valuable enemy piece with a lesser one behind | ray walk + piece values |
| Back-rank weakness | king home, intact pawn shield, enemy heavy piece reaching the home rank | file/rank masks + `attacksOf` |
| Legal move stats | legal moves / captures / checks / mates | `Board::generateMoves` + `checkState(move)` |
| Game phase | opening / middlegame / endgame from non-pawn material, piece count, ply | material + ply |

Output is a single JSON object per position (see `probe_chess_facts` for a live
example): `fen`, `sideToMove`, `phase`, `inCheck`, `material`, `pawns`, `files`,
`pieces`, `kingSafety`, `tactics`.

### B.2 The chess-native prompt contract

The fact pack is the *only* source of chess truth. A prompt template is built around
it, not around the FEN:

1. **Role and audience** — e.g. "club player", "expert"; perspective (neutral /
   white / black).
2. **The fact pack** verbatim (JSON).
3. **Hard rules** — the model may not name a square, move, evaluation, material
   count, or structural feature that is not in the pack. It may not invent a plan
   that contradicts the pack. It may not call a position better/worse in a way that
   conflicts with `material.balanceCp` and the engine facts.
4. **Output schema** — sections keyed to the pack (`structure`, `plans`,
   `piecePlay`, `kingSafety`, `candidates`), each sentence traceable to a field.

Chess-specific vocabulary is *gated on the pack*. The model may say "isolated queen's
pawn" only when `pawns.white.isolatedQueenPawn` is true, "the bishop pair" only when
`material.<side>.bishopPair` is true, "an open file" only when the file is in
`files.open`, "a knight on an outpost" only when `pieces.<side>.knightsOutposted > 0`.
This gating is what turns chess vocabulary from decoration into grounded analysis.

### B.3 Claim checker (implemented)

After generation, a deterministic verifier scans the text for chess claims and
checks them against the facts. Two pieces:

- **C++ query** — `ChessFacts::claim` / `::scidb::ai::claim ?fen? term ?side?`
  answers named claims (`isolatedPawn`, `iqp`, `doubledPawns`, `backwardPawn`,
  `passedPawn`, `hangingPawns`, `bishopPair`, `oppositeBishops`, `openFile`,
  `semiOpenFile`, `outpost`, `castled`, `backRank`, `fork`, `pin`, `skewer`,
  `enPrise`), optionally side-scoped.
- **Tcl driver** — `tcl/ai-claims.tcl` (`::ai::claims::check <fen> <text>`) scans for
  structural phrases (with a side taken from the preceding words) and for move-like
  tokens, and returns a list of ungrounded claims. `::ai::claims::verify` raises.

A claim is flagged only when the facts positively contradict it, so a clean result is
meaningful. The checker was hardened for real prose: **nearest** preceding color (not
black-first), immediate negation ("no isolated pawns", "0 open files") and list
negation ("no pins, forks, skewers"), plural term forms, compound-match rejection
("semi-open" is not "open file"), and **piece-placement verification**. On a fast cloud
model's output that cut false positives from 16 to 2 -- and the 2 remaining were genuine
model errors. Tested by `tests/test_ai_claims.tcl` (`make -C tests ai-claims`).

### B.4 Move-level facts (deterministic part implemented)

Position anatomy grounds static explanation. Annotation (F9) also needs per-move
facts. The deterministic half is implemented as `ChessFacts::toMoveJson` and exposed
by the probe:

```
probe_chess_facts --move "Nf3" "FEN"
probe_chess_facts --line "e4 e5 Nf3 Nc6" "FEN"     # one object per move
```

Each object is measured by applying the move on a throw-away board and carries:

- **identity:** `san` (Latin-1, not figurine), `uci` (king-destination UCI for standard
  castling), `from`, `to`, `piece`, `color`;
- **flags:** `capture`/`captured`, `promotion`, `castling`, `enPassant`, `check`,
  `mate`, `stalemate` — decoded from the `Board` check-state *bitmask* (the
  `board::Status` enum is a different thing and collides on value);
- **material:** `materialChangeCp` (opponent loss minus mover loss) and
  `materialBalanceWhiteCp`;
- **development:** `developed` (a minor piece left its home rank);
- **structure delta per side:** change in passed / isolated / doubled / backward /
  islands, plus `createsIqp`;
- **tactics delta per side:** `newUndefended` and `newPins` — pieces that *become*
  attacked-and-undefended or pinned because of this move;
- **motifs:** `discoveredAttacks` (friendly sliders that gain a target because the
  moved piece vacated the line, verified with `board::allSquaresBetween`, each flagged
  `check` when the target is the king), `newEnPrise` (pieces that become profitably
  capturable by a cheaper attacker), and `removesDefender` (enemy pieces left undefended
  and attacked because the move captured their sole defender);
- **static exchange:** for captures, `seeCp` via `Board::staticExchangeEvaluator` and
  `losesMaterial` (negative SEE, suppressed when the move is mate);
- `fenAfter`.

The position serializer additionally carries a top-level `moveStats` object
(`legalMoves`, `captures`, `checks`, `mates`) and a `motifs` object with per-side
`forks`, `enPrise`, `skewers`, and `backRankWeak`.

The extractor is bound into scidb's Tcl layer (`src/tcl/tcl_ai.cpp`, registered in
`tcl_base.cpp`):

```
::scidb::ai::facts ?fen?          ;# JSON anatomy for a FEN, or the current board
::scidb::ai::text  ?fen?          ;# the same, human-readable
::scidb::ai::moveFacts move ?fen? ;# JSON facts for one move
::scidb::ai::claim term ?side?       ;# a named claim on the current board
::scidb::ai::claimFor fen term ?side? ;# a named claim for a FEN
```

The binding adds no chess logic of its own -- it is a thin marshalling layer, so the
facts can only ever come from the C++ extractor. It is tested end-to-end in the real
app shell by `tests/test_ai_facts.tcl` (`make -C tests ai-facts`).

Two implementation notes that matter for trust: material and occupancy are read from
**bitboards**, not the cached `Board::material()`, because that cache is not refreshed
on a throw-away board after `doMove()`; and SEE must assign the **king a large value**
(`32767`, as the embedded `Guess` evaluator does), otherwise a defended capture reads as
a loss because the exchange treats the king as a free recapture. Castling UCI is
normalised to the king destination (`e1g1`) for standard chess, while Chess960 keeps
the king-to-rook form.

### B.5 Engine facts (implemented)

Evaluations come from a real engine, never from prose. `tcl/ai-engine.tcl` drives a
UCI engine (Stockfish by default) over a bidirectional pipe and returns structured
facts:

```
::ai::engine::evaluate <fen> ?-depth N? ?-multipv N?
    -> {kind cp|mate, value, cpl, bestMove, pv, multipv, depth}

::ai::engine::classify <fen> <san> ?-depth N?
    -> {uci, bestMove, evalBeforeCp, evalAfterCp, cpLoss,
        winPercentLoss, classification, depth}
```

`classify` resolves SAN to UCI and gets the post-move FEN from the C++ fact layer
(`::scidb::ai::moveFacts`), so it adds no chess of its own. Classification runs the
Lichess win-percentage curve over the centipawn loss with documented thresholds
(Best / Excellent / Good / Inaccuracy / Mistake / Blunder) -- and returns the raw
evals and the loss alongside the label, so the label is never the only evidence. It is
a deliberately dedicated client rather than the app's engine registry, so grounding
never depends on the user's configured engine list.

**Only-move gap.** `evaluate -multipv 2` reports `secondMove`, `secondCpl`, and
`gapCp` (best minus runner-up); `classify` folds that into a `gapCp`/`onlyMove` flag
(threshold `onlyMoveCp`, default 150). So "the only move was ..." is grounded in the
runner-up evaluation, not asserted.

Tested by `tests/test_ai_engine.tcl` (`make -C tests ai-engine`); it skips cleanly when
no engine is on PATH.

### B.6 Opening theory: ECO identification (implemented)

`::scidb::ai::eco <moves> ?startFen?` identifies the opening for a move line from the
ECO table (`src/data/eco.bin`) and returns `{code name}`:

```
::scidb::ai::eco {e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6}
    -> code B90  name {Sicilian / Sicilian Defence / Najdorf Variation}
```

It parses the moves into a `db::Line` (`Move::index()`), looks up
`EcoTable::getEco(startBoard, line)` and formats `getOpening(eco)`. The table is the
app's (loaded at startup via `::scidb::app::load eco`); the command errors clearly when
`isLoaded()` is false. Tested by `tests/test_ai_eco.tcl` (`make -C tests ai-eco`).

### B.7 Generation layer (implemented)

Three Tcl modules close the loop:

- `tcl/ai-provider.tcl` -- provider abstraction: `stub` (deterministic, for tests),
  `ollama` (local, the default first choice), `openai`, `anthropic`. `json`/`http` are
  required lazily so a missing tcllib package cannot break startup; a token budget is
  set with `-options {num_predict N}`.
- `tcl/ai-prompt.tcl` -- builds a constrained prompt: the fact pack verbatim, the
  grounding rules, the required sections, and engine eval only when requested.
- `tcl/ai-generate.tcl` -- `::ai::generate::position` runs prompt -> provider -> claim
  check -> retry with the contradiction fed back, returning `{text claims attempts grounded}`.

Verified end to end against a local Ollama model (`SCIDB_AI_LIVE=1`): the model
produced text and the claim checker flagged its ungrounded claims. Tested
deterministically with the `stub` provider by `tests/test_ai_generate.tcl`
(`make -C tests ai-generate`).

**Prompt shape.** The grounding rules are sent as the **system** message and the fact
pack as the **user** message; the user message ends with "Output ONLY the three
sections. Do not repeat or restate these instructions." Splitting them stopped small
models from echoing the rules back as content. The default model is `qwen3.8:4b` with
`think:false` (reasoning models otherwise return an empty `response`); `think:false` is
accepted by non-reasoning models too.

**Honest limitation:** the regex claim checker can also flag text that *quotes the
rules* ("use terms like isolated pawn, bishop pair, open file"), which a small model
tends to do. A structured output format, or ignoring instruction echoes, would reduce
that; the checker is conservative by design.

### B.8 UI wiring (implemented)

`tcl/app-ai.tcl` adds **Extras > "AI: Explain Position"**. It reads the current board
(`::scidb::pos::fen`), runs grounded generation **asynchronously** so the interface
never blocks, and renders the assessment plus any ungrounded claims in the HTML report
pane (`::application::report::showHtmlData`). Provider, model, depth, and retry count
come from `::application::ai::configure`. The menu entry is guarded by
`[info commands ::application::ai::analyze]` and is present in the generated
`scidb-beta`.

The async path lives in `tcl/ai-provider.tcl` (`completeAsync`, Ollama via
`::http::geturl -command`) and `tcl/ai-generate.tcl` (`positionAsync`, retry preserved).
Tested by `tests/test_ai_ui.tcl` (`make -C tests ai-ui`).

Still to come:

- **In-book / popularity:** whether a move is still "theory", and how often it is played,
  needs the opening tree / reference database -- the ECO code identifies the opening,
  it does not measure frequency.
- **Motifs:** passed-pawn breakthroughs and overloading/deflection.
- **Automated full-app test of `analyze`:** the command is verified by construction and
  by the generated script, but the report-widget path is not yet covered by an
  automated app test.

### B.5 Why this is "chess-pilled" and not a wrapper

A generic wrapper sends a FEN and trusts prose. This sends a structured chess dossier,
constrains vocabulary to the dossier, and verifies the prose against it. The model
never has to know where the pieces are — it never sees a board it must reason about —
which is exactly why the output can be trusted and, when wrong, fixed at the right
layer.

### B.9 Engine-as-tool and cloud models (implemented)

The model can now **drive Stockfish itself** rather than only reading engine facts from
the prompt. `tcl/ai-provider.tcl` speaks Ollama `/api/chat` with tool definitions
(`chat`, `chatAsync`), and `tcl/ai-generate.tcl` defines the tools and runs the loop
(`positionTools`, `positionToolsAsync`):

- `chess_engine(fen, depth?)` -> `::ai::engine::evaluate` (eval, best move, PV, gap)
- `chess_eco(moves)` -> `::scidb::ai::eco` (opening identification)

The loop sends the system rules + fact pack, executes any tool calls, feeds the results
back, and repeats (bounded). A live run with `deepseek-v4.1-flash:cloud` took ~3.2 s and
produced a PLANS section citing the tool's `-346 cp`, `d4c5`, and the full principal
variation -- engine facts the model obtained *by calling the tool*.

**Fast cloud default and pluggability.** The default model is
`deepseek-v4.1-flash:cloud` (fast -- ~194 tokens in 1.6 s -- and tool-capable). Any
model or provider can be swapped without editing code:

```
SCIDB_AI_MODEL=glm-5.3:cloud pi          # any Ollama tag, local or cloud
SCIDB_AI_PROVIDER=anthropic pi
::application::ai::configure -model kimi-k3:cloud
```

Tested by `tests/test_ai_tools.tcl` (`make -C tests ai-tools`): the `chess_engine` tool
against real Stockfish, and the tool loop with a scripted model.

### B.10 Corpus / precedent layer (prototype)

`scripts/corpus_precedent.py` builds a position -> continuation index from a PGN corpus
and answers "what did masters play here, and how did it score":

```
python3 scripts/corpus_precedent.py build --pgn FILE --db INDEX --max-games N --max-ply M
python3 scripts/corpus_precedent.py query --db INDEX --moves "d4 Nf6 c4 e6 Nc3 Bb4"
```

Position identity is placement + side + castling + en passant, so transpositions merge.
Verified on the 863k-game Lumbras GigaBase corpus (30k-game sample): Nimzo-Indian
4.e3 99.0% / 52.8% for White; QGD 3.Nc3 74.1% / 56.7% -- with move counts, shares,
scores and average rating. `scorePct` is reported **from the side to move** (with a
`sideToMove` field): after `1.d4 Nf6 2.c4 e6 3.Nc3`, `3...Bb4` is 99.8% at 47.1% for
Black. Regression-tested by `tests/test_corpus_precedent.py`. This is the **precedent** evidence the narrator cites
alongside engine facts.

**Corpus finding (important):** Lumbras GigaBase is **sorted by opening** -- the first
30k games are all Queen's Pawn; 1.e4 first appears ~5% into the file. Any "first N
games" sample is therefore biased, so a real index must either read the whole file
(~863k games, ~50 min at the observed rate) or sample at random byte offsets. The raw
game corpus is abundant; **human prose annotations are the scarce resource** (Lumbras'
"comments" are `%clk` clocks only), so the annotation layer still needs acquired
sources (public-domain books, licensed annotated DBs, user `.sci` files).

### B.11 Precedent wired into the prompt (implemented)

`tcl/ai-precedent.tcl` bridges the corpus index to the narration prompt:

```
::ai::precedent::configure -index /path/index.sqlite -script /path/corpus_precedent.py
::ai::precedent::lookup  <fen> ?-limit N?   -> dict (or {} when unknown)
::ai::precedent::summary <fen> ?-limit N?   -> one-line text
```

`::ai::prompt::position` appends a `MASTER PRACTICE:` block when an index is
configured, so the narrator cites real master data next to the engine facts:

```
ENGINE: eval=cp 24 best=e2e3 gapCp=6
MASTER PRACTICE: 2550 games: e2e3 99.0% (52.8% for White), d1c2 0.6%, g1f3 0.2%, f2f3 0.2%
```

A missing or unconfigured index silently yields no precedent (no error, no block),
and the module shells out to `scripts/corpus_precedent.py` only when asked, so the
app itself needs no Python at startup. Tested by `tests/test_ai_precedent.tcl`
(`make -C tests ai-precedent`), which builds a tiny index and checks lookup,
side-to-move reporting, the summary line, and presence/absence of the prompt block.

### B.12 Stockfish fork `narrate` + modern build (implemented)

The custom Stockfish fork (`engines/stockfish/`) now exposes the engine's own view of a
position as structured JSON via a `narrate` UCI command — **shadow-only**: it reads the
`Position` and never touches search or evaluation.

```
position fen <FEN>
narrate
```
```json
{"fen":"...","sideToMove":"white","phase":"opening","legalMoves":32,
 "material":{...,"balanceCp":-200},"pawns":{"white":{...,"isolated":1,"islands":3}},
 "pieces":{"white":{"mobility":18,...}},"kingSafety":{"white":{"shieldPawns":3,...}}}
```

Implementation `src/narration.{h,cpp}` (material, pawn structure, control/mobility via
`Position::attacks_by`, king safety via `attacks_bb`), wired as `Engine::narrate()`
(`src/engine.cpp`) and dispatched in `src/uci.cpp`. This is what the scidb side-project
asked for: the engine reports *its own* understanding (its bitboards, its pawn logic),
which the language layer then narrates — complementing the precedent corpus (B.10/B.11).

**Build.** The fork's real build is the tracked `src/Makefile` (gcc); the untracked root
`Makefile` is a stale scidb-style file with non-existent sources and no link rule. Link
errors like `undefined reference to Stockfish::Attacks::magic` are stale `-flto` objects,
fixed by `make -C src clean`. A modern **CMake** build (`CMakeLists.txt`) was added with
**clang by default** and a gcc option, mirroring the same source list:

```
cmake -S . -B build-clang -DCMAKE_BUILD_TYPE=Release && cmake --build build-clang -j8
cmake -S . -B build-gcc -DSF_USE_CLANG=OFF && cmake --build build-gcc -j8
```

All three builds (gcc/make, cmake+clang, cmake+gcc) produce **byte-identical `narrate`
output**. Documented in `engines/stockfish/BUILD.md`. The earlier unwired prose prototype
`ai_commentary.{h,cpp}` is superseded and excluded from both builds.

**Full index built and validated (2026-09-22).** The whole Lumbras GigaBase corpus was
indexed once: **863,790 games, 25,736,151 plies, 0 skipped, 1.81 GB**
(`/media/michael-g-thomas/sas_mirror/chess/lumbras_index.sqlite`, sha1 position keys).
`scripts/validate_index.py` passes **17/17**, confirming it is representative (the
earlier 30k sample was opening-sorted, so its 1.d4=85% and Nimzo 4.e3=99% figures were
artifacts). Real distributions from the full index:

- first moves: 1.e4 43.2%, 1.d4 37.3%, 1.Nf3 10.9%, 1.c4 7.4%
- replies to 1.e4: 1...c5 44.3%, 1...e5 27.8%, 1...e6 11.0%, 1...c6 8.3%
- replies to 1.d4: 1...Nf6 62.4%, 1...d5 26.3%
- Nimzo-Indian after 3...Bb4: 4.e3 41.5% (53.5% White) + 4.Qc2 35.4% -- the modern trend

(Minor: the start-position key holds 863,791 rows against 863,790 games -- one game
revisits the start position, e.g. via a null move. Harmless.)

### B.13 Engine-native anatomy in the pipeline + annotation extractor (implemented)

**Engine narration wired in.** `tcl/ai-narrate.tcl` drives the custom Stockfish fork's
`narrate` command and exposes it to the language layer:

```
::ai::narrate::configure -engine /path/to/fork-stockfish    # or $SCIDB_AI_NARRATE_ENGINE
::ai::narrate::lookup  <fen>          -> dict (or {} when unavailable)
::ai::narrate::summary <fen>          -> one-line text
::ai::narrate::compare <fen> <san>    -> anatomy deltas for a move
```

Two tools were added so the model can pull engine-native facts on demand:
`chess_narrate` (anatomy: material, pawn structure, mobility, king safety) and
`chess_narrate_delta` (how a move changes balance/mobility/isolated/passed counts).
Shadow-only, and a missing binary yields `{}` rather than an error. Tested by
`tests/test_ai_narrate.tcl` (17 checks; skips cleanly without the fork).

**Annotation extractor.** `scripts/annotation_extract.py` turns a PGN into
`(position, comment, NAG)` records, stripping `[%clk]/[%eval]` engine directives
(including nested ones) and keeping real prose plus NAGs. Records carry a sha1
position key, so they join with the precedent index. Tested by
`tests/test_annotation_extract.py` (12 checks).

Measured on Lumbras GigaBase: **~1,389 annotatable plies per 20,000 games**, of which
~1,337 carry genuine prose ("Inaccuracy. h5 was best.", "Mistake. Ne4 was best.") and
~1,028 carry NAGs -- engine-generated judgements rather than master prose, but real
judgement vocabulary. A full-corpus extraction runs in the background to
`/media/michael-g-thomas/sas_mirror/chess/lumbras_annotations.jsonl`.

**Auto-discovery.** `SCIDB_AI_PRECEDENT_INDEX` / `SCIDB_AI_PRECEDENT_SCRIPT` point the
precedent layer at a built index, and `SCIDB_AI_NARRATE_ENGINE` points it at the fork,
so a running scidb picks both up without code changes.

**Test wiring.** `tests/Makefile` runs the app-backed AI suites (`ai-tests`, 10 suites)
and the Python corpus tooling (`corpus-tests`) from `all` and `ci`.

### B.14 Annotation retrieval joined to positions (implemented)

The annotation extractor's output is indexed and retrieved by position, so the narrator
can cite how the corpus annotated similar positions.

- `scripts/annotation_index.py` — `build` (JSONL -> SQLite keyed by sha1) and `query`
  (by FEN). Built from the full Lumbras extraction: **84,361 records** (81,262 prose,
  62,706 NAGs), 12.4 MB (`lumbras_annotations.sqlite`).
- `tcl/ai-annotations.tcl` — `lookup` / `summary`; `SCIDB_AI_ANNOTATIONS_INDEX` /
  `..._SCRIPT` auto-discovery; a missing index yields no block.

The prompt now composes three independent evidence layers for one position:

```
ENGINE: eval=cp 77 best=a7a5 gapCp=3
MASTER PRACTICE: 1 games: b7a6 100.0% (100.0% for Black)
ANNOTATED EXAMPLES: "Inaccuracy. h5 was best." (NAG 6)
```

engine opinion + master precedent + corpus annotation -- all grounded and verifiable.
Tested by `tests/test_ai_annotations.tcl` (`make -C tests ai-annotations`; 11 app-backed
AI suites total). The annotation corpus is engine-generated prose (Lichess broadcast
style), not human master prose; it provides judgement vocabulary, not deep plans.

### B.15 Real master prose: ChessBase sources (implemented)

**Mega Database 2010 found and extracted.** It was in `/media/.../Videos/` as a 32-volume
RAR (`in-cmd10.001..032`) containing `in-cmd10.iso` (3.09 GB); the ISO holds the full
ChessBase DB. Extracted to `/media/michael-g-thomas/sas_mirror/chess/megadb2010/db/`
(2.4 GB): **4,463,293 games** (`.cbh` 205 MB + `.cbg/.cbj/.cbb/.cba/rb*`).

**New tool `src/cdb2pgn.cpp`** — exports any Scidb-openable database (`.cbh`, `.sci`,
`.si4`, ...) to PGN with comments and NAGs, via `Database::exportGame(index, PgnWriter&)`.
It needs a Tcl interpreter, `initializeStatics()` and the ECO table loaded (else
`GameInfo::addOpening` recurses forever) — see the file.

**Real master prose extracted** (annotated sources, not raw games). Only comments that
survive stripping `[%clk]/[%eval]` directives and rejecting ChessBase meta entries (clock
markers, `Pawn structure/Piece path (CBH payload: …)`, `Medal: …`, and `<xx> (term)`
glossary pairs) are counted as prose:

| Source | Games | Records | with prose | with NAGs |
|---|---|---|---|---|
| CBM168 (ChessBase Magazine 168) | 717 | 1,542 | 1,281 | 730 |
| CB Light Database | 14,831 | 3,343 | 2,550 | 1,793 |
| **combined** | 15,548 | **4,885** | **3,831** | 2,523 |

(The first extraction reported 5,007 records / 4,074 "prose" because any non-empty comment
counted as prose; the filter now in `scripts/annotation_extract.py` removes the
CBH-payload/medal/clock/glossary noise, and is verified to leak none of it.)

Built into `master_annotations.sqlite` (1.1 MB) and retrievable by position, e.g. after
`1.d4 d5 2.c4 e6`: *"In one of my previous videos made for CBM I explained to the reader
the serious problems which Scandinavian Defence players are facing now..."* and *"For the
3rd time in July I had to play this system in my game against the German GM L. Milov at
the tournament in Leiden."* -- genuine GM commentary.

Point `::ai::annotations` at it with
`SCIDB_AI_ANNOTATIONS_INDEX=.../master_annotations.sqlite`.

**Mega Database:** exporting it with `cdb2pgn` originally tripped two Scidb assertions on
comments that lack an English language flag; both are now guards (see B.16). With those in
place it exports cleanly and cheaply: **0.66 KB/game, ~0.34 comments/game**, so the whole
4.46M-game database is only ~3 GB of PGN -- not the multi-terabyte figure an earlier draft
reported (that came from passing the game limit in the *encoding* argument slot, which
exported the database unbounded). Its annotated subset carries real bilingual teaching
prose ("<de> ... <en> If the king has not yet castled, the weakest square is always f7"),
from which `prefer_english()` keeps only the English variant.

### B.16 Real master prose in the pipeline + Mega DB robustness (implemented)

The CBM168 + CB Light prose corpus is wired into the prompt. Over the position after
`1.d4 e6 2.e4 d5 3.Nc3`, the narration prompt carries three independent evidence layers
from three sources:

```
ENGINE: eval=cp -34 best=g8f6 gapCp=18
MASTER PRACTICE: 20243 games: g8f6 44.9% (43.8% for Black), f8b4 41.5%, d5e4 10.2%, b8c6 2.2%
ANNOTATED EXAMPLES: "In one of my previous videos made for CBM I explained to the reader ..."
```

**Verification status (measured, not assumed).** A *single* generation attempt is usually
but not always grounded: in a batch of 8 attempts, 6 returned `grounded=1` and 2 returned
`grounded=0` with one or two flagged claims. The verify-and-retry loop is what closes the
gap: with `-retries 2`, 4/4 runs converged to `grounded=1` (two of them on the second
attempt), because the flagged claims are fed back and the model rewrites without them.
The 5-flag sample quoted in an earlier draft was produced with `-retries 0` and was **not**
grounded; that claim was wrong and is retracted here.

The checker was hardened against the false-positive phrasings the live runs exposed
(copula post-negation "... are false"; negator separated by short words, "Neither side has
a back-rank weakness"; plural "back-rank weaknesses"; long comma lists) while still
flagging true contradictions. It remains deliberately conservative: an unrecognized
negation is flagged rather than silently accepted, which is the safe direction for a trust
layer, and the retry loop absorbs the remaining false positives.

Wire it with `SCIDB_AI_ANNOTATIONS_INDEX=.../master_annotations.sqlite`.

**Mega DB robustness fixes.** Exporting the Mega Database 2010 to PGN tripped two Scidb
assertions on external data: `Consumer::preparePhrase` demanded an English phrase, and
`Consumer::putPrecedingComment` demanded a non-empty event. Both are now guards in
`src/db/db_consumer.cpp` (keep the source language; ignore empty events), after which the
export runs with **0 stderr lines**.

**Correction (an earlier draft was wrong).** This section previously claimed bulk PGN export
of the Mega DB was impractical ("2.98 GB per 50k games", "~19 comments/game") and needed a
custom JSONL dumper. That was an artifact of `cdb2pgn <db> <out> [encoding] [max-games]`
being called with the game limit in the *encoding* slot, so the limit was ignored and the
export ran unbounded until it timed out. Measured correctly: 200,000 games -> 141 MB in 81 s,
and the full 4.46M-game database is ~3 GB at ~2.7 MB/s (~20 min). No custom dumper is needed.

### B.17 Claim-checker precision measured on real master prose (implemented)

The checker was run over all 3,831 prose records in `master_annotations.jsonl`
(each carries its position FEN). They are human-written and therefore true, so
every flag is a false positive:

```
PROSE=3831  ERRORS=0  FLAGGED=128  RATE=3.34%
move-sequence-only=41   structural-only=85   both=2
```

Causes of the 128 flags (each inspected):

- **41 records quote multi-move sequences** ("3.Nd2 c5 4.Ngf3 cxd4 ...") or a
  whole game. Move legality is checked against the single record position, so
  every move after the first is "illegal". This is by design: the checker targets
  generated narration of *one* position, not historical game prose.
- **The structural flags are dominated by piece placement** (knight 18, pawn 12,
  bishop 8, queen 8, rook 4) **and terms** (pin 16, castled 10, outpost 6). These
  are reference-frame and modality mismatches, not checker bugs: the prose often
  describes the *resulting* position ("Black gets a nice outpost on d5"), a
  counterfactual ("with a pawn on c6 instead of c7, Black could have ..."), or a
  general principle ("opposite-coloured bishops tend to be strong in endgames").

Hardening from this measurement: the checker now skips hypothetical/general
statements (marker before *or* after the term, optional copula) for structural
terms, piece placement **and** moves, removing 10 false positives (138 -> 128)
with no loss of true positives.

Honesty note: an intermediate figure of 2.24% appeared in an earlier draft. It was
an artifact of a transient bug in the placement loop that made `check` throw, while
the measuring harness's `catch` silently skipped those records. The valid figure is
3.34% with `ERRORS=0`.

### B.18 Mega Database 2010 annotation corpus extracted (implemented)

With the `db_consumer` guards in place and the correct `cdb2pgn` argument order
(`<db> <out> [encoding] [max-games]`), the whole 4.46M-game Mega Database exports to
**3.47 GB of PGN in ~20 minutes** (~2.7 MB/s, zero stderr). Extraction with 8 parallel
workers (~30 min) produced:

```
mega_annotations.jsonl    580,810 records   267,712 prose   419,267 nags   (141 MB)
mega_annotations.sqlite   580,810 rows                                   (96 MB)
```

That is ~70x the curated CBM168 + CB Light prose (3,831). The corpus is **multilingual**
(German, French, English -- ChessBase's international database) and noisier than the
magazine sources ("Hecht"; "Weiterer Partieverlauf ist unleserlich"), so it is kept as a
**separate** index and is not the default for the ANNOTATED EXAMPLES block:

```
SCIDB_AI_ANNOTATIONS_INDEX=.../master_annotations.sqlite   # curated English, default
SCIDB_AI_ANNOTATIONS_INDEX=.../mega_annotations.sqlite     # wide, multilingual
```

`prefer_english()` keeps the English half of ChessBase's bilingual teaching notes
("<de> ... <en> ..."); 4.9% of records are German-only and still carry a `<de>` tag.
Roughly 48 games in 50,000 carry a corrupt move list ("illegal san") and are skipped by
python-chess.

### B.19 English retrieval from the multilingual Mega corpus (implemented)

The 267,712-record Mega corpus is multilingual, so retrieving examples for an English
narration pulled French and German prose into the ANNOTATED EXAMPLES block
("ALAPIN a été...", "Er hatte bis hierher..."). A cheap stopword-ratio language test now
filters retrieval:

```
::ai::annotations::lookup  ->  script query --english     (config -english, default 1)
```

`looks_english()` counts English vs German vs French function words; text with no
stopwords at all (pure notation such as "Rc1 wins.") is treated as neutral and kept.
Verified retrieved: "The Burn Variation, a good choice...", "Critical opening position...",
"Stohl: 'Morozevich himself with Black prefers'". Verified dropped: "ALAPIN a été...",
"Er hatte bis hierher schon sehr zögerlich gespielt." The curated corpus is unaffected
(it is already English).

One bug found while wiring this: the filter initially kept *any* row carrying a NAG,
because it tested the `nags` column instead of an empty comment; it now keeps NAG-only
rows (no comment text to test) plus English prose.

New tests: `tests/test_annotation_index.py` (language detection + query filter, 12
checks), wired into `make -C tests corpus-tests`.

### B.20 Masters precedent index: Mega strong games merged with Lumbras (implemented)

The Mega Database's games do carry ratings once you look beyond the historical opening
range: of 4.46M games, 3.01M have a `WhiteElo` tag, **784,625 of them >= 2400 (26%)**, and
only 207 are junk. A new `--min-elo` filter on `corpus_precedent.py build` keeps a game
only when its stronger player meets the threshold (`max(WhiteElo, BlackElo) >= min`) and
skips unrated games -- which matters because the query path does not filter by Elo itself.

Built with 8 parallel workers (~20 min), the 2400+ subset of the Mega Database is
**32,137,362 plies** (~1.07M games) -- itself larger than Lumbras (25,736,151 plies).
Merged into a copy of Lumbras:

```
masters_index.sqlite   57,873,513 rows   4.06 GB   (Lumbras 25.7M + Mega 32.1M)
```

The 2400+ filter holds: merged `avgElo` stays ~2520-2551. Coverage roughly doubles -- the
Nimzo-Indian tabiya after `1.d4 e6 2.e4 d5 3.Nc3` now reports **47,026 games** instead of
20,243, and a rare middlegame position goes from 2 to 3. The larger sample also changes the
statistics (f8b4 46.5% now leads g8f6 40.2%).

```
SCIDB_AI_PRECEDENT_INDEX=.../masters_index.sqlite   # recommended (57.9M plies)
SCIDB_AI_PRECEDENT_INDEX=.../lumbras_index.sqlite   # Lumbras only (25.7M plies)
```

Both sources are Elo-filtered, so "master practice" means 2400+ throughout; the unfiltered
Mega games (many unrated, early historical) are deliberately not indexed.

### B.21 Evidence in the report pane + retry on the tools path (implemented)

The report pane previously showed only the narrative and any ungrounded claims, so a reader
could not see what the text was grounded *in*. It now renders three sections:

```
Evidence      MASTER PRACTICE: 47026 games: f8b4 46.5% (42.6% for Black), ...
              ANNOTATED EXAMPLES: "The Burn Variation, a good choice assuming Black ..."
Assessment    <the narrative>
(verified)    "All claims verified against the facts."   |   list of ungrounded claims
```

`::ai::generate::evidenceFromText` pulls the `ENGINE:` / `MASTER PRACTICE:` /
`ANNOTATED EXAMPLES:` blocks out of the prompt, both async paths attach them to the result
dict as `evidence`, and `::application::ai::toHtml` takes an optional evidence list
(backward compatible: `toHtml text claims ?evidence?`).

Also fixed: the **tools path never retried on ungrounded claims** -- `positionToolsAsync`
returned after a single attempt, so the UI's "AI: Explain Position" often showed
"unverified" even though the non-tools path retried. It now takes `-retries` (default 1,
passed from the UI's `Config(retries)`), feeds the contradicted claims back and regenerates.
Verified live: `grounded=1 rounds=3` with all three evidence blocks present; results remain
run-dependent (some runs still converge only after the retry, some report unverified), and
the pane reports which honestly rather than hiding it.

New tests in `tests/test_ai_ui.tcl`: evidence rendering, escaping, omission when absent,
`evidenceFromText` extraction, and an `evidence` key on the async result.

### B.22 Report-pane integration fixed (raw HTML vs sanitized dict)

Clicking Extras > "AI: Explain Position" failed at runtime with

```
missing value to go with key
Load {<p><b>Assessment</b></p><p>Analyzing the current position...</p>...}
::application::report::showHtmlData .application {AI assessment} {<p>...}
::application::ai::analyze .application
```

**Root cause.** `::application::report::showHtmlData` / `Load` expect the
sanitized-document dict produced by `::scidb::html::sanitize` (keys `html`, `media`,
`anchors`, `unresolved`, `warnings`, `converted`) -- `Load` begins with
`dict get $data html`. `app-ai.tcl` was passing a raw HTML **string**, so as soon as
the `.report` window already existed the Load path evaluated `dict get "<p>...</p>" html`
and died. The existing UI tests missed it because they never instantiate the report
widget (they test the rendering helpers in isolation).

**Fix.** `::application::ai::htmlData` runs the generated markup through
`::scidb::html::sanitize` (with a hand-built fallback dict), and
`::application::ai::showReport` feeds that to `showHtmlData`. All three call sites
(pre-analysis, error, result) use it.

**Tests.** `tests/test_ai_ui.tcl` now asserts the payload carries the keys `Load` reads,
that the markup survives sanitizing, and pins the regression: the raw-string payload
reproduces the original `dict get` failure, while `htmlData`'s payload is readable.

### B.23 Scrollbar press binds fixed (latent bug the report pane exposed)

Clicking a scrollbar raised

```
can't set "::::(sbset:orient)": variable isn't array
set [namespace current]::(sbset:orient) [.report.sw.sb cget -orient]
```

`tcl/widgets/scrolledframe.tcl` keeps its scrollbar state in namespace variables
(`set (sbset:orient) {}` inside `namespace eval scrolledframe`, read as
`$(sbset:orient)`). Its class binds were written as

```tcl
bind TScrollbar <ButtonPress-1> {+ set [namespace current]::(sbset:orient) [%W cget -orient] }
```

The script is **brace-quoted**, so `[namespace current]` is evaluated when the button is
pressed -- at global scope -- producing `::::(sbset:orient)`: a *different*, bogus variable
(and a plain error when that name already exists as a scalar). So the widget's own
`(sbset:orient)` was never written by a press, and any scrollbar click could abort.
The sibling binds one line below do it correctly with `[namespace code SbSet]` (substituted
at definition time).

Fixed to the same idiom:

```tcl
bind TScrollbar <ButtonPress-1> +[namespace code { set (sbset:orient) [%W cget -orient] }]
```

This is a pre-existing bug in a shared widget -- it affects every scrollbar in the
application, not just the report pane; the report pane merely made it easy to hit (it was
opened by the new AI feature). `tcl/scidb-beta` is a generated bundle, so `make -C tcl`
was rerun to pick the fix up.

Regression tests in `tests/test_app_report.tcl` (run by `make -C tests app-tcl`): one
asserts the press bind names `::scrolledframe` and no longer mentions `namespace current`,
the other evaluates the bound script and asserts it actually sets
`::scrolledframe::(sbset:orient)`. App suite: 61 passed, 0 failed.

### B.24 Report pane rendered the narrative in a ~90px column (fixed)

The AI pane wrapped every line after a few characters -- text squeezed into a narrow strip
at the left of a ~715px pane. Measured geometry showed the widget was fine
(`.report.sw.html.sub.html` = 714px wide), so the fault was in the *document* layout.

`tcl/widgets/html.tcl` (the app's tkhtml wrapper) lays a document out at `-fixedwidth`.
With the defaults it does nothing when the option is unset, then falls back to the
document's `minbbox`:

```tcl
set width [expr {min([lindex $bbox 2], 4000) + $Margin}]   ;# minbbox = widest single WORD
$w.sub.html configure -fixedwidth $width
```

`app-report.tcl` never passed `-fixedwidth`, so the whole document was pinned to the
widest word -- hence one word per line. The other HTML panes avoid this;
`app-information.tcl` explicitly does `$html configure -fixedwidth [expr {min($maxWidth,
$width - 40)}]`.

Fix: `application::report::FitWidth` sets the document width to the pane width, bound to
`<Configure>` on the html widget so it follows resizes, and called once before the first
`Load`. Both the wrapper **and** the inner widget are set, because the wrapper re-applies
its own `-fixedwidth` -- and re-runs the minbbox fallback -- on every parse, so setting
only the inner widget would be undone by the next `Load`.

Verified by rendering the pane under Xvfb and capturing it: the narrative now spans the
full width, `STRUCTURE`/`PIECES`/`PLANS` are separate paragraphs, evidence and claims are
proper bullet lists, and `fixedwidth` tracks the widget (714px widget -> 710).

Regression tests (`tests/test_app_report.tcl`): the document `-fixedwidth` must exceed 100
(i.e. not the widest-word fallback) and must not exceed the widget width. App suite:
63 passed, 0 failed.

### B.25 Tcl audit for flakiness (3 fixes)

Scope: `tcl/` is 235 files / 236,715 lines, so this was a *pattern-and-evidence* audit
rather than a line-by-line read: scan for the known flakiness classes, then verify
empirically (repeat the suites, and look for error noise the harness swallows).

**Found and fixed**

1. **`ai-engine`: no re-entrancy guard.** `evaluate` pumps the event loop
   (`vwait State(done)`), so a second concurrent call -- e.g. the user invoking
   *Explain Position* twice -- clobbered the shared `State(done)`/`State(lines)` and could
   hang or hand back the wrong position's evaluation. It now refuses with a clear error
   instead of corrupting (and always clears the guard, including on the error path).

2. **`ai-narrate`: blocking pipe read could freeze the UI.** `lookup` opened the engine
   with `-blocking 1` and read with `gets`; an engine that never exits hung the whole app
   (the queue-`quit` trick only helps engines that honour it). Made non-blocking with
   `fileevent` + a bounded `after` timeout, mirroring the engine client. Verified: the
   real fork answers in ~0.9 s, while `/bin/cat` (which echoes forever and never exits)
   now returns `{}` at exactly the 1200 ms timeout instead of blocking.

3. **`ai-narrate`: unguarded `$::env(PATH)`** in engine auto-discovery -- an unset PATH
   raised instead of failing the lookup. Guarded.

**Checked and found clean**

- `ai-provider` async: `::http::geturl -command` fires exactly once (completion or error,
  with its own timeout), so there is no double-callback to the UI.
- All external `exec` paths (`ai-precedent`, `ai-annotations`, `ai-narrate`) are wrapped in
  `catch` and return `{}`; a missing/failing helper cannot throw into the prompt builder.
- `ai-claims`, `ai-prompt`, `ai-generate`: no timers, no `exec`, no globals.
- Test flakiness: `make -C tests tcl` and `app-tcl` run 3x each -- 0 failures every time.
- Error noise: grepped all suite output for `invalid command name` / `can't read` /
  `can't set` / `no such element` -- zero occurrences (the only exceptions logged are the
  tests deliberately probing error paths).

**Observed but deliberately not changed**

- `tcl/utils/player-photos.tcl:386` waits unboundedly: `while {![eof $sudoPipe]} { vwait
  ... }`. If `sudo` hangs, that blocks the interface. It is the interactive superuser
  photo-install path, so a timeout belongs there only with testing against a real `sudo`
  prompt -- flagged rather than changed.

### B.26 Extended audit: widget-geometry and timer sweeps

Two mechanical classes checked across all 235 Tcl files.

**1. `winfo width/height` on an unmapped widget (reports 1).** 227 uses. The dialog
placement helper already does it right -- `tcl/utils/place.tcl` falls back to
`max([winfo reqwidth $path], [winfo width $path])` -- as does `app-database.tcl`
(`if {$height <= 1} { return }`) and `browser.tcl` (an explicit `> 1` guard before using a
size). The one unguarded case was `browser.tcl:393`, computing the browser's minsize from a
raw `winfo width` right after `update idletasks`; a window manager that has not yet
configured the window leaves that at 1, giving a bogus minsize on first open. It now uses
the same fallback idiom.

**2. `after <ms>` timers firing after their widget is gone.** 26 timer callbacks take a
widget argument. 24 guard explicitly (`winfo exists` and/or `after cancel` keyed by the
dialog), e.g. `app-database-openingprep.tcl`'s 250 ms poll returns early on a missing
dialog and cancels on `<Destroy>`, and `app-pgn.tcl`'s cursor timers check
`winfo exists` plus a counter. The remaining two (the `Tick` callbacks in
`corrclock.tcl`) are cancelled by a `<Destroy>` binding. Nothing to fix -- this codebase's
timer hygiene is sound.

Verified after the one change: tcl 0 failed / PASSED, app-tcl 0 failed / PASSED,
ai-tests 11 suites green.

### B.27 C1 shipped: selection → explanation (implemented)

Appendix C's first task is in the tree. The model is now reachable from the three panes
where context already exists, without a new menu:

- **Notation pane** — right-click a move → *Explain this move*. `::application::pgn::ExplainMove`
  reads the SAN and the position it was played from, then calls the shared entry point.
- **Game list** — right-click the selected row → *Explain this game*.
- **Comment editor** — right-click → *Explain this comment*.

All three route through one dispatcher, `::application::ai::explainSelection {kind payload}`,
which maps the selection to the right fact-pack builder and renders through the existing
`toHtml` / `showReport` path. The `analyze` body was factored into
`::application::ai::generate` (placeholder → grounded generation → claim check → retry), so
every entry point shares the same pipeline — the plan's "one grounding path".

Two supporting additions:

- `::scidb::game::query move <key>` returns the SAN at a key without disturbing the current
  position; `::scidb::game::query movefen <key>` returns the FEN *before* that move. The
  latter is what `moveFacts` / `classify` need (they parse the move in the position it was
  played from), and it avoids mutating game state to obtain it.
- `::ai::generate::buildMessages` / `positionToolsAsync` take an optional `-context` string:
  the selection is the task, the fact pack still grounds it.

Verified: `tests/test_app_move_query.tcl` (12 cases, `move` + `movefen`), tcl 0 failed /
PASSED, app-tcl 175 passed / 0 failed, ai-tests 11 suites green. The three context menus
were built in a headless probe and the entries confirmed present and enabled.

---

## Appendix C — More LLM-as-intermediary features (proposed)

Status: proposal, not committed scope. Date: 2026-09 (draft).

Sections 1–9 proposed the *grounding layer* and the first feature wave; Appendix B records
what shipped. This appendix proposes the **next** wave, chosen for one property: the model
sits *between the user and the app* — it turns intent into an action, or app state into
understanding — rather than being a destination the user visits. Every proposal below is
grounded in the machinery that already exists (fact packs, claim checker, the assistant
tool table, the report pane, the evidence layers), so each is an integration, not a new
subsystem.

The current surface is deliberately small: three menu entries (`AI: Explain Position`,
`AI: Assistant`, `AI: Choose Model...`) and a ~40-tool assistant. The gap is not capability
— the tools can already search, prepare, run engines and read state — it is **reach**. The
model is reachable only from a chat pane and one menu item. The features below widen reach
and shorten the path from "I want X" to X.

### C.1 The organising idea: the model as a *lens*, not a *place*

Three interaction shapes, in increasing order of ambition:

1. **Ambient** — the model annotates or explains something the user is already looking at,
   with no prompt typed (a hover, a selection, a status line).
2. **Command** — the user states an intent in the UI they are already in (a search box, a
   game list, a comment field) and the model produces a *validated* artifact (a query, a
   filter, a draft) that the existing deterministic code executes.
3. **Agentic** — the model chains existing tools to complete a multi-step task, with the
   user confirming each mutating step (the assistant already does this; the proposals
   extend *where* it can be invoked and *what* it can reach).

The rule from P1/P2 is unchanged: the model never reasons about the board and never
invents a fact. What changes is *where the user meets it*.

### C.2 Ambient features (no prompt typed)

#### C1 — Selection → explanation ("explain this") ⭐⭐⭐ E:S R:L
- **What:** Select a move, a comment, a game row, or a block of the report pane and get a
  grounded explanation of *that thing*, in place. A right-click "Explain" on a move in the
  notation pane explains the move (using `::ai::engine::classify` + `::scidb::ai::moveFacts`
  + the precedent/annotation layers); on a game row it summarizes the game; on a comment it
  expands or translates it.
- **Why:** the highest-frequency UX win. Today the user must copy context into the chat
  pane; here the context is already selected. It also makes the grounding layer reachable
  from every pane without new menus.
- **How:** a shared `::application::ai::explainSelection <kind> <payload>` that maps a
  widget selection to the right fact-pack builder, then renders through the existing
  `::application::ai::toHtml` / `showReport` path. The move case reuses `classify`; the
  game case reuses `DoCurrentGame`'s PGN + `position_moves`.
- **Guardrail:** identical claim-check + retry as `analyze`; the report pane already shows
  evidence and the verified/unverified verdict (B.21).

#### C2 — Hover/status-line "what is this?" ⭐⭐ E:S R:L
- **What:** a status-line hint for the current position or the hovered move, generated once
  and cached by position hash: "White is slightly better; the c4 pawn is isolated; last
  played 2019." One line, no pane.
- **Why:** zero-friction orientation. It is the cheapest possible use of the fact pack
  (which is already computed for the tree) and needs no LLM call at all for the
  deterministic half — the model is only needed to phrase it.
- **How:** reuse `::scidb::ai::text` (the human-readable fact pack) for the deterministic
  line; optionally pass it through the provider for phrasing, cached by
  `hash(fen, template_version, model)`. Degrade to the deterministic line when no provider
  is configured (P3/offline).
- **Note:** this is the one feature that should work *without* a model — the fact pack is
  already prose-able. The model is an enhancement, not a dependency.

#### C3 — "Explain the engine's line" in the analysis pane ⭐⭐⭐ E:S R:M
- **What:** a button in each analysis pane that narrates the engine's current PV in words,
  grounded in the PV itself plus the move facts for each move of the line.
- **Why:** the analysis pane is where users spend the most time and where the raw output
  (a string of moves and a number) is least self-explanatory. This is the natural home for
  "Consult AI" — closer to the work than a separate report pane.
- **How:** `::ai::engine::evaluate` already returns `pv`; feed the PV through
  `::scidb::ai::moveFacts --line` (B.4) to get per-move facts, then generate. The claim
  checker already validates move sequences against a position.
- **Guardrail:** the narration must cite the engine's own eval and PV; the claim checker
  flags any move not in the line.

### C.3 Command features (intent → validated artifact)

#### C4 — Natural-language search box in the database tab ⭐⭐⭐ E:M R:M
- **What:** a search field above the game list that accepts "Carlsen's losses as Black in
  the Najdorf since 2015" and produces the *existing* advanced-search selector, shown for
  editing and confirmed before it runs.
- **Why:** this is F8, but the UX point is *where* it lives: in the database tab, next to
  the game list, not in a chat pane. The assistant already has `search_games` +
  `BuildQuery` (which builds scidb's search language from checked fields, so no model text
  reaches the search engine) — this exposes that same path as a first-class UI control.
- **How:** reuse `::application::assistant::BuildQuery` and `CheckArgs`'s `search_games`
  validation verbatim; the model's only job is to fill the fixed field dict. Show the
  generated criteria as editable chips, then call the existing `::scidb::view::search`.
- **Guardrail:** never auto-execute; the query is always shown first (P5). The model emits
  *fields*, not query text.

#### C5 — "Find games like this one" ⭐⭐ E:S–M R:L
- **What:** from the current game, one click finds the most similar games in the active
  database — same opening, same material signature, same result pattern — and explains
  *why* they are similar.
- **Why:** a natural database task that today requires the user to hand-build a search.
  The similarity is deterministic (ECO + position keys from the precedent index); the model
  only phrases the rationale.
- **How:** the precedent index (B.10/B.20) already keys positions by sha1; take the game's
  positions, look up the most-shared continuations, and rank candidate games by overlap.
  The model summarizes the shared features from the fact packs.
- **Guardrail:** the "why similar" text is generated from the overlap facts, not invented.

#### C6 — Comment/annotation drafting in place ⭐⭐⭐ E:M R:M
- **What:** in the comment editor, a "Draft" button that proposes a grounded comment for
  the current move (using `classify` + move facts + precedent), which the user edits and
  saves through the existing `::scidb::game::update comment` path.
- **Why:** this is F9, but scoped to *one move, in the editor the user already has open*,
  rather than a batch job. It is the lowest-risk form of annotation writing (P4: the user
  is the review queue) and it meets the user where the write happens.
- **How:** `tcl/comment.tcl` already writes via `::scidb::game::update comment $key $pos
  $comment`; add a Draft button that fills the text widget. No new write path.
- **Guardrail:** the draft is never auto-saved; the claim checker runs before it is shown,
  and ungrounded claims are flagged inline in the editor.

#### C7 — "Explain this comment" / translate in place ⭐⭐ E:S R:L
- **What:** right-click a comment → "Explain" (expand a terse note into prose) or
  "Translate" (into another language slot, F10).
- **Why:** the corpus is multilingual (B.18/B.19) and many comments are terse
  ("Inaccuracy. h5 was best."). Expanding and translating them in place makes the existing
  database more readable without any new data.
- **How:** reuse the comment read/write commands and the language slots scidb already
  stores; translation transforms existing human text, so it is low-risk (no facts invented).

### C.4 Agentic reach (extend the assistant)

The assistant's tool table is the strongest asset and the least reachable. These extend
*what it can reach* and *where it can be invoked*, not its architecture.

#### C8 — Assistant entry points beyond the pane ⭐⭐⭐ E:S–M R:L
- **What:** invoke the assistant from (a) a global keyboard shortcut, (b) a right-click
  "Ask the assistant about this…" that pre-fills the selection as context, and (c) the
  command line (`--ask`, which already exists via `::remote`).
- **Why:** the assistant is currently a pane the user must open and type into. Pre-filling
  context from a selection removes the copy-paste step and makes the tool table reachable
  from anywhere.
- **How:** `ask` already accepts a request string and an `-observer`; add a context
  preamble built from the selection (reusing C1's selection→payload mapping). The
  `--ask`/`--chat` terminal path already exists (`attach`, `RemoteRead`).

#### C9 — Tools for the panes the assistant cannot see ⭐⭐ E:S–M R:L
- **What:** add read-only tools for the surfaces the assistant currently cannot reach:
  the current game's comments/annotations as structured records, the game list selection,
  the report pane contents, and the board's move history. Today the tool table covers
  search, prep, engines and diagnostics; `current_game` returns the game's comments only
  as part of its PGN, and there is **no** tool for the game-list selection or the report
  pane at all.
- **Why:** the assistant can answer "what is played here" but not "what does this game's
  comment say" or "what is selected in the game list". Closing that gap makes the existing
  conversational surface genuinely complete.
- **How:** thin wrappers, exactly like the existing `Do*` handlers: read the comment store
  (`::scidb::game::query`), the game list selection, and the report pane's current
  document. All read-only, so no confirmation needed.
- **Guardrail:** read-only tools only; any write stays behind the existing confirm gate.

#### C10 — "Do this for me" from a report ⭐⭐ E:M R:M
- **What:** the report pane (which already renders AI output and evidence) gains action
  links: after an explanation, "show these games", "start an engine here", "annotate this
  move". The link invokes the corresponding assistant tool.
- **Why:** closes the loop between *understanding* and *acting*. Today the explanation is a
  dead end; the user must re-state the intent in the chat pane.
- **How:** the report pane already renders sanitized HTML with anchors
  (`::scidb::html::sanitize` returns `anchors`); map a custom anchor scheme
  (`ai:tool:search_games?...`) to `runTool`. Mutating tools still confirm.
- **Guardrail:** the anchor only names a tool from the fixed table with checked arguments —
  the same gate as the chat path.

#### C11 — Multi-step task templates ⭐⭐ E:S R:L
- **What:** named, one-click assistant tasks that chain existing tools: "Prepare against
  the player in the game list", "Summarize this database", "Check my repertoire against my
  games". Each is a canned request string the assistant already knows how to fulfil.
- **Why:** the assistant can already do these, but the user must know to ask. Templates
  make the capability discoverable and repeatable, and they are pure prompt presets — no
  new code paths.
- **How:** a small table of `{label request}` entries surfaced in the assistant pane and
  the Extras menu; each calls `ask $request`. The tool table does the rest.

### C.5 Cross-cutting UX concerns for this wave

- **Latency honesty.** Every ambient feature (C1–C3) must show a placeholder immediately
  and stream or replace it, because it is invoked mid-task. The async paths already exist
  (`completeAsync`, `positionToolsAsync`); the UX rule is "never block the pane the user is
  working in".
- **Cache by position hash.** C2/C3 are invoked repeatedly on the same position; the
  content-addressed cache (F3) makes repeats free. This is what makes ambient features
  affordable.
- **One grounding path.** C1, C3, C6 and C10 must all route through the same
  fact-pack → prompt → claim-check → retry pipeline as `analyze`. Divergent paths are how
  trust erodes; the claim checker is only meaningful if everything goes through it.
- **Discoverability over capability.** The bottleneck is reach, not ability. Prefer
  surfacing the existing tools in the panes where the work happens over adding new tools.
- **Graceful absence.** With no provider configured, C2 falls back to the deterministic
  fact-pack line, and C1/C3/C4/C6/C10 show a "configure AI" affordance rather than failing
  (P3/offline).

### C.6 Suggested sequencing for this wave

| Order | Feature | Why first |
|---|---|---|
| 1 | C1 (selection → explain) | Highest frequency, reuses everything, no new menus |
| 2 | C4 (NL search box) | Highest-value database feature; reuses `BuildQuery` |
| 3 | C3 (explain the PV) | Meets users where they already are (analysis pane) |
| 4 | C6 (draft a comment) | Core DB workflow, lowest-risk write (user reviews) |
| 5 | C8, C9 (reach + missing tools) | Makes the assistant complete and reachable |
| 6 | C2, C5, C7, C10, C11 | Ambient polish and loop-closing |

### C.7 What this wave deliberately does not do

- No new grounding machinery — every feature reuses the fact pack, claim checker and
  evidence layers.
- No new write path — C6/C7 write through the existing comment commands, behind review.
- No autonomous action — C10's action links and C11's templates still confirm mutating
  tools, exactly as the chat path does.
- No model reasoning about the board — unchanged from P1.
