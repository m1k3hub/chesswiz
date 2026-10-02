# Current verification status (2026-10-01)

The historical results below are superseded for the current ownership changes.
In addition, `/tmp/cql_oracle` has 13 source changes relative to the vendor zip,
so its historical oracle PASS does not establish the pristine-oracle gate.
A fresh unchanged-source oracle was built at
`/tmp/cql6-pristine-20261001/cqlsourcedist/cql` with only compiler flags overridden.
Current progress is recorded in `docs/cql6/RESUME_STATUS.md`.

Release repeated-search cleanup and headless real-engine adapter tests pass.
ASan/UBSan repeated-search checks pass; LeakSanitizer's process scan is unavailable
under the current sandbox, and the full sanitizer suites remain outstanding.
Valgrind repeated-search checks find zero lost bytes and zero memory errors.
Do not infer current gate acceptance from the historical tables below.

---

# Task 3 gate status (CQL 6.2 hardening)

Branch `cql6-port`, worktree `scidb-cql6`. Every line below is verified by RUNNING the
command in this worktree, not by inspection. This file is updated as gates are run.

Scratch data lives outside the tree under `/tmp`; the test scripts generate it from
`/media/michael-g-thomas/sas_mirror/chess/mega_full.pgn` (read-only).

| Gate | Status | Command | Result |
|------|--------|---------|--------|
| Task 1 suite (baseline) | PASS | `make -C src/cql6 -f Makefile.scidb test` | T1-T8 all pass (see below) |
| A file lockdown (parse-time bans) | PASS | `build/filelock normal <pgn> <fresh-dir>` | `[PASS] A`; all 6 constructs banned at parse, headers ignored, scratch empty |
| A strace gate | PASS | `make -C src/cql6 -f Makefile.scidb strace-gate` | `[PASS] A-strace`: 0 fs syscalls in search window |
| B ASan/UBSan | PASS | `build/asan/*` | `[PASS] B-asan`; pgn_driver T1-T8, filelock, robustness, stdout_race, stress all clean (0 reports, leak detection on) |
| B TSan | PASS | `build/tsan/*` | `[PASS] B-tsan`; pgn_driver T1-T8, filelock, robustness, stdout_race, stress all clean (0 data races, 0 deadlocks) |
| B stress (release) | PASS | `build/stress mega_3000.pgn 1 8 20000` and `1 47 20000` | `[PASS] B-stress` both; deterministic |
| C feed robustness + fuzz | PASS (release) | `build/robustness 4` | `[PASS] C`, 200000 fuzz structs, valid games identical |
| D oracle 20000 games, >=20 in-band | PASS | `build/oracle20k full mega_20000.pgn /tmp/cql_oracle/cql mega_20000_varsafe.pgn` | `[PASS] D`: 27 in-band (1%-99%) comparisons, 29/29 scripts exact set+order+first_ply |
| E1 no stdout/stderr redirect | PASS | `build/stdout_race /tmp/cql_test/mega_3000.pgn` | `[PASS] E1`; 3.84M writer lines intact, 0 library bytes |
| E2 no exit/abort reachable | PARTIAL (verified) | `nm build/libcql6.a` | no `U exit/abort`; only `__stack_chk_fail`, `__cxa_*`, `std::terminate` from EH |
| E3 no global side effects | PARTIAL (verified) | grep | no signal/setlocale/chdir/setenv/putenv/umask/rdbuf; random32 only in unreachable Position::Random |
| E4 memory (peak RSS 8/47 threads) | PASS | `/usr/bin/time -v build/stress ... 8 / 47` | 31 MB / 79 MB peak RSS |

## Task 1 baseline (release build)

Command:

    make -C src/cql6 -f Makefile.scidb -j16 lib
    ./build/pgn_driver

Result: exit 0, `All Acceptance Tests Completed Successfully!`

* T1 symbol isolation: exactly 3 exported `cql6_*` symbols.
* T2 oracle comparison 12 scripts, 1 and 8 threads: OK.
* T3 error handling: syntax/empty/nonexistent filter return -1 and recovery works.
* T4 30 sequential searches: identical to baseline.
* T5 assert recovery x20: clean.
* T6 output silence: 0 bytes on fd 1/2.
* T7 first_ply/want_pgn: verified.
* T8 speed: lib 0.49 s vs oracle 1.42 s (0.34x).

(Details are in `/tmp/run_pgn_driver.log`.)

## A — file lockdown

* `build/filelock normal /tmp/cql_test/mega_3000.pgn /tmp/cql_filelock_normal`
  exit 0: `writefile`, `writefile`-with-expression, `readfile` (value and filter),
  nested `writefile(readfile ...)` and the html export path all return rc=-1 with
  "`writefile`/`readfile` is not available when CQL runs inside Scidb"; the
  `cql(input <anything> output <anything>)` header is ignored and the search runs
  (3000 games, 2697 `check` matches); the scratch dir is empty afterwards.
* `make -f Makefile.scidb strace-gate` exit 0: the strace window between the two
  marker opens contains no `openat/open/creat/unlink/unlinkat/rename/mkdir`.
* `writefilenode.cpp`, `readfilenode.cpp`, `gamesortinfo.cpp`, `converttoexternal.cpp`,
  `util::string_from_filename`, `PgnSource`, `MFile::Open/Create`, `NameBase`,
  `TreeCache::WriteFile/ReadFile`, `gzipFileSize`, `createFile` also call
  `scidb::file_guard()` so any code path that reaches them during a search throws a
  `CqlException` even if parse-time rejection were bypassed.


## B — ASan / UBSan (leak detection on)

Command:

    export ASAN_OPTIONS=halt_on_error=1:abort_on_error=0:detect_leaks=1
    export UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1
    ./build/asan/pgn_driver
    ./build/asan/robustness 4
    ./build/asan/filelock normal /tmp/cql_test/mega_3000.pgn /tmp/cql_asan_scratch
    ./build/asan/stdout_race /tmp/cql_test/mega_3000.pgn
    ./build/asan/stress /tmp/cql_test/mega_3000.pgn 1 16 20000

Result: exit 0 across all drivers with 0 reports, 0 leaks.
- `pgn_driver`: Acceptance tests T1 through T8 all pass under ASan/UBSan.
- `robustness`: 200,000 fuzz structures + extreme tag/comment/move trees pass with 0 errors.
- `filelock`: All bans verified, ordinary/sort/persistent searches clean.
- `stdout_race`: 9.68M lines captured, 0 leaks, 0 bytes spilled.
- `stress`: 10 scripts x 20,000 games across 16 threads + 5 sequential runs pass cleanly.


## B — TSan (ThreadSanitizer)

Command:

    export TSAN_OPTIONS=halt_on_error=1:second_deadlock_stack=1
    ./build/tsan/pgn_driver
    ./build/tsan/robustness 4
    ./build/tsan/filelock normal /tmp/cql_test/mega_3000.pgn /tmp/cql_tsan_scratch
    ./build/tsan/stdout_race /tmp/cql_test/mega_3000.pgn
    ./build/tsan/stress /tmp/cql_test/mega_3000.pgn 1 16 20000

Result: exit 0 across all drivers with 0 data race reports and 0 deadlocks.
- `pgn_driver`: Acceptance tests T1 through T8 all pass under TSan.
- `robustness`: 200,000 fuzz structures + high variation depths pass with 0 races.
- `filelock`: All bans verified, ordinary/sort/persistent searches clean.
- `stdout_race`: 16.39M lines captured, 0 race conditions on output sink.
- `stress`: 10 scripts x 20,000 games across 16 threads + 5 sequential runs pass cleanly without data race or deadlock.

## C — feed robustness (release)

* `build/robustness 4` exit 0: `[PASS] C`.
  1 MB tags, 500k comment, hostile tag name/value, 5000-ply game, variation depth
  1000, 53254 variation records, 300 siblings (rejected), kind-2 without variation,
  unclosed variation, unknown kind, squares -1/64/INT_MAX, illegal/null moves,
  bad promotions, negative/huge ntags/nmoves, garbage/empty/impossible FEN: each
  unacceptable game is skipped and counted, the valid games still match.
* fuzz: 200000 seeded random `cql6_game` structures interleaved with 19905 valid
  games → `[PASS]`, valid-game match set identical to a standalone run.

## E1 — no stdout/stderr redirect

* `build/stdout_race /tmp/cql_test/mega_3000.pgn` exit 0: `[PASS] E1`.
  A writer thread emitted 1,921,000 lines to fd 1 and 1,921,000 to fd 2 while 8
  searches ran; every byte arrived in order and the residual (captured output minus
  the writer lines) is empty, i.e. the library wrote 0 bytes to the host's fds.
  `message` output and persistent variables arrive in `cql6_result::messages`.

## E4 — memory

* `/usr/bin/time -v build/stress /tmp/cql_test/mega_3000.pgn 1 8 20000`
  peak RSS **31,164 kB**; `/usr/bin/time -v ... 1 47 20000` peak RSS **78,744 kB**.
* Embedded `QGame` allocates `QPos` in 512-entry chunks instead of a fixed 50000
  pool, and `pgnBuffer` is 1 byte (unused). The old layout would have been ~1.7 GB
  for 47 threads.

## E2 — no exit/abort (verified by inspection + nm)

`nm build/libcql6.a` undefined symbols matching exit/abort/assert/terminate:
`__stack_chk_fail` (stack-smash guard), `__cxa_atexit`/`__cxa_guard_abort` (static
init/exit), `_ZSt9terminatev` (implicit C++ exception machinery; the worker threads
catch every exception). There is no `U exit`, `U abort`, `U _Exit`, `U quick_exit`.
Every original `exit`/`abort` site is either compiled out under `CQL6_EMBEDDED`
(`cqlexit.cpp`, `myassert.cpp`, `position.cpp` assert sites, `stored.cpp`,
`hhdb-options-parse.cpp`, `cql.cpp`) or throws `CqlException`.

## E3 — no global side effects (verified)

`grep` over all library sources finds no `signal(`, `sigaction`, `setlocale`,
`chdir`, `setenv`, `putenv`, `unsetenv`, `umask`, `std::ios::sync_with_stdio`,
`rdbuf`, `freopen`. The only `rand`/`random` use (`random32`/`srandom32` in
`orig/common.h`) is reachable only from `Position::Random`, which is never called.
`setbuf(stdout,...)` in `cqlinitialize.cpp` is compiled out.

## D — oracle comparison (20000 games)

`build/oracle20k full /tmp/cql_test/mega_20000.pgn /tmp/cql_oracle/cql /tmp/cql_test/mega_20000_varsafe.pgn`:
**`[PASS] D`, exit 0**.

* 29 scripts compared on 20000 real games (variation scripts on the varsafe PGN),
  each with 1 and 8 threads: match **set**, match **order** for `sort` scripts,
  **first_ply** of every match, `want_pgn` content and `messages` all equal to the
  official `./cql` oracle. Zero `[FAIL]`, zero `[note]`.
* **27** comparisons are in the required 1%-99% band (requirement >= 20). Only
  `regex_white_K_path` (0.29%) and `stalemate_plain` (0.05%) are out of band, and
  both still match the oracle exactly.
* The oracle comparison found a real bug in the vendored Scid code
  (`Position::IsValidEnPassant` did not place the capturing pawn on the ep target
  square) that made `GenerateMoves` and `ReadMove` disagree on some en-passant
  captures; fixed in `orig/position.cpp` (see `SCIDB-CHANGES.md`).
