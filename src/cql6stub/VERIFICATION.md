Task 2b verification (2026-09-30)

The prefetch implementation is complete, but acceptance is not fully passing. In particular, the real-database headless benchmark does not meet the required fivefold speedup. See the final measurements below; the minimal fake-database harness must not be confused with the real-database runner.

Changed production files: `src/tcl/tcl_cql6.cpp` and `src/tcl/Makefile`. Updated acceptance entry point: `tests/test_app_cql6.tcl`. The shared new tests, frozen prefetch-task baseline, harnesses, build script and this report are confined to `src/cql6stub/`. The C API header and the owner's checkout were not edited. No installation was performed.

Each job owns a FIFO of unique game snapshots. `PrefetchCapacity` is 2048; the estimated queued allocation budget is 16 MiB. A single oversized game is permitted in an otherwise empty queue so it is not dropped. Retained worker snapshots and allocation reuse are outside the ready-queue byte budget. The initial prefetch is one queued Tcl event. A slice decodes for approximately 2 ms and publishes its batch under the job mutex. Further slices use zero-delay timers below the half-full mark, with a 1 ms polling timer above it. Workers wait only when the FIFO is empty and not finished, and observe cancel, close and interpreter deletion. Progress counts handouts, not prefetched games. Synchronous calls run the same slices on their calling thread while the engine runs separately.

Database lookup, identity checks, export and decoding stay on the interpreter thread. No database pointer or Tcl object is read by an engine worker. Each worker retains its own snapshot until its next callback; expired snapshots can be reused by the producer. Cancel/close clear unconsumed snapshots, interpreter deletion also removes timers/events, and engine completion releases retained snapshots. A job-table engine counter prevents another engine search from starting while a deleted interpreter's engine is still unwinding. A single indivisible decode or allocation can exceed the 2 ms budget; this is not a hard latency guarantee for arbitrary games/storage.

The adapter receives local optimization in the otherwise unoptimized developer build. `-U__OPTIMIZE__` preserves the surrounding libraries' mstl debug/backtrace class layouts. `CQL6_FLAGS` and the stub's `SANITIZE` variable support instrumenting these two components without changing other application sources. The stub's SLOW cost is now a fixed 5 ms per game.

Reproduce the minimal fake-database/real-Tcl tests:

```
make -C src/cql6stub -B harness harness-baseline
make -C src/cql6stub check-harness
```

Reproduce real-database headless tests from the repository root:

```
src/cql6stub/build_real_harness.sh
/tmp/cql6-real/headless-baseline src/cql6stub/real_baseline.tcl
CQL6_BASELINE_RATES="$(cat /tmp/cql6-real-baseline-rates)" \
CQL6_BASELINE_DUMP=/tmp/cql6-real-baseline-dump \
/tmp/cql6-real/headless tests/test_app_cql6.tcl
```

Inspect the Tcl test totals: tcltest's direct source form can return TCL_OK even if cases fail. The verification runs used a cleanup wrapper that raises a Tcl error when its failed-test count is nonzero. New throughput/order cases deliberately error when their measured baseline is not supplied; they do not invent a baseline or silently skip that comparison.

Standalone sanitizer builds use `make -C src/cql6stub -B harness harness-baseline SANITIZE='-fsanitize=address,undefined -fno-omit-frame-pointer'`, and separately `-fsanitize=thread`. Measure the frozen baseline under the SAME sanitizer first (`CQL6_RATES_OUT` chooses its rate-file path), then supply those rates and the baseline DUMP to `harness_tests.tcl`. The Tcl notifier is initialized on the interpreter thread before workers start; this removed an initial Tcl lazy-notifier initialization race report in the baseline harness. No TSan suppressions are used.

Both application executables also linked with the instrumented glue/stub. The real-database runner was built with each configuration using `CQL6_HARNESS_SANITIZE=address,undefined CQL6_HARNESS_DIR=/tmp/cql6-real-asan src/cql6stub/build_real_harness.sh`, and similarly `thread` / `/tmp/cql6-real-tsan`. Other copied application libraries were not instrumented. All 22 original CQL6 cases passed in both sanitized headless runs, with no sanitizer reports. The real runner follows tkscidb's process-lifetime Application ownership instead of introducing an Application teardown that the normal program never performs.

ASan/UBSan final standalone run: all five new cases passed, timer gaps 22/21/22 ms, idle speedups 6.49/7.04/6.87x for 1/4/16 workers; zero address/undefined-behavior reports. TSan final standalone run: all five passed, timer gaps 22/32/22 ms, idle speedups 8.00/6.13/6.03x; zero race reports. Its RSS deltas were +1236 KiB across 200 cancel/close/reopen jobs and +764 KiB across 200 interpreter deletions. ASan's RSS grew with quarantine (+54296 / +75656 KiB); the normal RSS-growth assertion is not applied to its quarantine.

LeakSanitizer was attempted with detect_leaks=1 and failed at exit because its ptrace/thread scan is prohibited here. Subsequent ASan runs used detect_leaks=0. Therefore leak-checker verification is unavailable; zero leak reports is not claimed.

The full GUI app test runner was attempted with xvfb-run. Xvfb cannot bind its display sockets in this sandbox and Tk cannot connect to the display. The complete existing GUI app suite therefore did not run. Headless results do not certify redraw/window responsiveness or the GUI's throughput. Earlier overlapping/longer timer runs also exceeded 40 ms (including 47 and 54 ms); those failures were retained, not hidden by increasing the threshold. Final serial measurements are recorded below.

Final real-database headless acceptance run: 27 cases, 24 passed, 2 failed, 1 skipped (interpreter deletion is exercised separately by the standalone harness). All 22 original cases passed. The three 20000-game SLOW searches lasted about 6.45 seconds each; maximum 20 ms timer gaps were 22/23/22 ms. The 500-game DUMP matched the frozen old adapter byte-for-byte, and 1/4/16-worker runs examined every game exactly once.

| Workers | Round-trip games/s | Prefetch games/s | Gain | Busy-loop round-trip games/s | Busy-loop prefetch games/s |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 11366 | 30789 | 2.71x | 3634 | 18039 |
| 4 | 9943 | 34052 | 3.42x | 3582 | 16547 |
| 16 | 9679 | 34406 | 3.55x | 3509 | 18616 |

The fivefold real-database throughput assertion FAILED; it has not been weakened. The initial pre-change fake-database baseline, measured before implementing prefetch, was 30777/27676/28620 games/s at 1/4/16 workers; subsequent paired reference measurements are also retained in the logs. All later comparisons run the frozen original host against the identical stub/build mode as the new host.

The final 200-job real-database cancel/close/reopen loop delivered the expected results and every finished job became unknown. RSS was 175332 -> 194208 KiB, a +18876 KiB (18.4 MiB) increase. The test's 16 MiB growth limit FAILED. It is not established whether this is a leak or allocator/database caching; no claim of leak-free real application behavior is made. The minimal harness explicitly checked the job table and engine counter, including 200 interpreter deletions, in addition to RSS comparisons.

The normal application build was restored after sanitizer verification. Rebuilding the standalone programs with `-B` is necessary when changing SANITIZE because make does not infer compiler-flag changes from timestamps. The official CQL 6 library remains unavailable; all tests used the requested stub.

The last normal standalone rerun finished 4/5: timer gaps were 50/21/34 ms, so its strict responsiveness assertion FAILED. Its throughput gains were 10.09/9.37/12.01x; the 200-job RSS deltas were +132 KiB and 0 KiB for interpreter deletion. Earlier normal serial runs passed all five, but the final 50 ms gap is retained as an unresolved timing observation.

Raw build/test evidence is preserved in `verification-logs/`, including the failed assertions and the unsuccessful leak scan/full-app startup. This task is not claimed fully accepted: real-database speed, real-process RSS stability, occasional normal timer outliers, full GUI-suite execution and leak-checker verification remain unresolved.
