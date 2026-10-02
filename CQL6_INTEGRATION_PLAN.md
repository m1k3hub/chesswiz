# CQL 6.2 in Scidb — integration plan

**Status:** in progress (2026-10-01). Engine and native Tcl glue have been imported
into this working tree from `cql6-port` and the separate glue worktree. The
integrated application builds; committing/merging and installing remain open.
Current validation evidence and live processes are recorded in
`docs/cql6/RESUME_STATUS.md`. Roadmap: `LONG_RANGE_PLAN.md` workstream 10.
**Companions:** `PATTERN_INDEX_PLAN.md` (what this engine is for), `PLAIN_LANGUAGE_SEARCH.md`
(the pattern library and the plain-language front end), `docs/cql6/` (the measurements below).

## 1. Decision

Scidb keeps its own CQL engine (`src/db/cql`, the original parenthesised dialect, `::scidb::cql::*`),
untouched, and gains the **official CQL 6.2** engine beside it (`::scidb::cql6::*`). 6.2 is a different
language (variables, functions, `if`, move-path regular expressions, transformations), so extending the old
engine toward it is not possible; the old one stays for the in-process single-position and per-game calls the
AI features make. The 6.2 engine reads **Scidb's native databases**, never a PGN export (export ran at ~1 MB/s,
20+ minutes per million games).

Licence: the source readme says all files outside `orig/` are "all rights reserved" (Costeff/Stiller) and
`orig/` is GPL-2 (Shane Hudson); the author's FAQ says MIT and the project owner has stated it is MIT. All
notices are kept (`src/cql6/VENDOR-NOTES.md`). Treat the discrepancy as open until the author confirms it in
writing.

## 2. Architecture

```
Tcl  ::scidb::cql6::search  (async, progress, cancel)            src/tcl/tcl_cql6.cpp   [glue]
  |  main thread decodes Scidb games into owned snapshots, 2 ms slices, bounded prefetch queue
  v
C API  cql6_search(script, options, next_game callback, ...)      src/cql6/cql6_api.h
  |  worker threads pull games from the callback (serialised), build a Scid Game from structured data,
  |  run their own parsed script tree, return matches as data (game number, first ply, optional PGN)
  v
libcql6.a   official CQL 6.2 sources + embedding changes          src/cql6/
            (one object, only 3 exported symbols: cql6_search, cql6_free_result, cql6_version)
```

Embedding changes to the original sources are small, marked `// scidb:` and listed in
`src/cql6/SCIDB-CHANGES.md`: errors become exceptions (no `exit`/`abort`), no output on stdout/stderr, a
structured game source instead of PGN parsing, parse-time ban of every file-access construct, per-search
re-initialisation of globals, symbol isolation (`-fvisibility=hidden`, `ld -r`, `objcopy`).

## 3. Measured facts (docs/cql6/)

* **Cost is game preparation, not matching.** One thread, cheap script, 1200 games (callgrind): ~96% of
  instructions go to building each game and its position tree; matching is ~3%. Matching dominates (18-34%)
  only for attack, pin, xray, shift and function/`find all` filters.
* **Removable overhead per script** (P2/P3, results identical): assertions 17-24% (more with a no-op
  `uassert`), eager per-position stalemate/mate/check detection ~21% (constant, whatever the script asks),
  the feed's legal-move generation ~21-24% and SAN strings ~9-11% (a trusted-move feed measured **1.6x** on one
  thread, same matches), early exit only for existence-only scripts (<= 7%, invalid for `sort`).
* **Thread scaling was broken** (P1): a global counter incremented ~79 M times per search made every thread
  fight over one cache line; one search used 20x more CPU at 32 threads than at 1 and gained nothing from
  threads. Fixed (`de2cfaa`): same stress workload, 1 thread 85.7 -> 66.2 s, 8 threads 85.5 -> **12.0 s**,
  16 threads 88.6 -> **8.4 s** (10.6x), CPU flat. Start-up (serial 38 MB `QGame` per thread, ~22 ms each) was
  also fixed by lazy chunked allocation.
* **Feed throughput** (glue, stub engine): the one-event-per-game design capped at ~3.5k games/s and starved
  the Tcl event loop (timer gaps ~100 ms); the prefetch buffer gives ~30k games/s with gaps ~22-36 ms.

## 4. Gates (nothing merges without them)

1. **Oracle**: for >= 20 scripts whose match count is between 1% and 99% of 20,000 real games, 1 and 8
   threads, variations on and off: the set of matching games, their order and `first_ply` equal the **pristine**
   official program's. (Build the oracle from the zip yourself; an oracle built from the modified tree proves
   nothing.)
2. **Sanitizers**: ASan+UBSan and TSan clean (no suppressions) over the acceptance suite, robustness/fuzz,
   file lockdown, stdout race and the 20,000-game stress at 16 threads.
3. **Lockdown**: every file-access construct of the language is rejected at parse time; a `strace` gate sees no
   file operation during a search.
4. **Never exits**: no `exit`/`abort`/`terminate` reachable from `cql6_search`; malformed host data (illegal
   moves, impossible FENs, huge strings, 200,000 fuzzed structures) is skipped or reported, never fatal.
5. **Silence and isolation**: the library writes nothing to stdout/stderr (no redirect of descriptors) and
   changes no process-wide state (signals, locale, stream buffers, cwd, environment).
6. **Glue**: async search keeps the GUI responsive (timer gap < 40 ms during a 20,000-game search), cancel,
   close and reopen during a search are safe, no job or memory leaks.

Status of each gate is recorded in `src/cql6/GATES.md` on the branch and must be re-verified by running, not
by reading it (the delegated agents wrote it).

## 5. Remaining work, in order

1. Re-verify gates 1-5 on the fixed engine (in progress: pristine-oracle run, ASan/UBSan and TSan suites).
2. Review every change to the original sources, especially `orig/position.cpp` (the `exit`/`abort` sites),
   the lockdown guards and the retained-parse-tree handling (the engine keeps parse trees alive; check growth
   over thousands of searches).
3. Performance: **trusted normalised feed** (only when the host has established move legality: skip generation and SAN; cheap
   sanity checks, validating mode for unvalidated sources), **lazy per-position features** (demand-driven by
   the script set), **assertions off in release** after the sanitizer gate, early exit for existence-only
   scripts, algorithmic work on xray/shift/attack/pin/`find all`.
   Native codec decoding alone is insufficient: the 2026-10-01 trusted-path rerun accepted one additional
   Twic game that the validating path rejected. Keep validation enabled for native databases until that
   difference is resolved. Imported native games can also contain explicit null placeholders.
4. Integrate the glue with the real library; **end-to-end test on native databases** (`twic_complete`, 1.17M
   games; `CCRL-4040`; `LumbrasGigabase_OTB`), comparing against the pristine official program on a PGN export
   of a 20,000-game subset; measure throughput of the whole path and profile each stage (Scidb decode, snapshot,
   engine build, matching). The glue tests must be self-contained (they currently depend on baseline files).
5. Multi-script evaluation on one prepared game (the prerequisite of the pattern index, `PATTERN_INDEX_PLAN.md`).
6. UI/entry points: a "CQL 6.2" search mode for power users; the plain-language search and assistant gain the
   engine through the vetted pattern library (no model ever writes CQL).
7. Merge `cql6-port` and the glue into `master`; build integration (`CQL6_LIB`, `-Isrc/cql6`), install.

## 6. Test data and tools

* Databases (copy, never modify): `/media/michael-g-thomas/sas_mirror/chess/{twic_complete,CCRL-4040,LumbrasGigabase_OTB}.{sci,scg,scn}`;
  PGN: `mega_full.pgn`. Load with `::scidb::db::load FILE nop {} -readonly yes` (`::scidb::db::open` is PGN only).
* Oracle: build `cql6-source-9-493.zip` (in `~/src/chess/`) with
  `make cql "CPP_FLAGS=-pthread -O2 -std=c++17 -w -DASSERTIONS -I. -I./orig"` (the original `-Werror` trips a
  modern gcc) after uncommenting the Linux lines in `makefile-flags`.
* Profiling: `valgrind --tool=callgrind --toggle-collect=cql6_search` (perf is blocked: `perf_event_paranoid=4`).
* Isolated instances for GUI tests: `--single-process`, a throwaway `HOME`, Xvfb.

## 7. Risks

* **Third-party code in-process** (~54k lines, old Scid code, many globals): the gates above exist because of
  this; keep sanitizer and fuzz runs in CI. An audit by reading has not been done.
* **Throughput of the feed** is bounded by decoding on the Scidb main thread (the database cursor shares codec
  state); parallel decode needs per-thread decoders.
* **Licence** (section 1).
* **Wrong ownership of long-running jobs**: delegated agents were slow and sometimes wrong; every claim is
  re-verified by running it.
