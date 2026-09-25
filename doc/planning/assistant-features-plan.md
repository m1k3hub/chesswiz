# Assistant features: implementation plan

Four features for the AI assistant (`tcl/app-assistant.tcl`), following
`prepare_against` (built). Order is by value per effort; each can ship alone.

Common rules, as for the existing tools:

- Tools that only read run without asking; anything that changes the user's
  data, board or views asks first (`confirm` in the tool table).
- Numbers come from Scidb, never from the model: every tool returns counts,
  scores and moves that the model reports, and the system prompt forbids
  inventing statistics.
- Long work never blocks the pane: it runs in the background and posts its
  result, like `explain_position` and `triage_errors`.
- Tests drive the model with the stub provider against a PGN fixture
  (`tests/test_app_assistant.tcl`), swapping `ActiveBase` rather than
  switching the app's database.

---

## 2. Move statistics for the board position

*"What is played here, and what scores best?" / "Is my move a novelty?"*

### What exists

- The tree (`::scidb::tree::*`, `src/tcl/tcl_tree.cpp`) computes per-move
  statistics for the current position in the reference base, on a worker
  thread.
- `tree::update <rating> <exact|fast|quick> <inclVariations>` returns 1 if
  a complete tree is cached, 0 if it started the worker; progress reaches
  the command given to `tree::init`, 255 meaning done.
- `tree::finish ... -sort <col>` then `tree::describe` give one dict per
  move: move, eco, frequency, score and draws (per mille), average rating,
  performance, last year, best player, first game index.
- There is no synchronous call. The opening-prep dialog polls `update` every
  250 ms (`app-database-openingprep.tcl:307`).
- `tree::findNovelties` compares ECO codes, not moves, so it cannot say
  whether a move is new.

### Design

- Tool `position_moves {limit?}`, read-only, asynchronous: it starts or
  reuses the tree for the board position and returns
  `started; the result is posted here`. When the tree completes, the rows
  are posted as a tool-style message and appended to the conversation (the
  same guard as `TriageDone`: not while a request is running).
- Alternative, simpler for the model: let `runTool` accept handlers that
  finish later. The request loop already runs from callbacks (`OnReply`),
  so a handler can return a "pending" marker plus a completion callback,
  and `Step` resumes when the tree is done. Worth doing once, since review
  (#4) needs the same thing.
- Reference base: the tree's current one (`tree::get`); if none, the active
  base, switching the tree base only for the query and restoring it
  afterwards (the opening-prep dialog's `restoreBase` pattern).
- Output per move: SAN, games, share %, score % for the side to move, draw %,
  average Elo, last year played, best player. The "total" row gives the
  position's game count.
- "Is my move a novelty?" is answered from the same rows: the move played in
  the game is either among them (with its count) or not. No new C++ is
  needed.

### Gotchas

- `tree::update` needs `tree::init` to have run (the tree pane does it at
  startup; call it defensively if the pane was never built).
- `tree::finish` sets the tree view's game filter as a side effect. That
  is harmless, but use the tree view, never view 0.
- The tree follows the board; if the user moves while it runs, discard the
  result (compare `tree::position` with the FEN the query started from).
- `app-tree.tcl:1082` tests for a `finish` result `unchanged` that the C++
  never returns. Leave it alone, but don't copy it.

### Work

| Step | Where | Size |
|---|---|---|
| Deferred tool results in `runTool` / `Step` | app-assistant.tcl | M |
| `DoPositionMoves` + tree wait + base save/restore | app-assistant.tcl | M |
| Tests: fixture base as tree base, stub model, novelty yes/no | test_app_assistant.tcl | S |

---

## 3. Plain-English search

*"Carlsen's wins with the Najdorf as Black since 2018."*

### What exists

- `::scidb::view::search <db> ?<variant>? <view> <null|and|or|not|reset|remove> <none|...> ?<query>?`
  (`tcl_view.cpp:450`) filters a view synchronously and changes no game
  data. `... reset none` clears the filter.
- Query language (`tcl_search.cpp:288`), nested Tcl lists: `AND`, `OR`,
  `NOT`; `playername white|black|any <glob>` (`=` prefix: exact,
  case-insensitive); `eventname`, `sitename`, `annotatorname <glob>`;
  `eco <code>` (exact short code); `rating <type> white|black|average <N|N-M>`;
  `material ...`; `position <idn>`.
- **Missing: date or year, result, and "won with White".** These are the
  core of most real questions.
- The advanced dialog builds its query in `BuildAdvancedSearchQuery`
  (`app-database-search-advanced.tcl:169`) and searches its own view.

### Design

1. **C++: new search terms** in `db_search` and `tcl_search.cpp`:
   - `date <from> <to>` (partial dates allowed, e.g. `2018` = 2018.??.??)
   - `result <1-0|0-1|1/2-1/2>`
   - `playerresult <glob> win|draw|loss ?white|black?`: the player's own
     result, which a combination of `playername` and `result` cannot express
     for "any colour"
   - `ecorange <from> <to>`, so ranges don't need 10–100 `OR` terms

   Each is a small `Search` subclass over `GameInfo`, like the existing ones.
2. **The model writes a structured query, not Tcl.** Tool
   `search_games {player?, color?, player_result?, opponent?, eco?, from?, to?, event?, min_elo?}`
   with an enum/JSON schema. `CheckArgs` validates it and `BuildQuery`
   turns it into the Tcl query. The model never produces query syntax,
   so a malformed or injected query cannot reach `view::search`.
3. **Two steps: count, then show.**
   - `search_games` runs on a scratch view (`view::new ... master slave`,
     `view::close` after) and returns the count, the first 10 games and
     the criteria as understood, with no confirmation.
   - `show_search` (confirm: it changes the user's game list) applies the
     same criteria to view 0 and switches to the database tab.
   - `clear_search` resets view 0.
4. Opening names are the model's job (Najdorf = B90–B99), as in
   `opening_score`. The criteria echo lets the user see the mapping.

### Gotchas

- An invalid query raises an error, so catch it and report it to the model
  as text.
- The optional variant argument is detected by the third argument being
  non-numeric; always pass the variant explicitly.
- Player globs are case-sensitive unless `=`-prefixed. Resolve names with
  `findPlayers` first and search by exact name.

### Work

| Step | Where | Size |
|---|---|---|
| `date`, `result`, `playerresult`, `ecorange` terms | src/db/db_search.*, src/tcl/tcl_search.cpp | M |
| `search_games` / `show_search` / `clear_search`, `BuildQuery` | app-assistant.tcl | M |
| C++-level tests of the new terms; Tcl tests on the fixture (counts, view 0 untouched by `search_games`, confirm on `show_search`) | tests/ | M |

---

## 4. "Where did I go wrong?" game review

### What exists

- `::scidb::game::evalProfile` returns `{ply value}` only for evaluations
  **stored** in the game (main line). Plain PGNs give `{}`.
- `::ai::engine::classify fen san ?-depth?` (`ai-engine.tcl:385`) evaluates
  before (multipv 2) and after a move and returns cp loss, win-% loss and a
  classification (Blunder ≥ 20 % win loss, Mistake ≥ 10, Inaccuracy ≥ 5).
  It blocks (it uses `vwait` inside) and is not re-entrant ("engine is
  busy").
- `::ai::generate::positionToolsAsync` explains one position with
  engine-grounded tools and claim checking. It is what "Explain position"
  uses.
- There is no whole-game annotator or blunder scan anywhere.

### Design

1. **Scan** (`::application::review`, new file `app-game-review.tcl`):
   - Walk the main line of the board game from a copy of its moves (FEN
     and SAN per ply, e.g. via `::scidb::game::dump`) so the board never
     moves.
   - Run `classify` per ply at a low depth (10–12), one ply per event-loop
     turn (`after idle` chaining), behind a busy flag, with a progress line
     in the pane.
   - Skip plies whose stored `evalProfile` values show no swing, when
     stored evaluations exist.
   - Optionally scan only the user's side, since "where did *I* go wrong"
     means the user's own moves. Take the user's name from the player
     dictionary or a setting, else ask.
2. **Select** the 2–3 worst plies by win-% loss (Mistake or worse). Re-check
   those at full depth (16) so the verdicts shown are solid.
3. **Explain** each selected ply with `positionToolsAsync` on the position
   *before* the move, with a prompt naming the move played, the engine's
   best move and the loss. Claims are checked against that FEN, which is
   also the fix for `ai-claims` flagging earlier moves as illegal.
4. **Report** in the Report pane: the eval curve (reuse the app-pgn eval
   strip drawing), then one section per turning point with a "go to move"
   link (`::scidb::game::go <pos> ply <n>`).
5. Assistant tool `review_game {side?}`: read-only, asynchronous, the
   result posted like triage. It is also worth a menu entry next to
   "AI: Explain Position".

### Gotchas

- Cost: 2 searches per ply × 80 plies. At depth 10 that is about 10–30 s
  on a desktop, so show progress and allow Stop (`::ai::engine` kills its
  process on timeout, so add a `cancel` proc).
- `classify` needs `stockfish` on PATH (`-engine` configures it). Detect it
  up front and say so plainly.
- Scidb's own engine system (`::scidb::engine::*`) is separate. Don't run
  both at once on a small machine.

### Work

| Step | Where | Size |
|---|---|---|
| Ply walk without moving the board; incremental classify loop with cancel | app-game-review.tcl, ai-engine.tcl (`cancel`) | M |
| Turning-point selection + full-depth recheck | app-game-review.tcl | S |
| Per-ply explanation prompt; report HTML with eval curve and links | app-game-review.tcl, app-ai.tcl | M |
| `review_game` tool, menu entry (mc strings in 5 languages) | app-assistant.tcl, menu.tcl, lang/*.tcl | S |
| Tests: stub engine answers (wrap `classify`), stub model; selection logic unit-tested on synthetic loss lists | tests/ | M |

---

## 5. Repertoire health check

*"Which of my lines score badly, and what do opponents play that I haven't
prepared?"*

### What exists

- A repertoire is an ordinary database of type `Openings`, `OpeningsWhite`
  or `OpeningsBlack`, one game per line. `repertoireBases`
  (`app-database-repertoire.tcl:416`) lists the open ones.
- The repertoire report measures coverage as distinct ECO codes via
  `ecoStats`. There is no command that walks the repertoire's move tree.
- `tree::findNovelties` is ECO-based as well.

### Design, in two phases

**Phase 1: ECO level (cheap, synchronous, no board involvement).**
- Tool `repertoire_check {repertoire?, reference?}`: compare
  `ecoStats(repertoire)` with the user's results in a reference base.
  - The reference is the user's own games, via `playerOpenings` from
    `prepare_against`, or a master base, via `ecoStats`.
  - Report lines in the repertoire that score below average (≥ N games).
  - Report ECO codes common in the reference, from the repertoire's side,
    that the repertoire lacks.
  - Report repertoire lines never reached in practice.

**Phase 2: move level (C++).**
- New `::scidb::db::lines <db> <variant> ?<maxPly>?`: walk every game's main
  line and variations in C++ and return the leaf positions (FEN or
  position key) with the move sequence. This avoids driving the board
  through every game.
- For each leaf, query the reference base's statistics for that position.
  The tree machinery is tied to the board and is asynchronous, so add a
  C++ `::scidb::db::positionStats <db> <variant> <fen>` that scans with the
  existing position search. That command also gives #2 a synchronous path.
- Report, per leaf: games, score for the repertoire's side, and the most
  common replies the repertoire doesn't cover (replies with ≥ X % share
  and no branch in the repertoire).

### Gotchas

- Repertoire colour: take it from the database type
  (`OpeningsWhite`/`OpeningsBlack`). For the plain `Openings` type, ask.
- Transpositions: match leaves by position, not by move order. A
  position-keyed search handles that.
- Size: repertoires of hundreds of lines × a large reference base. Run the
  phase-2 scan in a worker (as `playerStatistic` and `computeEcoStats` do)
  and report progress.

### Work

| Step | Where | Size |
|---|---|---|
| Phase 1 tool on `ecoStats` / `playerOpenings` | app-assistant.tcl | S |
| `db::lines`, `db::positionStats` (threaded) | src/db, src/tcl/tcl_database.cpp | L |
| Phase 2 report: weak leaves, uncovered replies | app-assistant.tcl or new file | M |
| Tests: tiny repertoire + reference fixtures | tests/ | M |

---

## Found while researching

- `OpeningPrepMethodFromLabel` (`tcl/app-database-openingprep.tcl:139`) puts
  its `switch` patterns in braces, so the `$::application::tree::mc::...`
  labels are never substituted and it always returns `exact`. Fix: switch on
  the substituted values (`switch -- $label [list $mc::UseFastMode {return fast} ...]`)
  or compare with `eq`.
- `HighlightNovelties` (`tcl/app-tree.tcl:1937`) uses ttk-treeview-style
  `tag` calls on Scidb's own table widget and looks non-functional. Check it
  before building on it.

## Suggested order

1. **#2 move statistics**, including deferred tool results (reused by #4).
2. **#5 phase 1**: small, and reuses `prepare_against`.
3. **#3 search**: the new C++ search terms are the bulk of it.
4. **#4 review**: the largest in UX work, and needs Stockfish on PATH.
5. **#5 phase 2**, with `positionStats` (which can also replace the
   asynchronous tree wait in #2).
