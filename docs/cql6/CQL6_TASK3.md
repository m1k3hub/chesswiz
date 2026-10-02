# Task 3: harden the embedded CQL 6.2 engine (sanitizers, file lockdown, feed robustness)

Same worktree and rules as Task 1 (`CQL6_TASK1.md`): only touch `src/cql6/`, never the owner's
main checkout, no `sudo`/`make install`/`git push`, commit on branch `cql6-port`. Task 1 (the embeddable
library `libcql6.a` with the C API of `src/cql6/cql6_api.h`, its feed and its tests) is finished and committed;
start by reading its code and `SCIDB-CHANGES.md` and making sure its tests still pass.

Why: this third-party engine (~54k lines, partly old Scid code) will run INSIDE a GUI application, on
scripts a user or an assistant supplies and on game data from any database. It was written as a
standalone program: it reads and writes files named by scripts, uses fixed-size C buffers, many globals,
and its authors note a known race at exit. None of that is acceptable in-process. Everything below is a
gate: the work is not done until all of it passes.

## A. File lockdown (embedded mode, `CQL6_EMBEDDED`)

A script must not be able to touch the filesystem. Find EVERY construct of the language and every code
path that opens, reads, writes, creates, renames or deletes a file or a directory (start with: the
`writefile`, `readfile` and dictionary filters, `writefilenode.cpp`, `dictionary*.cpp`, the input/output
clauses of the `cql(...)` header, `convertto*.cpp`, `gamesortinfo.cpp`, `util.cpp`, `orig/mfile.cpp`,
`orig/namebase.cpp`, `orig/tree.cpp`, `orig/misc.cpp`; grep for `fopen`, `ofstream`, `ifstream`, `open(`,
`remove`, `rename`, `mkdir`, `freopen`, `tmpfile`). Decide for each: unreachable from an embedded search
(then say so in `SCIDB-CHANGES.md`) or disabled. Disabled filters fail at PARSE time with a clear error
("`writefile` is not available when CQL runs inside Scidb") so no partial run happens. `input`/`output` in the
header stay ignored. The standalone program's behaviour is unchanged when `CQL6_EMBEDDED` is not defined.
Tests: one script per construct (write a file under a scratch dir, read `/etc/passwd`, dictionary to a
file, ...): each returns the error, and afterwards the scratch dir is empty and no file was opened (prove it
with `strace -f -e trace=openat,open,creat,unlink,rename,mkdir` on the test driver, filtering the library's
own legitimate opens: there should be none during a search).

## B. Sanitizers as a gate

Add targets `asan` (AddressSanitizer + UndefinedBehaviorSanitizer) and `tsan` (ThreadSanitizer) to
`Makefile.scidb`: they rebuild the library and the test driver instrumented (`-O1 -g -fno-omit-frame-pointer`)
and run the whole acceptance suite of Task 1 plus the new tests below, with `halt_on_error=1`. Then a stress
test `tests/stress.cpp`: at least 20000 games (repeat the test PGN games with changed game numbers), 16 worker
threads, 10 different scripts (incl. `sort`, `flip`, variations on, a `persistent` one that forces one thread,
scripts that fail mid-search), run back to back and also 5 searches one after another in the same process.
Requirements: ZERO sanitizer reports under both ASan/UBSan and TSan. Fix real bugs at their root in the
original code with minimal, `// scidb:`-marked changes (list them in `SCIDB-CHANGES.md` with the report
they fixed). A suppression file is allowed only for a finding in third-party code that is demonstrably a false
positive, each entry with a written justification; blanket suppressions, `no_sanitize` attributes on whole
files and `-fsanitize-recover` to "get it passing" are NOT acceptable. A genuine race that cannot be fixed
cheaply must be reported to the owner in your final message instead of hidden. The race that the
authors mention in `cqlexit.cpp` (`CqlIsExiting`) and every shared static/global (for example
`WriteFileNode::fileMap`, regex/env caches, node-tree statics) must be examined and either made
thread-safe or proven per-thread.

## C. Robustness of the feed

The host data reaches fixed-size Scid structures. Review every place strings and numbers from `cql6_game`
are copied (tag names/values, comments, FEN, squares, promo, kinds, counts) for overflows, unterminated
strings, NULL pointers, negative counts, illegal moves, unbalanced variation records, absurd depth. The feed
must NEVER crash or hang: a game it cannot accept is skipped and counted (add `long nskipped` to
`cql6_result`; append to the API header and docs) and the search goes on; a systemic problem returns an error.
Tests (run under ASan/UBSan): tags of 1 MB; a comment of 500k characters; a tag name with embedded NUL/newline/
quotes/braces/non-UTF-8 bytes; 5000-ply games; variation depth 1000 and 100000 sibling variations; kind 2 with
no open variation; squares -1/64/INT_MAX; illegal and null moves; `ntags`/`nmoves` negative or huge with NULL
arrays; a FEN that is garbage, empty, or has an impossible position; a fuzz loop of 200000 random
`cql6_game` structures (seeded, reproducible) interleaved with valid games: no crash, the valid games still
produce the same matches as when run alone.

## Report

Final message: what you changed, each gate's result with numbers (sanitizer runs: commands and exit
status, stress duration), every original-code change with the finding that motivated it, anything you could
not fix or are unsure of. Do not weaken a test or a sanitizer setting to make it pass.

## D. Strengthen the oracle comparison (do this FIRST)

Task 1's report counts scripts that match nothing on both sides (`stalemate`, `sort_filter`, `QQqq`,
`consecutive_checks`: 0 = 0) as passes; they prove almost nothing. Extend the test PGN to at least 20000
real games (first 20000 games of `/media/michael-g-thomas/sas_mirror/chess/mega_full.pgn`, scratch dir, not
committed) and require at least 20 oracle comparisons (1 and 8 threads, variations off and on) whose match
count is between 1% and 99% of the games, covering: piece counts, king/pawn structure, attacks, `flip`,
`flipcolor`, `shift`, `sort`, `echo`, `line`/`⊢` paths with regular expressions, `if`, `function`,
`persistent` (single thread), `comment`/`message` output with `want_pgn`, and move filters (`move`, captures,
promotions). Any script the oracle matches against a different set is a bug to fix, not a test to drop.
Also compare `first_ply` with the first `{CQL}` comment ply in the oracle's output for every match.

## E. Findings from the owner's review of Task 1 (fix these too; they are gates)

1. **Remove the process-wide stdout/stderr redirect** (`OutputSilencer` in `cql6_api.cpp`: `dup`/`dup2` over
   fd 1 and 2 for the length of a search). In a GUI program other threads write to those descriptors; the
   redirect swallows their output, races with them and leaks descriptors on an exception. The embedded library
   must simply NOT print: find every output site in the compiled sources (`printf`, `fprintf(stdout|stderr)`,
   `puts`, `putchar`, `fputs`, `cout`, `cerr`, `std::cerr`, `perror`, debug printers) and make it, under
   `CQL6_EMBEDDED`, append to a per-search message buffer or vanish (a small header force-included with
   `-include` that redirects the C stdio calls to a thread-safe sink is fine; `cout`/`cerr` uses must be
   reviewed one by one). `messages` in the result carries what a script is meant to print (persistent
   variables, `message` output). Test: a second thread writes to stdout and stderr continuously during a
   search and every byte arrives; the library itself writes nothing.
2. **No `exit`/`abort`/`_Exit`/`quick_exit`/`std::terminate` may remain reachable in an embedded build.** Known
   sites: `cqlexit.cpp` (lines 32-53), `hhdb-options-parse.cpp:29`, `orig/myassert.cpp:34`, `orig/stored.cpp:327`
   and `:339`, `orig/position.cpp:91`, `:1931`, `:2021`, and any others your own grep finds (also `assert`,
   `__builtin_trap`, `raise`). Each is either unreachable from `cql6_search` (prove it in
   `SCIDB-CHANGES.md`) or becomes a `CqlException`. The `position.cpp` ones are reachable with a host-supplied
   game (an illegal move, an impossible FEN): add a test per site that provokes it through the feed and
   shows an error/skip instead of a dead process. Check with `nm` that the final `libcql6.a` still has
   undefined references to `exit`/`abort`/`_exit` only where you proved them unreachable, and list them.
3. **No global side effects on the host process**: the library must not change signal handlers, `errno`-based
   state the host relies on, the locale (`setlocale`), the C++ stream buffers (`std::cout.rdbuf`), umask,
   the current directory, or environment. Grep for `signal(`, `sigaction`, `setlocale`, `chdir`, `setenv`,
   `putenv`, `srand`/`rand` (shared global state: use a private generator if needed), `std::ios::sync_with_stdio`.
   Report each and remove or confine it.
4. **Memory**: every `QGame` holds a 1 MB `pgnBuffer` and a 50000-entry `QPosPool`; with 47 threads this is
   large. Measure peak RSS for 8 and 47 threads and report it; shrink what can be shrunk safely (for example
   the unused `pgnBuffer` in embedded mode).
