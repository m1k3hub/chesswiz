# Fix report 3 — `cmdline`

Implementation revision: `f2d69e80e` (base `c8ed1a979`). Six separate finding commits are listed below. File:line citations in the finding table refer to the specified commit, rather than to later line numbers after additional tests were inserted.

## Findings and before/after evidence

| Finding | Fix commit and implementation | Test | Before → after |
|---|---|---|---|
| **R2F-01 / F-05**, internal adapters in the palette | `7f881d956`, `tcl/command-actions.tcl:42` sets a false visibility expression; `tcl/app-ask.tcl:520` also excludes `command.*` when merging palette rows. A literal `return 0` is unsuitable here because the registry catches its Tcl return status. | `7f881d956`, `tests/test_app_command_fixes.tcl:433`, `R2F-01-hidden-adapters`: real `Typed`/`Suggest` and registry labels, including the eight reported phrases. | All 25 adapters leaked → none leaked; incomplete grammar commands still carry missing slots. Full fixes suite at this commit: **31 passed / 1 failed → 32 passed / 0 failed**. Logs: `fix3_R2F-01_before.log`, `fix3_R2F-01_after.log`. |
| **R2F-02 / F-04**, ECO correctness and latency | `16c5d1516`, `tcl/command-line.tcl:16` folds accents; `:65` precomputes disjoint family ranges, splitting gaps and volume boundaries; `:122` retrieves them; `:140` identifies canonical London/Sveshnikov hierarchies; `:156` ranks without the A-volume penalty. | `16c5d1516`, `tests/test_app_command_fixes.tcl:150` and `:167`: real suggestions, London Enter/search, and per-keystroke timing. `tests/test_app_command_acceptance.tcl:379` retains p95 < 10 ms and adds max < 25 ms. | Both new tests failed before: wrong names, cross-volume ranges, **3381.318 ms** worst keystroke. Both pass after; focused run worst **9.015 ms**. Expected first ranges: Sicilian B20–B99, Najdorf B90–B99, King's Indian E60–E99, English A10–A39, Dutch A80–A99, Réti A04–A09, London D02, Sveshnikov B33. Logs: `fix3_R2F-02_before.log`, `fix3_R2F-02_after.log`. |
| **R2F-03 / F-07**, running AI engine ignores thread changes | `2dfcd6995`, `tcl/ai-engine.tcl:215` compares saved threads when reusing the live process, sends the changed UCI option and waits for `readyok`; `:259` records the initial applied value. Changes during a search take effect before the next search, without interrupting the current request. | `2dfcd6995`, `tests/test_app_command_fixes.tcl:377`, `R2F-03-running-engine-threads`: real Stockfish, real `best move` / `set Stockfish threads` Enter, a UCI execution trace (no replacement), direct executable and named profile, idle and in-flight changes. Cleanup shuts down the engine. | Four observed update checks **0 0 0 0 → 1 1 1 1**. Logs: `fix3_R2F-03_before.log`, `fix3_R2F-03_after.log`. This tests best-move execution; the shared `ensure` implementation also serves other callers, but this test does not claim to execute every annotation/review workflow. |
| **R2F-04 / F-10 / RF-01**, draw completion cannot be parsed | `6952fb979`, `tcl/command-line.tcl:552` serializes normalized `1/2-1/2` as the grammar word `draw` during completion. Execution arguments retain normal result validation. | `6952fb979`, `tests/test_app_command_fixes.tcl:312` drives incomplete Enter; `:329`, `R2F-04-draw-completion`, fills event/from, presses Enter again, and checks real `search_games` arguments and filtered game counts. | Before: no runnable suggestion for `find games result 1/2-1/2 event Biel`. After: both completed queries execute, retain result `1/2-1/2`, and show the one drawn fixture game. Logs: `fix3_R2F-04_before.log`, `fix3_R2F-04_after.log`. |
| **R2F-05 / F-05**, misleading palette-alias error | `5dfcf2b21`, `tcl/app-ask.tcl:1855` accepts grammar rows as alias targets and excludes palette rows. Palette aliases are not introduced; Save uses the existing “Select a complete command in Ask first” prompt. | `5dfcf2b21`, `tests/test_app_command_fixes.tcl:561`, `R2F-05-palette-alias`: real Assistant Preferences palette row, actual Aliases dialog and Save button. | Wrong prompt check **0 → 1**; no alias is saved in either case. Logs: `fix3_R2F-05_before.log`, `fix3_R2F-05_after.log`. |
| **R2F-06 / F-09**, overstated coverage and stubbed database opening | `f2d69e80e`, `tests/test_app_command_e2e.tcl:24` makes `open_database` real; `:194` requires the fixture to be closed before Enter. Setup no longer pre-opens that fixture; the dead source fixture is removed. `tcl/dialogs/fileselectionbox.tcl:1015` initializes geometry before reading it, fixing the first-use error exposed by the real picker test. | `f2d69e80e`, `tests/test_app_command_e2e.tcl:194`, `command-e2e-1`; `tests/test_app_command_fixes.tcl:914`, real picker return shape and actual opening; `:936`, both formats through the real converter and real save dialog; `:952`, incomplete playerless wins through Enter, then completed real search. | With the strengthened closed-fixture precondition, stubbed opening failed (**1 1 0**); unstubbed opening passes, and the full e2e suite passes **51/51**. Real-picker test separately failed on missing `Priv(geometry:FileDialog)` before the geometry fix and passes without that background error afterward. Conversion and wins tests are added coverage, not claims of newly reproduced functional failures. Logs: `fix3_R2F-06_before.log`, `fix3_R2F-06_after.log`, `fix3_R2F-06_picker_before.log`, `fix3_R2F-06_paths.log`. |

The final fixes suite has **40 tests**, including nine added in this round (`f2d69e80e`, `tests/test_app_command_fixes.tcl:150`, `:167`, `:329`, `:407`, `:540`, `:561`, `:914`, `:936`, `:952`). Final serial counts below are authoritative.

## Corrections to the previous report

- **Opening and end-to-end coverage:** the old claim that every command verified real state was too broad. The new opening check genuinely opens an initially closed local file (`f2d69e80e`, `tests/test_app_command_e2e.tcl:24`, `:194`). Heavy/network/modal terminal operations still have explicit stubs (`f2d69e80e`, `tests/test_app_command_e2e.tcl:170`); their assertions verify dispatch, not completed external effects (`:43`). No claim of complete real execution of all 51 workflows is made.
- **Playerless wins:** the old test only inspected Match. The new test presses Enter on the incomplete command, asserts no dispatch, supplies the missing player and executes the real search (`f2d69e80e`, `tests/test_app_command_fixes.tcl:952`).
- **CBH conversion:** the old CBH check was matcher-only. The added test now reaches the real converter for both `sci` and `cbh`, inspects each real save dialog's file types and cancels it (`f2d69e80e`, `tests/test_app_command_fixes.tcl:936`). It does **not** claim a completed CBH conversion or support for converting PGN into CBH.
- **Voice:** the prior reference to voice coverage in `test_app_command_fixes.tcl` was incorrect. Existing voice tests are in `24dbdabb9`, `tests/test_app_command_ui.tcl:47` and `:56`; this round does not add voice behavior.
- **Latency:** the earlier p95 did not establish a maximum. The maximum now has its own assertion (`16c5d1516`, `tests/test_app_command_acceptance.tcl:379`) and is included in the final benchmark evidence below.
- **Counts:** the final table is computed from actual runner summaries, including sourced tests. In particular, `test_app_ask_review.tcl` includes the sourced assistant-plan tests; it must not be counted only by its locally declared tests.
- **Expectations:** REREVIEW2's audit found no remaining weakened corpus expectations to restore. The restored `1/2-1/2` corpus expectation remains intact (`95190a9b4`, `tests/command_corpus.tcl:53`); the new completion fix changes displayed grammar text, not that execution contract (`6952fb979`, `tcl/command-line.tcl:552`).

## Serial verification

**All 11 branch-touched test files passed in full: 159 passed, 0 failed, 0 skipped.** The two corpus files are sourced by these tests; `run_app_tests.tcl` is their runner. Comparison: `baf4e4f86..f2d69e80e`.

Completed serial suite runs at implementation revision `f2d69e80e`: **48 runs, 737 passed, 0 failed, 5 skipped** (45 app-runner invocations, two additional pure-Tcl runs, one standalone engine run). This total excludes the aborted optional reachability attempt described below. Its completed replacement runs only four non-UI checks.

App suites used the requested isolated HOME / `PULSE_SINK=cwtests` / `timeout 900 xvfb-run -a -s '-screen 0 1920x1080x24' src/tkchesswiz tests/run_app_tests.tcl -file <test>` invocation, with stdin closed. Suites were launched one at a time. The optional reachability rerun adds a `-match` restriction; no branch-touched test has a match restriction. The pure Tcl suites use `tclsh tests/run_all.tcl`; the standalone engine suite uses `src/tkchesswiz tests/test_ai_engine.tcl`. Runner and machine-readable results: `fix3_run_serial.py`, `fix3_serial_results.json`.

| # | Suite | Runner | Passed | Failed | Skipped | Log |
|---:|---|---|---:|---:|---:|---|
| 1 | `test_command_line.tcl` | app | 9 | 0 | 0 | [fix3_serial_app_test_command_line.log](fix3_serial_app_test_command_line.log) |
| 2 | `test_command_learning.tcl` | app | 7 | 0 | 0 | [fix3_serial_app_test_command_learning.log](fix3_serial_app_test_command_learning.log) |
| 3 | `test_app_command_sources.tcl` | app | 3 | 0 | 0 | [fix3_serial_app_test_app_command_sources.log](fix3_serial_app_test_app_command_sources.log) |
| 4 | `test_app_command_ui.tcl` | app | 8 | 0 | 0 | [fix3_serial_app_test_app_command_ui.log](fix3_serial_app_test_app_command_ui.log) |
| 5 | `test_app_command_e2e.tcl` | app | 51 | 0 | 0 | [fix3_serial_app_test_app_command_e2e.log](fix3_serial_app_test_app_command_e2e.log) |
| 6 | `test_app_command_effects.tcl` | app | 16 | 0 | 0 | [fix3_serial_app_test_app_command_effects.log](fix3_serial_app_test_app_command_effects.log) |
| 7 | `test_app_command_recipes.tcl` | app | 6 | 0 | 0 | [fix3_serial_app_test_app_command_recipes.log](fix3_serial_app_test_app_command_recipes.log) |
| 8 | `test_app_command_learning.tcl` | app | 3 | 0 | 0 | [fix3_serial_app_test_app_command_learning.log](fix3_serial_app_test_app_command_learning.log) |
| 9 | `test_app_command_acceptance.tcl` | app | 6 | 0 | 0 | [fix3_serial_app_test_app_command_acceptance.log](fix3_serial_app_test_app_command_acceptance.log) |
| 10 | `test_app_command_fixes.tcl` | app | 40 | 0 | 0 | [fix3_serial_app_test_app_command_fixes.log](fix3_serial_app_test_app_command_fixes.log) |
| 11 | `test_app_ask.tcl` | app | 22 | 0 | 0 | [fix3_serial_app_test_app_ask.log](fix3_serial_app_test_app_ask.log) |
| 12 | `test_app_ask_help.tcl` | app | 5 | 0 | 0 | [fix3_serial_app_test_app_ask_help.log](fix3_serial_app_test_app_ask_help.log) |
| 13 | `test_app_ask_i18n.tcl` | app | 10 | 0 | 0 | [fix3_serial_app_test_app_ask_i18n.log](fix3_serial_app_test_app_ask_i18n.log) |
| 14 | `test_app_ask_i18n_more.tcl` | app | 1 | 0 | 0 | [fix3_serial_app_test_app_ask_i18n_more.log](fix3_serial_app_test_app_ask_i18n_more.log) |
| 15 | `test_app_ask_keys_real.tcl` | app | 6 | 0 | 0 | [fix3_serial_app_test_app_ask_keys_real.log](fix3_serial_app_test_app_ask_keys_real.log) |
| 16 | `test_app_ask_review.tcl` | app | 29 | 0 | 0 | [fix3_serial_app_test_app_ask_review.log](fix3_serial_app_test_app_ask_review.log) |
| 17 | `test_app_ask_scope.tcl` | app | 7 | 0 | 0 | [fix3_serial_app_test_app_ask_scope.log](fix3_serial_app_test_app_ask_scope.log) |
| 18 | `test_app_ask_speech.tcl` | app | 12 | 0 | 3 | [fix3_serial_app_test_app_ask_speech.log](fix3_serial_app_test_app_ask_speech.log) |
| 19 | `test_app_assistant.tcl` | app | 61 | 0 | 0 | [fix3_serial_app_test_app_assistant.log](fix3_serial_app_test_app_assistant.log) |
| 20 | `test_app_assistant_surface.tcl` | app | 10 | 0 | 0 | [fix3_serial_app_test_app_assistant_surface.log](fix3_serial_app_test_app_assistant_surface.log) |
| 21 | `test_app_assistant_panel.tcl` | app | 27 | 0 | 0 | [fix3_serial_app_test_app_assistant_panel.log](fix3_serial_app_test_app_assistant_panel.log) |
| 22 | `test_app_assistant_engine.tcl` | app | 2 | 0 | 0 | [fix3_serial_app_test_app_assistant_engine.log](fix3_serial_app_test_app_assistant_engine.log) |
| 23 | `test_app_assistant_args.tcl` | app | 9 | 0 | 0 | [fix3_serial_app_test_app_assistant_args.log](fix3_serial_app_test_app_assistant_args.log) |
| 24 | `test_app_assistant_jobs.tcl` | app | 5 | 0 | 0 | [fix3_serial_app_test_app_assistant_jobs.log](fix3_serial_app_test_app_assistant_jobs.log) |
| 25 | `test_app_assistant_me.tcl` | app | 7 | 0 | 0 | [fix3_serial_app_test_app_assistant_me.log](fix3_serial_app_test_app_assistant_me.log) |
| 26 | `test_app_actions_api.tcl` | app | 9 | 0 | 0 | [fix3_serial_app_test_app_actions_api.log](fix3_serial_app_test_app_actions_api.log) |
| 27 | `test_app_actions_core.tcl` | app | 19 | 0 | 0 | [fix3_serial_app_test_app_actions_core.log](fix3_serial_app_test_app_actions_core.log) |
| 28 | `test_app_actions_gates.tcl` | app | 7 | 0 | 0 | [fix3_serial_app_test_app_actions_gates.log](fix3_serial_app_test_app_actions_gates.log) |
| 29 | `test_app_action_reachability.tcl` | app | 4 | 0 | 1 | [fix3_serial_app_test_app_action_reachability.log](fix3_serial_app_test_app_action_reachability.log) |
| 30 | `test_app_action_handlers_fixed.tcl` | app | 12 | 0 | 0 | [fix3_serial_app_test_app_action_handlers_fixed.log](fix3_serial_app_test_app_action_handlers_fixed.log) |
| 31 | `test_app_actions_all.tcl` | app | 105 | 0 | 0 | [fix3_serial_app_test_app_actions_all.log](fix3_serial_app_test_app_actions_all.log) |
| 32 | `test_app_inventory_actions.tcl` | app | 10 | 0 | 0 | [fix3_serial_app_test_app_inventory_actions.log](fix3_serial_app_test_app_inventory_actions.log) |
| 33 | `test_app_systemone.tcl` | app | 53 | 0 | 0 | [fix3_serial_app_test_app_systemone.log](fix3_serial_app_test_app_systemone.log) |
| 34 | `test_app_notice.tcl` | app | 9 | 0 | 0 | [fix3_serial_app_test_app_notice.log](fix3_serial_app_test_app_notice.log) |
| 35 | `test_app_convert.tcl` | app | 2 | 0 | 1 | [fix3_serial_app_test_app_convert.log](fix3_serial_app_test_app_convert.log) |
| 36 | `test_app_deutsch_translations.tcl` | app | 4 | 0 | 0 | [fix3_serial_app_test_app_deutsch_translations.log](fix3_serial_app_test_app_deutsch_translations.log) |
| 37 | `test_app_menu_translations.tcl` | app | 5 | 0 | 0 | [fix3_serial_app_test_app_menu_translations.log](fix3_serial_app_test_app_menu_translations.log) |
| 38 | `test_app_menu_toolbar_translations.tcl` | app | 2 | 0 | 0 | [fix3_serial_app_test_app_menu_toolbar_translations.log](fix3_serial_app_test_app_menu_toolbar_translations.log) |
| 39 | `test_app_analysis_integration.tcl` | app | 5 | 0 | 0 | [fix3_serial_app_test_app_analysis_integration.log](fix3_serial_app_test_app_analysis_integration.log) |
| 40 | `test_app_analysis_pane_ids.tcl` | app | 1 | 0 | 0 | [fix3_serial_app_test_app_analysis_pane_ids.log](fix3_serial_app_test_app_analysis_pane_ids.log) |
| 41 | `test_app_analysis_stop.tcl` | app | 13 | 0 | 0 | [fix3_serial_app_test_app_analysis_stop.log](fix3_serial_app_test_app_analysis_stop.log) |
| 42 | `test_app_play_engine.tcl` | app | 32 | 0 | 0 | [fix3_serial_app_test_app_play_engine.log](fix3_serial_app_test_app_play_engine.log) |
| 43 | `test_app_engine_match.tcl` | app | 22 | 0 | 0 | [fix3_serial_app_test_app_engine_match.log](fix3_serial_app_test_app_engine_match.log) |
| 44 | `test_app_ai_engine_choice.tcl` | app | 3 | 0 | 0 | [fix3_serial_app_test_app_ai_engine_choice.log](fix3_serial_app_test_app_ai_engine_choice.log) |
| 45 | `test_app_engines.tcl` | app | 16 | 0 | 0 | [fix3_serial_app_test_app_engines.log](fix3_serial_app_test_app_engines.log) |
| 46 | `test_command_line.tcl` | tclsh | 9 | 0 | 0 | [fix3_serial_tclsh_test_command_line.log](fix3_serial_tclsh_test_command_line.log) |
| 47 | `test_command_learning.tcl` | tclsh | 7 | 0 | 0 | [fix3_serial_tclsh_test_command_learning.log](fix3_serial_tclsh_test_command_learning.log) |
| 48 | `test_ai_engine.tcl` | engine | 26 | 0 | 0 | [fix3_serial_engine_test_ai_engine.log](fix3_serial_engine_test_ai_engine.log) |

Skips: three unavailable Whisper capabilities in `test_app_ask_speech.tcl`, one absent CBH fixture in `test_app_convert.tcl`, and the deliberately excluded optional `reachability-ui` sweep. The latter is not an environment skip and must not be reported as a full reachability pass.

Final benchmark (`16c5d1516`, `tests/test_app_command_acceptance.tcl:379`, run at `f2d69e80e`): **4,864,741 games, 51 commands, p50 0.50 ms, p95 4.07 ms, max 14.10 ms**. The final fixes-suite keystroke test measured **11.303 ms** maximum (`16c5d1516`, `tests/test_app_command_fixes.tcl:167`; final log `fix3_serial_app_test_app_command_fixes.log`). Both assertions pass; these are warmed-index measurements, not cold-start claims.

Final verification: `git diff --check` passes, implementation working tree is clean, and no running Stockfish, tkchesswiz test, or fake-UCI process owned by this worktree remains. The process/branch snapshot is saved in `fix3_final_checks.txt`.


## Execution limitation and restrictions

The first attempt at the optional, unchanged `test_app_action_reachability.tcl` was stopped (exit 143) after discovering that its real UI sweep includes Lichess panels. Its dynamic case enumeration includes the training-menu family (`f2d69e80e`, `tests/test_app_action_reachability.tcl:283`, `:404`); TV and event panel opening automatically requests public data (`f2d69e80e`, `tcl/lichess-tv.tcl:195`, `tcl/lichess-events.tcl:206`). The initial attempt had already invoked those panels. **I cannot certify that no Lichess requests occurred before it was stopped; this did not respect the intended no-network boundary.** Evidence is preserved in `fix3_reachability_aborted.log` and `fix3_serial_attempts_before_restriction.json`.

The subsequent run explicitly selects only the four non-UI reachability checks; its UI sweep is counted as one skip. This is an additional suite, not one of the 11 test files changed by the branch. All 11 branch-touched test files were run without a match restriction. No user's token file was read, printed or logged: app tests and their child probes used isolated HOME directories. The script preserves that isolation and uses scoped Python temporary-directory cleanup because command review rejected `rm -rf` (`fix3_run_serial.py`).

No merge or push was performed; all implementation commits are on `cmdline`. Final process verification is recorded with the serial results below.

## Jev decision

No model call was added. These fixes use exact registry predicates, ECO-catalog lookup, option comparison, serialization and UI state checks; Jev would add uncertainty and network latency to deterministic contracts. Relevant implementations: `7f881d956`, `tcl/command-actions.tcl:42`; `16c5d1516`, `tcl/command-line.tcl:65`; `2dfcd6995`, `tcl/ai-engine.tcl:215`; `6952fb979`, `tcl/command-line.tcl:552`; `5dfcf2b21`, `tcl/app-ask.tcl:1855`. Engine facts remain with Stockfish; the new engine test uses its real process (`2dfcd6995`, `tests/test_app_command_fixes.tcl:377`). No Jev integration or local model backend was started.
