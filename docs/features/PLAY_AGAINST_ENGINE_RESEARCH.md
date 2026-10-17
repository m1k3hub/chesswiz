# Play against an engine — research notes (Scid and ScidvsPC)

**Status:** research only (2026-09-30); nothing implemented. Roadmap: `LONG_RANGE_PLAN.md`
workstream 11. Sources studied: `~/src/chess/scid-code` ("Scid") and `~/src/chess/scidvspc-code`
("SvP"); paths below are relative to their `tcl/` directories. The survey was made by a read-only
agent over the real code; line numbers are theirs and worth re-checking before quoting.

Both "serious game" implementations descend from the same 2007 code; SvP is a UI and polish fork.
Neither repo's BUG_LOG/DONE_TODO says anything about them.

## 1. What they offer

* **Serious game** (`tools/sergame.tcl`; Scid 675 lines, SvP 865). UCI engines only. Setup: engine,
  four time modes (time+increment per side, fixed depth, nodes, seconds per move), polyglot book,
  a built-in list of about 60 opening lines, start from the current position, pondering, "coach is
  watching", store score (Scid) or clock (SvP). **No colour option** (the engine plays the upper
  side; flip the board first). **Strength comes only from the engine's own saved UCI options**
  (UCI_Elo, Skill Level). No adjudication thresholds, no human name or Elo.
* **Tactical game** (`tools/tacgame.tcl`): opponent hard-wired to Phalanx over xboard, plus a second
  "coach" UCI engine that tracks the opponent's blunders; Elo slider, blunder threshold.
* **Review game** (Scid, `tools/reviewgame.tcl`): a "guess the move" trainer, not an opponent.
* **Computer tournament** (SvP, `tools/comp.tcl`, 1231 lines): 2..N engines, round-robin / carousel /
  first-plays-others, per-game or per-move time, book, score-as-comment, adjudication buttons, UCI and
  xboard. The only engine-vs-engine implementation in either repo.
* **During play**: the main board; SvP adds a play window with analog/digital clocks and Resume,
  Resign, Restart and Quit buttons. Scid has no window, only clock strings in the game-info bar.

## 2. Engine control

* Scid sergame sends `isready`, then `position fen <fen>` (never the move list, so engines lose
  repetition history), then `go wtime W btime B winc I binc I` or `go depth|movetime|nodes`; no
  `movestogo`; `ucinewgame` is never sent; hash and threads are not set. It waits with
  `vwait` on `bestmove`. Pondering: `position fen … moves <ponder>` + `go ponder`, then `ponderhit` or
  `stop`.
* The tournament does it better: `ucinewgame`, `isready`, then `position startpos|fen … moves <full
  coordinate history>` and `go movetime T` or `go wtime … btime … winc … binc …`; a ponder miss sends
  `stop` and sets a sentinel so the stale `bestmove` is discarded. xboard: `protover 2`, `level 0 mm:ss
  inc` or `st`, `time`/`otim` in centiseconds before each move, moves as bare coordinates; `resign` and
  `1/2-1/2` lines are honoured.
* Scid's newer **`enginecomm.tcl`** (2020) is the cleanest foundation in either repo: typed async
  messages (`SetOptions`, `NewGame`, `Go`, `StopGo` -> `InfoReady`, `InfoGo`, `InfoPV`, `InfoBestMove`,
  `InfoDisconnected`), a per-engine send queue where a new `Go` replaces a queued one and sends an
  implicit `StopGo`, protocol auto-detect (`uci`, then `xboard` after 2 s). **But sergame, tacgame and
  reviewgame do not use it.** Its xboard path maps only depth and movetime (no clocks), and pondering is
  a TODO.
* Strength recorded in the game: SvP writes the SkillLevel or UCI_Elo value as a PGN extra tag.

## 3. Clocks

* `::gameclock` (`misc.tcl`) is a **tick counter incremented by `after 1000`**: 1 s resolution,
  drifts under load, remaining time stored negated, flag fall only turns the display red (no forfeit
  event), a negative time is sent to the engine as a negative `wtime`. SvP adds pause/resume, an
  elapsed-time comment `[%emt m:ss]`, and no increment for book moves; Scid stores `[%clk h:mm:ss]`.
* **Best timing design: the tournament** (`comp.tcl`): real wall-clock (`clock clicks -milli` before
  `go` and after the reply), the engine's time is decremented by the measured duration, increment added
  unless the move was a book move, a negative time loses, a watchdog `after (wtime+2000)` is armed per
  move, and a per-move limit of 175% of nominal. The on-screen clock is display only.

## 4. Game state machine

* Both serious games **poll `engineGo` every 1000 ms**; a `playMode premove` hook rejects human moves
  while it is the engine's turn (that blocks premoves rather than implementing them).
* Takeback: Scid only through the coach dialog; SvP pauses the engine, trims its repetition history,
  offers Resume (which sends `Clear Hash`). Resign: SvP only. **No draw offers or claims in either.**
  No engine-score adjudication in sergame (the tactical game shows an "I resign" box after 3 scores beyond
  5.5).
* End detection: Scid sergame only checks a trailing `#` in the SAN (no stalemate, 50-move or
  insufficient material); SvP detects mate, stalemate, 50-move and threefold (insufficient material
  not in sergame); the tournament detects all of them (its repetition test uses only the placement field,
  which is wrong when castling or en passant rights differ).

## 5. Saving

* Scid keeps the game in the current slot for the user to save; tags: Event "Serious game", Date,
  player names (the human is literally "Player"); no Result/TimeControl/Elo/Round. SvP saves into the
  current database at game end without asking, with Event "UCI Game", skill/Elo, Opening, Timemode tags
  and `[%emt]` comments; the tournament sets White/Black/Event/Date/Round/TimeControl and saves only if the
  base is writable (otherwise the games are discarded).

## 6. Weak points (avoid these)

* `vwait` everywhere (ready-ok, bestmove, start-up). Nested event loops; an engine that dies during a
  wait leaves it pending forever (only the tournament has a watchdog). `startEngine` is a 5 s polling loop
  with `update`.
* An illegal or failing engine move is ignored (`sc_move add` result not checked); the next poll asks
  again, and the tournament can spin.
* Hard-coded engine slots (3 sergame, 2 coach, 6 review) and a book slot that clashes with another tool;
  game state in globals shared with other tools (`lastPlayerMoveUci`, `::lFen`, `::pause`); tournament
  engines hosted in hidden analysis windows.
* Repeated fixes in the changelogs: threefold repetition, "broken once the engine left the opening", a
  crash on an empty book name, a UI freeze when aborting with the coach running.

## 7. Recommendation for Scidb's first version

Build on Scidb's existing asynchronous engine layer (not on blocking `vwait` code):

1. one human, one engine, one board; no polling, no `vwait`;
2. setup: engine, explicit colour, start (new or current position), time control (base + increment,
   per-move time, depth, nodes), book on/off;
3. a game controller that owns the state: whose turn, wall-clock clocks for both sides, flag loss,
   mate, stalemate, threefold, 50-move and insufficient material, **validation of every engine move**;
4. strength through UCI options (`UCI_LimitStrength`, `UCI_Elo`, `Skill Level`), recorded in the PGN;
5. resign, draw offer (the engine accepts when its score is flat), takeback;
6. an explicit save to a chosen database (not the user's current game) with Result, TimeControl, Elo and
   Round tags and `[%clk]` comments;
7. engine crash and timeout handling that always ends the wait.

**Copy:** the tournament's wall-clock ledger and flag watchdog; `position … moves <full list>` so repetition
and 50-move state reach the engine; `ucinewgame` + `isready` at start; the "stop leaves a sentinel so a stale
`bestmove` is dropped" idea; `enginecomm.tcl`'s per-engine queue where a newer `Go` replaces an older one;
SvP's result tags and `[%clk]`/`[%emt]` comments; the play-mode hook that blocks human input on the engine's turn.
**Avoid:** polling, `vwait`, `after 1000` counters as clocks, fixed engine slots, ignoring the outcome of
applying an engine move, shared global game state, engines inside analysis windows.

**Later:** pondering, hints, a coach with blunder warnings and takeback offers, a specific-opening list,
adjudication thresholds, tournaments (round-robin, carousel), a review-game trainer, a score-in-comment
option.

## 8. Open decisions

* Build in the C++ engine layer (`src/app/app_uci_engine.cpp`, `app_winboard_engine.cpp`: UCI and
  WinBoard, asynchronous, reuses the engine list and settings) or on the blocking Tcl driver
  `tcl/ai-engine.tcl` (UCI only, one-shot facts). The C++ layer is the right foundation; it needs a play
  search mode (`go wtime btime winc binc movestogo`, `bestmove` callback, `ucinewgame`).
* First-version scope: the list in section 7, or less.
