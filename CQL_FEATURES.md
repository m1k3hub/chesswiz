# CQL-Powered Features — plan and design

**Status:** implemented. The code is in `tcl/ai-cql.tcl` (the profile, themes, training and
quality modules), with hooks in `tcl/ai-brief.tcl`, `tcl/ai-studyplan.tcl`,
`tcl/ai-annotate.tcl`, the Extras menu and the assistant. The tests are in
`tests/test_app_cqlfeatures.tcl`.
**Update (2026-10-03):** in standard chess the profile, the move themes, the structures of
a position (study plan) and the training sets now run on the CQL 6.2 engine and the whole
pattern library (38 patterns, `tests/test_app_pattern_library.tcl`): a player's games in one
multi-script pass (`::ai::cql::Matches6`), one position with `::scidb::cql6::position`
(`src/tcl/tcl_cql6.cpp`, ~11 ms for all event patterns), training candidates from the pattern
index when the database has one. Variants keep the legacy engine and its 12 patterns. Patterns
in `::ai::search::MatchBefore` match the position before their move (a CQL line from the move
on); training and themes take the move from there.
**Builds on:** `::scidb::cql::*` (`src/tcl/tcl_cql.cpp`), the pattern library in
`tcl/ai-search.tcl`, and `PLAIN_LANGUAGE_SEARCH.md`.

## 0. Common ground

CQL is exact. It sits on the ground-truth side of the firewall (`AI_PRODUCTS_PLAN.md`
§0), next to Stockfish and the fact layer. The four features below use it only to
**find and label positions**:

- the engine decides what a move is worth
- the database decides what happened
- a model may only restate what these give it

### New primitive

`::scidb::cql::position <fen> <script> ?<move>?` tests one position, or one move and the
position after it. The study plan and the annotator work on FENs, not database games.

### Pattern library (`::ai::search::Patterns`)

Every pattern now has a kind:

| Kind | Patterns |
|---|---|
| `event` (something happens) | checkmate, smothered mate, stalemate, en passant, underpromotion, double check |
| `structure` (a kind of position) | kings on opposite wings, rook ending, pawn ending, **isolated queen's pawn**, **opposite-coloured bishops**, **queenless middlegame** |

The three structures in bold are new. Each is checked on positions that have it and
positions that don't.

- `::ai::search::patternIds ?kind?` lists the ids, optionally of one kind.
- `::ai::search::structures <fen>` returns the structures a position shows.

## 1. Opponent brief by pawn structure

**Question it answers:** which kinds of position does this opponent reach, and how do
they score in them?

**How it works:**
- `::ai::cql::profile <base> <variant> <player> ?-colour? ?-games N?` takes the player's
  latest N games (default 200) from `BuildQuery`.
- For each structure pattern, it runs `::scidb::cql::match` on each game and counts the
  games that reach the structure, with the player's score in them (1, ½, 0 from their
  side).
- The output is a dict per structure (games, score, sample game numbers) plus a text
  block.

**Brief integration:** the text block is appended to the preparation facts *before* the
stance is chosen. So:
- the stance classifier sees it
- the rule-based stance can pick it up ("they score 31% in IQP positions" feeds
  `punish_weakness`)
- the narrator can only restate it

A structure appears only with at least 3 games, so tiny samples don't read as
tendencies.

**Firewall:** the counts and scores are database facts. No model is involved in
producing them.

## 2. More accurate study plan and auto-annotation

**Study plan:**
- Each mistake gets `structures` from `::ai::search::structures <fen before the move>`.
- The plan gains a "By structure" section: count and damage per structure, and the
  share of the player's mistakes that happened in it.
- Each cluster lists its dominant structures.
- The pattern labels (tactical, opening, …) are unchanged. Structure is a second,
  exact dimension, not a guess.

**Auto-annotation:**
- The grounded prompt for a gated move gets a `THEMES (CQL)` line: the event patterns
  that the *move* satisfies (tested with `position fen cql san`: en passant,
  underpromotion, double check, smothered mate) and the structures of the position
  after it.
- The rules already forbid the model from going beyond the facts. Themes give it
  vocabulary that is guaranteed true ("a smothered mate"), and the claim checker still
  audits everything.

## 3. Training sets from your own games

**Question it answers:** give me puzzles of pattern X from my games.

**How it works:** `::ai::cql::training <parent> ?-patterns ids? ?-player P? ?-max N?
?-depth D? ?-done CMD?`
1. **Find:** a `search_games` query (the player, optionally) AND the pattern's `cql`
   term. `::scidb::cql::match` gives the first ply h where the pattern appears.
2. **Pose:** the puzzle is the position before move h; the move played at h is the
   candidate solution. The game is read through `::scidb::game::load` +
   `::scidb::game::query mainline`, and the user's game is restored afterwards, as the
   study plan does.
3. **Verify** (engine, multipv 2): the played move must be the engine's best, **and**
   either a forced mate or at least 1.5 pawns ahead of the second-best move. That makes
   the solution unique. Everything else is rejected, with the reason counted.
4. **Emit:** a PGN with one game per puzzle:
   - `[FEN]`, `[SetUp "1"]`
   - `[Event "Training: <pattern>"]`
   - the source game's players and date
   - the solution move followed by the engine's line (up to 5 plies)
   - a comment naming the source game

   The file is written to `~/.scidb/training/` and its path is reported, so the user
   can open it as a database and train.

**Eligible patterns:** the events with a decisive move (checkmate, smothered mate, double
check, underpromotion).

**Firewall:** CQL finds the positions, the engine certifies the solutions, and no
model is involved.

## 4. Data-quality checks

**Question it answers:** which games in this database are internally inconsistent?

| Check | CQL |
|---|---|
| mate scored as a draw | `(match :result 1/2-1/2 (position :terminal :mate))` |
| White mated, scored 1-0 | `(match :result 1-0 (position :terminal :wtm :mate))` |
| Black mated, scored 0-1 | `(match :result 0-1 (position :terminal :btm :mate))` |
| stalemate scored as decisive | `(match :result 1-0 (position :terminal :stalemate))`, and the same with 0-1 |

**How it works:** `::ai::cql::quality <base> <variant>` runs every check with
`::scidb::cql::search` and returns `{check {game …}}`. The report lists each issue with
the games involved (number, players, result). "Show in game list" filters the main list
to the OR of the failing checks, using the `cql` search term.

**What import already fixes:** the PGN importer corrects a result that contradicts a
final checkmate or stalemate. For example, a mate scored `1/2-1/2` is stored as the
mating side's win, and a stalemate scored `1-0` as `1/2-1/2`. So the checks guard
databases from other sources and results edited after import.

**Firewall:** fully deterministic, and nothing is written. Fixing is left to the user,
because the database and the PGN source may disagree for reasons only a human can
judge.

## Surfaces

| Feature | Extras menu | Assistant tool |
|---|---|---|
| Structure profile | in the brief | `structure_profile {player colour}` |
| Study plan / annotation | the existing entries | the existing tools |
| Training set | "AI: Training Set from Games…" | `training_set {pattern player max}` |
| Data-quality check | "AI: Check Results…" | `check_results {}` |

## Fixed on the way

- **Tagging.** `:forany <tag> <designator>`, `:tagmatch <tag> <designator>` and
  `$tag[squares]` track a piece's identity across the game (the document's
  "same rook visits all four corners" example works). Limitation: candidate
  marks come from the start position, so a pawn that only promotes to the
  designator's piece is not a candidate.

- **`:exclude`.** A game is excluded (at the whole-game level) when an
  excluded sub-position list matches anywhere, or (bare form) when the
  containing position list matches. It does not affect the containing
  position's own result; the walker continues past a hit until the game ends.

- **The accumulator extension.** `:accumulate <name>` counts the
  transformations for which the position list matches, `:sumrange <name> <range>`
  gates on the accumulated value, and `:reset <name>` clears it. The accumulator
  map is per board position and shared across the nested position lists, so
  "count the passed pawns" works.

- **The transformation keywords.** The spatial flips (`:flip*`) and the
  translations (`:shift*`) are implemented. Flips are applied to the board (a
  reflection is a bijection, so a pattern D reflected by F matches board B iff
  D matches F(B)); shifts are applied to the position list's designators
  through an active shift, because the CQL edge behaviour makes a shift a
  non-bijection. Multiple transformation keywords compose. See the CHANGELOG.

- **`:variations` and `:variationsonly`.** The game consumer skipped every variation
  (`cql_game_matcher.cpp`), and both keywords were refused with `Not_Implemented`. It
  now walks the variations when a position list asks for them and passes
  `flags::IsInsideVariation`; `Position::match` applies the include/exclude gate
  (`:variations` = main line + variations, `:variationsonly` = variations only, no
  keyword = main line only). A query without either keyword behaves exactly as before.

- **Square-colour designators.** CQL's special `L` (light) and `D` (dark) square
  designators are now parsed (`src/db/cql/cql_designator.cpp`): `[L?]`/`[D1]` and the
  bare `BL?`/`b[D?]` forms. The `opposite_bishops` pattern no longer enumerates the
  32 light and dark squares by hand. Using `L`/`D` for both the files and the ranks
  is refused with `Square_Colour_Not_Allowed`.

- **`Board::checkState` never reported stalemate.** It searched for a legal move only
  when the side to move was in check. The importer's result correction, the
  "Drawn by stalemate" termination and the fact layer's `stalemate` field all depended
  on it and had never worked. The search now runs either way; it stops at the first
  legal move, so it costs little.

- **The study plan could not audit a named player.** `GamesToStudy` passed a partial
  criteria dict to `BuildQuery`, which failed inside a `catch`. It now fills the dict
  through `CheckArgs search_games`.
- **The study plan never read a game.** It called `::scidb::game::load` without a slot,
  which failed inside a `catch`. The audit and the training builder now read games into
  slots of their own (30 and 31; the merge dialog uses 20 and 21), so the user's board
  is never touched and nothing needs restoring.

## Limits

- **Variations:** the matcher visits the main line by default. A position list with
  `:variations` searches the main line and the variations, `:variationsonly` only the
  variations. Without either keyword, a structure reached only in a variation does not
  count.
- **Speed:** `profile` and `quality` decode games synchronously. The profile is capped
  at the latest 200 games, while quality reads the whole database once per check. Both
  are fine for club-size databases and slow for millions of games (see the progress
  item in `PLAIN_LANGUAGE_SEARCH.md` §6).
- **Training speed:** it runs one engine search per candidate. It is capped by `-max`
  and cancellable.
