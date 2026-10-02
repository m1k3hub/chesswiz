# Task 2: the Scidb side of the CQL 6.2 engine (`::scidb::cql6::*`), against a stub engine

This directory is a COPY of the Scidb source tree (Tcl/Tk + C++ chess database) including its built
objects, so incremental builds are fast. It is not a git repository. You may change ONLY:

* new: `src/tcl/tcl_cql6.cpp`, `src/tcl/tcl_cql6.h` (if you want one)
* new: `src/cql6stub/*` (a STUB of the engine, see below; it is never shipped)
* edit: `src/tcl/Makefile` (add the new source), `src/tcl/tcl_base.cpp` (register the module, as
  `media::init`/`diag::init` are registered), `src/Makefile` (link the engine library)
* new: `tests/test_app_cql6.tcl`
Do not touch anything else, do not run `sudo`/`make install`, and never touch
`/media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex` (the owner's real checkout).

## Background

Scidb has an old in-process CQL matcher (`src/db/cql`, Tcl `::scidb::cql::*`, see `src/tcl/tcl_cql.cpp`
for how it reads games from an open database: use it as your pattern for opening a database cursor,
iterating games and decoding moves). We are adding the OFFICIAL CQL 6.2 engine beside it. That engine
is being made embeddable by someone else: it will be a static library `libcql6.a` with exactly the C API in
`src/cql6/cql6_api.h` (READ THAT FILE FIRST; it is the contract and must not be edited). Instead of
reading a PGN file it calls a host callback `cql6_next_fn` to get each game, and returns the matches as data.
You write the host side: the Tcl command that feeds games from a Scidb database to `cql6_search`.

The real library does not exist yet. You develop and test against a stub you write in `src/cql6stub/`
(`cql6_stub.cpp` implementing the same four functions, plus a tiny `Makefile` producing
`src/cql6stub/libcql6stub.a`). `src/Makefile` must link the library named by a make variable,
`CQL6_LIB`, defaulting to `cql6/build/libcql6.a` (the real one) and overridable on the command line:
`make -C src CQL6_LIB=cql6stub/libcql6stub.a`. Use that for all your testing.

## Tcl API (namespace `::scidb::cql6`)

```
::scidb::cql6::version
    -> the engine's version string (cql6_version())

::scidb::cql6::search <database> <variant> <script> ?-threads N? ?-variations 0|1? ?-max N? ?-pgn 0|1? ?-command CMD?
    Runs the CQL script text over every game of the open database.
    Without -command: synchronous; returns the result dict (below), or raises a Tcl error with the
    engine's message (syntax error etc.).
    With -command: returns a job id at once (an integer) and runs the search on a worker thread so the
    GUI never blocks; when it ends the main thread calls  CMD <resultdict>  from the event loop, where the
    dict is {ok 1 ...result...} or {ok 0 error MESSAGE}.
::scidb::cql6::progress <job>     -> games examined so far (integer), or -1 for an unknown/finished job
::scidb::cql6::cancel <job>       -> 1 if the job was running; it ends soon with the matches found so far and
                                     `cancelled 1` in its result
```
Result dict: `matches {{game N first_ply P ?pgn TEXT?} ...} games G threads T cancelled 0|1 messages TEXT`
(`game` is the 0-based Scidb game index; `pgn` only with `-pgn 1`).

## Converting a Scidb game into `cql6_game`

For each game of the database (in index order), in the callback:
* `number` = the game's 0-based index in the database
* `fen` = the start position FEN when the game does not start from the standard position, else NULL
* `tags` = at least White, Black, Event, Site, Date (PGN format `YYYY.MM.DD`, `????.??.??` when unknown),
  Round, Result (`1-0`, `0-1`, `1/2-1/2`, `*`), WhiteElo, BlackElo, ECO when present, plus any extra tags
  Scidb keeps for the game that are cheap to get; keep the strings alive until the next call of the same thread
* `moves` = the game tree as the `cql6_move` records of the header: the main line, and, when `-variations 1`,
  the variations (kind 1 .. kind 2 nesting) with their comments; squares 0..63 (a1=0 .. h8=63), promo 0 or
  'Q','R','B','N'. Castling is the king's move (e1g1), en passant the pawn's move. Skip games Scidb cannot
  decode (count them, do not abort).
The engine serialises calls of the callback with its own mutex, so the callback need not lock, but it is
called from engine worker threads, not from the Tcl thread: do not call the Tcl API or touch Tk in it.
Decide and DOCUMENT in a comment what makes reading the database from a worker thread safe (for example
the search holding a reference to the cursor/database for its whole run, and refusing to start when the
database is being written to) and what happens if the database is closed while a job runs (it must not crash:
cancel the job, deliver `{ok 0 error "database closed"}`).
Nothing in the database is modified.

## Engineering rules

* No global mutable state other than a job table guarded by a mutex; several jobs may exist but the ENGINE runs
  one search at a time: a second `search` while one runs returns the engine's error (or waits; document it).
* Delivering the asynchronous result: `Tcl_ThreadQueueEvent` + `Tcl_ThreadAlert` to the main thread (the Tcl
  interpreter's thread), never `Tcl_Eval` from the worker.
* No blocking of the Tcl thread except in the synchronous form.
* Follow the file's neighbours for style (tabs, `// vi:set ts=3 sw=3:`, `createCommand`, `setResult`, error helpers).

## The stub engine (`src/cql6stub/cql6_stub.cpp`)

Implements the four functions with this deterministic behaviour, chosen so the glue can be tested without the
real engine. It runs the callback loop on its own threads as the real one does (`threads` workers, default 4,
callback serialised by a mutex) and treats `script_text` as a command:
* `MATCH_ALL`: every game matches, first_ply 0
* `MATCH_EVEN`: games whose `number` is even match, first_ply = number % 7
* `DUMP`: every game matches; with `want_pgn` the `pgn` field is a one-line text describing exactly what was
  received: `number=N fen=FEN|- ntags=T tags=name:value,... moves=from-to[promo],...` with variation records written
  `(` for kind 1 and `)` for kind 2 and comments as `{text}`
* `SLOW`: sleeps 3 ms per game, then matches all games (for progress/cancel/async tests)
* `ERROR`: returns non-zero with message `stub error`
* anything else: matches nothing
`max_matches` and `threads` are honoured; `ngames` counts games received.

## Acceptance tests (`tests/test_app_cql6.tcl`, run them)

Follow `tests/test_app_cqlfeatures.tcl` (it builds a small PGN fixture and opens it) and run with
`cd tests && xvfb-run -a ../src/tkscidb-beta run_app_tests.tcl -match 'cql6-*'` after
`make -C src CQL6_LIB=cql6stub/libcql6stub.a` (build from `src`, the top-level make is not needed).
1. `version` returns the stub's string.
2. `MATCH_ALL`/`MATCH_EVEN` on a 12-game fixture return the right game indexes; `-max` and `-threads` honoured.
3. `DUMP` on hand-made games checks the conversion: tags incl. Elo/ECO/Date, a non-standard start FEN,
   castling (both sides), en passant, each promotion piece, a variation with a comment (with `-variations 1`;
   with `-variations 0` no kind 1/2 records and no comment).
4. Errors: `ERROR` and a bad database name raise a Tcl error with a useful message; the app keeps working.
5. Async: `SLOW` over a 600-game fixture with `-command`: the Tcl event loop stays responsive (a timer
   fires every 20 ms while it runs: check the largest gap), `progress` grows, the result arrives in the
   callback with all 600 games; then `cancel` after ~300 games returns `cancelled 1` with fewer games.
6. Closing the database while a job runs does not crash and delivers `ok 0`.
7. The complete existing app test suite still passes (`run_app_tests.tcl` without `-match`).

Finish with an honest report: files changed, test results with numbers, anything unverified or risky
(especially the thread-safety argument in point "Converting"). Do not weaken a test to make it pass.
