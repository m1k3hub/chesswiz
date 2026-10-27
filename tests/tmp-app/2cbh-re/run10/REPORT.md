# Run 10 report — 2026-10-27

**Status: partial; live reverse engineering, GUI validation and commits are blocked.**

## Delivered

- Read BRIEF.md including its handover, format-design §19, and required Jev
  guidance. Used the cached help, without fetching it again or scanning big
  fixtures. HELP-NOTES.md records attributes, setter paths, URLs, storage
  hypotheses and distinctions that the help does not settle.
- The important missed medal path is notation right-click > Special annotation
  > Set Medal, or the quotation-mark key. List `+` sets User medal. This is
  help evidence, not a newly measured medal mapping.
- Added database Export > ChessBase 2CBH (Save as), routed through
  app::View::exportGames to cb2::writeDatabase. The codec remains read-only;
  use Save as instead of appending into an open database.
- Added cb2::encodeGame: basic tags, ratings, source, annotator, teams, the
  existing medal flags, setup/Chess960 positions, and legal move trees with
  nested variations. Encoding leaves the editor position unchanged. The
  reverse document order of subtree storage is covered by tests.
- Unsupported annotations (comments, NAGs, marks, move information) and
  database text are refused before any destination file is written. The
  current low-level writer has no annotation encoder. Other optional tags
  remain limited to the existing writer's coverage. No silent annotation
  stripping or app-level lossy append was added.
- Added tests/test_app_2cbh_export.tcl with three synthetic games, UTF-8,
  nested variations, teams, a setup, codec decode/reopen, append refusal and
  all-games preflight when a later game has a comment. Added backend adapter
  tests and incremental-build dependencies. Corrected the writer header's
  obsolete claim that annotators live at +0x93c.
- Updated format-design §17/§19 and docs/CHANGELOG.md. All changed source,
  test, documentation and Makefiles have mode 644.

## Validation

- `make -C tests 2cbh`: **PASS: 3996 checks** (test-2cbh.log).
- `make -C tests 2cbh-elo`: **PASS: 1156/1156 Elo values**, 578 games
  (test-elo.log).
- `make -C src -j2 tkchesswiz`: **PASS**, application shell linked
  (build-shell.log). The app library also built (build-app.log).
- `git diff --check`: pass. Tcl script completeness checks pass for export.tcl
  and test_app_2cbh_export.tcl; these do not substitute for runtime tests.
- Attempted `PULSE_SINK=cwtests timeout 45 xvfb-run -a src/tkchesswiz
  tests/run_app_tests.tcl -file test_app_2cbh_export.tcl`: **blocked** at Tk
  startup, `couldn't connect to display ":646"` (test-app.log). Test bodies
  did not run and are not claimed to pass.
- The first new backend test failed because a freshly constructed Game's edit
  key needed moveToMainlineStart() before adding moves. Fixed the fixture;
  the final run above passes. No production preconditions were weakened.

## Execution blockers and remaining work

1. Ghidra: `curl --max-time 5 http://127.0.0.1:8089/` fails with `failed to
   open socket: Operation not permitted`. X: `DISPLAY=:901 xdpyinfo` fails
   despite the X901 socket being present. This session forbids socket use.
   No CBase26 setters, database probes, new screenshots or reopen checks
   could be performed. The prior attempt's shots/ files are not new evidence.
   The inherited run10/dbs/ directory contains no files.
2. The unknown +0x93c namebase, game titles +0x50/+0xe76, genuine medal bit
   assignment/copies, unmapped flags and tail timestamps remain open. No
   guessed field mapping was added. Retry the documented UI paths with small
   2–3 game probes when Wine/Ghidra are accessible; use bounded reads.
3. Re-run the Tcl app suite above with X access, then open and reopen its
   exported database in CBase26 and check for integrity warnings. Existing
   run-8 writer validation does not establish this new app route's acceptance.
4. Git cannot create
   `.git/worktrees/wt-2cbh-re/index.lock`: **Read-only file system**.
   `git add` and the requested first small commit both failed; no commits
   were created. Source edits remain in this worktree on re/2cbh-next.
   HELP-NOTES.md and this report are under the ignored scratch tree and
   require explicit staging when Git writes are available. No proprietary
   databases, cached help pages, images from help, or decompiler output were
   staged or committed. The pre-existing untracked src/db/test_2cbh binary
   was retained.
5. Graph discovery was attempted first, but its MCP tool returned “requires
   approval” under an approval-never policy. Local searches were used after
   that failure. No model was used for parsing, legal move decisions or
   format checks. Jev is unnecessary for these deterministic operations;
   no local or cloud Jev backend was started or called.

Suggested commit separation once Git is writable: cached-help map; Save as
implementation and tests; format/changelog/report update. The work is not
fully complete until the blocked live probes and acceptance checks are done.

RUN10-DONE


## Second pass — live acceptance

- X :901 and Ghidra HTTP are available. All three app Tcl export tests pass.
- Preserved the app test's three-game Export output in ignored dbs/app-export.
  CBase26 opened and reopened it with no integrity page; all four binary
  files retain their SHA-256 values. Screenshots: shots/app-first-clean.png,
  shots/app-reopened.png. No writer fix was needed for this acceptance check.
- Live field probes and append feasibility are in progress.
