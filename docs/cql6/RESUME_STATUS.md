# CQL 6.2 completion status — 2026-10-01

The goal remains active. Work was recovered from `cql6-port`, including the
uncommitted native Tcl adapter, and imported into the writable main workspace.
Unrelated existing AI edits remain in place. The separate CQL worktree and Git
metadata became read-only mid-session; committing/merging and system installation
are unavailable under the current permission profile. Code, builds and tests can
continue inside this workspace and `/tmp`.

## Implemented in the writable workspace

- Vendored embedded engine and native Tcl adapter; real library is the default.
- Recursive engine-library build rule, fixing the stale stub-link issue.
- Separate stub-host and real-language adapter tests.
- Search-scoped heap ownership for Node, Token, Environment, Range, Transform and
  DirectionParameter, replacing lifetime retention of parser allocations.
- RAII game ownership and worker joins on partial startup failures; checked result
  allocation and cleanup on errors; bounded storage for header strings.
- Repeated distinct-search memory regression and explicit native database runner.
- Portable sanitizer script working directories and 16-worker/20,000-game stress
  commands. Sanitizer targets now include the repeated-search regression.

## Current evidence

- Release `repeated-search`: 3,000 distinct valid/invalid searches; RSS growth after
  warmup 475,136 bytes.
- Release baseline T1–T8 passed after parser cleanup, before the final RAII API
  change. Its oracle was subsequently found modified; those comparisons are not
  pristine-oracle evidence.
- Valgrind on the final RAII/ownership code: 1,000 searches, zero memory errors;
  zero definitely/indirectly/possibly lost bytes; 392 reachable bytes in 4 blocks.
  No suppressions. Log `/tmp/cql6-current-valgrind-cleanup.log`.
- ASan/UBSan final-code repeated-search: 3,000 searches, exit 0 and no reports
  with `detect_leaks=0`. LeakSanitizer itself fails its thread scan under the
  sandbox (fatal ptrace diagnostic); this is not a clean leak-scan PASS.
- ASan/UBSan robustness/fuzz: 200,000 structures, valid match set identical,
  `[PASS] C` with address/undefined-behavior checks active and leak scan disabled.
- Headless app-backed real-engine tests: 5/5 passed after explicit null-move support, including null followed by a legal move.
- Xvfb app tests: unavailable with current display/socket restrictions. The
  headless tests do not establish full GUI acceptance.
- Existing `/tmp/cql_oracle` differs in 13 source files from the vendor zip.
  A fresh oracle was extracted from `cql6-source-9-493.zip` to
  `/tmp/cql6-pristine-20261001/cqlsourcedist` and built with original source and
  compiler flags overridden only. Full 20,000-game/29-script comparison PASSED: 29 scripts, 27 in band, matching sets/order/first_ply at 1 and 8 workers.
- Native database triplets were copied (2.3 GiB total) to `/tmp/cql6-native-data`.
  Twic 20,000-game check matches/first_ply agree at 1 and 8 workers, variations
  off/on (16,689 matches); timer maxima 24/27/32/23 ms. CCRL then failed: all 2,311,070 supplied games were rejected. A stub snapshot
  showed native null-move placeholders carrying PGN import-error comments. The
  adapter encoded null moves as illegal 0-to-0 ordinary moves. Explicit null move
  support (kind 3, matching official PGN semantics) has been implemented. Release
  repeated-search passed again (3,000 searches, 475,136-byte RSS growth); native
  gates are rerunning after that change. Other native databases
  are still being tested. These metrics do not certify isolated full GUI timing.

## Live sessions and logs (revalidate before relying on them)

- pristine 20k oracle: completed, `/tmp/cql6-current-pristine-oracle.log`.
- native triplet tests after null support: session 16266, `/tmp/cql6-current-native-null.log`.
- TSan build: completed, `/tmp/cql6-current-tsanbuild.log`.
- ASan robustness before null support: completed, `/tmp/cql6-current-asan-robustness.log`.
- release gate drivers: completed, `/tmp/cql6-current-gatedrivers-build.log`.

## Next work — full original scope preserved

Finish and inspect pristine oracle/native runs; run complete sanitizer, lockdown,
stdout-race and 16-thread stress suites against the final source. Re-audit vendor
changes and error paths. Finish trusted-feed/lazy-feature/release-assertion and
algorithmic performance work; add multi-script evaluation on one prepared game.
Compare native 20,000-game subsets against pristine PGN oracle results and profile
decode/snapshot/build/match stages. Finish self-contained glue tests, strict GUI
responsiveness and lifecycle/leak checks. Add CQL 6.2 power-user UI plus vetted
pattern routing for plain-language/assistant search. Finally merge/build/install
and audit every requirement; keep the goal active until all are proved.

TSan repeated-search passed 3,000 searches with no reports and 819,200-byte
RSS growth after warmup, before the null-move addition.

Null-move tests/build artifacts: `/tmp/cql6-current-null-repeat.log`,
`/tmp/cql6-current-null-realtests.log` (5/5). Current strace-gate session 86594
and log `/tmp/cql6-current-strace.log` need inspection. All sanitizer/oracle
gates must be rerun or reviewed against the null-record change.

Strace gate is blocked by sandbox ptrace denial (PTRACE_TRACEME/PTRACE_SEIZE),
not an engine filesystem result. ASan null-support rebuild session 3133,
log `/tmp/cql6-current-asan-null-build.log`. CCRL native rerun now accepts the
20,000-game subset at 1/8 workers and variations off/on: zero check matches
(as expected from stored import-error/null placeholders), timer maxima 22 ms.

Native functional rerun completed: all three copied databases agree on match
identity and first_ply at 1/8 workers with variations off/on. Lumbras has
16,859/16,864 check matches (variations off/on); all reported timer gaps across this run were below 40 ms.
This remains headless evidence, not the required GUI acceptance gate.

ASan null-support rebuild completed. New repeated-search plus 200,000-structure
robustness run is live as session 89881; logs `/tmp/cql6-current-asan-null-repeat.log` and
`/tmp/cql6-current-asan-null-robustness.log`. Revalidate the tool handle next turn.

## Performance continuation

Session 89881 completed successfully: repeated 3,000 searches and 200,000 fuzz
structures passed ASan/UBSan, with the sandbox-incompatible leak scan disabled.

Added explicit `trusted_moves` and `lazy_features` options. The validating path
remains the default. Trusted preparation avoids legal-move generation and eager
SAN when PGN is not requested; scripts demand check/mate/stalemate state through
their parsed descendants. Native Tcl searches enable lazy state but retain move
validation. Also reset pooled QPos `deleteOriginalComment` between games.

`feed_modes` compares all four preparation modes, with variations and annotated
PGN off/on, including matches, order, first_ply, PGN and result metadata. All nine
scripts passed on 3,000 and 20,000 games. Logs `/tmp/cql6-feed-modes.log` and
`/tmp/cql6-feed-modes-20k.log`. Sanitizer build targets now include this driver.

Do not enable trusted mode by default for native databases: on Twic it accepted
one additional game (16,690 check matches versus validating 16,689). Native codec
decoding alone does not prove legality. Restoring validation reproduced all prior
three-database match counts at 1/8 workers, variations off/on:
`/tmp/cql6-perf-validated-native.log`. Concurrent test load produced timer gaps
up to 52 ms; strict GUI responsiveness remains unproved.

Shared PGN test feeders now encode explicit null records instead of ordinary
from==to moves. Makefile dependencies ensure all users rebuild after feeder edits.
The oracle driver accepts host-only `CQL6_TEST_FEED_MODE` (bit 0 trusted,
bit 1 lazy) to test preparation changes against the unchanged pristine oracle.

Live handles (inspect before relying on completion):
- Baseline pristine oracle rerun: 35471, `/tmp/cql6-perf-pristine-oracle.log`.
- Lazy-state pristine oracle after feeder rebuild: 65744,
  `/tmp/cql6-perf-lazy-pristine-oracle.log`.
- Optimized ASan/UBSan feed-mode run: 41283,
  `/tmp/cql6-perf-asan-feed-modes.log` (leak scan disabled).
- ASan performance rebuild 99840 completed; `/tmp/cql6-perf-asan-build.log`.
- Native 82747 and release feed-mode 1449 completed successfully.

Still outstanding: full sanitizer suite and final audit, native PGN/pristine
comparison, stage profiling, multi-script prepare-once semantics, algorithmic
performance, UI/pattern entry points, isolated GUI/lifecycle checks, merge/install.
Git metadata and installation paths remain outside writable roots. Goal active.

## Multi-script continuation

Previous turn was progress (performance options, parity checks and validation
default correction). Baseline pristine oracle 35471 and lazy oracle 65744 both
completed PASS D: 29 scripts, 27 in band. ASan/UBSan preparation-mode run 41283
also completed with no report and exact four-mode parity (leak scan disabled).

Implemented prepare-once multi-script C API through appended options, preserving
three exports. Each script has its own parsed trees/environment, variation view,
annotation/tag/regex/path state, sorting, per-script match limit and comment level.
Any persistent script forces one worker; persistent output includes script index.
Embedded `CqlCommentLevel` is now thread-local and explicitly selected by workers.
QGame restores the union variation mode before preparing each subsequent game.
PGN restoration uses null for absent comments to avoid spurious empty braces.

Release `multiscript` passed 13 scripts / 3,000 games, requested 1/8 workers,
PGN off/on and limits 0/3. Exact output matches separate searches, including
persistent isolation; a nonpersistent eight-worker batch and malformed-script
recovery passed. `/tmp/cql6-multiscript.log`. Single-script repeated search passed
3,000 searches with 65,536-byte RSS growth; four-mode preparation parity also
passed after the API restructuring (`/tmp/cql6-multiscript-repeat.log`,
`/tmp/cql6-multiscript-feed-modes.log`). Sanitizer targets include the batch driver.

Live handles:
- 55647: build and 20k batch parity, `/tmp/cql6-multiscript-20k.log`.
- 98824: ASan rebuild with batch driver, `/tmp/cql6-multiscript-asan-build.log`.

The final small `cql6_version` change uses an immutable function-local string
to avoid concurrent assignments. Rebuild before final validation; the active
builds may have compiled its earlier equivalent single-threaded implementation.

Next: inspect the two live handles, run batch sanitizer checks; expose additional
scripts in native Tcl with owned string storage. The decoder must honor the
parsed scripts' union variation requirement (current adapter only uses the
explicit `-variations` option). Resolve this before claiming native batch support.
One option is a host preparation callback invoked after parsing, before feeding,
to publish the required variation mode safely to the prefetcher. Stub harness
must implement the same callback if introduced. Original UI, native PGN oracle,
profiling, full gates and merge/install scope all remain outstanding.

Native Tcl batch exposure is now implemented: `-scripts LIST` owns all script
strings for the job lifetime, and batch matches include `script` identity.
The C options' optional `prepare_feed` callback publishes parsed union variation
requirements before feeding. Native prefetch waits for this publication under
the job mutex; synchronous searches wait on the same condition. Stub engine
also calls this callback. No engine worker uses Tcl objects or Tcl evaluation.
Documented in `docs/cql6/NATIVE_API.md`.

New app-backed runner `/tmp/cql6-batch-native/runner` built successfully and real
tests passed 7/7: prior single-script tests, batch limit/identity/feed count, and
mixed mainline/variation header views on a legal mate variation. Log
`/tmp/cql6-batch-realtests.log`. The fixture now includes that variation.

20k batch session 55647 remains live; last output verified PGN parity for 13
scripts / 19,983 accepted games (17 skipped corrupt feeds). The test's persistent
expectation was corrected to count accepted games, not raw dataset size.
ASan rebuild session 98824 completed. Updated ASan rebuild plus batch test is
running as 10472, logs `/tmp/cql6-batch-final-asan-build.log` and
`/tmp/cql6-batch-asan.log`; leak scan remains disabled under ptrace restrictions.
Revalidate these handles before restarting or claiming completion. UI and all
other original outstanding requirements remain active.

## Power-user UI continuation

20k batch handle 55647 completed PASS, including exact PGN at requested 1/8
workers, limits 0/3, 13 scripts, 19,983 accepted and 17 rejected games.
ASan batch handle 10472 also completed PASS with no address/UB reports (leak
scan disabled). Their logs remain `/tmp/cql6-multiscript-20k.log` and
`/tmp/cql6-batch-asan.log`.

Added `tcl/app-database-search-cql6.tcl`, included in the Tcl build, with a
database-menu entry, script editor, worker/variation controls, async search,
progress/cancellation, script output and match list opening native game indices.
Result insertion yields every 100 rows; closing cancels jobs and scheduled
callbacks. Dialog epochs discard completion from a closed/reopened instance.
Headless callback checks passed 2/2 (`tests/test_cql6_ui_callbacks.tcl`), proving
sliced insertion and stale-result rejection only. Actual GUI acceptance is still
unproved with the display restrictions. No model-facing CQL route was added yet.

Current live handles:
- 49965: TSan rebuild, `/tmp/cql6-batch-tsan-build.log`.
- 2297: full ASan/UBSan suite, `/tmp/cql6-batch-asan-suite.log`; leak scan disabled,
  pristine oracle path supplied to Makefile. Inspect driver-specific oracle
  behavior before relying on its comparisons.

Original remaining requirements are unchanged: vetted-pattern NL/assistant
routing, native PGN/pristine comparisons, stage profiling, algorithmic/early-exit
work and release assertions decision, complete final gates, GUI/lifecycle/leaks,
merge/build/install. Git and system installation writes remain unavailable.

The Tcl script bundle build completed successfully (`/tmp/cql6-ui-script-build.log`).
Added native `-view N` support: snapshot selected game indices, decode only those
candidates, retain original database indices. Reject invalid/unused game views.
New self-contained filtered/empty-view test passed alongside the previous seven
tests (8/8), `/tmp/cql6-view-realtests.log`. This is the metadata-narrowing
prerequisite for vetted pattern routing; model-facing routing still needs wiring.
View update-mode order follows the actual table enum (`unused unused unused unused
master slave`), rather than the misleading command usage order.

Latest app runner rebuild/test is session 81350, log `/tmp/cql6-view-native-build.log`; tests
`/tmp/cql6-view-realtests.log`. Sanitizer handles 2297 and 49965 remain live and
must be inspected before restarting. No goal-completion claim is made.

## Vetted-pattern continuation

Latest native runner build/test 81350 completed 8/8. TSan rebuild 49965 completed.
Introduced 12 application-owned `Patterns6` templates keyed by the existing vetted
ids; no model text becomes CQL. New fixtures compare every template with legacy
semantics and require positive coverage for each (added isolated d-pawn, opposite
bishops and queenless examples). Corrected the old rook fixture's illegal Ra8+
while in check by using a legal starting position. `tests/test_app_cql6patterns.tcl`
passed both all-template parity and actual metadata-prefilter/native-view routing.
Log `/tmp/cql6-patterns-route-test.log`.

Added `::scidb::view::setGames` with index validation and view-list notification
through Application::setGameFilter. Assistant SearchView builds metadata-only
queries, runs the trusted application template against `-view`, and applies match
indices. PlainRun and DoSearchGames use it; DoShowSearch saves/reuses validated
criteria so it also follows the native route. Variant/stub paths retain legacy
matching. The new route currently executes synchronously: async plain-language
responsiveness remains required and must not be claimed complete.

Native build `/tmp/cql6-pattern-native/runner` succeeded (24656); route tests
passed. Tcl bundle rebuild is live as 75913, `/tmp/cql6-pattern-script-build.log`.
Full TSan suite is live as 58430, `/tmp/cql6-batch-tsan-suite.log`.
ASan suite 2297 remains live (`/tmp/cql6-batch-asan-suite.log`), with leak scan
disabled due sandbox ptrace limitations. Inspect every live handle before retry.

Original remaining scope still includes native PGN/pristine comparison,
profiling and algorithmic work, early-exit/release assertions decision, full
sanitizer/lockdown/isolation/GUI/lifecycle/leak gates, merge/build/install.

## Async pattern and native oracle-input continuation

SearchView now supports native asynchronous jobs and guarded completion callbacks.
Plain-language Search returns immediately, disables competing actions, cancels its
job on dialog destruction and uses dialog epochs to discard stale results before
changing the view. Assistant tools retain return values through a Tcl event wait
that services GUI/native prefetch events. Cancelled searches do not apply partial
match lists. Pattern tests passed 5/5: all 12 templates with positive fixtures,
metadata routing, async return/delivery, guarded stale completion and cancellation.
`/tmp/cql6-patterns-async-test.log`. The NL dialog test now waits for async completion.

Acceptance driver now accepts its oracle path as argv[1] and flushes gate progress;
ASan/TSan make targets pass ORACLE_BIN to it. Current suite processes started with
the earlier driver and therefore do not prove pristine T1-T8 oracle attribution;
the separate full pristine oracle gate is still the authoritative comparison.

ASan 2297 has progressed through the batch, feed modes, repeated-search, T1-T8,
robustness and file-lockdown commands and is currently at stdout-race. Inspect
actual PASS output before attributing full gate completion. TSan 58430 remains
live in batch parity with its first two cases printed. Their test processes are
in separate sandbox PID namespaces, so ps from another exec cannot observe them;
use the verified tool handles. Tcl async bundle rebuild 64098 needs inspection.

Added `tests/cql6_export_native_subsets.tcl`: exports first 20,000 native indices
from each copied triplet with comments/variations/setup tags, preserves explicit
null moves, and writes export-row to native-index mappings. Export is live as
49981, `/tmp/cql6-native-subset-export.log`, outputs `/tmp/cql6-native-oracle-inputs`.
Next use those inputs and mappings for direct native/pristine comparisons.
All original unfinished requirements remain active, including profiling,
performance decisions, final gate breadth, actual GUI checks and merge/install.

## Direct native/pristine comparison

All three exports completed (49981): 20,000 games each, copied databases only,
explicit nulls retained. Native seven-script batches at 1/8 workers, variations
off/on completed (46706). Pristine oracle TSV generation completed (25690).
Artifacts `/tmp/cql6-native-oracle-inputs` and `/tmp/cql6-native-oracle-results`;
logs `/tmp/cql6-native-oracle-generate.log`, `/tmp/cql6-native-oracle-results.log`.
`tests/cql6_compare_native_oracle.py` maps oracle game numbers to native indices
and compares ordered results including first_ply. It found 12 failed comparisons
out of 84 (`/tmp/cql6-native-oracle-compare.log`), affecting two stored games:

- Twic native index 1005: illegal 17...O-O-O passes through d8, attacked by
  White's Qd3. Native validating feed rejects the whole game; pristine PGN parser
  truncates at the legal prefix (33 plies). Thus `initial` and `terminal` differ
  at both worker counts and both variation settings. Check/mate and other tested
  scripts match. This explains the earlier trusted-feed extra match: blindly
  accepting the illegal castle produced later positions the oracle never sees.
- CCRL index 13562: terminal matches agree, but native first_ply=1 versus
  oracle -1. The original long import-error comment can suppress CQL annotation
  (`MarkBoard::gameAppendComment` limit 4500). Native first_ply is currently
  inferred from pending comment entries before emission, so it can overclaim.
- Lumbras: all seven scripts/1 and 8 workers/variations on and off agree exactly.

Do not report native gate completion yet. Resolve native imported-illegal-prefix
semantics without weakening generic C API rejection of malformed host games;
derive first_ply from actual annotation emission semantics, including long and
removed comments. Avoid treating a safer subset as full native parity.

Oracle helper now records process exit status; full oracle gate rejects failures
instead of treating empty outputs as valid. New host-only `native_oracle` driver
also rejects failed pristine runs. Shared feeder dependency forces rebuilt tests.
Existing live sanitizer binaries predate this status check; do not overattribute.
ASan 2297 currently running pristine full oracle after stdout isolation passed;
TSan 58430 still running batch parity. Inspect those handles before any restart.

## Native parity fixes and long-comment regression

Added explicit `truncate_illegal_moves` compatibility mode and `ntruncated`
reporting. Generic feeds continue to reject illegal games by default; the native
adapter retains and reports the legal prefix, matching upstream PGN ingestion.
First-ply reporting now uses the same annotation construction and size limits as
PGN emission, including removecomment behavior. The UI labels -1 as "not annotated".

The clean release rebuild completed, but its new annotation regression exposed
an upstream stack overflow: TextBuffer::PrintString copied an arbitrarily long
word into a 1024-byte array. Replaced it with std::string storage. Release tests
now pass all comment boundaries 0/4490/4496/4497/4500/4800/5000 with PGN and
removecomment off/on, and explicit legal-prefix/default-rejection behavior.
Logs `/tmp/cql6-annotation-limits.log`, `/tmp/cql6-legal-prefix.log`.
Repeated 3000 searches again report 65536 bytes RSS growth after warmup
(`/tmp/cql6-parity-repeat.log`). Multi-script parity rerun is live as 46899.

App-backed final-source runner rebuilt at `/tmp/cql6-parity-native/runner`.
Native seven-script/three-database/1-and-8-worker/variation comparisons against
cached pristine oracle results are live as 75158, log
`/tmp/cql6-native-parity-fixed.log`; comparison will write
`/tmp/cql6-native-parity-fixed-compare.log`. Native tests are live as 91312,
`/tmp/cql6-native-fixed-tests.log`. These have not yet passed; the observed
45 ms timer gap already prevents claiming the strict 40 ms gate.

Focused final-source ASan/UBSan build and annotation/prefix tests are live as
40498, isolated in `/tmp/cql6-final-asan` so old suites 2297 and 58430 are not
disturbed. Leak detection disabled only for the known ptrace limitation; no
full sanitizer or leak gate claim. All outstanding plan items remain active.

Native comparison 75158 completed successfully: all 84 ordered match/first-ply
comparisons equal pristine CQL (seven scripts, three 20k native subsets, 1/8
workers, variations off/on). Both previously discrepant games are resolved.
`/tmp/cql6-native-parity-fixed-compare.log` contains 84 PASS and no FAIL.
Release multi-script regression 46899 passed, including exact annotated PGN,
script independence, limits/sort/persistents, and feed-once behavior.
Native test 91312 also completed successfully, but its measured 45 ms gap
still fails the separate strict responsiveness gate.

Old-source ASan/UBSan suite 2297 completed exit 0: acceptance, robustness,
lockdown, stdout race, full pristine oracle and 20k/16-worker stress all pass.
It predates the fixes above, so full final-source suite is restarted as 57038,
`/tmp/cql6-final-asan-suite.log`, with the pristine executable explicitly passed
to acceptance tests too. No suppressions; leak scanning remains unavailable.
TSan 58430 remains old-source/live; inspect before rebuilding its tree.

Focused final-source ASan/UBSan 40498 completed exit 0, annotations and legal
prefix tests both PASS (`/tmp/cql6-final-asan-{annotations,prefix}.log`). Full
final-source suite 57038 now running multi-script regression after these tests
passed. Old TSan 58430 still verified live in acceptance driver.
Final native runner also passed UI callback tests (2/2 via tclsh) and vetted
pattern tests (5/5 via runner, `/tmp/cql6-final-pattern-tests.log`).

Added bounded native profiling workload `tests/cql6_profile_native.tcl` with
database/game-count/script/variation environment settings. Smoke workload
examines exactly 1200 selected Twic games: 992 matches, 505 ms.
`tests/build_cql6_native_runner.py --cql-library` now supports linking an isolated
profiling archive; `Makefile.scidb STRIP=true` preserves internal symbols while
retaining release symbol isolation. Debug optimized profiling archive and
app-backed runner build live as 43274 (`/tmp/cql6-profile-build.log`,
`/tmp/cql6-profile-native-build.log`). Next run callgrind toggles for
`cql6_search` and `*requestGame*` to include worker engine and main-thread
decode/snapshot costs, and report nested costs without double counting.

Profiling build 43274 completed; nm confirms local requestGame, QPos::visitRoot
and CqlNode::match_game symbols in `/tmp/cql6-profile-native/runner`.
Callgrind workload is now verified live as 67963, log
`/tmp/cql6-native-check-profile.log`, output
`/tmp/cql6-native-check.callgrind`, followed by automatic inclusive annotation
to `/tmp/cql6-native-check-profile.txt`. Database opening is still instrumented
but collection disabled until the scoped functions; no stage results yet.
Valgrind emits a brk-segment growth warning, which has not terminated the run.
Reproduction and overlapping-cost interpretation documented in
`docs/cql6/NATIVE_PROFILING.md`. Plan status now reflects imported working-tree
integration rather than claiming code exists only in the original worktrees.

Callgrind 67963 completed exit 0; collection scope verified (requestGame and
cql6_search present). Results recorded in NATIVE_PROFILING.md: native pipeline
72.37%, engine 27.63% of 4.125B instructions; native isValidMove 63.00% (nested),
engine populate 15.86%, tree construction 9.74%, matching 1.18%. Main bottleneck
is Consumer::putMove M_REQUIRE(board().isValidMove), whose board checks generate
legal moves repeatedly. Investigate assertion handling while preserving mstl
ABI and malformed-data semantics; do not simply enable unsafe trusted feeds.
Full ASan 57038 and old TSan 58430 still verified live at the last poll.

## Native move-validation optimization

Added a normal-chess fast path in Board::isValidMove: prove a non-null move
fully legal first, which proves at least one legal move exists without generating
the entire move set for checkState. Original checkMove contract remains unchanged;
null, other variants and permissive illegal candidates retain terminal checks.
Assertions remain enabled, native engine feed still validates independently.
Added `tests/cql6_board_validation.cpp`, compiled via runner builder's new
`--harness` option: 81364 comparisons against the original validator expressed
using unchanged checkMove, including mate/stalemate, pinned/check positions,
null/illegal moves, castling, en passant and promotions. PASS.

New app runner `/tmp/cql6-board-native/runner` built successfully. All 84 native
pristine comparisons passed again (56855 terminal exit 0;
`/tmp/cql6-board-native-compare.log`). Native glue tests 8/8 PASS,
`/tmp/cql6-board-real-tests.log`. Release smoke workload still 992 matches,
1200 games, 212 ms versus earlier 505 ms (single samples, not a broad benchmark).

Updated Callgrind run live as 82341, outputs
`/tmp/cql6-native-check-fast.callgrind`, log
`/tmp/cql6-native-check-fast-profile.log`, then inclusive no-auto-annotation
report `/tmp/cql6-native-check-fast-functions.txt`. Full 20k native timing rerun
started; inspect current session and `/tmp/cql6-board-native-timing.log`.
Final ASan engine suite 57038 remains live, progressing through feed modes;
old TSan 58430 passed acceptance and 200k fuzz, now in file lockdown.

Updated Callgrind 82341 completed exit 0: instructions fell 50.10% from 4.125B
to 2.058B. Native slice cost 2.985B -> 0.918B; engine unchanged at 1.140B.
Profiling guide updated with evidence. Full native timing remains live as
24415; early 20k Twic cases about 3.3 sec with timer gaps 22-24 ms.

Native timing 24415 completed exit 0: all twelve database/worker/variation cases
show timer gaps 22-26 ms (formerly up to 45 ms). Twic 3.12-3.32 sec,
CCRL 0.90-1.07 sec, Lumbras 3.36-3.82 sec. Results match across workers.
`/tmp/cql6-board-native-timing.log`; gamenumber-limited feed examines slightly
more than 20k due to worker stop boundaries, as already documented. This proves
the headless event-loop measurement, not the actual Tk GUI/lifecycle gate.
ASan 57038 now in acceptance comparisons; old TSan 58430 in stdout race after
file lockdown PASS. Do not rebuild either live suite's tree.

## Final gates and GUI acceptance (Claude, 2026-10-01 evening)

Run outside the Codex sandbox, so ptrace-based tools worked:
- LeakSanitizer on (`detect_leaks=1`): repeated-search (3,000), multiscript, robustness/fuzz all exit 0.
- strace lockdown gate: `[PASS] A-strace`, no file syscalls during searches.
- Final-source ASan/UBSan suite and TSan suite: every gate PASS, no reports
  (`/tmp/cql6-final-asan-suite.log`, `/tmp/cql6-claude-final-tsan.log`).
- Stub glue harness 5/5 in release, ASan/UBSan and TSan. Its frozen DUMP baseline
  predates the `truncated` key, so the comparison now ignores that key.
- App suite under Xvfb with the real engine: 553/553. C++ backend tests pass.

Live GUI test (isolated HOME, Xvfb, driven by Tk `send`) on the 1.17M-game Twic copy:
981,748 `check` matches in about 180 s. Measured and fixed GUI stalls, all of
which scaled with result size: per-match Tcl dictionaries (about 80 ms per
million objects to create and again to free), `namespace code` turning the big
result into a string (327 ms), and a million-row ttk::treeview (1 s to clear,
40 ms per redraw). The glue gained `-compact` and `-paged` plus
`::scidb::cql6::matches` and `::scidb::cql6::release` (see NATIVE_API.md). The
dialog shows a virtual list: the treeview holds only the visible rows. Search,
cancel, script error, scroll/End/wheel, open game, re-run and close mid-search
all verified.

Residual: occasional 40–120 ms timer gaps during GUI searches that do not
reproduce run to run. The headless full search, timed inside the glue slices,
shows none over 30 ms, so they come from the GUI/X/OS layer rather than CQL.
The assistant pattern route uses `-compact`.
