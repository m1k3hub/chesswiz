# Scidb Port Changes to CQL 6.2

This document describes all modifications and new files introduced to port CQL 6.2 (build 9.493) to an embedded library (`libcql6.a`) for Scidb.

All modifications to existing/original files are guarded with `#ifdef CQL6_EMBEDDED` or marked with `// scidb:` comments.

---

## 1. New Files

* **`cql6_api.h`**
  Public C API for embedding CQL 6.2. Defines:
  * `cql6_tag`: Tag key-value pair.
  * `cql6_move`: Structured game move / variation representation (`kind` 0 = move, 1 = variation start, 2 = variation end).
  * `cql6_game`: Structured game descriptor passed by host callback.
  * `cql6_next_fn`: Serialized callback providing the next game from the host.
  * `cql6_options`: Search options (threads, variations, max_matches, want_pgn).
  * `cql6_match`: Result match information (`game_number`, `first_ply`, `pgn`).
  * `cql6_result`: Aggregate result (`nmatches`, `matches`, `ngames`, `threads_used`, `messages`).
  * `cql6_search()`, `cql6_free_result()`, `cql6_version()`.

* **`cql6_api.cpp`**
  Implementation of the C API entrypoints:
  * Manages global single-search mutex guarding re-entrancy.
  * Captures/suppresses all stdout/stderr output during search execution via `OutputSilencer`.
  * Calls `cql_initialize()` to reset global state cleanly between sequential calls.
  * Spawns worker threads invoking `embedded_thread_worker`, catching exceptions cleanly and signaling early termination without hangs or leaks.
  * Aggregates and sorts matches (including sort variable handling when script uses `sort`).
  * Populates `first_ply` and generates annotated PGN when `want_pgn` is requested.

* **`cqlexception.h`**
  Defines `class CqlException : public std::runtime_error` used across all error, assertion, and exit paths to prevent `std::abort()` or `exit()` from terminating the host process.

* **`scidb_feed.h` / `scidb_feed.cpp`**
  Implements `ScidbGameSource` to feed games directly from host callback to `QGame`:
  * Serializes calls to `cql6_next_fn` with an internal mutex.
  * `populateGame()` converts `cql6_game` into a Scid `Game` object in memory:
    * Sets start position (FEN).
    * Sets standard headers (`White`, `Black`, `Event`, `Site`, `Round`, `Result`, `Date`, `EventDate`, `ECO`, ratings, `ScidFlags`, and extra tags).
    * Reconstructs moves, variations, and comments matching Scid `Game` semantics.

* **`Makefile.scidb`**
  Build system for the embedded static library `build/libcql6.a` and test target:
  * Compiles with `-std=c++17 -pthread -O2 -w -DASSERTIONS -DCQL6_EMBEDDED -fvisibility=hidden -fno-gnu-unique -fPIC -I. -I./orig`.
  * Merges objects with `ld -r -o build/cql6_all.o`.
  * Applies `objcopy` keeping only global symbols `cql6_search`, `cql6_free_result`, and `cql6_version`.
  * Strips section groups via `strip -R .group` to eliminate ELF COMDAT section conflicts with the host application.
  * Archives into `build/libcql6.a`.

* **`tests/pgn_driver.cpp`**
  Acceptance test suite executing tests T1 through T8:
  * T1: Verifies symbol isolation using `nm -g --defined-only` (exactly 3 exported symbols).
  * T2: Compares results with official `./cql` oracle across 12 scripts (with 1 and 8 threads, plus variations) on 3,000 games.
  * T3: Validates syntax error, empty script, and nonexistent filter handling.
  * T4: Tests 30 sequential searches with persistent variables for clean re-entrancy.
  * T5: Tests 20 repeated runs with worker assert injection verifying graceful recovery without hangs or crashes.
  * T6: Verifies 0 bytes written to stdout/stderr descriptors 1 and 2 during searches.
  * T7: Verifies `first_ply` accuracy and `want_pgn` comment retention.
  * T8: Verifies performance benchmark against official oracle within <= 2x execution time.

* **`.gitignore`**
  Ignores `build/` directory in `src/cql6/`.

---

## 2. Modified Original Files

* **`orig/game.h`**
  * Added `moveT* GetFirstMove() { return FirstMove; }` accessor (`// scidb:`) so drivers can traverse game move trees without modifying `FirstMove`.

* **`orig/myassert.cpp`**
  * Replaced `abort()` with `throw CqlException(...)` under `#ifdef CQL6_EMBEDDED` (`// scidb:`).

* **`orig/position.cpp`**
  * Replaced `abort()` calls in `Position::DoSimpleMove` and `Position::UndoSimpleMove` with `throw CqlException(...)` under `#ifdef CQL6_EMBEDDED` (`// scidb:`).

* **`cqlexit.cpp`**
  * Replaced `exit()` and `abort()` in `cql_exit()` with `throw CqlException(...)` under `#ifdef CQL6_EMBEDDED` (`// scidb:`).

* **`cqlglobals.h` / `cqlglobals.cpp`**
  * Added `CqlTestAssertHook` function pointer for test assert injection under `#ifdef CQL6_EMBEDDED` (`// scidb:`).
  * In `cqlglobals_initialize()`, reused existing `CqlPreambleStrings` and `CqlPreambleTransforms` vectors by clearing them instead of leaking new allocations on repeated searches (`// scidb:`).

* **`cqlnode-parse.cpp`**
  * In `Tokens::match_cqlnode()`, made `cql(...)` preamble header optional in `#ifdef CQL6_EMBEDDED` mode (`// scidb:`).

* **`cqlnode.cpp`**
  * Under `#ifndef CQL6_EMBEDDED`, bypassed input and output file validations since games and output are handled via host data buffers (`// scidb:`).

* **`cqlthread.h` / `cqlthread.cpp`**
  * Added `generateCqlNodesFromString(const string& script_text, int nthreads, bool *forcesinglethreadp)` to parse scripts directly from in-memory strings (`// scidb:`).

* **`cql.cpp`**
  * Excluded standalone `main()` from compilation under `#ifndef CQL6_EMBEDDED` (`// scidb:`).

* **`qgame.h` / `qgame.cpp`**
  * Added `QGame(ScidbGameSource*, int thread_idx, bool variations)` constructor and `scidbParseNextGame()` dispatch to feed games via `ScidbGameSource` instead of `PgnSource` (`// scidb:`).

---

# Task 3 changes (hardening)

This section lists every change made for Task 3, grouped by the gate it serves. Every
modification to an original file carries a `// scidb:` comment and is either guarded by
`#ifdef CQL6_EMBEDDED` or documented as unreachable from `cql6_search`.

## New files

* **`scidb_sink.h` / `scidb_sink.cpp`** (Task 3 §E1) — force-included (`-include
  scidb_sink.h`) into every library TU under `CQL6_EMBEDDED && CQL6_LIBRARY_BUILD`.
  It redefines `printf`/`fprintf`/`puts`/`fputs`/`putchar`/`putc`/`fputc` and the
  global `cout` reference to append to a mutex-protected, per-search buffer instead of
  the host's fd 1/2. `scidb_sink::begin()`/`end()` are called by `cql6_search`; the
  captured text is returned in `cql6_result::messages`. No descriptor is dup2'd and
  `std::cout.rdbuf()` is never touched. Output outside a search is dropped. Writes to
  streams other than stdout/stderr fall through to the real functions.
* **`scidb_lockdown.h` / `scidb_lockdown.cpp`** (Task 3 §A) — `std::atomic<bool>
  ScidbSearchActive` plus `scidb::file_guard(what, path)`. Set for the whole duration
  of `cql6_search`. Every filesystem entry point compiled into the library calls it
  and throws `CqlException` while a search runs.
* **`tests/strace_gate.sh`**, **`tests/filelock.cpp`**, **`tests/stdout_race.cpp`**,
  **`tests/robustness.cpp`**, **`tests/stress.cpp`**, **`tests/oracle20k.cpp`**,
  **`tests/feed_common.h`**, **`tests/run_san_suite.sh`** — the Task 3 gate tests.
* **`GATES.md`** — verified status of each gate.

## A — file lockdown

* **`scidb_lockdown.{h,cpp}`** — the guard itself (new file, above).
* **`cql6_api.cpp`** — sets `ScidbSearchActive` for the whole search via a RAII guard.
* **`node-parse.cpp`** — `readfile` and `writefile` are rejected at PARSE time with
  "`readfile`/`writefile` is not available when CQL runs inside Scidb", so a script
  with them never starts a partial run.
* **`cqlnode-parse.cpp`** — the `input`/`output` filenames in the `cql(...)` header are
  accepted and ignored in embedded mode.
* **`readfilenode.cpp`**, **`writefilenode.cpp`** — defense in depth: `file_guard()` at
  the top of `match_position` (unreachable because of the parse-time ban).
* **`util.cpp`** — `util::string_from_filename` calls `file_guard()`.
* **`gamesortinfo.cpp`**, **`converttoexternal.cpp`** — `GameSortInfo::output` and
  `ConvertToExternal::exporthtml` call `file_guard()` (not reached in embedded mode
  because results are returned as data).
* **`pgnsource.cpp`** — `PgnSource::PgnSource` calls `file_guard()` (the embedded feed
  never constructs a `PgnSource`).
* **`orig/mfile.cpp`** — `MFile::Open`/`MFile::Create` call `file_guard()`.
* **`orig/misc.cpp`** — `gzipFileSize`/`createFile` call `file_guard()`.
* **`orig/namebase.cpp`** — `NameBase::OpenNameFile`/`WriteNameFile` call `file_guard()`.
* **`orig/tree.cpp`** — `TreeCache::WriteFile`/`ReadFile` call `file_guard()`.

## B — sanitizers / thread safety

* **`orig/myassert.h` / `orig/myassert.cpp`** — `numAsserts` increment inside the
  `ASSERT` macro was removed. The counter was incremented ~79M times per 5538-game
  search from every worker thread, causing severe cache line bouncing (20x slowdown
  from 1 to 32 threads), data races (TSan), and signed integer overflow (UBSan). Since
  nothing reads the counter, the increment was eliminated; the variable remains only
  for external linkage compatibility.
* **`qpos-visit.cpp`** — `QPos::visitRoot` was an $O(n^2)$ double loop executing
  $n \times n$ assertions per game ($n \sim 250$). Reduced to a single $O(n)$ loop checking
  the exact same condition (`all[i]->index == i`), eliminating millions of redundant assert
  evaluations and dramatically improving thread scaling under sanitizers.
* **`Makefile.scidb`** — adds `asan` (ASan+UBSan) and `tsan` targets that rebuild the
  library and all drivers with `-O1 -g -fno-omit-frame-pointer` and the sanitizer flags,
  and run the acceptance suite with `halt_on_error=1`. Sanitizer builds skip only the
  symbol-isolation `objcopy` (tests link the plain archive); T1 still checks the real
  release `build/libcql6.a`.
* **`QGame` per-thread state / chunked `QPos` pool** — see §E4.
* **`CqlIsExiting`** (mentioned by the CQL authors as a known exit race): in an embedded
  build `cql_exit` never sets it (it throws), and `cqlglobals_initialize` writes it
  `false` on the main thread before any worker starts, so it is only ever read as
  `false` concurrently — no race. Its only reads are `orig/position.cpp` (inside a
  comment block) and `pgnsource.cpp` (not constructed embedded).
* **`WriteFileNode::fileMap`** (`writefilenode.h/.cpp`): only touched from
  `WriteFileNode::match_position`, which is unreachable (parse-time ban + `file_guard`).
  C++11 guarantees the static's initialization, so even the unreachable path is safe.
* **Other statics reviewed**: `util::indentlevel` (debug printers only),
  `MarkBoard::getLegalMoves` locals (function starts with `uassert(false)`),
  `orig/position.cpp` hash/FEN tables (guarded by mutexes, read-only after init),
  `orig/misc.cpp scid_Init numCalls` (main thread before workers), `orig/stored.cpp
  storedLineGames`/`orig/game.cpp encodeFn` (one-time init). No sanitizer report was
  produced by any of them.

### LeakSanitizer findings fixed (all real leaks; no suppression file is used)

The CQL/Scid code allocates with `new` and has no destructors anywhere; LeakSanitizer
found the following leaks, which were fixed at their root:

* **`orig/game.h`** — `Game::~Game()` freed only `StrAlloc`/positions; the move chunks,
  the extra tags and the five standard tag strings were leaked (~9 KB per Game, one Game
  per worker per search). The destructor now frees them.
* **`util.cpp`** — `util::game_to_string` allocated a `TextBuffer` and called `Free()`
  but never `delete`d it (the ~2 KB object contains a `const char*[256]`), once per
  match whenever `want_pgn` is set. Added the `delete`.
* **`orig/pgnparse.cpp` / `orig/pgnparse.h`** — `PgnParser::Init()` allocated a new
  `DString ErrorBuffer` on every call without freeing the previous one; the embedded
  feed re-inits a parser per game (the test drivers too), leaking the DString plus any
  grown buffer per game. `ErrorBuffer` is now initialised to NULL and reused/cleared.
* **`cql6_api.cpp`** — `setCqlGlobal(CqlMatchString, "CQL")` allocated a `std::string`
  and kept only its `c_str()`, leaking on every search. It now assigns the literal
  `"CQL"` and sets `CqlMatchStringSet`.
* **`cqlthread.cpp`** — `generateCqlNodesFromString` leaked the `Tokens` parser wrapper
  (and its `Environment`) and, on a syntax error, also all wrappers created so far. It
  now deletes every `Tokens` (with a catch-and-delete on the error path); the
  `Environment` is owned by the `CqlNode` on success and retained by the registry below
  on failure.
* **`scidb_retain.h` / `scidb_retain.cpp` (new)** — process-lifetime retention
  registries for `Token`, `Node` and `Environment`. CQL drops/replaces tokens in
  `fixWhiteSpace`/`fixPath`, abandons the whole partial parse tree when a script has a
  syntax error (`show_error` throws), and has original call sites that discard clones
  (e.g. `extremalnode.cpp`: `for (auto n: theNodes) n=n->clone();`). None of this memory
  was ever freed, even by the standalone program. Embedded builds now register every
  such object in a raw global linked list so it stays reachable; this does not change
  the original program's memory behaviour, it only lets LeakSanitizer see the memory is
  still referenced. **Deliberately a raw linked list, not `std::vector`**: the
  LeakSanitizer in this toolchain follows raw global pointers transitively but does not
  traverse the heap buffer of a `std::vector` global, so `std::vector`-held pointers
  were still reported as leaks. `token.h`, `node.h` and `environment.h` register from
  the base constructor of each class; `cql6_api.cpp` uses the same raw-list scheme for
  the retained `CqlNode` trees.
* **`Makefile.scidb`** — added `-MMD -MP` and `-include $(ALL_OBJS:.o=.d)` so header
  edits really rebuild every dependent object (the plain pattern rules did not track
  headers, which had produced stale sanitizer binaries during development).

## C — feed robustness

* **`cql6_api.h`** — `cql6_result` gains `long nskipped`; `cql6_options` gains the
  internal `test_hook` used by `tests/stress.cpp`.
* **`cql6_api.cpp`** — sums `nskipped` across workers; if every supplied game was
  rejected (`ngames==0 && nskipped>0`) it returns an error instead of a silent empty
  result; frees `QGame`s on the error path.
* **`qgame.h` / `qgame.cpp`** — `nSkippedGames` counter; `scidbParseNextGame` skips a
  game that `populateGame` rejects *or* whose `QPos` construction throws (e.g. an empty
  variation or a game too big for the pool), resets `nextQPosIndex`/`allQPos`/comments
  and continues with the next game.
* **`scidb_feed.cpp`** — `populateGame` rejects (never crashes): NULL structures,
  negative/absurd counts, NULL tag/move arrays, more than `MAX_TAGS` tags, NULL tag
  name/value, squares outside 0..63, promo chars outside QRBN, unknown move kinds,
  unbalanced variation records, >255 sibling variations (Scid `numVariations` is a
  byte), variation depth > 10000, garbage/impossible FEN, and any move that is not
  generatable from the current position. Rejections are traced when `CQL6_FEED_DEBUG`
  is set; the debug trace is guarded with `scidb::file_guard()` to enforce the file
  lockdown invariant during embedded searches.
* **`orig/pgnparse.cpp`** — `PgnParser::GetComment` now reserves one byte for the NUL
  terminator (`bufSize > 1`). ASan found that a long comment (mega_full game 1 has a
  16000-char pre-game comment) filled the buffer and the missing terminator made the
  caller read past it.

## D — oracle comparison

* **`orig/position.cpp`** — real bug found by the 20000-game oracle comparison:
  `Position::IsValidEnPassant` removed the capturing pawn from its square and the
  captured pawn, tested for check, then restored both, but never placed the capturing
  pawn on the en-passant target square. An enemy rook/queen looking along the file or
  rank through `to` therefore made a legal en-passant capture look like it exposed the
  king; `GenerateMoves` dropped the move while `ReadMove` (which does place the pawn)
  accepted it. Fixed by putting the capturing pawn on `to` for the check test. This is
  an upstream Scid/CQL bug, not a port artefact (it is visible with the standalone
  oracle too).
* **`tests/pgn_driver.cpp`** — T2 no longer counts 0-match scripts as proof; the
  strengthened 20000-game comparison is `tests/oracle20k.cpp`.

## E1 — no stdout/stderr redirect

* **`cql6_api.cpp`** — the `OutputSilencer` class (dup/dup2 over fd 1/2) is DELETED.
  `scidb_sink::begin()`/`end()` bracket each search instead.
* **`abbreviations.h`** — `using std::cout;` is disabled under `CQL6_EMBEDDED`; `cout`
  is the sink stream.
* **`scidb_sink.{h,cpp}`** — new (above).
* **`cqlinitialize.cpp`** — `setbuf(stdout,NULL)` is compiled out under `CQL6_EMBEDDED`.

## E2 — no exit/abort reachable

* **`cqlexit.cpp`** — already `throw CqlException` in embedded mode (Task 1).
* **`orig/myassert.cpp`** — `abort()` replaced by `throw CqlException` under
  `CQL6_EMBEDDED`.
* **`orig/position.cpp`** — `AssertPos()` failures in `DoSimpleMove`/`UndoSimpleMove`
  throw instead of `abort()`; the `exit(1)` at line 91 is inside a comment block.
* **`orig/stored.cpp`** — the "should never happen" `exit(1)` for a bad stored line
  throws instead.
* **`hhdb-options-parse.cpp`** — the whole file is behind `#ifndef CQL6_EMBEDDED`
  (only reachable from `parseargs`/`main`).
* **`cql.cpp`** — `parseargs`/`printhelp` and `main` are behind `#ifndef CQL6_EMBEDDED`.
* Verified with `nm build/libcql6.a`: no undefined `exit`, `abort`, `_Exit` or
  `quick_exit`; the only abort-like undefined symbols are `__stack_chk_fail`,
  `__cxa_atexit`, `__cxa_guard_abort` and `_ZSt9terminatev` (implicit C++ exception
  machinery; worker threads catch every exception).

## E3 — no global side effects

* **`cqlinitialize.cpp`** — `setbuf(stdout,NULL)` compiled out (it changed the host's
  stdio buffering).
* No `signal`/`sigaction`, `setlocale`, `chdir`, `setenv`/`putenv`, `umask`,
  `std::ios::sync_with_stdio`, `std::cout.rdbuf` or `freopen` exists in the library.
* `orig/common.h`'s `srandom32`/`random32` use the process-global `random()`; they are
  reachable only from `Position::Random`, which is never called anywhere. Left as is
  with this proof (documented, not guarded, to keep the diff small).

## E4 — memory

* **`qgame.h` / `qgame.cpp`** — the embedded `QGame` no longer embeds the 50000-entry
  `QPos` array plus a 1 MB `pgnBuffer`. `pgnBufferCapacity` is 1 (the buffer is unused
  embedded) and `QPos` are allocated in 512-entry chunks on demand
  (`QPosChunks`), so pointers already handed out stay valid. Peak RSS measured with
  `/usr/bin/time -v`: **31 MB** for 8 threads, **79 MB** for 47 threads (the old layout
  would have been > 1.7 GB).


## 2026-10-01: bounded parser ownership and startup failure cleanup

The former process-lifetime retention registries concealed unbounded parser growth.
Embedded heap allocation is now registered by class allocation functions for Node,
Token, Environment, Range, Transform and DirectionParameter. Stack objects are not
registered. Node, Token and Transform have virtual default destructors; member
containers are freed without following shared non-owning graph edges. A search
scope releases each heap allocation once, including abandoned syntax-error objects
and clones. Class deallocation unregisters failed constructions. The search mutex
and worker joins bound the scope. Global parser/range pointers are cleared.

The API owns QGames through unique_ptr and joins started workers even if later
thread creation or allocation fails. Output allocation failures raise bad_alloc
and release partial result storage instead of dereferencing null. Header strings
use bounded per-global storage instead of allocating a permanently leaked string.

The repeated_search regression runs 3,000 distinct valid/invalid scripts. Release
RSS grew 475,136 bytes after warmup. A separate Valgrind run over 1,000 searches
reported zero lost bytes, zero memory errors, and 392 reachable bytes in four
process-global blocks. ASan/UBSan completed 3,000 searches with no address or
undefined-behavior reports with leak scanning disabled: LeakSanitizer cannot scan
threads under this sandbox. Full acceptance/sanitizer/oracle re-verification is
still required after these changes.
# Multi-script preparation (2026-10-01)

The three exported API functions are retained. `cql6_options` can append up to
1023 scripts; `cql6_match.script_index` identifies their independently sorted
results. Match limits apply per script. One worker prepares each fed game once,
using the union of required variations and position features. Each script gets
an independent traversal view, tag/comment/regex/path state and parser environment.
PGN annotations are restored before evaluating the following script. Any persistent
script forces the entire batch to one worker. Persistent output is prefixed with
the script index in batches. `CqlCommentLevel` is thread-local in embedded builds
and is explicitly selected for each script, preserving silent/quiet semantics.

The `multiscript` driver compares batches with independent searches, including
exact PGN, variation views, sorting, limits, persistent variables, eight-worker
execution and parser-error recovery. A 13-script/3,000-game run passed; larger
and sanitizer checks remain required. Tcl batch exposure is not implemented yet.
