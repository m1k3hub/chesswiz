# AI Products Plan — from infrastructure to features

**Status:** plan + Wave 0 implemented (`tcl/app-voice.tcl`, `scripts/stt-transcribe.py`).
**Companion:** `JEV_USE_CASES.md` (the decision-model contracts) and
`LLM_REACH_PLAN.md` (the grounding pipeline tasks) — this document is the product
slate the infrastructure was built for.

## 0. The three primitives, and the firewall

Everything below is a composition of what the tree already has:

| Primitive | Where it lives | What it guarantees |
|---|---|---|
| **Grounded analysis loop** | `tcl/ai-generate.tcl`, `tcl/ai-claims.tcl`, `tcl/ai-prompt.tcl`, `src/db/db_chess_facts*` | facts in → prose out → ungrounded chess claims caught and retried |
| **Bounded decision models** (Jev-class) | `tcl/ai-systemone.tcl` + the chooser | calibrated `choice`/`noul`/`score` with confidence gates — ranking, bucketing, gating only |
| **Local data acquisition** | `tcl/app-download-games.tcl`, `::ai::precedent` index, player photos, format importers | games/media/models arrive on the machine, never the other way |

**The firewall (never negotiable):** move quality, evaluations, tablebase outcomes
and opening identity come from Stockfish, the fact layer, or the ECO table. The
classifier ranks and gates; the LLM narrates; neither is ever the authority on the
board. Every feature below restates its own version of this.

**Cross-cutting requirements** (apply to every feature in this document):

1. **Pluggable, never hard-coded.** No model, backend, engine, voice or port is
   named in logic. Everything is chosen in a dialog or an env var, and discovered
   at runtime where possible.
2. **Graceful absence.** Missing server, missing binary, missing GPU, no
   microphone ⇒ the feature hides, disables, or degrades to a deterministic path.
   Startup must survive a poisoned settings file (see `b62d63b`).
3. **Confidence-gated.** Anything a classifier decides has a threshold, an env
   override, and a fallback that is today's behaviour.
4. **Local-first and private.** Audio, error logs, games and comments do not leave
   the machine unless the user picked a cloud backend for that task.
5. **Fit the machine.** Features must work on 8 GB Turing/Pascal cards and on CPU;
   measure and state the cost.
6. **Auditable.** Where a report makes a claim, the fact/engine line that grounds it
   is available to the user ("show your work").
7. **Bounded blast radius.** Mutations confirm; a wrong classification costs a
   screen, not data.

---

## Wave 0 — Voice-driven assistant (implemented)

### Design

```
 microphone ─► record (raw PCM 16k mono) ─► silence trim ─► STT ─► text
                                                                   │
                                        ┌──────────────────────────┴─────────┐
                                        │  assistant::ask (unchanged)        │
                                        │  router / tools / confirm gate     │
                                        └──────────────────────────┬─────────┘
                                                                   │ reply
                                                        TTS (only for voice turns)
```

* **Recording** — raw PCM (`arecord`/`ffmpeg`/`rec`, auto-detected, configurable),
  written incrementally so a poller can watch the tail for silence and **stop on
  its own** after the user stops speaking. The WAV wrapper is written by us
  (`wav::fromRaw`), so we never depend on a recorder finalising a header.
* **Silence** — RMS per 20 ms window; trim head/tail, drop clips that are all
  silence. Pure functions, unit-tested on synthetic PCM.
* **Speech to text** — pluggable command; the shipped engine is
  `scripts/stt-transcribe.py` (faster-whisper, CPU int8 or CUDA float16, model
  chosen by the user). Two modes: **one-shot** (any command that prints the
  transcript) and **server** (the same script with `--serve`, model loaded once,
  transcripts exchanged line-by-line — this removes the ~2 s per-call load cost).
* **Assistant** — the transcript is sent through the ordinary
  `::application::assistant::ask`, so routing, tools, grounding and the **confirm
  gate are inherited unchanged**. Voice adds no new authority.
* **Speech back** — optional TTS (piper with a voice model, else espeak-ng), mode
  `voice` (default: speak replies to spoken requests), `always`, or `off`.
* **Honesty about errors** — recognition is imperfect (proper nouns in particular:
  "Nepomniachtchi" was heard as "Nepomniage"). Therefore: the transcript is shown
  in the pane, a **review mode** can hold it in the entry for editing, mutating
  tools still confirm with the *resolved* action, and the tool layer's own
  fuzzy-name handling (candidate lists) covers the rest.

### Integration

| Piece | Where |
|---|---|
| capture, STT, TTS, session flow | `tcl/app-voice.tcl` (`::application::voice`) |
| transcriber CLI | `scripts/stt-transcribe.py` (`--serve` for the persistent mode) |
| assistant pane button + status | `tcl/app-assistant.tcl` (guarded by `info commands ::application::voice::toggle`) |
| Extras menu + key binding | `tcl/menu.tcl`, `tcl/application.tcl` |
| assistant tool `voice_status` | `tcl/app-assistant.tcl` (Actions table) |
| settings | options file (`::application::voice::WriteOptions`), env overrides |

### Settings

```
SCIDB_AI_STT=auto|off|"<command template>"      default auto (discovers engines)
SCIDB_AI_STT_MODEL=small.en                     tiny.en | base.en | small.en | medium.en | large-v3 ...
SCIDB_AI_STT_DEVICE=cpu|cuda                    cpu → int8, cuda → float16
SCIDB_AI_STT_SERVER=1                            keep the model loaded between utterances
SCIDB_AI_RECORDER=auto|"arecord -q -f S16_LE -r 16000 -c 1 -t raw -"
SCIDB_AI_TTS=auto|off|piper|espeak-ng           default auto (discovers engines)
SCIDB_AI_TTS_VOICE=<name or .onnx path>         piper voice
SCIDB_AI_TTS_MODE=voice|always|off              default voice (speak only voice turns)
SCIDB_AI_VOICE_REVIEW=1                         hold the transcript for editing
SCIDB_AI_VOICE_MAX_SECONDS=30                   hard cap per utterance
SCIDB_AI_VOICE_SILENCE_MS=900                   auto-stop after this much silence
```

### Reliability contract

| Question | Answer |
|---|---|
| Can voice make a chess claim wrong? | No — it only produces *text*; everything downstream is the audited text path. |
| Can a misheard command act destructively? | Only through the existing confirm gate, which shows the resolved action. |
| What if there is no microphone/engine? | The button and menu entry disable, `voice_status` says what is missing and how to fix it. |
| What if the STT server dies? | The one-shot path is retried once; then the utterance is reported as failed and the pane keeps the typed path. |
| Does audio leave the machine? | No. The model is downloaded once; inference is local. |

### Cost measured on this machine

`espeak-ng` audio → faster-whisper, CPU int8, 48-core Xeon (per call, model load
included): `tiny.en` ~2.9 s (inaccurate), `base.en` ~2.2 s (inaccurate),
`small.en` ~4.2 s (exact). **Server mode removes the load**: measured live in the
app, cold 4.7 s / warm 2.1 s for the same sentence, transcript exact. Default is
`small.en` — for a spoken command, correct beats two seconds faster — and
`--device cuda` is a config change, not a code change.

Live checks that passed in the app: exact transcript → `assistant::ask`; a silent
clip reports "nothing heard"; a difficult name came back imperfect ("prepare
against Nepomniachtchi" → "repair against Nepomniac"), which is exactly why the
transcript is shown, review mode exists, and the confirm gate shows the resolved
action.

---

## Wave 1 — Analysis products with receipts

| Feature | Composition | Reliability | Effort | State |
|---|---|---|---|---|
| **Study plan** (mistake autopsy) | the engine classifies every studied move → each mistake is labelled by *pattern* from the position facts (undefended pieces, pins, forks, phase, king safety) — deterministic rules first, the classifier as a second opinion behind a confidence gate → clusters ranked by count and damage → a plan with the evidence and what to train, and an optional model summary grounded in the cluster table | the engine owns what happened; the classifier only labels, and falls back to rules; examples are engine verdicts | M | **shipped** |
| **Annotation fact-checker** | the existing deterministic claim checker pointed at *human* prose: every comment of a game is read with the position it annotates and reported only when the facts contradict it | reproducible, no model, no engine, no network; only positive contradictions are reported, so a clean report is meaningful | S | **shipped** |
| **Auto-annotate a game** (flagship) | `::ai::engine::classify` per move (truth) → a deterministic gate over the engine's verdict decides which moves deserve prose → a dedicated grounded draft (`ai::provider::completeAsync` + the move facts) → `::ai::claims::check` → `::scidb::game::update addcomment`/`annotation` | only the engine classifies moves; the gate cannot invent; a comment whose claims the facts contradict is never written; the game is left modified for the user to save | M | **shipped** |
| **Mistake autopsy + study plan** | batch classify the user's games → cluster by engine features → classifier labels the *pattern* (`choice`: tactical/opening/endgame/time) → LLM writes a plan grounded in the clusters (claims checked) | patterns are labelled, not invented; examples are engine-verified | M |
| **Annotation fact-checker** | paste any annotated PGN → `::ai::claims::check` + fact layer flag the author's ungrounded claims | deterministic checker; no model involved | S |
| **Provable endgames** | Syzygy tablebase into the fact layer → "was it winning?" *proved*, then explained | tablebase is truth; the LLM may not contradict it | M |

## Wave 2 — Preparation and data

| Feature | Composition | Reliability | Effort |
|---|---|---|---|
| **One-click opponent brief** | `download_games` → `prepare_against` + dossier → classifier ranks their dangerous lines → engine verifies each → claim-checked brief in the report pane | engine decides soundness; classifier ranks; checker audits | M |
| **Repertoire gap detector** | repertoire DB × my games × opponent's games → classifier scores urgency → candidates validated by Stockfish | engine is the arbiter of playability | M |
| **Novelty radar** | `::ai::precedent` × fresh imports → find new moves → classifier labels (novelty/side-line/transposition/blunder) | "playable?" is the engine's answer | M |
| **Correspondence copilot** | XFCC move in → engine → repertoire compare → 3 candidates → position-type label → "out of book" warning | candidates engine-verified; auto-submit keeps its deterministic material gate | M |

## Wave 3 — Self-maintaining data

| Feature | Composition | Reliability | Effort |
|---|---|---|---|
| **Curation pipeline** | scheduled `download::run` (headless, shipped) → duplicate detection → classifier arbitrates ambiguous merges (confidence-gated, user reviews) → digest | dedupe is deterministic; only doubtful merges ask the classifier | M |
| **Weekly digest / watchers** | timer → download → import → precedent check against my repertoire → report pane | facts are deterministic counts; prose checked | S–M |
| **Online-game sync** | Lichess per-game fetch (shipped) batched by account → tag as mine → feed Wave 1 | same path, no new trust | S |
| **Import triage** | on import: classifier buckets games (tournament/analysis/fragment), ECO-tags via the table | buckets are advisory and reviewable | S |

## Wave 4 — Agent, meta and tuning

| Feature | Composition | Effort |
|---|---|---|
| **Named workflows** | chained tools behind one request ("prepare for my league game"), mutations gated | S–M |
| **Model-fit + calibration battery** | detect device memory → recommend the quant → download → serve → run a 10-item battery → report accuracy/latency per backend and *suggest thresholds* | M |
| **Threshold autotune** | record every user override of a classifier verdict; refit thresholds offline | S |
| **"Show your work"** | render the grounding fact/engine line beside each generated claim | S–M |
| **Self-repair loop** | triage → issue file → coding-agent handoff → re-run tests (half shipped) | S |

## Anti-ideas (do not build)

Move quality, "who stands better", opening names, tablebase verdicts, and any
"is this a good move" — Stockfish/facts/ECO or nothing. No feature may let a model
speak about the board without a grounding line. No autonomous mutation without the
confirm gate. No cloud call for audio, error logs or private games by default.

## Sequencing and success measures

| Wave | Ship gate |
|---|---|
| 0 voice | transcript reaches `ask`; mutating tools still confirm; no-mic and no-STT paths degrade cleanly; suites green |
| 1 auto-annotate | annotated game opens in stock Scidb; zero ungrounded move mentions across a 20-game sample; runtime < 2 s/move on CPU |
| 2 brief/copilot | every suggested move appears in an engine PV; the user can trace each sentence to a fact |
| 3 curation | a month of TWIC runs unattended; zero data loss; every merge decision is reviewable |
| 4 tuning | thresholds refit from real overrides; battery output reproducible |

## Status

| Feature | State |
|---|---|
| Error triage, rhetoric/coverage advisories, tool pre-routing | shipped |
| **Auto-annotate a game** (`tcl/ai-annotate.tcl`, Extras + assistant tool) | **shipped** |
| **Study plan** (`tcl/ai-studyplan.tcl`, Extras + `study_plan` tool) | **shipped** — engine-bound: one search per studied move, so a sample of games takes minutes; the report names the patterns and the evidence |
| **Annotation fact-checker** (`tcl/ai-factcheck.tcl`, Extras + `factcheck_annotations` tool) | **shipped** — verified live: a human comment claiming an isolated queen's pawn in a position without one is flagged | — engine-only mode for free, LLM prose checked against the facts; needs `::scidb::game::query mainline` (new, C++), which returns {key san fenBefore} per ply without disturbing the board |
| Download games (GUI + assistant + headless) | shipped |
| Classifier backends in the chooser (kev/simple-jev/plumb/jev) | shipped |
| **Voice-driven assistant** | **shipped (Wave 0)** |
| Everything else | planned here |
