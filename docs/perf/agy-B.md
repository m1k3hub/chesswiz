# Chesswiz Interactive GUI Performance Diagnosis (Area B)

Date: 2026-11-24  
Environment: Headless `Xvfb :92` (`1920x1080x24`) + `openbox`, fresh `HOME` per run, `PULSE_SINK=cwtests`, `SCIDB_AI_UNCALIBRATED=1`, `src/tkchesswiz -encoding utf-8 tcl/chesswiz --single-process`.  
Host: 48-CPU Linux workstation (note: per `docs/perf/PERF-LOG.md` P1, drawing/alpha-blending on GNOME/Xwayland `:0` is ~3–5× slower than Xvfb, so GUI paint/XSync costs reported below are lower bounds for `:0`).  
Note on Jev knowledgebase (`~/.config/jev-kb/JEV-REQUIRED-READING.md`): read as required; this task is strictly diagnostic (no feature code written).

## Executive Summary (Ranked by User-Visible Impact)

| Rank | ID | User Action | Measured Median (3× runs) | Primary Root Cause | Expected Fix Gain |
|---|---|---|---|---|---|
| 1 | **B1** | Move stepping / hold-key (`goto +1`/`-1`) | **23.2–24.3 ms/step** (~41 Hz) idle; **52.4–79.1 ms/step** (~13–19 Hz) w/ Stockfish | `::toolbar::childconfigure` unconditionally calls `RefreshRegistryLabels` (734 `winfo` + 576 `plainText`/step, +103×/15 moves via `UpdatePinState`); `adjustLinePosition` runs sync `update idletasks` every step | **5–8× faster** (~3–5 ms/step idle, ~6–10 ms/step w/ engine) |
| 2 | **B2** | Engine analysis start (`startEngine Stockfish` -> first PV) | **2,749–2,814 ms** (2.8 s) | Default `cores = cpus - 1` (47 threads, `+1,294 ms`); `uci::Engine::sendOptions` sends unchanged defaults `NumaPolicy=auto` (`+386 ms`) and `EvalFile` (`+406 ms`, reloads 98 MB NNUE); redundant `ucinewgame`+`isready` (`+41 ms`) | **~4.5× faster** (~620–680 ms, saving >2.1 s) |
| 3 | **B3** | Notation pane redraw & loading long annotated games | **254–602 ms** redraw; **246–341 ms** load (200–300 mv, 114–174 KB) | 81.7% (`211 ms`) in Tcl `pgn::DoLayout` doing 25k+ single-token `$w insert` + 7,610 named marks; `pgn::refresh 1` refreshes active game **twice** + `BusyCursor` walks 1,341 widgets | **3–5× faster** (`pgn::refresh`: 600 ms -> ~120 ms; single load/refresh -> ~80–120 ms) |
| 4 | **B4** | UI theme switch (`::theme::setTheme`) | **453.9 ms** (`-> dark`), **392.2 ms** (`-> scidblue`), **203.8 ms** (`-> default`) | `ask::ThemeChanged` triggers `Prewarm`/`_BuildAskRows` (`~225 ms`); `KeyIcon` re-renders 540 icons; `ApplyThemeToWidgetTree` (6,098 `winfo`); `scidblue` triggers `TableMinSize` (18×) + full `RebuildBoard` | **3–4× faster** (~100–130 ms) |
| 5 | **B5** | Board / window resize (new square size) | **218.4 ms** (`Walnut`), **162.4 ms** (`Marmorate`), incl. 50 ms debounce | `RebuildBoardNow` calls `MakePieces` **3×** (`146 ms`): 2× board sizes + 1× `MakeFigurines` (`89 ms` supersampled shadow-diffused 16 px icons, plus `FigurineDict` leak); `ComputeCoordFont` loops Xft fonts (`27 ms`) | **~2.5–3× faster** (~75–90 ms incl. debounce; ~25–40 ms work) |
| 6 | **B6** | PGN Display Setup dialog open & close (even on Cancel) | **135–159 ms** open; **134 ms** (G0) / **459.8 ms** (G4) close | Cancel/close (`RevertOptions`) unconditionally runs full `pgn::refresh yes` (double-rendering G4 + `BusyCursor` + 38× `RefreshRegistryLabels`); open runs `::font::copyFonts` (28 Xft fonts, `65 ms`) + builds all 10 sub-panes eagerly | Close: **>25× faster** (<15 ms on no-op cancel); Open: **~2× faster** (~65–80 ms) |
| 7 | **B7** | Assistant pane Show (`::application::assistant::panel::Show`) | **361.8 ms** (1st open), **153.4 ms** (repeat) | `PlaceBesideBoard` runs **twice**, calls `$twm load $layout` (1,004–1,109 `twm` calls, 816 `WriteOptionsRecursive`, 359 `AttachShortcutTag`), forcing full `RebuildBoard` + `MakeFigurines` (`74 ms`) + `::update` | **~3× faster** (~50–70 ms) |
| 8 | **B8** | Board theme switch (`::board::setTheme`, shadow/textured) | **207.7 ms** (`Marmorate`) vs **34.9 ms** (`Glass`) | `setupPieces all` re-renders **all** registered sizes (`MakePieces` ×2 = `203 ms`); `MakePieces` runs a `shadowSize`-iteration supersampled Tcl photo `overlay` copy loop per piece | **~4–6× faster** (~35–50 ms) |
| 9 | **B9** | Board Setup Preferences dialog open | **212.6 ms** (1st), **106.0 ms** (median) | Calls `::board::setupPieces` -> `MakePieces` **twice** (`182 ms`) + `ComputeCoordFont` (`19 ms`) on open | **~3× faster** (~35–45 ms) |
| 10 | **B10** | Engines Administration dialog open | **119.5 ms** (median) | `::countrybox` eagerly inserts ~280 countries into `tcombobox`/`tlistbox` (1,404 `tlistbox::WidgetProc` + 2,827 `lookupColor` -> `::colors::lookup` -> `::theme::isDark` calls) | **~3–4× faster** (~30–40 ms) |

---

## Detailed Bottleneck Findings

### B1 — Move Stepping / Hold-Key Rate (`goto +1` / `-1`, Idle and With Engine)
- **User action**: Stepping forward/backward through a game via keyboard arrows (`Right`/`Left`) or mouse wheel (especially holding a key at 30 Hz repeat rate, or scrubbing while Stockfish analysis is active).
- **Measured time (3× runs, median)**:
  - Clean 40-move game (`G0`, 80 plies):
    - `goto +1` ×40 with `update` per step: **972.9 ms** (`[953.4, 1013.7, 972.9]`) -> **24.32 ms/step (41.1 Hz)**
    - `goto +1` ×40 burst (no `update` between steps, single `update` at end): **728.8 ms** (`[726.0, 747.6, 728.8]`) -> **18.22 ms/step**
  - Heavily annotated 300-move game (`G4`, 600 plies, 174 KB):
    - `goto +1` ×40 with `update`: **935.4 ms** (`[909.9, 972.8, 935.4]`) -> **23.38 ms/step (42.8 Hz)**
    - `goto +1` ×40 burst: **783.5 ms** (`[782.1, 783.5, 788.1]`) -> **19.59 ms/step**
  - With Opening Tree pane open (2,177-game `twic1667.pgn.gz`):
    - `goto +1` ×15 with `update`: **363.5 ms** (`[363.5, 357.3, 368.7]`) -> **24.23 ms/step (41.3 Hz)**
  - **With Stockfish analysis active**:
    - Default 47 threads (`goto +1` ×15 with `update`): **1,187.1 ms** (`[1284.3, 1161.9, 1187.1]`) -> **79.14 ms/step (12.6 Hz)** (earlier run: **65.06 ms/step / 15.4 Hz**)
    - 4 threads (`goto +1` ×15 with `update`): **596.5 ms** (`[590.3, 611.8, 596.5]`) -> **39.77 ms/step (25.1 Hz)**
- **Where the time goes** (proc-level trace on 20 steps idle / 15 steps w/ engine):
  1. `::application::board::UpdateControls` ([tcl/app-board.tcl:2347-2369](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/app-board.tcl#L2347-L2369)) -> `::toolbar::childconfigure` ([tcl/widgets/toolbar.tcl:406-466](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/widgets/toolbar.tcl#L406-L466)) -> `::toolbar::RefreshRegistryLabels` ([tcl/widgets/toolbar.tcl:983-1008](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/widgets/toolbar.tcl#L983-L1008)):
     - Idle (20 steps): `UpdateControls` = **430.7 ms incl / 220.1 ms self** (~65% of burst time), causing **14,678 `winfo` calls** (734/step), **11,520 `::action::plainText` calls** (576/step), and **180 `::action::NoteRegistryChange` -> `InvalidateAskRows` -> `::application::ask::ListVisible` calls**.
  2. `::application::analysis::UpdateInfo` ([tcl/app-analysis.tcl:1627](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/app-analysis.tcl#L1627)) -> `UpdatePinState` ([tcl/app-analysis.tcl:2335-2341](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/app-analysis.tcl#L2335-L2341)) -> `::toolbar::childconfigure`:
     - Engine active (15 steps): `UpdatePinState` fired **103 times** (**641.7 ms incl / 333.0 ms self**), pushing total calls to **29,116 `winfo`** + **15,808 `::action::plainText`** + **247 `NoteRegistryChange`**!
  3. `::application::pgn::ProcessGoto` -> `See` -> `::pgn::setup::adjustLinePosition` ([tcl/pgn-setup.tcl:566-570](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/pgn-setup.tcl#L566-L570)):
     - Calls synchronous `update idletasks` on **every single move step** (**139.1 ms** / ~6–7 ms/step on Xvfb; forces full Tk layout/paint + XSync even during burst key-repeat; far worse on Xwayland `:0`).
- **Root cause**:
  - `::toolbar::childconfigure` unconditionally invokes `RefreshRegistryLabels` at line 465 regardless of which option was configured or whether the value actually changed. `RefreshRegistryLabels` iterates over **all toolbars and all ~72–92 buttons in the entire application**, resolves each tooltip, runs `::action::plainText`, mutates `::action::Registry`, and sets `changed = 1` unconditionally even when no label changed, invalidating Ask rows every time. `UpdateControls` calls `childconfigure -state` 8× per move step, and `UpdatePinState` calls it on every single UCI `pv`/`clear` update.
  - `adjustLinePosition` forces synchronous `update idletasks` per move step to read the scrollbar fraction.
- **Concrete proposed fix**:
  1. In `::toolbar::childconfigure` ([tcl/widgets/toolbar.tcl:423-466](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/widgets/toolbar.tcl#L423-L466)): early-return / skip `SetupTooltips` and `Tooltip hide` if only `-state` was passed and `$Specs(state:$w:$toolbar) eq $val`; only update the registry label for the **single widget `$w`** (not all toolbars!) and ONLY when `-tooltip`, `-tooltipvar`, or `-text` actually changed and the resulting plain text differs from the current `::action::Registry` entry.
  2. In `UpdatePinState` ([tcl/app-analysis.tcl:2335-2341](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/app-analysis.tcl#L2335-L2341)): cache last applied pin-button state on `Vars(pin:state)` and skip calling `childconfigure` when unchanged (eliminates ~99% of PV-driven calls).
  3. In `::pgn::setup::adjustLinePosition` ([tcl/pgn-setup.tcl:566-570](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/pgn-setup.tcl#L566-L570)): coalesce via `after idle` per text widget instead of calling synchronous `update idletasks` inside `ProcessGoto`.
  - **Expected gain**: Idle stepping drops from **~24 ms/step (41 Hz)** to **~3–5 ms/step (>200 Hz)**; engine-active stepping (combined with B2 thread cap) drops from **~65–79 ms/step (13–15 Hz)** to **~6–10 ms/step (>100 Hz)**.
- **Risk**: Very low. Single-widget label updates preserve exact registry/Ask behavior when a tooltip/text changes; coalescing `adjustLinePosition` via `after idle` keeps line-aligned scrolling after burst steps settle.

---

### B2 — Engine Analysis Start Latency (`startEngine Stockfish` -> First PV Line)
- **User action**: Clicking "Start Engine" / opening analysis with bundled Stockfish (`stockfish-chesswiz`).
- **Measured time (3× runs, median)**:
  - Default config (`cores=47, mem=256`):
    - Sync call + pane creation: **52.8 ms** (`[28.6, 52.8, 56.5]`)
    - Time to first PV line (`BestLine` populated): **2,748.5 ms** (`[2939.5, 2748.5, 2659.0]`) — confirmed in Batch 4: **2,814.1 ms** (`[3142.5, 2737.7, 2814.1]`)
  - Controlled comparison (same Chesswiz build, overriding `threads`):
    - `threads=4`: **1,520.5 ms** (`[1520.5, 1568.7, 1496.6]`)
    - `threads=1`: **1,542.4 ms** (`[1523.7, 1551.1, 1542.4]`)
  - Raw CLI `/usr/local/games/stockfish-chesswiz` (`uci` -> `readyok`, 3× medians):
    - `Threads=1, Hash=16, no NumaPolicy`: **581.2 ms** (`uciok` 546 ms)
    - `Threads=4, Hash=256, no NumaPolicy`: **612.0 ms** (`uciok` 519 ms)
    - `Threads=47, Hash=256, no NumaPolicy`: **1,773.4 ms**
    - `Threads=47, Hash=256, NumaPolicy=auto`: **2,108.8 ms**
- **Where the time goes** (timestamped UCI protocol trace via `::scidb::engine::log open`):
  - `0.0 -> 48.5 ms`: spawn `stockfish-chesswiz`, receive banner, send `uci`.
  - `48.5 -> 578.8 ms` (**530 ms**): Stockfish initial `uci` / embedded NNUE init -> `uciok`.
  - `578.8 -> 964.6 ms` (**+386 ms**): Chesswiz sends unchanged default `setoption name NumaPolicy value auto` -> Stockfish re-probes NUMA topology and re-replicates its 98 MB NNUE weights across both NUMA nodes.
  - `964.6 -> 1361.4 ms` (**+406 ms** measured at 1T): Chesswiz sends unchanged default `setoption name EvalFile value nn-1a298aa575a0.nnue` -> forces Stockfish to **reload and verify the 98 MB NNUE network a second time**.
  - `1361.4 -> 2594.0 ms` (**+1,233 ms**): Chesswiz sends `setoption name Threads value 47` -> Stockfish spawns and NUMA-binds 47 threads (`24/24:23/24`) and allocates per-thread structures + clears 256 MB hash.
  - `2597.1 -> 2637.8 ms` (**+41 ms**): Chesswiz sends `ucinewgame` + second `isready` on a brand-new engine process.
  - `2637.8 -> 3100.9 ms` (**+463 ms** at 47T vs **+63 ms** at 1T): `go infinite` finishes thread/NUMA setup before first PV arrives (`FIRST_BESTLINE` at 3,105 ms).
- **Root cause**:
  1. [tcl/engine.tcl:698](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/engine.tcl#L698) sets `current:cores [expr {max(1, [::scidb::misc::numberOfProcessors] - 1)}]`, defaulting to **47 threads** on a 48-CPU host (unbounded scaling with core count; hurts both startup latency and interactive GUI responsiveness while analyzing).
  2. `uci::Engine::sendOptions()` ([src/app/app_uci_engine.cpp:1219-1332](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/src/app/app_uci_engine.cpp#L1219-L1332)) emits `setoption` for every option in the profile without checking `if (val == opt.dflt) continue;` even though `app::Engine::Option` already stores `dflt` ([src/app/app_engine.h:125](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/src/app/app_engine.h#L125)). On modern Stockfish, re-sending default `NumaPolicy` and `EvalFile` triggers ~800 ms of redundant NUMA/NNUE reloads!
  3. `uci::Engine::startAnalysis()` ([src/app/app_uci_engine.cpp:308-312](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/src/app/app_uci_engine.cpp#L308-L312)) sends `ucinewgame` + `isready` even on the very first search of a newly spawned engine.
- **Concrete proposed fix**:
  1. In `uci::Engine::sendOptions()` ([src/app/app_uci_engine.cpp:1219-1332](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/src/app/app_uci_engine.cpp#L1219-L1332)): on initial startup (`!isAnalyzing`), skip sending any profile option whose value equals the engine's reported default (`val == opt.dflt`), especially `NumaPolicy` and `EvalFile`/`EvalFileSmall` (or track whether the user actually changed it from default). Saves **~790 ms** immediately at any thread count.
  2. In [tcl/engine.tcl:698](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/engine.tcl#L698): cap default interactive analysis threads to a sensible default (e.g., `min(4, max(1, cpus / 2))` or `min(8, ...)` while still letting users raise it in Engine Setup). Saves **~1,300–1,600 ms** on high-core workstations and halves CPU contention during interactive move stepping.
  3. In `uci::Engine::startAnalysis()` ([src/app/app_uci_engine.cpp:308-312](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/src/app/app_uci_engine.cpp#L308-L312)): omit `ucinewgame` (and the redundant pre-`position` `isready` when `readyok` was just received) on the first search after process start. Saves **~40 ms**.
  - **Expected gain**: Total start-to-first-PV drops from **~2,800 ms** to **~620–680 ms** (**~4.5× faster**, saving >2.1 s).
- **Risk**: Low. Skipping `setoption` when `val == opt.dflt` on a fresh process is standard UCI best practice (only keep sending if an option is changed mid-session or differs from engine-reported default). Capping default threads preserves full manual configurability.

---

### B3 — Notation Pane Redraw & Loading Long Annotated Games
- **User action**: Loading a heavily annotated game from the list (`::game::new`), refreshing the notation pane (`::scidb::game::refresh -immediate`), or changing notation display settings such as font size / column style (`::application::pgn::refresh 1`).
- **Measured time (3× runs, median — 100% valid parsed PGNs in `valid_annotated.pgn`)**:

| Game Size (Mainline Plies / Rendered Chars / Lines) | Load (`::game::new`) | `scidb::game::refresh -immediate` | `application::pgn::refresh 1` | Toggle Column Style |
|---|---:|---:|---:|---:|
| G0: 40 mv (80p, 485 chars, 4 lines, clean) | 59.3 ms | 16.8 ms | 56.4 ms | — |
| G1: 80 mv (160p, 13.4 KB, 165 lines, med annot) | 72.0 ms | 28.7 ms | 77.0 ms | — |
| G2: 120 mv (240p, 49.5 KB, 619 lines, heavy nested) | **104.6 ms** | 67.1 ms | **170.3 ms** | — |
| G3: 200 mv (400p, 114.0 KB, 1,347 lines, v.heavy) | **246.0 ms** | **173.6 ms** | **375.4 ms** | **417.9 ms** |
| G4: 300 mv (600p, 174.1 KB, 2,047 lines, extreme) | **340.5 ms** | **253.8 ms** | **599.6 ms** | **601.7 ms** |

- **Where the time goes** (exact C++ vs Tcl split on G4 `scidb::game::refresh -immediate`, 9,371 nodes, 2 callbacks):
  - **Total (`refresh` + `update`)**: **258.4 ms** (`[269.5, 256.2, 258.4]`)
    - **Tcl `::application::pgn::DoLayout`**: **211.1 ms (81.7%)** (`[220.9, 209.9, 211.1]`)
    - **C++ serialize + dispatch**: **39.4 ms (15.2%)** (`[39.4, 38.4, 40.5]`)
    - **Tk paint (`update`)**: **7.9 ms (3.1%)** (`[9.2, 7.9, 6.8]`)
  - Inside `::application::pgn::DoLayout` ([tcl/app-pgn.tcl:1273-1750](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/app-pgn.tcl#L1273-L1750)), proc breakdown on G4:
    - `InsertMove` (7,610 calls), `PrintMove` (6,733 calls), `PrintComment` (1,752 calls), `PrintNumericalAnnotation` (876 calls), `Indent` (877 calls), `PrintMoveInfo` (584 calls).
  - Inside `::application::pgn::refresh 1` ([tcl/app-pgn.tcl:395-414](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/app-pgn.tcl#L395-L414)) on G4 (**599.6 ms** unprofiled):
    - `::scidb::game::refresh` called **10 times** -> `InsertMove` called **15,220 times** (literally **2× the 7,610 moves** of G4!) because the loop `for {set i 0} {$i < 9}` calls `::scidb::game::refresh $i` (including `$Vars(index)`!) AND THEN line 409 calls `::scidb::game::refresh $Vars(index) -immediate` a **second time**!
    - `::widget::busyCursor on`/`off` walks **1,341 widgets** (`BusyCursor`), adding ~45–60 ms.
    - `::pgn::setup::configureText` configures all 9 slots unconditionally even when only 1 slot is open.
- **Root cause**:
  1. Double refresh + full-app `BusyCursor` walk in `::application::pgn::refresh` ([tcl/app-pgn.tcl:395-414](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/app-pgn.tcl#L395-L414)).
  2. Per-token Tcl -> `tk::text` churn in `DoLayout`/`InsertMove` ([tcl/app-pgn.tcl:1293-1750](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/app-pgn.tcl#L1293-L1750)): every space, move number, move SAN, NAG, bracket, and comment executes a separate `$w insert cur ...` command, and every move node calls `$w mark set $key cur left` (inserting 7,610 named marks into Tk's text B-tree, making subsequent index/mark lookups and deletions progressively slower).
  3. On `::game::new` load of G4 (**340.5 ms**), `::scidb::game::switch` is called 3 times plus `ShowEmptyHint` + `PrepareAsHeader` + `UpdateControls` (B1).
- **Concrete proposed fix**:
  1. **Quick win (zero risk)**: In `::application::pgn::refresh` ([tcl/app-pgn.tcl:400-411](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/app-pgn.tcl#L400-L411)): skip `$Vars(index)` inside the `0..8` loop when `$regardFontSize` will call `::scidb::game::refresh $Vars(index) -immediate` (or pass `-immediate` directly on `$i == $Vars(index)`), and only `refresh`/`configureText` open slots (`[::scidb::game::query $i open?]`). Also avoid recursive 1,341-widget `BusyCursor` walk for sub-100 ms refreshes (set cursor only on the PGN pane or after a 150 ms threshold). **Expected gain**: `pgn::refresh 1` drops from **600 ms -> ~260 ms** immediately!
  2. **Structural fix**: In `DoLayout` ([tcl/app-pgn.tcl:1273-1750](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/app-pgn.tcl#L1273-L1750)), batch consecutive `(text, taglist)` pairs into a single `$w insert cur {*}$batch` call per variation or every ~64 tokens (flushing only when a mark must be placed, or placing marks via integer offsets after bulk insert — or emitting Tk text insert batches from C++). **Expected gain**: reduces `DoLayout` on G4 from **211 ms -> ~60–80 ms** (~3× faster load and redraw on long annotated games).
- **Risk**: Quick win is negligible risk; batching `$w insert` in `DoLayout` is medium risk (must preserve exact mark gravity & fold/indent tag ranges; well covered by existing `tests/test_app_annotated_display.tcl`).

---

### B4 — UI Theme Change (`::theme::setTheme`)
- **User action**: Switching the application ttk theme (`default` -> `dark`, `dark` -> `scidblue`, `scidblue` -> `default`).
- **Measured time (3× runs, median)**:
  - `default -> dark`: **453.9 ms** (`[456.1, 453.9, 438.2]`)
  - `dark -> scidblue`: **392.2 ms** (`[431.5, 371.8, 392.2]`)
  - `scidblue -> default`: **203.8 ms** (`[135.4, 206.4, 203.8]`)
- **Where the time goes** (proc-level profile):
  - **`default -> dark` (748 ms profiled / 454 ms unprofiled)**:
    1. `::application::ask::ThemeChanged` ([tcl/app-ask.tcl:523-547](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/app-ask.tcl#L523-L547)) -> `SchedulePrewarm` -> `Prewarm` -> `::action::labels` -> `AskRows` -> `_BuildAskRows`: **224.7 ms incl** (rebuilds the entire Ask command row cache synchronously during `update`!).
    2. `SetupCurrentTheme` -> `ApplyThemeToWidgetTree` ([tcl/widgets/theme.tcl:645-750](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/widgets/theme.tcl#L645-L750)): **88.1 ms incl / 61.1 ms self** (walks all 658+ widgets, **6,098 `winfo` calls**).
    3. `ttk::ThemeChanged` -> `event generate <<ThemeChanged>>` to **658 widgets** -> `::toolbar::KeyIconStates` (54 calls) -> `KeyIcon` ([tcl/widgets/toolbar.tcl:2281-2314](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/widgets/toolbar.tcl#L2281-L2314)): **540 calls, 52.8 ms incl** (`2,831 image` calls re-keying alpha on every toolbar icon).
    4. `::colors::lookup` (**2,742 calls**, `56.6 ms`) -> `::theme::isDark` (**2,463 calls**) -> `currentTheme` (**3,067 calls**).
  - **`dark -> scidblue` (508 ms profiled / 392 ms unprofiled)**:
    1. `TableMinSize` (**18 calls, 142.0 ms incl**) + `GenerateTableMinSizeEvent` (**70.0 ms incl**).
    2. `RebuildBoard` (**105.1 ms incl**, including `MakePieces` `25.5 ms` + forced `::update` `94.5 ms`) — triggered by theme metric changes even though the board square size / theme did not meaningfully change!
    3. `KeyIcon` (**540 calls, 53.3 ms incl**) + `::colors::lookup` (**2,739 calls, 67.2 ms incl**).
- **Root cause**:
  - `::application::ask::ThemeChanged` calls `InvalidateCache` + `SchedulePrewarm`, throwing away and rebuilding the entire Ask action-label/row cache (`_BuildAskRows`) even though command labels and accelerators are completely theme-independent.
  - `::toolbar::KeyIcon` keys all 540 toolbar icons eagerly during `<<ThemeChanged>>` (including buttons on hidden tabs/panes).
  - `::theme::isDark` re-queries `currentTheme` (`ttk::style theme use`) thousands of times instead of caching a boolean updated once in `setTheme`.
  - Switching to `scidblue` triggers cascading `TableMinSize` (18×) and a full `RebuildBoard` + `::update`.
- **Concrete proposed fix**:
  1. In `::application::ask::ThemeChanged` ([tcl/app-ask.tcl:523-547](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/app-ask.tcl#L523-L547)): do **not** call `InvalidateCache` or `SchedulePrewarm` on visual theme changes — only restyle `$Priv(entry)`, `$Priv(placeholder)`, and `$Priv(list)` colors if already created. Saves **~120–180 ms** immediately.
  2. Cache `::theme::IsDark` as a plain variable updated inside `::theme::setTheme` ([tcl/widgets/theme.tcl:174-182](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/widgets/theme.tcl#L174-L182)) so `::theme::isDark` and `::colors::lookup` avoid 3,000+ `ttk::style theme use` calls.
  3. In `::toolbar::KeyIconStates`, only re-key icons for currently mapped toolbars on `<<ThemeChanged>>`, deferring unmapped toolbars to `<Map>`.
  4. Debounce `TableMinSize` / `GenerateTableMinSizeEvent` (coalesce to 1 `after idle` per table) and skip `RebuildBoard` when board canvas dimensions & board theme are unchanged.
  - **Expected gain**: Theme switch drops from **392–454 ms** to **~100–130 ms** (**3–4× faster**).
- **Risk**: Low. Ask command text/accelerators never depend on light/dark theme; caching `IsDark` in `setTheme` is exact.

---

### B5 — Board / Window Resize (`ConfigureWindow` -> `RebuildBoardNow`)
- **User action**: Resizing the main application window or dragging a pane sash so the board square size changes.
- **Measured time (3× runs, median, end-to-end from `wm geometry` to `afterRebuild` + `update`)**:
  - Default `Walnut` theme (fresh uncached square sizes, incl. 50 ms debounce): **218.4 ms** (`[218.4, 210.1, 218.4]`)
  - `Marmorate` theme (fresh uncached square sizes, incl. 50 ms debounce): **162.4 ms** (`[173.7, 162.4, 149.3]`)
  - Repeated resize between cached sizes (`1300x820 -> 1850x1020`, Walnut): **102.4 ms** (`[194.3, 102.4, 83.7]`; first uncached = **194.3 ms**)
  - Isolated `MakePieces` for a single fresh square size: **45.2 ms** (`Walnut`), **73.7 ms** (`Marmorate`)
- **Where the time goes** (proc-level profile of Walnut resize `1120x710 -> 1760x980`):
  1. **`::board::pieceset::registerFigurines` -> `MakeFigurines` -> `MakePieces`**: **89.3 ms incl** ([tcl/app-board.tcl:1665](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/app-board.tcl#L1665), [tcl/board-pieceset.tcl:210-264](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/board-pieceset.tcl#L210-L264)) — single biggest slice of resize!
  2. **`::board::setupPieces` -> `pieceset::makePieces` -> `MakePieces` (2 calls)**: **57.1 ms incl** ([tcl/app-board.tcl:1679-1688](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/app-board.tcl#L1679-L1688), [tcl/board-basic.tcl:423-466](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/board-basic.tcl#L423-L466)).
  3. **`ConfigureBoard` -> `ComputeCoordFont`**: **26.6 ms incl** ([tcl/app-board.tcl:2185-2215](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/app-board.tcl#L2185-L2215)).
  4. **Forced `::update` inside `RebuildBoard`**: **20.0 ms incl** ([tcl/app-board.tcl:1582](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/app-board.tcl#L1582)) + 50 ms debounce ([tcl/app-board.tcl:1227](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/app-board.tcl#L1227)).
- **Root cause**:
  - `MakeFigurines` ([tcl/board-pieceset.tcl:235-264](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/board-pieceset.tcl#L235-L264)) renders **all 12 pieces** (`wk bk wq wr wb wn wp bq br bb bn bp`, including kings which never appear in the captured-material bar!) using full supersampled `MakePieces` with `shadow 0.05` and `linear` shadow diffusion for ~16 px icons every time `pieceSize` changes by even 1 px. Furthermore, `unregisterFigurines` ([tcl/board-pieceset.tcl:228](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/board-pieceset.tcl#L228)) has a bug: it decrements undefined `BoardSizeDict` instead of `FigurineDict`, leaking figurine photos on every resize.
  - `::board::setupPieces` runs `MakePieces` twice because `PieceSizeDict` keeps stale/secondary sizes registered (`Preload` at [tcl/app-board.tcl:1196](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/app-board.tcl#L1196) + other variant layouts at line 1679).
  - `ComputeCoordFont` ([tcl/app-board.tcl:2196-2206](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/app-board.tcl#L2196-L2206)) loops calling `$w itemconfigure coordA -font [list $family $size]` + `bbox`, creating/loading multiple Xft fonts per resize.
- **Concrete proposed fix**:
  1. Quantize material-bar figurine sizes to 3 discrete buckets (e.g., `14`, `18`, `22` px), omit `wk`/`bk` and shadow diffusion at <=22 px in `MakeFigurines`, and fix the `BoardSizeDict` -> `FigurineDict` typo at [tcl/board-pieceset.tcl:228](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/board-pieceset.tcl#L228). Saves **~85 ms** on every resize!
  2. Only call `setupPieces $Dim($sqsize)` for the active board size (not `all`/inactive variant sizes). Saves **~25–50 ms**.
  3. Cache `ComputeCoordFont` results by `(family, factor, offset)` (or compute directly from `font metrics` of one reference font size by linear scaling + single verification). Saves **~25 ms**.
  4. Replace `::update` at [tcl/app-board.tcl:1582](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/app-board.tcl#L1582) with `update idletasks` or remove.
  - **Expected gain**: Active resize work drops from **~168 ms** (`218 ms` incl. 50 ms debounce) to **~35–45 ms** (`~85 ms` incl. debounce) — **~3.5–4× faster** redraw!
- **Risk**: Low. Quantizing tiny captured-piece icons to 14/18/22 px is visually indistinguishable and eliminates a real image memory leak.

---

### B6 — PGN Display Setup Dialog (`::application::pgn::ConfigureEditor`) Open & Close
- **User action**: Opening and closing (even cancelling without changes) the PGN Display Setup dialog (`Preferences` / notation pane configure).
- **Measured time (3× runs, median)**:
  - With short game (`G0`, 80 plies):
    - Open: **159.2 ms** (`[172.7, 159.2, 139.5]`)
    - Close (Cancel / destroy): **134.1 ms** (`[144.5, 134.1, 123.1]`)
  - With long annotated game (`G4`, 600 plies, 174 KB):
    - Open: **134.5 ms** (`[134.5, 120.3, 159.9]`)
    - **Close (Cancel / destroy)**: **459.8 ms** (`[472.9, 406.8, 459.8]`)
- **Where the time goes** (proc-level profile on G0):
  - **Open (`162 ms` profiled)**:
    1. `::font::copyFonts` ([tcl/pgn-setup.tcl:587](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/pgn-setup.tcl#L587)): **65.0 ms incl** (`28 font` commands = `69.1 ms`, split across `registerTextFonts` 25.3 ms, `registerSymbolFonts` 19.8 ms, `registerFigurineFonts` 19.7 ms).
    2. Eagerly building all 10 option sub-panes upfront ([tcl/pgn-setup.tcl:634-648](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/pgn-setup.tcl#L634-L648)): `BuildFrame(MoveStyle)` **19.9 ms**, `BuildFrame(Font)` -> `::dialog::choosefont::embedFrame` **14.0 ms**, `BuildFrame(topics)` ×5 + `choosecolor::embedFrame` (~20 ms).
  - **Close (`250 ms` profiled on G0; `460 ms` unprofiled on G4)**:
    1. `RevertOptions` ([tcl/pgn-setup.tcl:777-811](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/pgn-setup.tcl#L777-L811), line 803): unconditionally calls `foreach cxt $ContextList { ::pgn::${cxt}::refresh yes }` -> triggers B3's **full double-refresh** (`157.6 ms` on G0, **~400+ ms on G4**!) + `BusyCursor` (1,237 widgets)!
    2. Inside that refresh: `38` calls to `::toolbar::childconfigure` -> `RefreshRegistryLabels` (B1: **64.5 ms**, `6,785 winfo` + `2,014 plainText` calls)!
- **Root cause**:
  - Closing/cancelling the dialog unconditionally triggers a full PGN refresh across all contexts (`RevertOptions` line 803) even when the user changed zero settings (`$Priv(applied) == 0` and `New_* == Revert_*`).
  - Opening eagerly duplicates 28 Xft fonts (`::font::copyFonts`) and constructs all 10 hidden sub-panes (including the full system font picker and color cube) before the user ever clicks those tabs.
- **Concrete proposed fix**:
  1. In `RevertOptions` ([tcl/pgn-setup.tcl:777-811](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/pgn-setup.tcl#L777-L811)): track a `dirty` flag (or compare `Options`/`Colors`/`::font::Options` against `Revert_*`); if nothing changed and `$Priv(applied) == 0`, skip `::font::useLanguage` and skip `::pgn::${cxt}::refresh yes` entirely on close!
  2. Lazy-build sub-panes (`MoveStyle`, `Diagrams`, `Font`, `colors`) on first selection in `SelectionChanged` instead of building all 10 upfront, and only copy/create `setup` fonts if/when a font option is edited (using existing `$context` fonts for preview until edited).
  - **Expected gain**: Cancel/close drops from **134–460 ms** to **<15 ms** (**>25× faster** on G4); open drops from **135–159 ms** to **~50–70 ms** (**~2.5× faster**).
- **Risk**: Low. Comparing against `Revert_*` is exact; lazy sub-pane construction already fits `SelectionChanged`'s switch architecture.

---

### B7 — Assistant Pane Show (`::application::assistant::panel::Show`)
- **User action**: Toggling/showing the docked Assistant pane beside the board.
- **Measured time (3× runs, median)**:
  - First open: **361.8 ms**
  - Subsequent opens (median of 3): **153.4 ms** (`[361.8, 153.4, 151.1]`)
  - Hide: **24.5 ms** (`[22.1, 24.5, 26.7]`)
- **Where the time goes** (proc-level profile):
  - **First open (`375.3 ms` profiled)**:
    1. `PlaceBesideBoard` ([tcl/app-assistant-panel.tcl:299-329](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/app-assistant-panel.tcl#L299-L329)) called **TWICE** (`162.7 ms incl`) -> calls `$twm load $layout` -> `::twm::WidgetProc` (**1,109 calls**, `106.0 ms incl`), `WriteOptionsRecursive` (**812 calls**, `18.9 ms`), `AttachShortcutTag` (**358 calls**, `14.1 ms`).
    2. `RebuildBoard` (**185.9 ms incl**): `MakeFigurines` -> `MakePieces` (**73.7 ms**), `ComputeCoordFont` (**13.4 ms**), forced `::update` (**84.8 ms incl**).
    3. `ttk::ThemeChanged` (**43.8 ms incl**).
  - **Repeat open (`168.9 ms` profiled)**:
    1. `PlaceBesideBoard` still called **TWICE** (**90.3 ms incl** -> `::twm::WidgetProc` 1,004 calls, `WriteOptionsRecursive` 816 calls, `AttachShortcutTag` 359 calls, `SaveOption` `13.0 ms`!).
    2. `RebuildBoard` -> `::update` (**72.0 ms incl**).
- **Root cause**:
  - `Show` opens the pane AND calls `PlaceBesideBoard` twice (once via `Show` and again via callback/re-entry), and `PlaceBesideBoard` rewrites the entire TWM layout via `$twm load $layout` — which tears down/re-parents panes, re-attaches shortcut tags to 359 widgets, serializes options recursively (816 calls), and forces a full `RebuildBoard` + `MakeFigurines` + `::update`.
- **Concrete proposed fix**:
  1. Deduplicate the double `PlaceBesideBoard` invocation (guard with an already-beside check on the current layout tree before calling `$twm load`).
  2. Use incremental TWM pane docking/insertion (or preserve existing sibling panes instead of reloading the entire layout) and avoid writing options to disk (`SaveOption` / `WriteOptionsRecursive`) synchronously inside `Show` — defer option persistence with `after idle`.
  3. Combined with B5 (`MakeFigurines` + `::update` fixes), eliminates the 74–186 ms `RebuildBoard` hit.
  - **Expected gain**: First open drops from **362 ms -> ~80–100 ms**; repeat open from **153 ms -> ~45–60 ms** (**~3× faster**).
- **Risk**: Medium (TWM layout placement logic has delicate compact-vs-wide geometry constraints; must test both `< required` tabbed mode and `>= required` 3-column mode).

---

### B8 — Board Theme Change (`::board::setTheme` on Shadow/Textured Themes)
- **User action**: Switching board themes to a textured / shadow-diffused theme (e.g., `Marmorate`, `Woodgrain`, `Walnut`).
- **Measured time (3× runs, median)**:
  - Switch to `Marmorate`: **207.7 ms** (`[235.5, 207.7, 169.4]`)
  - Switch to `Glass` (no heavy shadow diffusion): **34.9 ms** (`[34.7, 37.5, 34.9]`)
- **Where the time goes** (proc-level profile of `setTheme Marmorate`):
  - `::board::setTheme` (**208.6 ms incl**) -> `SetPieceStyle` -> `setupPieces` ([tcl/board-basic.tcl:423-466](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/board-basic.tcl#L423-L466)) -> `pieceset::makePieces` -> `MakePieces` ([tcl/board-pieceset.tcl:267-580](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/board-pieceset.tcl#L267-L580)): **2 calls = 203.1 ms incl / 196.7 ms self** (85% of total; `image` 262 calls).
  - `::application::board::Redraw` -> `RebuildBoard`: **22.3 ms incl**.
- **Root cause**:
  1. `::board::setupPieces all` re-renders **every size in `PieceSizeDict`** (at least 2 sizes because `Preload` registers the startup size and never unregisters it until board close), doubling the cost (`2 × ~100 ms`).
  2. Inside `MakePieces` ([tcl/board-pieceset.tcl:468-483](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/board-pieceset.tcl#L468-L483)), when `$shadowDiffuse ne "none"`, a Tcl loop runs `shadowSize` iterations (`~12–25×` per piece × 12 pieces = ~200+ iterations) executing `piece(sh) copy $sh -compositingrule overlay` at full supersampled `$sampleSize x $sampleSize` resolution, plus creating/deleting 5–6 temporary photo images per piece!
- **Concrete proposed fix**:
  1. Unregister superseded sizes in `PieceSizeDict` (or in `setupPieces all`, only render the active visible board size synchronously and mark other sizes dirty for lazy rebuild on demand). Cuts cost **in half immediately** (`208 ms -> ~105 ms`).
  2. Move the `shadowSize` diagonal-smear shadow loop into a single C++ `::scidb::tk::image` primitive (alongside existing `::scidb::tk::image diffuse` at line 482) operating in-place on the pixel buffer instead of 200+ Tk photo overlay copies, and reuse temporary `piece(bg)`/`piece(sh)`/`piece(fg)` photos across the 12-piece loop instead of `image create`/`delete` per piece.
  - **Expected gain**: Textured/shadow board theme switch drops from **208 ms -> ~35–50 ms** (**4–6× faster**).
- **Risk**: Low. C++ pixel-loop shadow smear produces bit-identical output to the Tcl overlay loop.

---

### B9 — Board Setup Preferences Dialog Open (`::board::options::openConfigDialog`)
- **User action**: Opening Board Preferences / Setup (`Board -> Setup...`).
- **Measured time (3× runs, median)**:
  - Open: **106.0 ms** median (`[212.6, 34.1, 106.0]`; **212.6 ms** on first open!)
  - Close: **22.8 ms** (`[19.0, 22.8, 28.1]`)
- **Where the time goes** (proc-level profile on open, `295.3 ms` profiled):
  1. `::board::setupPieces` -> `pieceset::makePieces` -> `MakePieces` (**2 calls**): **181.6 ms incl / 175.6 ms self** (61% of total).
  2. `RebuildBoard` -> `ConfigureBoard` -> `ComputeCoordFont`: **42.3 ms incl** (`ComputeCoordFont` = **19.5 ms**).
- **Root cause**:
  - Opening the dialog ([tcl/board-options.tcl:869,1672-1690](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/board-options.tcl#L1672-L1690)) registers the preview board's square size and triggers `setupPieces` twice (creating two full supersampled piece sets via B8's slow `MakePieces` loop) plus runs `ComputeCoordFont` on the preview board.
- **Concrete proposed fix**:
  - Combine B8's C++ shadow smear + single-size `setupPieces` (only render the preview square size once) and defer non-active tab preview setup until the tab is selected.
  - **Expected gain**: First open drops from **213 ms -> ~45–60 ms** (**~4× faster**).
- **Risk**: Low.

---

### B10 — Engines Administration Dialog Open (`::engine::openAdmininstration`)
- **User action**: Opening Preferences -> Engines (`::engine::openAdmininstration .application`).
- **Measured time (3× runs, median)**:
  - Open: **119.5 ms** (`[119.5, 130.5, 109.1]`)
  - Close: **21.9 ms** (`[24.8, 21.9, 21.2]`)
- **Where the time goes** (proc-level profile, `278.3 ms` profiled):
  1. `::countrybox $setup.ccountry` ([tcl/engine.tcl:283](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/engine.tcl#L283) -> [tcl/widgets/countrybox.tcl:29-120](file:///media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/tcl/widgets/countrybox.tcl#L29-L120)):
     - `::ttk::tcombobox::WidgetProc` (**294 calls, 219.7 ms incl**) -> `::tlistbox::WidgetProc` (**1,404 calls, 221.2 ms incl**) -> `lookupColor` (**2,827 calls, 101.4 ms incl**) -> `::colors::lookup` (**2,836 calls**) -> `::theme::isDark` (**2,838 calls**) -> `currentTheme` (**2,838 calls**)!
     - `MakeItems` (283 calls), `ExtractValue` (280 calls), `image` (1,067 calls).
  2. `MakeEngineList` (3 engines): only **16.3 ms incl**.
- **Root cause**:
  - `::countrybox` eagerly inserts all ~280 countries with flag icons into its dropdown `tlistbox` one row at a time during dialog construction, even though the dropdown is closed and rarely opened. Each row insertion invokes `tlistbox::WidgetProc` ~5 times and calls `lookupColor` -> `::colors::lookup` -> `::theme::isDark` -> `currentTheme` ~10 times per row (~2,830 lookups!).
- **Concrete proposed fix**:
  1. Lazy-populate `::countrybox`'s ~280-row dropdown list on first dropdown open (`-postcommand` / `<ButtonPress-1>`), displaying only the currently selected country's name/code on dialog open. (Also benefits every other dialog using `::countrybox`, e.g., Player Card / Search dialogs.)
  2. In `tlistbox` + `::theme::isDark` (shared with B4), cache theme/table colors per widget instead of calling `::colors::lookup` -> `::theme::isDark` 10× per inserted row.
  - **Expected gain**: Engines Administration open drops from **120 ms -> ~30–40 ms** (**3–4× faster**).
- **Risk**: Very low. The combobox entry displays the bound `-textvariable` without needing the popup listbox populated until opened.

---

## Measured Interactive Areas Below Threshold (<100 ms, Verified Fast)

All other prompt-required interactive areas were benchmarked (3× runs, medians on `:92`) and confirmed below the ~100 ms threshold (aside from first-ever cold paint where noted):

| Area / Action | Data Size | Median (ms) | Runs (ms) | Notes |
|---|---|---:|---|---|
| Load game from DB list (`::game::new`) | 2,177-game TWIC DB (game #100) | 45.1 | `[89.6, 45.1, 39.0]` | Scales up on long annotated games (see **B3**) |
| Tab switch `board -> database` | 54 games / 2,177 games | 63.1 / 30.3 | `[89.3, 63.1, 33.1]` / `[127.3, 27.6, 30.3]` | First-ever cold switch on 2,177 games = 127 ms; steady-state 30 ms |
| Tab switch `database -> board` | 54 games / 2,177 games | 40.3 / 39.4 | `[42.2, 39.6, 40.3]` / `[37.2, 40.0, 39.4]` | Fast |
| Tab switch `board <-> information` | 54 games | 24.8 / 43.1 | `[24.8, 69.7, 14.4]` / `[46.7, 41.4, 43.1]` | Fast |
| DB sub-tabs (`player`/`event`/`site`/`annotator`/`position`/`games`) | 2,177-game TWIC DB | 15.9–26.8 | first cold: 36–57 ms; steady: 15–27 ms | Fast |
| Layout switches: `TogglePaneZoom` / `twm load` / `openPane tree` | 54 / 2,177 games | 21.5 / 39.2 / 72.1–86.6 | `openPane tree` 1st on 2,177 DB = 135 ms, steady 86.6 ms | Board resize & Assistant pane are slow (see **B5**, **B7**) |
| Dialog: Keyboard Preferences (open / close) | — | 23.4 / 13.2 | `[33.4, 23.4, 22.6]` / `[13.2, 14.6, 12.9]` | Fast |
| Dialog: PGN Export Options (open / close) | — | 12.5 / 10.8 | `[15.4, 10.5, 12.5]` / `[80.3, 10.8, 8.3]` | Fast (unlike PGN Display Setup **B6**) |
| Dialog: Assistant Preferences (open / close) | — | 18.6 / 9.7 | `[22.4, 17.4, 18.6]` / `[9.7, 8.1, 11.3]` | Fast |
| Dialog: Manage Layouts (open / close) | — | 48.9 / 16.5 | `[65.2, 48.9, 45.0]` / `[19.2, 16.5, 15.7]` | Fast |
| Dialog: Play Against Engine (open / close) | — | 28.7 / 8.8 | `[40.6, 28.7, 27.3]` / `[8.8, 8.8, 8.1]` | Fast |
| Ask field: type `'engine'` -> Refresh done | — | 11.4 | `[59.3, 11.4, 7.7]` | Fast after prewarm; prewarm itself costs ~180–225 ms (see **B4**) |
| Engine Stop (`Stop` -> `bestmove`) / Power down + close pane | Stockfish | 16.7 / 39.2 | `[16.7, 16.1, 16.7]` / `[39.2, 34.0, 41.9]` | Stop & close are fast; start is 2.8 s (see **B2**) |

---

## Exact Reproduction Commands

All measurements are reproducible headlessly on `:92` (substitute any unused display). Scratch scripts and generated valid annotated PGN (`valid_annotated.pgn`, 362 KB, 5 games from 80 to 600 plies with 3-level nested variations) were stored under `/tmp/claude-1000/-media-michael-g-thomas-sas-mirror-src-chess-scidb-code-codex/b004314a-e474-44e6-b425-aa1a8d7ec8d9/scratchpad/agy/B/`.

### 1. Headless Xvfb + Chesswiz Launch
```bash
Xvfb :92 -screen 0 1920x1080x24 -nolisten tcp &
DISPLAY=:92 openbox &
H=$(mktemp -d)
DISPLAY=:92 HOME="$H" PULSE_SINK=cwtests SCIDB_AI_UNCALIBRATED=1 \
  src/tkchesswiz -encoding utf-8 tcl/chesswiz --single-process share/sample/twic1667.pgn.gz &
# Dismiss first-start language chooser via Tk send:
DISPLAY=:92 /usr/bin/wish - <<<'wm withdraw .; catch {send -async Chesswiz {.application.lang.top.en invoke}}; exit'
```

### 2. Repro Commands (via `DISPLAY=:92 /usr/bin/wish`)
- **B1 (Move stepping idle & w/ Stockfish)**:
  ```tcl
  # Idle (40 steps):
  send Chesswiz {
    ::scidb::game::go -1 start; update
    set t0 [clock microseconds]
    for {set i 0} {$i < 40} {incr i} { ::application::board::goto +1; update }
    expr {([clock microseconds]-$t0)/1000.0}
  }
  # Engine active (15 steps):
  send Chesswiz {
    set num [::application::analysis::startEngine Stockfish]
    # wait for ::application::analysis::BestLine $::application::analysis::NumberToTree($num)
    set t0 [clock microseconds]
    for {set i 0} {$i < 15} {incr i} { ::application::board::goto +1; update }
    expr {([clock microseconds]-$t0)/1000.0}
  }
  ```
- **B2 (Stockfish start to first PV + UCI traffic trace)**:
  ```tcl
  send Chesswiz {
    set ::t0 [clock microseconds]
    ::scidb::engine::log open {apply {{tag msg} {puts "[format %.1f [expr {([clock microseconds]-$::t0)/1000.0}]] ms $msg"}}} uci
    set num [::application::analysis::startEngine Stockfish]
    set tree $::application::analysis::NumberToTree($num)
    while {[llength [::application::analysis::BestLine $tree]] == 0} { update; after 2 }
    expr {([clock microseconds]-$::t0)/1000.0}
  }
  ```
- **B3 (Long annotated game load & notation redraw)**:
  Generate a valid 300-move (600-ply) nested-variation annotated PGN (or open any large annotated PGN) and run:
  ```tcl
  send Chesswiz {
    set t0 [clock microseconds]; ::scidb::game::refresh [::scidb::game::current] -immediate; update
    set dt1 [expr {([clock microseconds]-$t0)/1000.0}]
    set t1 [clock microseconds]; ::application::pgn::refresh 1; update
    set dt2 [expr {([clock microseconds]-$t1)/1000.0}]
    list refresh_immediate_ms $dt1 pgn_refresh_1_ms $dt2
  }
  ```
- **B4 (UI theme switch)**:
  ```tcl
  send Chesswiz {
    set t0 [clock microseconds]; ::theme::setTheme dark; update
    set d1 [expr {([clock microseconds]-$t0)/1000.0}]
    set t1 [clock microseconds]; ::theme::setTheme scidblue; update
    set d2 [expr {([clock microseconds]-$t1)/1000.0}]
    list to_dark_ms $d1 to_scidblue_ms $d2
  }
  ```
- **B5 (Board resize to fresh square size on Walnut)**:
  ```tcl
  send Chesswiz {
    wm geometry .application 1120x710+10+10; update; after 200; update
    set ::rb 0; ::application::board::afterRebuild {set ::rb 1}
    set t0 [clock microseconds]; wm geometry .application 1760x980+10+10
    while {!$::rb} { update }; update
    expr {([clock microseconds]-$t0)/1000.0}
  }
  ```
- **B6 (PGN Display Setup open & Cancel/close on long annotated game)**:
  ```tcl
  send Chesswiz {
    set ::t0 [clock microseconds]
    after 1 {proc _p {} {
      if {[winfo exists .application.pgnSetup] && [winfo ismapped .application.pgnSetup]} {
        update idletasks; set ::t1 [clock microseconds]; destroy .application.pgnSetup
      } else { after 5 _p }
    }; _p}
    ::application::pgn::ConfigureEditor; update
    set t2 [clock microseconds]
    list open_ms [expr {($::t1-$::t0)/1000.0}] close_ms [expr {($t2-$::t1)/1000.0}]
  }
  ```
- **B7 (Assistant pane Show)**:
  ```tcl
  send Chesswiz { set t0 [clock microseconds]; ::application::assistant::panel::Show; update; expr {([clock microseconds]-$t0)/1000.0} }
  ```
- **B8 (Board theme switch to Marmorate)**:
  ```tcl
  send Chesswiz { set t0 [clock microseconds]; ::board::setTheme Marmorate; ::application::board::Redraw; update; expr {([clock microseconds]-$t0)/1000.0} }
  ```
- **B9 (Board Setup Preferences open)**:
  ```tcl
  send Chesswiz { set t0 [clock microseconds]; ::board::options::openConfigDialog .application ::application::board::Redraw; update; expr {([clock microseconds]-$t0)/1000.0} }
  ```
- **B10 (Engines Administration open)**:
  ```tcl
  send Chesswiz {
    set ::t0 [clock microseconds]
    after 1 {proc _p {} {
      if {[winfo exists .application.adminEngines] && [winfo ismapped .application.adminEngines]} {
        update idletasks; set ::t1 [clock microseconds]; destroy .application.adminEngines
      } else { after 5 _p }
    }; _p}
    ::engine::openAdmininstration .application; update
    expr {($::t1-$::t0)/1000.0}
  }
  ```
