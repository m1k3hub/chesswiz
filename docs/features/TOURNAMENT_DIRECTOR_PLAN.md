# Tournament Director (TD) for Chesswiz: plan

Status: draft 2, 2026-11-14 (after the ChatGPT and Gemini reviews; see section 6, which overrides sections 3 to 5 where they conflict). Mission 5.
Goal: the user can run a complete chess event, for humans, engines, or both, from start to finish. The event can be run through the TD workspace or by asking the assistant ("run a thematic London System 3+2 round robin between my engines", "pair round 4", "Smith withdrew", "who won on tiebreak?").

## 1. What a TD does (scope)

| Phase | Duties |
|---|---|
| Set-up | Event rules: system (round robin / double round robin, FIDE Dutch Swiss, knockout, Scheveningen, team), rounds, time control, tiebreak order, bye rules, default time, rating system (FIDE / national / unrated), prize fund and how tied prizes are split. |
| Registration | Players: name, FIDE ID, rating, federation, title. Late entries, requested half-point byes, sections, seeding, pairing numbers, drawing of lots. |
| Each round | Pairing (with colour balance, no repeat games, floats and the bye); publishing pairings and boards; manual override with an audit trail; recording results (including forfeits, double forfeits, adjourned games and later corrections); withdrawals and late arrivals. |
| During play | Laws of Chess: illegal moves, flag falls, insufficient material, draw claims (threefold, 50 moves), the 75-move and fivefold rules; fair play; rulings and appeals. |
| Finish | Standings after each round (Buchholz, Buchholz Cut 1, Sonneborn-Berger, direct encounter, wins, ARO, performance rating); crosstable; prizes; norms; FIDE TRF rating report; PGN, HTML and bulletin publishing. |
| Engine extras | Opening sets played with both colours; adjudication; several games at once; crash and timeout handling; Elo estimate with error bars; SPRT. |

Reference tools: Swiss-Manager / Vega / SwissSys (desktop human events); JaVaFo / bbpPairings (FIDE-endorsed pairing engines); Tornelo / chess-results (web publishing); cutechess-cli / fastchess (engine events). None of them mixes humans, engines and online players, and none has an assistant TD. That combination is what Chesswiz adds.

## 1b. Product principle (user, 2026-11-14)
Build **complete tournament-manager software** inside Chesswiz, as good as Swiss-Manager or Vega for a human TD, **and make it fully operable by the assistant**.
- Every screen, field, button and report is a registry action with typed arguments. Nothing exists only in the UI.
- A parity test enforces it, as in the menu mission: every TD UI action has an Ask tool equivalent, and the reverse.
- The assistant can run an event from creation to the TRF report without the user touching the TD window. The user can also do everything by hand.

## 1c. Existing tournament managers per platform (ideas, code, inspiration)

| Platform | Program | Licence / status | What to take |
|---|---|---|---|
| Windows | **Swiss-Manager** | Commercial, FIDE-endorsed (JaVaFo) | Workflow standard: tournament wizard, player import from rating lists, round tabs, result entry by board number, chess-results upload, team events. UX reference for the Players / Pairings / Results tabs. |
| Windows | **SwissSys**, **WinTD** (WinTD also on Mac) | Commercial | US Chess rules, prize calculator, wall charts, team scoring, "pairing card" view, manual pairing with warnings. SwissSys uses bbpPairings, which confirms that choice. |
| Win / Linux / macOS / Raspberry Pi | **Vega** | Freeware, endorsed (JaVaFo) | 30+ tiebreaks, HTML site generation, cross-platform proof; an import/export partner for TRF round-trip tests. |
| Linux (KDE) | **Chessament** | Open source (KDE) | Qt/KDE Swiss manager: data model and TRF handling to read for ideas. |
| Win / Linux / macOS | **Gambit Pairing** (PyQt6), **Pawn** (Tauri/Rust), **Ponziani Swiss** (Java), **JavaPairing** (GPLv3), **Coronate** (web) | Open source (licences must be checked one by one) | Read for UI flows, the TRF parser and tiebreak code; take test vectors and edge cases. Copy code only where the licence is compatible with GPL-2+. **Code reuse is limited to bbpPairings** (helper program). Everything else is a reference. |
| Engine side, all platforms | **cutechess-cli**, **fastchess** | GPL / MIT | Opening-book options, concurrency, SPRT, adjudication flags, PGN tagging: copy the option set for engine events. |
| Web / iPad | **Tornelo**, **ChessManager**, **chess-results**, **SwissSystem (iPad)** | Commercial services | Live public standings, player self-registration and mobile result reporting. Phase 3+: optional HTML/JSON publishing. |
| macOS gap | Few native Mac tools (WinTD, the iPad app, web tools) | | Chesswiz already runs on macOS, so a native cross-platform TD is a real gap to fill. |

Before coding, the P1 investigation reads Chessament, Gambit, Pawn and Ponziani source (data model, TRF I/O, tiebreaks) and records patterns and test vectors in `docs/features/td-research/`.

## 2. Existing Chesswiz code to reuse

| Need | Existing code | Reuse |
|---|---|---|
| Engine-vs-engine games, clocks, adjudication, tablebase claims, Termination tag, saving games to a database | `tcl/engine-match.tcl` (`::enginematch::StartMatch`, `RequestMove` test hook, watchdog, flag falls, resign/draw rules, local Syzygy then online tablebase) | Extract a **game runner** (`::td::runner`) that plays one pairing given two seats, a clock and an optional start position, and returns a result plus Termination. `engine-match` becomes a thin client of it. |
| Human vs engine at this computer | `tcl/play-engine.tcl` (board input, wall-clock clock ledger, resign/draw/takeback) | Human-at-board seat for a round's local game. |
| Engine roster and configuration | `tcl/engine.tcl`, `tcl/engines/`, `::enginematch::EngineNames` | Engine seats choose from the configured engines. |
| Player identity: FIDE ID, rating, federation, title | `tcl/player-data.tcl` (monthly FIDE list, on request), `tcl/player-dict.tcl`, `tcl/player-card.tcl`, `tcl/playertable.tcl` | Registration autocomplete and pre-fill; the rating list is frozen at the event's start date. |
| Online play | `tcl/lichess-api.tcl` (`challengeUser`, `challengeAi`, `arenas`, `swissOfTeam`), `tcl/lichess-events.tcl`, the board stream | Lichess seats: a game is created by a challenge and its result is collected from the stream. Phase 3 may also create Lichess Swiss/Arena events. |
| Game storage and PGN | Native database layer (`scidb::db`, `scidb::game`), clipbase, `tcl/export.tcl`, `tcl/app-pgn.tcl` | Each event gets its own database. Games carry Event, Site, Date, Round, Board, White/Black, Elo and FideId tags. PGN export is unchanged. |
| Crosstable display | `tcl/crosstable.tcl` (upstream Scidb crosstable, already reachable as the `tournament.table` action) | Live standings view. Extend it with the new tiebreak columns and a pairings tab, keeping a single crosstable widget. |
| Printing and HTML | `tcl/print.tcl` (native PDF), crosstable HTML save | Pairing sheets, wall charts, score sheets, bulletin. |
| Rules of play | Native move generation / position (`scidb::pos`, `scidb::game`): legality, repetition, 50/75 moves, insufficient material | The arbiter checks for engine and local games, and suggested rulings for over-the-board games. |
| Assistant | `tcl/app-assistant.tcl`, the action registry (`tcl/actions.tcl`, `inventory-actions.tcl`, `dropdown.tcl` tool dispatch), `tcl/knowledge.tcl` topic pages, capability gates (`tcl/capability.tcl`) | TD tools are registry actions (one registry). The TD reference becomes knowledge topic pages. A `td` capability module controls everything. |
| Menus | Registry dropdown/context (menu mission) | Training > Tournament Director..., plus C-contexts for the pairings and standings tables. |

## 3. New components

### 3.1 Tournament model (`tcl/td-model.tcl`, pure Tcl, no Tk)
- Entities: Event, Section, Player (seat kind: `human-local | human-otb | engine | lichess`), Round, Pairing (board, white, black, result, termination, game id), Bye, Withdrawal, Ruling, AuditEntry.
- **Storage is FIDE TRF-2016 (TRF16) plus a Chesswiz extension record.** TRF is both the save format and the export. It is the format bbpPairings, Swiss-Manager and Vega read, and the FIDE rating report.
- Saved after every change (atomic write with a `.bak` copy), so the event resumes after a crash or restart.
- Undo through the audit log: every pairing override, result correction and ruling is a reversible audit entry.

### 3.2 Pairing (`tcl/td-pair.tcl`)
- Round robin and double round robin: Berger tables (FIDE C.05 Annex 1), with a bye for an odd number of players; drawing of lots.
- Knockout: seeded brackets, mini-match length, an Armageddon or blitz playoff.
- Swiss: **bundle bbpPairings** (the open-source FIDE-endorsed engine) as a helper program, like Stockfish, built for Linux, Windows and macOS. Input and output are TRF. It covers Dutch (2026 rules) and Burstein.
  - Its checker mode validates every manual override; an illegal override is allowed only with an explicit TD ruling entered in the audit log.
  - Do not write our own Dutch pairer. Fallback if the helper program is missing: refuse Swiss and allow round robin or knockout only (capability gate).
- Accelerated pairings and requested byes go through bbpPairings options or TRF fields.

### 3.3 Tiebreaks and standings (`tcl/td-score.tcl`)
- FIDE C.07 tiebreaks: Buchholz (+ Cut 1 / Median), Sonneborn-Berger, direct encounter, wins, wins with black, ARO, TPR, Koya, cumulative.
- Unplayed games are handled the FIDE way (virtual opponent).
- Prize allocation with splitting rules. Elo estimate with error bars and SPRT for engine events.
- Golden tests: reproduce published crosstables (chess-results events and examples from the FIDE manual) exactly.

### 3.4 Round runner (`tcl/td-runner.tcl`)
- Takes the pairings and starts each game according to its seat kinds:
  - engine vs engine: the extracted game runner; N at once (N set by the user, default `cores / threads per engine`).
  - human-local vs engine/human: a board slot with `play-engine`-style input.
  - human-otb: no game is played in the app; the TD enters the result (optionally with PGN entry later).
  - lichess: challenge plus the stream; the result is collected automatically; a timeout counts as a forfeit, subject to TD confirmation.
- Opening themes (`tcl/td-openings.tcl`): a name ("London System"), an ECO range, or a move list gives a balanced opening set. The source is the user's databases or a bundled book. Each opening is played with both colours (the existing suite logic in `engine-match`).
- Gameplay screen: the board shows one game; a game switcher lists the boards; a round-progress bar.

### 3.5 Arbiter (`tcl/td-arbiter.tcl`)
- Automatic for games played in the app: illegal move (FIDE time penalty, or a loss on the second illegal move in blitz/rapid as configured), flag falls versus insufficient material, automatic 75-move/fivefold endings, engine claims for 3-fold/50.
- Over-the-board and disputes: the TD describes the incident in words, the assistant cites the rule (Laws of Chess, from knowledge topics), and the TD confirms. The ruling is recorded in the audit log.
- Fair-play hooks (phase 3): engine-match statistics on human games, run offline, as a report only and never an automatic decision.

### 3.6 TD workspace (`tcl/td-ui.tcl`)
- Tabs: Event, Players (registration and FIDE autocomplete), Pairings (per round, with drag-to-swap override and a checker warning), Results, Standings (crosstable widget), Report.
- Printing: pairings, standings, wall chart, score sheets; HTML export; PGN; TRF.
- All actions are registry actions (menus, context menus, Ask, toolbar), following the menu-mission rules: one registry, capability-gated, translated.

### 3.7 Assistant as TD
- Tools (registry actions): `td.create`, `td.register`, `td.import_players`, `td.pair_round`, `td.override_pairing`, `td.start_round`, `td.enter_result`, `td.correct_result`, `td.bye`, `td.withdraw`, `td.ruling`, `td.standings`, `td.crosstable`, `td.finish`, `td.export`, `td.status`.
- Knowledge pages:
  - Laws of Chess summary (with article numbers)
  - FIDE C.04 / C.05 / C.07 essentials
  - time-control names ("blitz" means 3+2 by default)
  - TD procedures
- The assistant explains each pairing and ruling with its source. Decisions that change standings need confirmation, unless the user has granted "director mode".
- Progress messages after each round, and a final report: winner, tiebreaks, best games, opening statistics for themed events.

## 4. Phases (each one a Zenith mission with VAL contracts)

| Phase | Delivers | Acceptance highlights |
|---|---|---|
| **P1 Engine round robin + assistant TD** | Model + TRF save, Berger, tiebreaks, the extracted runner (N at once), opening themes, standings view, TD tools. | "Thematic London 3+2 double round robin, 6 engines" via Ask runs to completion (fake engine in tests, real Stockfish variants in a live smoke run); golden round robin crosstables; resume after kill -9. |
| **P2 Human Swiss / round robin** | bbpPairings helper program (3 OS), registration with FIDE data, over-the-board result entry, byes and withdrawals, overrides with audit + checker, arbiter rulings, printing, FIDE TRF report. | bbpPairings output matches the FIDE worked examples; TRF round-trips through Vega and Swiss-Manager import; reproduce two published chess-results Swiss events round by round. |
| **P3 Mixed and online** | Human-local and Lichess seats in the same event, knockout, teams/Scheveningen, fair-play report, optional creation of Lichess Swiss/Arena events. | Mixed human + engine + Lichess event (Lichess part read-only or in the user's own team, never challenging strangers without consent). |

## 5. Risks
- **Pairing correctness:** handled by bbpPairings plus golden tests. Never certify our own Swiss implementation.
- **Licensing:** check the bbpPairings licence against GPL-2+ before bundling (reported as Apache-2.0 / GPL; confirm in the repository).
- **CPU:** running games at once with multithreaded engines distorts results; default threads = 1 per engine during events.
- **Assistant authority:** rulings and result changes always go in the audit log, and the user confirms any that change standings.
- **Lichess terms of service:** bot/board API limits; no automatic challenges to people who haven't agreed.
- **Scope creep:** national federation formats (US Chess and others) come after P2.

## 6. Draft-2 changes from the external reviews (ChatGPT via codex, Gemini via agy). Where this section conflicts with sections 3 to 5, this section wins.

### Accepted by both reviewers
1. **Storage:** TRF is NOT the storage format. The canonical store is a versioned, transactional event store: SQLite (bundled through Tcl's sqlite3) or an append-only event journal. It holds stable ids, schema migrations, immutable audit events, game references to the Scidb database, pending results, claims, clock adjustments, publication revisions and external (Lichess) game ids. TRF is an adapter at the edges: pairing-engine input/output and the FIDE report. **Support TRF16 and TRF26** (FIDE now specifies TRF26).
2. **Assistant authority:** typed domain commands and queries, not literal button parity. Every mutation has a dry-run preview and then a commit (`td.pair_round {commit 0}`), an event revision number with a stale-revision rejection, an idempotency key, and an audit entry. Corrections after publication create a new publication revision; history is never rewritten. The assistant cites pinned regulation sources and states its uncertainty. Rulings and appeals stay accountable to the human TD. The UI and the assistant use the same commands, so parity is checked at the command level.
3. **Regulation editions are pinned per event** (Laws 2023, C.04.3 2026, C.07 2026 and so on). Unplayed games are separate categories: requested bye, pairing-allocated bye, full-point bye, forfeit win/loss, withdrawal before pairing versus after pairing, and played. Direct encounter is recursive over tied subgroups. Unrated players have an explicit policy. Exact rational arithmetic is used. Every tiebreak value comes with a breakdown of what contributed to it.
4. **Arbiter rules per setting**, separately for OTB, local digital, engine and platform play:
   - **Dead position:** "the opponent cannot mate by any legal sequence", not a material count.
   - **Claims:** intended-move claims, incorrect claims.
   - **Precedence:** checkmate takes precedence over the 75-move ending.
   - **Default time** is published (zero if not specified).
   - **Rapid/blitz:** both supervision regimes.
   - **Illegal moves:** an illegal GUI attempt is not an OTB illegal move.
5. **Round robin (C.05):** colours of pairing number 1 decided by lot. Withdrawal rule: before 50% of games played, results are annulled for standings (but still rated); from 50% on, remaining games are forfeits.
6. **Lichess integration around ownership:**
   - **Accounts:** one token cannot play other people's games. Organiser challenges / bulk pairing, human Board API and BOT accounts are separate. Engine help is never relayed through a human account. Blitz/bullet engine seats need a dedicated BOT account.
   - **Clocks and pairings:** Lichess owns the platform clocks and results; a lost stream is NOT a forfeit. A native Lichess Swiss owns its own pairings.
   - **Requests:** requests are serialised, with one minute of pause after a 429. Revoked tokens, disconnects, declined challenges and duplicate events never invent results.
7. **Runner isolation before concurrency:**
   - **Per-game state:** each game has its own state machine, monotonic clock, process and config snapshot, and its own move-overhead buffer.
   - **Shared resources:** persistence is serialised; CPU/RAM scheduling is bounded (engine threads 1, hash ≤ RAM/2N).
   - **Phase P0:** refactor engine-match into the runner, with the existing engine-match tests green before any TD state exists.
   - **Pipe handling:** if Tcl event-loop jitter causes false flags, move the clock and pipe multiplexing to C++ or adapt cutechess/fastchess as the runner backend (evaluate in P0).
8. **Cut or defer:** norms are reduced to "norm screening" (full B.01 is P4). Burstein is cut. Teams/Scheveningen move to P4 (they need Team→Match→Board). Fair-play inference and SPRT are deferred.
9. **Missing duties to model (P2/P3):**
   - **Before play:** registration deadlines, check-in, eligibility, schedules and postponements, arbiter assignments.
   - **Results:** signed result approval, correction deadlines.
   - **Disputes:** complaints, appeals (committee, deadline, deposit, and a "provisional pending appeal" result), sanctions.
   - **Regulations:** published and frozen competition regulations.
   - **Prizes:** eligibility snapshots, one prize per player, Hort system, rounding, payment records.
   - **Ratings:** FIDE rating eligibility validation (mixed engine events are never FIDE-rated).

### Disagreements, to be settled in the P0 investigation against primary sources (record the verdict in docs/features/td-research/)
- **bbpPairings licence:** ChatGPT says Apache-2.0 (cites LICENSE.txt); Gemini says MIT. Read LICENSE.txt and check the binary dependencies. Both licences are GPL-compatible.
- **bbpPairings checker mode:** ChatGPT implies it exists (and that output must be parsed, since exit 0 does not mean compliant); Gemini says no checker mode exists. Check the README. If there is none, write our own C.04 absolute/quality-criteria checker for manual overrides. A TD ruling never makes a prohibited pairing "compliant"; it is logged as an override.
- **Virtual opponent:** ChatGPT says it was abolished in C.07 2026; Gemini says it is the current C.07 §16. Implement exactly the current C.07 (2026) text, with worked examples.
- **Illegal-move penalties in rapid/blitz:** Gemini claims a 2023 change. Implement exactly Laws 2023 Art. 7.5 and Appendices A/B.

### Revised phases
| Phase | Delivers |
|---|---|
| **P0** | Research: read Chessament, Gambit, Pawn and Ponziani; settle the disagreements; pin a bbpPairings release. Refactor the engine-match runner, with existing tests green. Build the event store, the command layer (preview/commit, revisions, idempotency, audit) and the assistant command bridge. |
| **P1** | Round robin (C.05) for humans (manual results) and engines (runner, opening themes, N at once with a jitter test). C.07 tiebreaks with breakdowns. Standings and crosstable. The assistant TD runs your London System blitz event end to end. |
| **P2** | Dutch Swiss through bbpPairings with our own override checker; registration from FIDE data; byes, withdrawals and late entries; arbiter rules; prizes; TRF16/26 export; rating-eligibility checks; printing. |
| **P3** | Local human seats and Lichess seats (ownership model); knockout; appeals workflow; publication revisions; HTML publishing. |
| **P4** | Teams/Scheveningen, full B.01 norms, fair-play report, SPRT, national federation formats. |

### Added acceptance tests
- FIDE C.04.3/C.07 torture vectors: pairing-allocated bye, two requested half-point byes, a withdrawal shifting Buchholz, a bracket collapse with floats.
- A 10-player round robin where one player withdraws after round 4 (annulled) and another after round 6 (forfeits).
- SIGKILL in the middle of a round with 4 games running at once: completed games are preserved and no game ends with a duplicate or missing result.
- 50 games at 0+0.1 with N=8 using an instant mock engine: 0 false flag falls.
- Ask replay of a 5-round Swiss containing an override, a correction and a late entry, then undo/redo, giving byte-identical standings and TRF.
- Stale confirmations, repeated tool calls (idempotency), adversarial player names, and a correction after publication.
- Interrupt at every persistence boundary and get a consistent recovery.
