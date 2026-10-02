# Task 1: make CQL 6.2 embeddable (library + structured game feed)

You are working in a git worktree of the Scidb chess database, branch `cql6-port`.
ONLY touch files under `src/cql6/` (plus `CQL6_TASK1.md` notes you must not commit).
Never touch `/media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex` (the owner's
main checkout with uncommitted work), never run `sudo`, `make install` or `git push`.
Commit your work on the branch `cql6-port` when it passes the acceptance tests.

## Background

`src/cql6/` is the unmodified official CQL 6.2 source (build 9.493): a standalone program
that reads a PGN file, runs a CQL script (a chess query language) over every game and writes
matching games to a PGN file. We want to embed it inside a C++ application (Scidb) that keeps
its games in its own database format, so **games must come from a host callback instead of a
PGN file**, and results must come back as data, not as an output PGN file.

How the program works (verified by reading the source; re-verify what you rely on):

* `cql.cpp` main -> `cql_execute` (`cqlthread.cpp`). One `CqlNode` tree and one `QGame` per
  thread (`generateCqlNodes`), threads run `thread_exec`: `while (qgame->parseNextGame())`
  -> `cqlnode->match_game(qgame)` -> on a match `setFirstComment`, `qgame->mergeComments()`,
  `makeInfo(qgame)` (which builds a `GameSortInfo` holding the annotated PGN text).
* Games come from one shared `PgnSource` (mutex protected; it splits the file into one
  text buffer per game); each thread then parses its buffer with `PgnParser::ParseGame`
  into a Scid `Game` (`orig/game.h`) inside `QGame::pgnParseNextGame()` (`qgame.cpp`).
  **That function is the injection point**: after it, `QGame` holds a populated `Game` and the
  matching core needs nothing else. Study `orig/pgnparse.cpp` (`ParseGame`) to see exactly which
  `Game`/`Position` calls build a game (tags, start position from FEN, moves, variations,
  comments, result), and reproduce them from structured data.
* The script file is read with `Lexer::lexFile(filename)`; `lexString(contents)` also exists.
  A script starts with a header such as `cql(input games.pgn output out.pgn) ...`; in the
  embedded mode `input`/`output` must be ignored (the host supplies the games).
* Errors: `uassert`, `eassert`, `cql_exit(...)` print a message and call `exit(1)` or, when threads
  run, `std::abort()`. `cqlexit.cpp` has an `#ifndef INTEGRATED` guard but nothing else does.
* Many globals (`cqlglobals.cpp`: `CqlDebug`, `CqlRunningThreads`, `CqlIsExiting`, ...), a
  function `cql_initialize()`, and persistent script variables (single-thread scripts).
* It prints progress and a summary line to stdout.

## Deliverable

A static library `src/cql6/build/libcql6.a` built by `make -C src/cql6 -f Makefile.scidb lib`
(create `Makefile.scidb`; leave the original Makefiles alone) with this C API in
`src/cql6/cql6_api.h` (plain C linkage; `extern "C"`; no C++ types in the header):

```c
typedef struct { const char* name; const char* value; } cql6_tag;

/* one move record of the game tree of one game. kind:
 *   0 = a move of the current line
 *   1 = start of a variation (it replaces the move just before it); the next records are its moves
 *   2 = end of the current variation (back to the line it came from)
 * from/to are squares 0..63 (a1=0, b1=1, ... h8=63). promo is 0 or one of 'Q','R','B','N'.
 * comment may be NULL. */
typedef struct { int kind; int from; int to; int promo; const char* comment; } cql6_move;

/* one game, filled in by the host. All memory belongs to the host and must stay valid until the
 * host is called again from the SAME library thread or the search ends. */
typedef struct {
    int         number;     /* host's game number (returned with matches); may be any int >= 0 */
    const char* fen;        /* start position, NULL = the standard start position */
    int         ntags;  const cql6_tag*  tags;   /* White Black Event Site Date Round Result WhiteElo ... */
    int         nmoves; const cql6_move* moves;
} cql6_game;

/* Called by the library to get the next game. Return 1 and fill *g, or 0 when there are no more.
 * The library serialises these calls with its own mutex: the host need not be thread safe.
 * `thread` (0..threads-1) identifies the calling worker. */
typedef int (*cql6_next_fn)(void* ctx, int thread, cql6_game* g);

typedef struct {
    int threads;        /* 0 = automatic (hardware threads - 1), 1 = single thread */
    int variations;     /* 1 = also search variations (like the -variations option) */
    int max_matches;    /* 0 = no limit */
    int want_pgn;       /* 1 = return the annotated PGN of every match */
} cql6_options;

typedef struct { int game_number; int first_ply; char* pgn; } cql6_match;
    /* first_ply: mainline ply (0 = start position) of the first position that got the match
       comment, -1 if only variation positions matched. pgn: malloc'd, NULL unless want_pgn. */

typedef struct {
    int         nmatches;  cql6_match* matches;    /* sorted by game_number */
    long        ngames;                            /* games examined */
    int         threads_used;
    char*       messages;                          /* malloc'd text the script printed (e.g. persistent variables), or NULL */
} cql6_result;

/* Returns 0 on success (result filled, free with cql6_free_result), else non-zero and a message in
 * err[errlen] (syntax error, runtime assert, ...). NEVER exits, aborts or writes to stdout. */
int  cql6_search(const char* script_text, const cql6_options* opt, cql6_next_fn next, void* ctx,
                 cql6_result* out, char* err, size_t errlen);
void cql6_free_result(cql6_result* r);
const char* cql6_version(void);     /* e.g. "6.2 build 9.493" */
```

`script_text` is the script itself (not a path). Only one `cql6_search` may run at a time in a
process (guard with a mutex; a second concurrent call fails with an error message), but any number
of sequential searches with different scripts must work (re-initialise the globals each time).

## Required engineering

1. **No exits.** Turn every `exit`/`abort`/`cql_exit`/failed-assert path into a C++ exception
   (define one exception class) thrown where it happens and caught (a) at the API entry and
   (b) at the top of every worker thread (an exception escaping a `std::thread` terminates the
   process). When a worker fails, stop the other workers cleanly and return the error text.
   Do not leave locks held. Keep the original behaviour for the standalone `cql` program if that
   is cheap (e.g. behind `#ifndef CQL6_EMBEDDED`), otherwise just the embedded behaviour.
2. **No stdout/stderr output** from the library during a search. Capture what the script is meant
   to print (persistent variables etc.) into `messages` if you can find it cheaply.
3. **Structured feed instead of PGN.** Add a game source class used by `QGame` in place of
   `PgnSource`/`PgnParser` when embedded (mind `QGame::pgnBuffer` = 1 MB per QGame: keep
   memory use sane). Build the `Game` from `cql6_game` with the same `Game` API calls the PGN
   parser makes (look at `ParseGame`), including starting FEN, variations and comments, so the
   matching core sees the same thing as with a PGN file. Keep `game->SetNumber`, tag section
   initialisation, regex history reset etc. exactly as `pgnParseNextGame` does.
4. **Results as data**, not an output file: skip `GameSortInfo::output`. Build `cql6_match` per
   match; `first_ply` from the match comments (before they are merged) or from whatever the
   code exposes; `pgn` only when `want_pgn` (it is `makeInfo`'s text, otherwise skip that cost).
   Sorting (`sort` filters in scripts) and `max_matches` should behave as in the original.
5. **Symbol isolation.** The library will be linked into a large application that has its own
   global classes with overlapping names. Compile with `-fvisibility=hidden -fPIC`, merge all
   objects with `ld -r` into one object, then `objcopy --keep-global-symbol=...` so that the ONLY
   global defined symbols of `libcql6.a` are `cql6_search`, `cql6_free_result`, `cql6_version`.
   (Weak/COMDAT symbols must be made local too.)
6. Flags: `-std=c++17 -pthread -O2 -w -DASSERTIONS -DCQL6_EMBEDDED -I. -I./orig`
   (`-Werror` of the original makefile trips on a modern gcc, do not use it).
7. Record every change to an original file in `src/cql6/SCIDB-CHANGES.md` (file, why) and mark each
   change in the source with a `// scidb:` comment. New code goes in NEW files where possible
   (`scidb_feed.cpp`, `cql6_api.cpp`, ...). Keep the diff to original files small.

## Acceptance tests (you must write and run them; put them in `src/cql6/tests/`)

Use the OFFICIAL program as the oracle: `make cql "CPP_FLAGS=-pthread -O2 -std=c++17 -w -DASSERTIONS -I. -I./orig"`
in a COPY of `src/cql6` (so the vendored tree stays clean), giving `./cql`.
Test PGN: take the first 3000 games of `/media/michael-g-thomas/sas_mirror/chess/mega_full.pgn`
(read-only; extract with `awk`/`head` into a scratch dir, do not commit it).

* T1 `make -C src/cql6 -f Makefile.scidb lib` builds `build/libcql6.a`; `nm -g --defined-only` of it
  shows exactly the three `cql6_*` symbols.
* T2 A driver `tests/pgn_driver.cpp` links the library, reads the test PGN with the **vendored
  `PgnParser`** (this driver may use internals) into `cql6_game` structures (tags, FEN, mainline moves
  AND variations AND comments as far as the parser gives them) and feeds them through `cql6_search`.
  For at least 12 different scripts (write simple ones yourself: `check`, `stalemate`, `mate`,
  `[R]==1 and [r]==1 and [P]==5 and [p]==5 and [QBNqbn]==0`, `Kg1 Rf1 Pf2 Pg2 Ph2`, a `flip`/`flipcolor` one,
  a `sort` one, plus about 6 from `examples/` whose input line you replace), the set of matching game
  numbers equals the set printed/written by the official `./cql` on the same PGN (game numbers in the
  official output PGN are in its `{Game number N}` comments). With 1 thread AND with 8 threads.
  Also one script with `variations` on.
* T3 Errors: a script with a syntax error, an empty script and a script using a nonexistent filter
  return non-zero with a useful message and the process keeps running; after each, a normal search works.
* T4 Re-entrancy: 30 sequential searches with different scripts in one process, including a script
  with a persistent variable; results identical to running each once in a fresh process.
* T5 A worker hitting an internal assert mid-search (inject one with a tiny hook or use a script that
  triggers one) returns an error and does not hang or crash (run it 20 times).
* T6 Nothing is written to stdout/stderr during any search (redirect fd 1 and 2 to a file in the test).
* T7 `first_ply` is correct for `check` on a few hand-checked games, and `want_pgn` returns PGN that
  contains the match comment.
* T8 Speed: searching the 3000 games with `stalemate` through the feed takes no more than about 2x the
  official `./cql` time on the same machine (report both numbers).

Report at the end (in your final message): what you changed, every test's result with the numbers,
and anything you could not do or are unsure about. Be honest about failures; do not weaken a test to
make it pass.
