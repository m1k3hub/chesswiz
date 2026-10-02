# Ask Scidb — coverage map and plan

**Status:** adopted 2026-10-02 (decisions in §8); phase 0 in progress.
**Question it answers:** how does a chess player get the full power of Scidb without
learning Scidb's menus, dialogs and query languages?
**Why:** ease of use. Every decision below is weighed by one test: can a chess player
who has never read a manual get it done by saying what they want?
**Companions:** `LLM_FEATURES_RESEARCH.md` (principles P1–P7, Appendix C reach ideas),
`LLM_REACH_PLAN.md` (C1–C11), `AI_PRODUCTS_PLAN.md` (the firewall, Waves 0–4),
`PLAIN_LANGUAGE_SEARCH.md` (vetted patterns), `CQL_FEATURES.md`, `PATTERN_INDEX_PLAN.md`,
`ROADMAP_SCIDB_VS_CHESSBASE.md`, `LONG_RANGE_PLAN.md` (WS 10 CQL 6.2, WS 11 play).

## 1. Thesis

Scidb already has more analytical power than a player will ever find: a native
database for millions of games, an opening tree with a 13-section report,
repertoire and opponent preparation, engines, ChessBase media, and, since
`1254816`, the official CQL 6.2 pattern language. Most of it sits two or three
levels deep in right-click menus (§3.3), and CQL is a programming language.

The assistant is the way in. The goal is: **a player says what they want in chess
terms, and Scidb does it with everything it has, shows the result on the board
and in the game list, and shows how it got there.** No other chess database can
offer this, because none combines all four ingredients:

| Ingredient | Scidb | ChessBase | Web platforms (lichess, chess.com) |
|---|---|---|---|
| Your own, private, multi-million-game collection | yes, local | yes, local | only your online games |
| An exact language for chess patterns | CQL 6.2 (official engine) | fixed search masks | fixed "insights" dimensions |
| An engine as the authority on move quality | yes | yes | yes, server-side |
| A language layer that is checked against the facts | yes (fact pack, claim checker) | "Consult AI", reviewed as generic and contradicting the engine (Research §1) | coach-style text |

The combination is the product. Any single ingredient can be copied. A pattern
language becomes usable by non-programmers only when a model writes it, and that
only works when the facts and the engine check what the model says.

## 2. What a player wants: the jobs

Thirteen jobs cover what players do with a database. The map in §3 is organised by them.

| # | Job | Example request |
|---|---|---|
| J1 | Keep a collection | "Add this week's TWIC", "Get rid of the duplicates" |
| J2 | Find games | "Kasparov's wins with the Najdorf after 1990" |
| J3 | Find positions and patterns | "Games where Black sacrificed the exchange on c3 and won" |
| J4 | Study openings, build a repertoire | "What's fashionable against my Caro-Kann now?" |
| J5 | Prepare for an opponent | "I play Müller on Saturday, what does he do against 1.d4?" |
| J6 | Review my own games | "Where did I go wrong last night?" "Why do I lose with Black?" |
| J7 | Analyse a position or a game | "Is this exchange sacrifice sound?" |
| J8 | Train | "Give me 20 tactics from my own games" |
| J9 | Learn from media | "Find the video where the lesson covers this position" |
| J10 | Players and events | "Show the crosstable of Biel 2015", "Who is this player?" |
| J11 | Publish and share | "Make a PDF of my annotated games from the club championship" |
| J12 | Correspondence chess | "Which ICCF games need a move?" |
| J13 | Play | "Play me a game at 1800 strength" |

## 3. Coverage map

The columns are:
- **GUI**: what exists and how deep it is (MM = Main Menu, DB-RC = right-click a database, Maint = DB-RC ▸ Maintenance).
- **Assistant**: the tools that reach the job (`tcl/app-assistant.tcl`).
- **Lands**: where the assistant's result ends up: in the GUI, or only as chat text.
- **Gap**: what is missing.

### 3.1 By job

**J1 Keep a collection**
- **GUI:**
  - switcher toolbar: open, new, close
  - DB-RC: import, export, archive, recode, download games
  - Maint: convert to .sci, strip, compact, find duplicates (with "Check Group (AI)"), mark as opening DB
  - working sets in every report
- **Assistant:** `open_database`, `discover_databases`, `download_games`, `export_database` (opens the dialog), `list_open_databases`, `database_summary`.
- **Lands:** opens the database or dialog.
- **Gap:** no import, convert, duplicates, compact, mark-as-repertoire or working-set tools.

**J2 Find games**
- **GUI** (all in Maint, depth 2):
  - Advanced, Rating and Material search
  - Plain-Language Search
  - name filters in the Events, Sites and Annotator lists
  - "Games like this" in the game-list right-click menu
- **Assistant:** `search_games`, `show_search` (asks for confirmation), `clear_search`, `open_search`, `similar_games`.
- **Lands:** text first; the game list only after a confirmation.
- **Gap:** no material or rating fields in `search_games`. Filtering the list is read-only, so it shouldn't need a confirmation.

**J3 Find positions and patterns**
- **GUI:**
  - CQL 6.2 Search (Maint, depth 2): you write the script yourself
  - position search: Tree mode and the Position tab
  - Material search
- **Assistant:**
  - `search_games` with `pattern`: 12 vetted ids only
  - `structure_profile`: 6 structures
- **Lands:** a count in text; the list after confirmation; never at the matching position.
- **Gap:** **this is the biggest gap.** Anything outside the 12 ids is unreachable. There is no "positions like the current board". Matches don't open at the matching move, although CQL 6.2 returns `first_ply`.

**J4 Openings, repertoire**
- **GUI:**
  - Tree pane (toolbar and right-click)
  - Opening Report (13 sections, Tree right-click)
  - Opening Prep (labelled "Opening Report…" in Maint)
  - Repertoire Report
  - add a line to the repertoire (game-bar right-click)
  - pin the best engine line
  - highlight novelties
  - ECO table
- **Assistant:** `position_moves`, `opening_score`, `repertoire_check`, `database_trend`, `novelty_label`.
- **Lands:** text, plus the Report pane for trends.
- **Gap:**
  - The Opening Report, Repertoire Report and highlight-novelties are unreachable.
  - Nothing can add to a repertoire.
  - Nothing can set up a position from a description or a move sequence.

**J5 Prepare for an opponent**
- **GUI:**
  - Player Prep Report and Opponent Dossier (player right-click ▸ Prep Report ▸ button, depth 3)
  - player card
- **Assistant:** `prepare_against`, `opponent_brief`, `player_stats`, `structure_profile`.
- **Lands:** the Report pane (brief), otherwise text.
- **Gap:**
  - can't open the Prep Report, Dossier or player card
  - can't turn a weak line into "show me those games"

**J6 Review my own games**
- **GUI:**
  - annotate (Extras)
  - Explain move / line / game (right-click menus)
  - Fact-Check Annotations
  - Study Plan
- **Assistant:** `annotate_game`, `explain_position`, `study_plan`, `factcheck_annotations`, `current_game`.
- **Lands:** the game or the Report pane.
- **Gap:**
  - The assistant doesn't know who "I" am, although MM ▸ Setup ▸ Private Player Card exists.
  - It can't load a given game ("my last game").
  - It can't move the board to a position.

**J7 Analyse**
- **GUI:**
  - Analysis pane (pin a line, multi-PV)
  - Compare Engines (MM ▸ Tools)
  - engine console
- **Assistant:** `start_engine`, `stop_engine`, `engine_analysis`, the engine options tools, `explain_position`.
- **Lands:** the analysis pane.
- **Gap:** no Compare Engines, no position setup from a FEN or a description, no "analyse moves 20–30".

**J8 Train**
- **GUI:** Training Set from Games (Extras), which writes a PGN. There is no training mode.
- **Assistant:** `training_set` (asks for confirmation).
- **Lands:** a PGN file and the Report pane.
- **Gap:**
  - puzzles come only from the 4 CQL events
  - no themed sets ("knight forks from my games")
  - no way to solve the puzzles inside Scidb

**J9 Media**
- **GUI:** Media pane, lesson sync, video transcripts.
- **Assistant:** `transcribe_media`.
- **Lands:** text.
- **Gap:** no "find the lesson that covers X", no "play the video from here".

**J10 Players, events**
- **GUI:**
  - player card (with FIDE, Wikipedia and other links)
  - Player Dictionary (MM ▸ Tools)
  - crosstable with "Narrate event" (Events right-click)
- **Assistant:** `player_stats`, `event_types`.
- **Lands:** text.
- **Gap:** can't open the player card, a crosstable or the event narration.

**J11 Publish**
- **GUI:** export to PDF, HTML, LaTeX or PS; crosstable as HTML.
- **Assistant:** `export_database`, which opens the dialog.
- **Lands:** the dialog.
- **Gap:** can't export a selection or a working set ("my annotated games from the club championship").

**J12 Correspondence**
- **GUI:** Correspondence Games and ICCF Settings (MM ▸ Tools).
- **Assistant:** none.
- **Gap:** read-only status questions are fine to add. **Never** give the assistant a path that sends a move (see §6.4).

**J13 Play**
- **GUI:** none; WS 11 is proposed.
- **Assistant:** none.
- **Gap:** this follows WS 11, not this plan.

### 3.2 Structural gaps (cutting across jobs)

1. **The chat loop only works with Ollama.** `chatAsync` (`app-assistant.tcl:612–633`)
   answers "chat not supported" for the `openai` and `anthropic` adapters. CQL authoring
   and multi-step plans need a capable model; local 8 GB models are weak at a niche
   language like CQL. The killer feature is gated on this.
2. **It only responds.** The only unprompted text is the greeting
   (`app-assistant.tcl:2703`). It has no offers and no suggestions, and it never says
   "you can also…".
3. **Results stay in the chat.** Of the ~35 tools a player would use, most return
   text. Filtering the list asks for confirmation although it changes nothing
   stored. Nothing opens a game at a move.
4. **It doesn't know the player or the selection.** It has no "me" (the Private
   Player Card is unused) and no selected games, comments or move history (C9
   planned, `LLM_REACH_PLAN.md` Task 6).
5. **One way in.** Extras ▸ AI: Assistant, voice, `--ask`/`--chat`. There is no
   global shortcut and no "Ask about this…" in the right-click menus (C8 planned,
   Task 5).
6. **No workflows.** Every request is one exchange with at most 8 tool rounds.
   Named jobs ("prepare for Saturday") are planned as C11 (Task 11, Wave 4).
7. **Not installed.** The installed binary predates CQL 6.2 (`1254816`) and the
   media fixes (`90a8c65`, `b35f30d`).

### 3.3 Hard to find without the assistant

These are reachable only deep in menus; each is a candidate for a tool or an offer:
- **Maint, depth 2:**
  - all five search dialogs
  - Opening Report and Opening Prep
  - Repertoire Report
  - Find Duplicates
- **Depth 3:**
  - the Opponent Dossier
  - Mark As Opening Database, which every repertoire feature needs first
  - NAG submenus
- **Right-click only:**
  - add to repertoire (and only once a writable repertoire DB is open)
  - highlight novelties
  - Games Like This
  - game flags
  - Narrate event
- **Defects found on the way** (fix independently):
  - "Opening Report…" in Maint opens the Opening Prep dialog (`app-database.tcl:1534`/`2284`).
  - The search-presets menu (`app-db-games.tcl:592`) has no caller.
  - `opponent_brief` can download TWIC without the confirmation that `download_games` asks for.

## 4. The vision: six pillars

### P1 — Ask anything about your games (the position finder)

Any request about positions or patterns gets answered. The request goes to the
cheapest exact route that can answer it, in this order:

1. **Header fields** (`search_games`), the same as today.
2. **A vetted pattern** from the library: exact, fixture-tested, later indexed (`PATTERN_INDEX_PLAN.md`).
3. **A model-drafted CQL 6.2 script**, checked as in §5.
4. **The current board** as a query: "positions like this one" becomes a CQL script
   built from the board (material, pawn structure, piece placement, with a chosen
   tolerance).

The answer is a set of **positions**, not games. Each result opens at the matching
move (`cql6_match.first_ply`). The game list shows the filtered games, and the
reply gives the count, a few diagrams and the query.

### P2 — Show, don't tell

Every answer lands where the player works:
- the game list is filtered
- the board is at the position
- the tree is at the line
- the report has clickable links (C10)

Each answer ends with one line on how it was done, for example "(Search ▸ Advanced:
Elo ≥ 2400; 212 games)". The player gets the result and learns the program.
Read-only changes to the view, such as a filter, a board position or an opened
report, need no confirmation. Mutations still do (§6).

### P3 — Offer, don't wait

At natural moments, the assistant offers two or three concrete next steps, which
the player takes with one click:

| Moment | Offers |
|---|---|
| A large database is opened | "Openings in this database" · "Find positions…" · "Duplicates?" |
| Your own game is loaded (the Private Player Card names you) | "Review this game" · "Where did it go wrong?" · "Games like this" |
| A player is selected | "Prep report" · "How does he score with Black?" · "Brief" |
| A position on the board | "Games with this position" · "Positions like this" · "Explain" |
| A search returns 0 games | "Loosen: drop the year?" |

The offers come from rules first. A System One classifier may rank them, within
its contract (`JEV_USE_CASES.md` §6). An offer is a button that runs a tool, so it
uses C10's `ai:tool:` links.

### P4 — Jobs, not features

Named multi-step workflows with a visible plan and progress (C11):
- **Prepare for <opponent>:** brief, weak lines, games, positions to study, export a PDF.
- **Review my last N games:** annotate, recurring errors, study plan, training set.
- **Build a repertoire for <colour/opening>:** tree statistics, a fashion check,
  gaps, adding lines (confirmed).
- **Train <theme>:** run the position finder on the player's own games, then an
  engine filter, then puzzles.

### P5 — Trust (unchanged principles, applied to more power)

The firewall stands (`AI_PRODUCTS_PLAN.md` §0):
- Move quality and evaluations come from the engine.
- Whether a game matches comes from CQL.
- Counts come from the database.

The model translates and narrates. It never answers a chess question from its own
knowledge. Every result can be traced to a query the player can see, edit and
rerun.

### P6 — Strong by default, local on request

Ease of use needs a model that understands loose requests, plans several tool calls
and writes correct CQL. Local models on an 8 GB card don't, reliably. So:

- **The default is a strong cloud model.** The chat loop speaks to the `anthropic`
  and `openai` providers as well as Ollama.
- **Local models are opt-in**, one switch in AI: Choose Model, for players who want
  everything on the machine.
- **What leaves the machine:**
  - **Sent:** the request, the CQL reference, and the tool results the model reads
    (game headers, moves, statistics, at most 6000 characters a reply).
  - **Never sent:** a whole database. Audio is transcribed locally either way.
- **First use shows a short notice:** which provider, what is sent, and how to switch
  to local. It doesn't ask for consent; it informs once.

## 5. The position finder in detail

The position finder is the first build. It turns a request into a checked CQL 6.2
search, runs it, and returns positions.

```
request ──► route ─┬─► header fields only ─────────────────────────► search_games
                   ├─► vetted pattern id (library, later index) ──► search_games
                   └─► draft CQL 6.2 (model)
                          │  parse check (cql6_search over zero games)
                          │  ≤ 2 repair rounds with the parser's message
                          ▼
                       probe: run on a sample (first ~5k games after header narrowing)
                          │  show 3 matching positions as diagrams, plus the script
                          │  "Is this what you meant?"  [Search all] [Edit] [Refine…]
                          ▼
                       full run: async, cancellable, -view narrowing, progress
                          ▼
                       results: count · game list filtered · open at first_ply ·
                                script shown · [Save as pattern]
```

### 5.1 Why diagrams are the check

A player can't review CQL, but a player can look at three positions and say "yes,
that's a knight fork" or "no, those are pawn forks". The probe turns the unsolvable
problem of checking the translation into a chess judgement the player is good at.
Each probe position comes from the database, so nothing in it is invented.

### 5.2 Drafting

- **The prompt holds** a CQL 6.2 reference card: the constructs that matter for
  positional questions, plus the 12 library templates as worked examples. Most
  models have seen little CQL.
- **The header part of a request** ("after 2000", "Black won", "Elo > 2500") goes to
  the typed `search_games` fields and narrows the games with `-view`. The CQL holds
  only the positional part. This keeps scripts short and runs fast.
- **When unsure**, the model may ask one clarifying question ("forks by any piece, or
  knights only?") instead of guessing.
- **Parse errors** go back to the model with the parser's message, at most twice.
  After that the reply is the last error and the draft in an editable box.

### 5.3 Running

- **Engine:** CQL 6.2 only. It is file-locked (`src/cql6/scidb_lockdown.h`:
  `writefile`/`readfile` fail at parse time, and no file syscalls happen during a
  search). It is cancellable, and it runs off the GUI thread.
- **Bounds:** the run has a time budget, with progress shown and a cancel button. A
  script without a header narrowing on more than about 1M games warns about the
  expected time first.
- **Results:** `-paged` results, the same as the CQL 6.2 dialog.

### 5.4 The learning library

**[Save as pattern]** stores a script that the player accepted, together with its
probe positions, as a **user pattern**. The positions they accepted are its first
fixtures.
- **The router uses it like a library template**, but marked as "yours" and never
  as vetted.
- **Promotion to the vetted library** stays a human step with fixture games, as
  `PATTERN_INDEX_PLAN.md` §8 requires. That keeps the index and its speed claims
  for vetted patterns only.

### 5.5 What the user sees

> **You:** games where Black sacrificed the exchange on c3 and won, since 2000
> **Scidb:** I searched 1.17M games, narrowed to Black wins since 2000 (412,880), for a
> black rook taking on c3 and being taken back while Black has no material compensation.
> Here are 3 matches — is this what you meant? [diagrams] [Search all] [Edit] [Refine]
> **You:** search all
> **Scidb:** 1,284 games. The game list is filtered; double-click opens each one at the
> sacrifice. Query: *Black won, 2000–; CQL:* `cql() … ` (Search ▸ CQL 6.2 to edit) [Save as pattern]

### 5.6 This needs a rule change

`PLAIN_LANGUAGE_SEARCH.md` §2 and §6, `AI_AUTOMATION_AUDIT.md` §3,
`PATTERN_INDEX_PLAN.md` §8 and `SYSTEM_ONE_FEATURES.md` §3a forbid any model-written
CQL. Their reason was that a model could produce "a malformed or runaway query" and
a result the user can't check.

Since then:
- **Malformed:** the parser rejects it, and the repair loop and edit box handle what is left.
- **Runaway:** CQL 6.2 is async, cancellable, time-bounded and file-locked. The
  CQL 6.2 dialog already runs any script a user types.
- **Can't check:** the probe diagrams and the visible script handle this. A wrong
  translation costs a wrong search the player can see and correct. It is never a
  chess claim the player is asked to believe.

This also returns to the original proposal, Research F8 (l.207–218): "show the
generated query, let the user edit it… retry-on-parse-error". The proposed
replacement rule is:

> **A model may draft CQL; it never decides a match and never runs unseen.** Every
> drafted script is parsed by CQL 6.2, shown with sample matching positions before a
> full run, and stays visible and editable with its results. Vetted library patterns
> remain human-written and fixture-tested; drafted scripts are never indexed and
> never promoted without fixtures.

**Adopted 2026-10-02.** The five documents above now carry the amended rule. The
`search_games` tool contract stays as it is; the drafted path is a new tool,
`find_positions`.

## 6. Guardrails (what does not change)

1. **The firewall:** see P5. The engine is the only authority on move quality.
2. **Confirmation for mutations:** saving, adding to a repertoire, stripping, compacting, importing and writing files.
3. **Grounded prose:** generated prose goes through `ai-generate`/`ai-claims`. One grounding path; no second one (`LLM_REACH_PLAN.md`).
4. **Correspondence:** the assistant never makes or sends moves in a correspondence
   game. Making a move there submits it to ICCF without confirmation
   (`move.tcl:510–528`), so tools that set up positions or make moves refuse when
   the game has an `ICCFGameID`.
5. **Privacy:** the default model is in the cloud and local is opt-in (P6). What is sent
   is stated once on first use. A whole database is never sent, and audio stays local.

## 7. Plan

Each phase ships on its own and is useful alone.

| Phase | What | Size | Depends on |
|---|---|---|---|
| **0 Prerequisites** | `sudo make install` (CQL 6.2 + media fixes). Chat loop for the `anthropic`/`openai` adapters (tool calling); a strong cloud model as the default, local opt-in, the first-use notice (P6). "Me" from the Private Player Card. | S–M | — |
| **1 Position finder** | §5: `find_positions` tool, router, reference card, parse/repair loop, probe diagrams, async full run with `first_ply` jump, script shown, Save as pattern. Rule change §5.6. | L | 0 |
| **2 Results land in the GUI** | Read-only view changes without confirmation; open a game at a ply; set up a position from a FEN or moves; C10 report links; the "how it was done" line. | M | — |
| **3 Reach the unreachable** | Tools for §3: Opening Report, Repertoire Report, player card, crosstable, dossier, material/rating fields, current-board position search, duplicates, working sets, export a selection, add to repertoire (confirmed). Fix the §3.3 defects. | M | 2 |
| **4 Offers** | P3: contextual offer buttons, rules first and classifier-ranked later; C8 entry points (shortcut, "Ask about this…" in the right-click menus). | M | 2, 3 |
| **5 Workflows** | P4: named jobs with a visible plan and progress (C11). Themed training sets from the position finder. | L | 1, 3 |

**How it is measured:** a corpus of about 150 real player requests across J1–J13,
each with its expected outcome (tool, query or positions). It runs on every
change; the score is "solved without the player touching a menu". The corpus
goes into `tests/` beside `test_app_nlsearch.tcl`. The position-finder part is
checked with the probe: do the sampled positions match the request?

## 8. Decisions

Decided 2026-10-02:

1. **The CQL rule** (§5.6): adopted, and the five documents are amended.
2. **Models:** strong cloud models are the default for the whole language layer,
   CQL drafting included. Local models are opt-in (P6). This replaces the local-first
   rule of `LLM_FEATURES_RESEARCH.md` P3 and `AI_PRODUCTS_PLAN.md` requirement 4.
3. **The reason:** ease of use (see the header).

Still open:

4. **Run policy:** probe and then confirm a full run (as proposed), or run the full
   search at once when the probe has 3 or more matches and the player has done that
   before? Decide once phase 1 has real use.
5. **Name:** "Ask Scidb" for the feature, with `find_positions` as the tool?
