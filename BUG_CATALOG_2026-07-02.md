# Bug Catalog — Scidb Codebase Audit
Date: 2026-07-02
Auditor: Claude (four parallel review passes)
Previous audit: BUG_CATALOG_2026-05-01.md

## Methodology
Four passes over everything changed since the 2026-05-01 audit (21 commits + uncommitted working tree):
1. **Uncommitted diff review** — all 14 modified files (`::util::fileExtension` refactor, configure, check-build).
2. **Split-completeness audit** — mechanical inventory diff of pre-split `app-database.tcl` (e341859^) and pre-move `gamebar.tcl` (16e39cc^) vs the union of the 8 current module files: 300+ procs, 325 mc strings, file-scope state, top-level side effects, Makefile load order.
3. **New C++ review** — `sys::ThreadGroup` + its 3 uses in `db_maintenance.cpp` (vs pre-refactor behavior), tree-row identity refactor (25a0ffa), snprintf/strtol fixes (382943b, ff1100a).
4. **Tcl-wide dangling-symbol sweep** — 214 files / ~99.5k lines; namespace-aware resolution of all qualified command tokens and `$`-variable uses against an index of 4,645 proc defs and 10,611 variable/mc defs (+17,082 lang-file entries). 131 command + 94 variable candidates manually triaged; C-defined commands (`::scidb::*`, `::fam::*`, `::tkhtml::*`), Tk internals, and dynamic names eliminated.

Key P1s (1, 2, 3, 5, 6, 7, 12, 14) were independently re-verified by the orchestrator against source.

Recurring root causes:
- (a) Feature code appended **after** the closing `} ;# namespace` lines of a file, leaving procs/vars global (app-db-players.tcl, app-db-games.tcl).
- (b) mc strings defined in one panel's `mc` namespace but consumed from another panel's namespace (tree↔analysis, vars↔tree, database↔gamebar).
- (c) Procs called at their pre-refactor namespace addresses.
- (d) The dotted-extension refactor (`::util::fileExtension`) updated most consumers to dotted patterns but left `openBase` dotless.

---

## P1 — broken features / broken startup

### BC-1: `openBase` cannot open any database — dotted vs dotless extension mismatch (UNCOMMITTED)
**File:** `tcl/app-database.tcl:469`
The uncommitted line `set ext [::util::fileExtension $file]` overwrites the dotless `ext` computed just above it (via `::scidb::misc::mapExtension`) with a **dotted** one (`.sci`, `.pgn.gz` — see `tcl/start.tcl:526`). Every downstream consumer in `openBase` is dotless:
- encoding switch :516 and load switch :521 (`sci - si3 - si4 - cbh - cbf`, `pgn - pgn.gz - zip`) — **no arm matches, `::scidb::db::load`/`::import::open` never runs**, falls to :552 → "Cannot open file" for every database
- `$ext ne "sci"` :524 / `$ext == "sci"` :557 — readonly + sci-upgrade logic dead
- hard-link check :490 vs switcher's dotless store (`database-switcher.tcl:671`)

The other refactored sites (newBase :649, OpenArchive :826, UpdateAfterSwitch :1079, database-switcher.tcl:643) correctly use dotted patterns; only `openBase` was left behind. **Fix:** strip the dot (`string range [...] 1 end`) or convert openBase's comparisons to dotted.

### BC-2: Tree-row identity filter always fails — hex producer vs Tcl-integer consumer (commit 25a0ffa)
**Files:** `src/app/app_application.cpp:2245` (producer), `src/tcl/tcl_view.cpp:567` (consumer)
Producer formats the hash as bare hex: `out.identity.format("%llx %u %u %u %u %s", ...)`. Consumer parses element 0 with `Tcl_GetWideIntFromObj`, which accepts decimal or prefixed (`0x`) forms only. Any hash containing a–f → parse error → "invalid tree identity"; an all-digit hash parses as the wrong *decimal* value → hash compare at `app_application.cpp:2300` fails → "unable to apply tree identity". Either way, opening-prep "apply filter" (identity flows via `tcl/app-database-openingprep.tcl:404-410` into `::scidb::view::setTreeFilter -identity`) never works.
**Fix note:** `0x%llx` still fails for hashes ≥ 2^63 (Tcl wide is signed; larger hex → bignum). Safest: format `(long long)hash` as signed decimal, cast back to `uint64_t` on read.

### BC-3: `RatingDialogName` dropped by search sub-split — Rating Search dialog dead (commit 235fcb3)
**File:** `tcl/app-database-search-rating.tcl:440`
`OpenRatingSearch` calls `RatingDialogName`, whose definition existed in the pre-split file (e341859^:tcl/app-database.tcl:4089) and in the intermediate app-database-search.tcl, but was dropped by 235fcb3. Defined in **no** current file (whole-tree grep). Opening the Rating Search dialog → `invalid command name "RatingDialogName"`. Also baked into the built `tcl/scidb-beta`.
**Fix** (mirror `MaterialDialogName`):
```tcl
proc RatingDialogName {file variant} {
	return .rating_[string map {: _ . _ / _} $file]_${variant}
}
```

### BC-4: `::ui::message` — command defined nowhere; 14 call sites, including inside error handlers
**Files:** `tcl/app-analysis.tcl:1794,1819,1862,1869,1893,1898,2010,2033,2041,2045`; `tcl/app-db-games.tcl:649,658`; `tcl/app-db-players.tcl:1569`; `tcl/app-tree.tcl:1960`
No `proc`, no `namespace eval ui`, nothing in src/ registers it. Every status/error path of the new analysis/preset/novelty features raises `invalid command name "::ui::message"` — and several sit inside `trap` handlers, so the original error is masked.

### BC-5: `tcl/app-pgn.tcl` cursor block — malformed switch + missing `::xcursor::supported?` at **source time**
**File:** `tcl/app-pgn.tcl:3242-3259`
Two stacked bugs:
1. The `switch [tk windowingsystem]` body contains `variable collapse` / `variable expand` **inside** the braces, so they parse as pattern/body pairs (`variable`→`collapse`, `variable`→`expand`), not variable declarations.
2. The x11 arm calls `[::xcursor::supported?]` — no such proc exists (`tcl/utils/xcursor.tcl` defines setCursor/unsetCursor/loadCursor/names/deleteCursor only; never existed in git history). This is top-level code in `namespace eval cursor`, so **on X11 the error fires while sourcing app-pgn.tcl** — a load-time failure.
Same missing proc called (inside a proc, so runtime) at `tcl/setup-board.tcl:1659` when the board-setup dialog installs drag cursors on X11.

### BC-6: Opponent Dossier block is outside all namespaces
**File:** `tcl/app-db-players.tcl:1587-2311` (namespaces close at :1581-1583)
`RefreshOpponentDossier`, `BuildOpponentDossier` (:1910), `PopulateOpponentDossier` (:2071), `OpenOpponentDossier`, etc. are **global procs**. Confirmed consequences:
- ~35 `$mc::Prep*`/`$mc::Dossier*` derefs (:1629-2126) resolve to `::mc::*` — missing; the defs live in `::application::database::player::mc` (:49-99). First failure: `wm title … $mc::OpponentDossierTitle` (:1938) as soon as the dossier opens via prep-report.
- Unqualified calls to player-ns procs → invalid command: `OpenPrepReport`, `PrepReportDialogName`, `PrepReportReady?`, `FilterPrepReportByOpening`, `UnpackPlayerStats`, `PrepReportRangeText`, `PrepReportRatingText`, `PrepReportPlayerIndex`.
- `variable PrepReportData` in the global procs binds `::PrepReportData`, never populated (player ns fills its own) → 'can't read' errors.
**Fix:** move the block inside the player namespace (before the closers) or wrap it in `namespace eval ::application::database::player`.

### BC-7: Variation-window right-click menu — all mc strings missing (empty mc block)
**File:** `tcl/app-variation.tcl:591,596,606,612,619`
`PopupMenu` (bound at :165) derefs `$mc::StartSearch`, `mc::UseExactMode`/`UseFastMode`, `$mc::AutomaticSearch`, `$mc::LockReferenceBase`, `$mc::ChooseReferenceBase` in ns `::application::vars` — but the file's own `namespace eval mc` block (:31-34) is **empty**; the strings live in `::application::tree::mc` (app-tree.tcl:35-45). Right-click in the variation window → immediate 'no such variable'.

### BC-8: Tree-panel right-click menu — cross-namespace mc strings + wrong proc address
**File:** `tcl/app-tree.tcl:1689,1690,1742`
- `$mc::AnalyzeThisPosition` (:1689) and `$mc::HighlightNovelties` (:1742) are defined only in `::application::analysis::mc` (app-analysis.tcl:66,82), not `::application::tree::mc`. First deref aborts the `PopupMenu` build (bound to `<<TableMenu>>` at :411) → **entire tree-panel context menu broken**.
- `[namespace code [list AnalyzePosition …]]` (:1690) resolves to `::application::tree::AnalyzePosition`; the proc is `::application::analysis::AnalyzePosition` (app-analysis.tcl:1781) → invalid command on click.

### BC-9: Repertoire wiring — wrong namespaces on procs and strings
- `tcl/app-analysis.tcl:1867` — calls `::gamebar::findTemporaryPosition`; the proc is `::application::database::findTemporaryPosition` (app-database-repertoire.tcl:471). Trigger: analysis-panel "Pin best line to repertoire" button (:445).
- `tcl/app-analysis.tcl:1832-1833` — `$mc::NoRepertoireBases`/`$mc::NoRepertoireBasesDetail` in `::application::analysis`; defs are `::application::database::mc::*` (app-database-repertoire.tcl:37-38). Same button, no-repertoire branch.
- `$::gamebar::mc::NoRepertoireBases` at `tcl/app-database-repertoire.tcl:462,531` and `tcl/app-db-players.tcl:912,921,968` — `::gamebar::mc` has no such var anywhere. Breaks add-to-repertoire menu construction (P1 at the repertoire sites; P2 at the prep-report fallbacks).

### BC-10: Gamebar "Re-load current game" always errors
**File:** `tcl/widgets/gamebar.tcl:1852`
`$::engine::mc::ThrowAwayChanges` — nonexistent (tcl/ + lang files). The real symbol is `::application::mc::ThrowAwayAllChanges` (application.tcl:48). Menu entry wired at :1594-1597 → errors on every click.

### BC-11: Crosstable context menu build aborts
**File:** `tcl/crosstable.tcl:1391`
`$::widget::mc::Next` — no such var; should be `$::widget::mc::Label(next)` (widgets/misc.tcl:34; the accelerator on the adjacent line :1395 already uses `Label(next)`). Inside `PopupMenu` (:1588, bound `<ButtonPress-3>` :298).

### BC-12: Player-card right-click menu — wrong mc namespace
**File:** `tcl/player-card.tcl:853`
`[set mc::Show[string toupper $opt 0 0]]` in ns `::playercard` → `::playercard::mc::ShowHtml`/`ShowLog` missing; the parallel block at :754 correctly uses `::crosstable::mc::Show…` (defs crosstable.tcl:81-82).

### BC-13: `newAnalysisPane` called at wrong address + `active?` arity mismatch
- `tcl/app-db-players.tcl:1577` (`::application::analysis::newAnalysisPane`) and `tcl/app-analysis.tcl:1804` (unqualified from `::application::analysis`) — the proc is `::application::newAnalysisPane` (application.tcl:410); no `namespace path` set. Trigger: prep-report "Analyze position" / tree-menu AnalyzePosition.
- Same paths: `active?` called with 0 args (app-analysis.tcl:1799; app-db-players.tcl:1574) but `proc active? {number}` (app-analysis.tcl:539) → wrong-#-args error.

---

## P2 — error paths, leaks, rarer UI paths

### BC-14: `db_maintenance` leaks async block-file readers + workers when a worker throws (commit 4ca81d1)
**File:** `src/db/db_maintenance.cpp:410-418` (worst), also :325-331, :465-472
`group.join()` re-throws the first worker exception **before** the caller's cleanup loops (`db.closeAsyncReader(readers[i])`, `delete workers[i]`). Pre-refactor code joined, cleaned up unconditionally, then raised. A corrupt game throwing in `resolveDuplicateRange` leaves all N `BlockFileReader`s registered in `BlockFile::m_asyncViews` (`src/util/u_block_file.cpp:980-984`; only `closeAsyncReader` removes them) — repeated failed "find duplicates" runs accumulate live views. Phases 1/3 leak only heap workers (P3).
**Fix:** join-without-throw, clean up, then rethrow (or RAII the readers/workers).

### BC-15: ECO-table OK button calls nonexistent `::scrolledtable::activeIndex`
**File:** `tcl/ecotable.tcl:299` — scrolledtable.tcl has `active` (:440) and `index` (:448), no `activeIndex` anywhere. Wired to the ECO-table dialog OK button (:211).

### BC-16: `$::fsbox::mc::CannotOpenTrashFiles` undefined
**File:** `tcl/widgets/database-switcher.tcl:1233` — no such string exists (adjacent `CannotOpenUri`/`InvalidUri` do). Trigger: `ParseUriFiles` when dropped/opened URIs include trashed files.

### BC-17: Search-presets block in app-db-games.tcl is global + its mc strings are misplaced (latent)
**File:** `tcl/app-db-games.tcl:499-704` (namespaces close at :498)
Same pattern as BC-6: global procs; `$mc::SaveCurrentSearch` etc. (:607-667) resolve to missing `::mc::*`; the string values were dumped at `::application::analysis` namespace top level **outside any mc block** (app-analysis.tcl:1904-1913). Currently latent — `ShowSearchPresetsMenu` has no caller. Likewise `SetupMultiEngineAnalysis` (app-analysis.tcl:1939-2058) has no caller but hits BC-4's `::ui::message` if ever wired.

### BC-18: `$mc::CannotCreateDirectory` undefined in `::font`
**File:** `tcl/fonts.tcl:2355` — trigger: ChessBase-font install when `~/.fonts` mkdir fails.

### BC-19: `$mc::CannotOpenCursorFiles` referenced from child ns `::application::pgn::cursor`
**File:** `tcl/app-pgn.tcl:3257,3274` — def is `::application::pgn::mc::CannotOpenCursorFiles` (:74); qualified `mc::` lookup from the child ns doesn't see the parent's. Fires when cursor files are unreadable.

---

## P3 — hardening / cosmetic / notes

### BC-20: `~ThreadGroup` can `std::terminate` via M_RAISE during unwinding
**File:** `src/sys/sys_thread_group.cpp:37-40` — dtor calls `join()`, which ends in `M_RAISE` if a worker threw. An exception between `start()` and `join()` at a call site (e.g. `bad_alloc`, throw from `db.openAsyncReader`) unwinds → dtor joins → if a worker also threw, throw-during-unwind → terminate. **Fix:** dtor should join-and-swallow (log).

### BC-21: `ThreadGroup::start` leaks a *running* thread if `push_back` throws
**File:** `src/sys/sys_thread_group.cpp:57-70` — `thread->start(runnable)` succeeds, then `m_threads.push_back` can throw `bad_alloc`; the thread is never joined/deleted and keeps running against state that unwinds. bad_alloc-only. **Fix:** reserve() up front or push before start.

### BC-22: "José" theme name corrupted to U+FFFD (UNCOMMITTED)
**File:** `tcl/start.tcl:142` — the `é` byte was replaced by the UTF-8 replacement character (editor re-encode accident). `::themes::update` no longer matches the "José" board theme → silently skipped by migration/cleanup.

### BC-23: `databaseName` shows doubled suffix for `.pgn.gz`
**File:** `tcl/start.tcl:573-592` — `ext` is now `.pgn.gz` but `file rootname` strips only `.gz`, so `games.pgn.gz` displays as "games.pgn .pgn" (old code showed "games.pgn .gz" — also wrong; not a regression, fix incomplete).

### BC-24: `src/check-build.tcl` fallback passes without exercising the app layer (UNCOMMITTED)
**Lines 6-13** — if `::scidb::app::initialized?` is absent, "OK" is printed whenever `::zlib::crc` exists; running under the wrong interpreter now yields a pass. Also: no `make check-build` target exists anywhere, so nothing invokes this script.

### BC-25: `tooltip::x11DropShadow` forwards to nonexistent `::x11::dropShadow`
**File:** `tcl/end.tcl:112` — `namespace eval x11` (:89) defines only makeFrameless/makeToolbar/changeDesktop. Latent — no in-tree caller found.

### BC-26: `genderbox` accelerator-collision path uses undefined `$mc::Female`/`$mc::Computer`
**File:** `tcl/widgets/genderbox.tcl:228,233` — `::genderbox::mc` defines only the `Gender(…)` array. Locale-dependent (non-English accelerator collisions only). Possibly pre-existing upstream.

### BC-27: gamebar exportGame `.pgn.gz` extension value changed (behavior note, UNCOMMITTED)
**File:** `tcl/widgets/gamebar.tcl:834` — now passes `pgn.gz` where old code passed `gz`; export.tcl (:690, :3037) treats both as default. Likely intentional; no regression.

---

## Verified clean
- **Split losslessness (e341859 + 235fcb3 + 16e39cc):** all 300+ procs except BC-3; all 325 mc name+value pairs verbatim; file-scope arrays/variables correctly homed; all top-level side effects (options hookWriter, UndockingNotebook bindings, icons) in core; Makefile load order correct (8 files, core first, distinct source guards); zero duplicate definitions across split files; only 4 proc-body diffs vs monolith, all from the fileExtension refactor (BC-1 covers the broken one).
- **ThreadGroup core semantics:** joins all threads before rethrow; first-exception-wins matches old code; exception slot race-free (pthread_join happens-before); work partitioning byte-identical; per-worker state still private; parallel dup-detection still gated on `db.isReadonly()`.
- **Tree-identity refactor (except BC-2):** element order/count agree; empty-ECO handled (5-or-6-element list); 15-byte ECO truncation gone; listObj refcounting correct; no old pipe-format remnants anywhere.
- **382943b** (db_writer snprintf) and **ff1100a** (parseRange strtol — base 10, endptr, saturation all handled) clean.
- **Uncommitted diff:** configure `package vcompare` fix correct; `::util::fileExtension` helper itself correct; menu.tcl/archive.tcl/fileselectionbox.tcl/fsbox.tcl/database-switcher.tcl dotted-pattern updates all consistent (several previously-dead `.pgn.gz` branches now reachable); proxy-parsing rewrite in web.tcl/update-photos.tcl strictly better than old logic; board.tcl exec quoting valid.
- **Symbol sweep near-misses cleared:** `array set` definitions (annotation::sections, font::mapCodeToNag), icon families, lazy fsbox icons, `mc::T_$t`-style dynamic names, guarded dead migration code in end.tcl.
