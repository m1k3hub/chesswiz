# Fixit Plan — Bug Catalog 2026-07-02
Derived from: BUG_CATALOG_2026-07-02.md
Plan date: 2026-07-02

## Overview

27 bugs total: **13 P1** (broken features/startup), **6 P2** (error paths/leaks),
**8 P3** (hardening/cosmetic). Four root-cause patterns account for most of them:

| Pattern | Bugs | Description |
|---------|------|-------------|
| (a) code after namespace closers | BC-6, BC-17 | procs/vars left global; mc derefs resolve to `::mc::*` |
| (b) mc strings in wrong namespace | BC-7, BC-8, BC-9, BC-12, BC-16, BC-18, BC-19 | defined in panel X, consumed from panel Y |
| (c) wrong proc address / arity | BC-3, BC-9, BC-10, BC-11, BC-13, BC-15 | stale namespace paths after split |
| (d) dotted vs dotless extension | BC-1, BC-23 | `::util::fileExtension` returns dotted, consumers expect dotless |

Plus: BC-2 (hex/decimal format mismatch), BC-4 (phantom `::ui::message`),
BC-5 (malformed switch + missing proc at source time), BC-14/BC-20/BC-21 (ThreadGroup C++ issues).

---

## Phase 1 — P1 Critical (startup blockers + totally broken features)

These must be fixed before anything else; several prevent the app from even
loading on certain platforms (BC-5 on X11) or make core features non-functional
(BC-1: can't open any database).

### 1.1 BC-5 — app-pgn.tcl source-time crash on X11 (2 sub-fixes)

**File:** `tcl/app-pgn.tcl:3242-3259`

**Sub-fix A — malformed switch:** The `variable collapse` / `variable expand`
lines are inside the `switch [tk windowingsystem]` body, parsed as pattern/body
pairs. Move them above the `switch`:

```tcl
namespace eval cursor {
	variable collapse {}
	variable expand {}

	switch [tk windowingsystem] {
		x11 {
			...
		}
		win32 - aqua {
			...
		}
	}
}
```

**Sub-fix B — missing `::xcursor::supported?`:** Add a proc to
`tcl/utils/xcursor.tcl` (returns 1 if any cursor-loading mechanism is available,
0 otherwise — since `loadCursor` exists, `supported?` can simply return 1, or
check for the xcur shared-file directory). Also called at `tcl/setup-board.tcl:1659`.

**Effort:** ~15 min
**Test:** `source tcl/app-pgn.tcl` on X11 without error; cursor setup in board
dialog works.

---

### 1.2 BC-1 — openBase extension mismatch (dotless consumers)

**File:** `tcl/app-database.tcl:469`

The uncommitted line `set ext [::util::fileExtension $file]` overwrites the
dotless `ext` (from `mapExtension`) with a dotted value. All downstream
comparisons use dotless (`sci`, `pgn.gz`, etc.).

**Fix:** Remove line 469 entirely. The dotless `ext` computed at lines 462-467
is correct and consumed correctly by all downstream code. The other refactored
sites (newBase, OpenArchive, etc.) were correctly updated to dotted patterns;
this one was simply not needed — `openBase` already normalizes to dotless.

**Alternative (if the dotted helper is desired for consistency):** Convert all
comparisons in `openBase` to dotted (`.sci`, `.pgn.gz`, etc.) — but this is
more invasive and risk-prone. Prefer removal.

**Effort:** ~5 min (1-line deletion)
**Test:** Open `.sci`, `.si4`, `.pgn`, `.pgn.gz`, `.zip` databases; verify
readonly/upgrade logic for `.sci`.

---

### 1.3 BC-4 — `::ui::message` defined nowhere (14 call sites)

**Files:** `tcl/app-analysis.tcl` (10 sites), `tcl/app-db-games.tcl` (2),
`tcl/app-db-players.tcl` (1), `tcl/app-tree.tcl` (1)

No definition exists anywhere. Several call sites are inside `trap`/error
handlers, masking the original error.

**Fix:** Define a minimal `::ui::message` proc. Based on usage patterns (status
notifications, not modal dialogs), it should write to the status bar or log.
Add to `tcl/application.tcl` (top-level namespace, near other UI utilities) or
a new small `tcl/utils/ui.tcl`:

```tcl
proc ::ui::message {text} {
	::log::info UI $text
	# Or: update status bar if one exists
}
```

Check if there's a status-bar mechanism (e.g. `::statusbar::show`) to use
instead of just logging. If the intent was a toast/status message, wire to that.

**Effort:** ~20 min (define proc + verify all 14 call sites make sense with it)
**Test:** Exercise analysis pin, novelty highlight, search preset save — verify
message appears (in log or status bar) instead of `invalid command name`.

---

### 1.4 BC-6 — Opponent Dossier block outside all namespaces

**File:** `tcl/app-db-players.tcl:1587-2311` (after closers at :1581-1583)

The entire Opponent Dossier block (`RefreshOpponentDossier`,
`BuildOpponentDossier`, `PopulateOpponentDossier`, `OpenOpponentDossier`, etc.)
is global. ~35 `$mc::*` derefs resolve to missing `::mc::*`; unqualified calls
to player-ns procs fail; `variable PrepReportData` binds wrong scope.

**Fix:** Move the block inside the player namespace. Concretely:
1. Cut lines 1587–2311 (everything after the three `} ;# namespace` closers and
   the `vi:set` comment).
2. Paste them **before** line 1581 (`} ;# namespace player`), i.e. inside
   `::application::database::player`.
3. Verify that `variable` declarations and unqualified proc calls now resolve
   correctly within the player namespace.

**Effort:** ~30 min (mechanical move + verify indentation + spot-check symbols)
**Test:** Open opponent dossier from prep-report; verify title, data population,
all referenced procs resolve.

---

### 1.5 BC-2 — Tree-row identity hex vs decimal format mismatch

**Files:** `src/app/app_application.cpp:2245` (producer), `src/tcl/tcl_view.cpp:567` (consumer)

Producer: `out.identity.format("%llx %u %u %u %u %s", ...)` — bare hex.
Consumer: `Tcl_GetWideIntFromObj` — accepts decimal or `0x`-prefixed only.
Hex digits a–f → parse error; all-digit hex → wrong decimal value.

**Fix (recommended by auditor):** Change producer to format the hash as signed
decimal: `(long long)hash`. On the consumer side, `Tcl_GetWideIntFromObj` will
parse it correctly; cast back to `uint64_t` for comparison.

**Producer change** (`app_application.cpp:2245`):
```cpp
out.identity.format("%lld %u %u %u %u %s",
    static_cast<long long>(tree->hash()),
    ...);
```

**Consumer change** (`tcl_view.cpp:567`): After `Tcl_GetWideIntFromObj(&hash)`,
cast: `uint64_t realHash = static_cast<uint64_t>(hash);` and use `realHash` in
the comparison at `app_application.cpp:2300`.

Also verify the comparison site at `app_application.cpp:2300` uses the same
cast.

**Effort:** ~30 min (C++ change + verify round-trip for hashes with a–f digits,
all-digit hashes, and hashes ≥ 2^63)
**Test:** Opening-prep "apply filter" works; tree identity round-trips correctly.

---

### 1.6 BC-3 — `RatingDialogName` dropped by search sub-split

**File:** `tcl/app-database-search-rating.tcl:440`

`OpenRatingSearch` calls `RatingDialogName`, which was dropped in commit 235fcb3.
No definition exists anywhere.

**Fix:** Add the proc, mirroring `MaterialDialogName` in
`app-database-search-material.tcl:33`. Add near the top of the
`namespace eval database` block (after line 30):

```tcl
proc RatingDialogName {file variant} {
	return .rating_[string map {: _ . _ / _} $file]_${variant}
}
```

**Effort:** ~5 min
**Test:** Open Rating Search dialog; verify no `invalid command name`.

---

### 1.7 BC-8 — Tree-panel right-click menu (mc strings + wrong proc address)

**File:** `tcl/app-tree.tcl:1689,1690,1742`

- `$mc::AnalyzeThisPosition` (:1689) and `$mc::HighlightNovelties` (:1742) are
  in `::application::analysis::mc`, not `::application::tree::mc`.
- `[namespace code [list AnalyzePosition …]]` (:1690) resolves to
  `::application::tree::AnalyzePosition` but the proc is
  `::application::analysis::AnalyzePosition`.

**Fix:**
1. Either move/add the mc string defs to `::application::tree::mc`, or qualify
   the derefs as `$::application::analysis::mc::AnalyzeThisPosition` and
   `$::application::analysis::mc::HighlightNovelties`. **Prefer qualifying** —
   the strings logically belong to the analysis panel.
2. Change `:1690` to use the fully-qualified proc:
   `[list ::application::analysis::AnalyzePosition $table $row]` (drop
   `namespace code` since it's cross-namespace).

**Effort:** ~10 min
**Test:** Right-click tree panel → context menu appears with "Analyze this
position" and "Highlight novelties"; clicking Analyze opens analysis pane.

---

### 1.8 BC-7 — Variation-window right-click menu (empty mc block)

**File:** `tcl/app-variation.tcl:591,596,606,612,619`

mc block at :31-34 is empty; strings live in `::application::tree::mc`
(app-tree.tcl:35-45). Deref `$mc::StartSearch` etc. → 'no such variable'.

**Fix:** Either populate the `::application::vars::mc` block with the needed
strings, or qualify the derefs as `$::application::tree::mc::StartSearch` etc.
Since the strings are identical to the tree panel's, **qualify the derefs** to
avoid duplication:

- `$mc::StartSearch` → `$::application::tree::mc::StartSearch`
- `$mc::UseExactMode` → `$::application::tree::mc::UseExactMode`
- `$mc::UseFastMode` → `$::application::tree::mc::UseFastMode`
- `$mc::AutomaticSearch` → `$::application::tree::mc::AutomaticSearch`
- `$mc::LockReferenceBase` → `$::application::tree::mc::LockReferenceBase`
- `$mc::ChooseReferenceBase` → `$::application::tree::mc::ChooseReferenceBase`

Verify exact variable names against app-tree.tcl:35-45.

**Effort:** ~15 min
**Test:** Right-click in variation window → menu appears with all entries.

---

### 1.9 BC-9 — Repertoire wiring (wrong namespaces on procs and strings)

**Files:** `tcl/app-analysis.tcl:1832-1833,1867`; `tcl/app-database-repertoire.tcl:462,531`;
`tcl/app-db-players.tcl:912,921,968`

Three sub-issues:
1. `::gamebar::findTemporaryPosition` (:1867) → should be
   `::application::database::findTemporaryPosition`.
2. `$mc::NoRepertoireBases`/`$mc::NoRepertoireBasesDetail` (:1832-1833) in
   `::application::analysis` → defs in `::application::database::mc` (repertoire
   file :37-38). Qualify as `$::application::database::mc::NoRepertoireBases`
   and `...::NoRepertoireBasesDetail`.
3. `$::gamebar::mc::NoRepertoireBases` at repertoire :462,531 and players
   :912,921,968 → should be `$::application::database::mc::NoRepertoireBases`.

**Effort:** ~15 min
**Test:** Analysis "Pin best line to repertoire" with no repertoire bases →
dialog shows correct message; add-to-repertoire menu works.

---

### 1.10 BC-10 — Gamebar "Re-load current game" error

**File:** `tcl/widgets/gamebar.tcl:1852`

`$::engine::mc::ThrowAwayChanges` → nonexistent. Real symbol:
`::application::mc::ThrowAwayAllChanges` (application.tcl:48).

**Fix:** Change to `$::application::mc::ThrowAwayAllChanges`.

**Effort:** ~5 min
**Test:** Click "Re-load current game" with unsaved changes → confirmation
dialog appears with correct message.

---

### 1.11 BC-11 — Crosstable context menu `$::widget::mc::Next` undefined

**File:** `tcl/crosstable.tcl:1391`

Should be `$::widget::mc::Label(next)` (widgets/misc.tcl:34; the accelerator on
:1395 already uses `Label(next)`).

**Fix:** Change `$::widget::mc::Next` → `$::widget::mc::Label(next)`.

**Effort:** ~2 min
**Test:** Right-click crosstable → "Next" menu entry appears.

---

### 1.12 BC-12 — Player-card right-click menu wrong mc namespace

**File:** `tcl/player-card.tcl:853`

`[set mc::Show[string toupper $opt 0 0]]` in `::playercard` → missing. Parallel
block at :754 correctly uses `::crosstable::mc::Show…`.

**Fix:** Change to `[set ::crosstable::mc::Show[string toupper $opt 0 0]]`.

**Effort:** ~2 min
**Test:** Right-click player card → "Show Log"/"Show HTML" entries appear.

---

### 1.13 BC-13 — `newAnalysisPane` wrong address + `active?` arity mismatch

**Files:** `tcl/app-db-players.tcl:1574,1577`; `tcl/app-analysis.tcl:1799,1804`

- `::application::analysis::newAnalysisPane` → proc is `::application::newAnalysisPane`.
  Both call sites need `::application::newAnalysisPane`.
- `[active?]` called with 0 args but `proc active? {number}` requires 1 arg.
  At `app-analysis.tcl:1799`: need to pass the analysis number. At
  `app-db-players.tcl:1574`: need to pass the current analysis pane number.

**Fix:**
1. `app-analysis.tcl:1804`: `newAnalysisPane` → `::application::newAnalysisPane`.
2. `app-db-players.tcl:1577`: `::application::analysis::newAnalysisPane` →
   `::application::newAnalysisPane`.
3. `app-analysis.tcl:1799` and `app-db-players.tcl:1574`: Determine the correct
   analysis number to pass to `active?`. In `app-analysis.tcl`, the proc is
   inside `::application::analysis`, so `$Vars(number)` or similar should
   provide it. In `app-db-players.tcl`, need to determine which analysis pane
   is active.

**Effort:** ~20 min (need to trace what number to pass to `active?` at each site)
**Test:** Prep-report "Analyze position" / tree-menu AnalyzePosition → analysis
pane opens without error.

---

## Phase 2 — P2 (error paths, leaks, rarer UI)

### 2.1 BC-14 — db_maintenance leaks async readers + workers on worker exception

**File:** `src/db/db_maintenance.cpp:410-418` (worst), also :325-331, :465-472

`group.join()` rethrows before the caller's cleanup loop. Pre-refactor:
joined, cleaned up unconditionally, then raised.

**Fix:** Wrap each `group.join()` + cleanup in try/catch:

```cpp
try {
	group.join();
} catch (...) {
	// cleanup first, then rethrow
	for (unsigned i = 0; i < workers.size(); ++i) {
		delete workers[i];
		db.closeAsyncReader(readers[i]);
	}
	throw;
}
// normal cleanup
for (unsigned i = 0; i < workers.size(); ++i) {
	appendDuplicateGroups(result, workers[i]->groups);
	delete workers[i];
	db.closeAsyncReader(readers[i]);
}
```

Apply the same pattern to all three sites (:325-331, :410-418, :465-472).
The :325 and :465 sites leak only heap workers (no readers), but still need
the try/catch for cleanup.

**Alternative:** Add a `joinNoThrow()` method to ThreadGroup that joins all,
collects the exception message, but doesn't raise. Then the caller checks
and raises after cleanup. This avoids try/catch boilerplate at 3 sites but
changes the ThreadGroup API.

**Preferred:** Add `ThreadGroup::joinAndCollect(mstl::string& failMsg)` or
make `join()` set an error flag instead of throwing, then have callers raise
after cleanup. This matches pre-refactor semantics most cleanly.

**Effort:** ~45 min
**Test:** Run "find duplicates" on a database with a corrupt game → verify no
reader leak (check BlockFile::m_asyncViews count before/after).

---

### 2.2 BC-15 — ECO-table OK button calls nonexistent `activeIndex`

**File:** `tcl/ecotable.tcl:299`

`::scrolledtable::activeIndex` doesn't exist. scrolledtable has `active`
(returns active row) and `index` (returns selection index).

**Fix:** Looking at the context:
```tcl
set index [::scrolledtable::activeIndex $w.table]
```
The proc needs to return the index of the active/selected row. Based on
`scrolledtable::active` (returns active row) and `scrolledtable::index`
(returns selection), and the existing `rowToIndex` proc (:481), the correct
replacement is likely:
```tcl
set row [::scrolledtable::active $w.table]
set index [::scrolledtable::rowToIndex $w.table $row]
```
Or check if `::scrolledtable::index` directly gives what's needed. Verify
against how `CurrentSelection` uses the result.

**Effort:** ~15 min
**Test:** Open ECO table dialog, select a row, click OK → correct ECO code
returned.

---

### 2.3 BC-16 — `$::fsbox::mc::CannotOpenTrashFiles` undefined

**File:** `tcl/widgets/database-switcher.tcl:1233`

No such string. Adjacent `CannotOpenUri`/`InvalidUri` exist.

**Fix:** Add the mc string to the fsbox mc namespace. Find where
`CannotOpenUri` is defined and add nearby:
```tcl
set CannotOpenTrashFiles "Cannot open trashed files."
```
Or, if the feature (opening trashed files) isn't supported, change the message
to reuse `CannotOpenUri` or a more generic message.

**Effort:** ~10 min
**Test:** Drop/open URIs that include trashed files → error dialog appears
with correct message.

---

### 2.4 BC-17 — Search-presets block global + misplaced mc strings (latent)

**File:** `tcl/app-db-games.tcl:499-704` (after closers at :498)

Same pattern as BC-6. Currently latent (no caller for
`ShowSearchPresetsMenu`). The mc strings were dumped at
`::application::analysis` top level outside any mc block
(app-analysis.tcl:1904-1913).

**Fix:**
1. Move the search-presets block (499-704) inside the `::application::database`
   namespace (before `} ;# namespace database` at :497).
2. Move the mc string definitions from app-analysis.tcl:1904-1913 into an
   appropriate `mc` block (either `::application::database::mc` or a new
   `::application::database::searchPresets::mc`).

Since this is latent, it's lower priority but should be fixed to prevent
future wiring from hitting the same errors.

**Effort:** ~25 min
**Test:** N/A (latent) — verify no regressions from the move; source the file
without error.

---

### 2.5 BC-18 — `$mc::CannotCreateDirectory` undefined in `::font`

**File:** `tcl/fonts.tcl:2355`

Trigger: ChessBase-font install when `~/.fonts` mkdir fails.

**Fix:** Add the mc string to the `::font::mc` namespace:
```tcl
set CannotCreateDirectory "Cannot create directory '%s'."
```
Find the `namespace eval mc` block in fonts.tcl and add it there.

**Effort:** ~5 min
**Test:** Simulate mkdir failure → error dialog with correct message.

---

### 2.6 BC-19 — `$mc::CannotOpenCursorFiles` child-ns lookup miss

**File:** `tcl/app-pgn.tcl:3257,3274`

Def is `::application::pgn::mc::CannotOpenCursorFiles` (:74), but called from
child ns `::application::pgn::cursor` as `$mc::...` which resolves to
`::application::pgn::cursor::mc` (doesn't exist) or `::mc` (missing).

**Fix:** Qualify the deref as `$::application::pgn::mc::CannotOpenCursorFiles`
at both :3257 and :3274.

**Effort:** ~5 min
**Test:** Make cursor files unreadable → error message appears.

---

## Phase 3 — P3 (hardening / cosmetic / notes)

### 3.1 BC-20 — `~ThreadGroup` can `std::terminate` during unwinding

**File:** `src/sys/sys_thread_group.cpp:37-40`

Dtor calls `join()`, which `M_RAISE`s if a worker threw. Exception during
unwind + throw → terminate.

**Fix:** Dtor should join without throwing:
```cpp
ThreadGroup::~ThreadGroup()
{
	try { join(); }
	catch (...) { /* log and swallow */ }
}
```
Or add a `joinNoThrow()` that logs the error but doesn't raise.

**Effort:** ~10 min
**Test:** Verify destructor doesn't terminate when a worker threw during
exception unwinding.

---

### 3.2 BC-21 — `ThreadGroup::start` leaks a running thread if `push_back` throws

**File:** `src/sys/sys_thread_group.cpp:57-70`

`thread->start()` succeeds, then `m_threads.push_back` can throw `bad_alloc`;
thread is never joined/deleted.

**Fix:** Reserve capacity up front, or push a placeholder before starting:
```cpp
bool ThreadGroup::start(Thread::Runnable const& runnable)
{
	Thread* thread = new Thread;
	m_threads.push_back(thread);  // may throw — but thread isn't started yet
	if (!thread->start(runnable))
	{
		m_threads.pop_back();
		delete thread;
		return false;
	}
	return true;
}
```
Or call `m_threads.reserve()` before the loop at call sites.

**Effort:** ~10 min
**Test:** Hard to test (requires `bad_alloc` injection); verify by code review.

---

### 3.3 BC-22 — "José" theme name corrupted to U+FFFD (UNCOMMITTED)

**File:** `tcl/start.tcl:142`

The `é` byte was replaced by U+FFFD (editor re-encode accident).

**Fix:** Replace the corrupted bytes with the correct UTF-8 for "José"
(`Jos\xc3\xa9`).

**Effort:** ~2 min
**Test:** Verify "José" theme matches in `::themes::update`.

---

### 3.4 BC-23 — `databaseName` doubled suffix for `.pgn.gz`

**File:** `tcl/start.tcl:573-592`

`file rootname` strips only `.gz`, so `games.pgn.gz` → `games.pgn .pgn.gz` →
after switch → `games.pgn .pgn` (doubled). Old code also showed wrong output.

**Fix:** Strip the compound extension properly:
```tcl
set ext [::util::fileExtension $name]
# For compound extensions like .pgn.gz, strip both parts
if {$ext eq ".pgn.gz" || $ext eq ".bpgn.gz"} {
	set name [file rootname [file rootname $name]]
} else {
	set name [file rootname $name]
}
```
Then the switch at :581 already maps `.pgn.gz` → display `.pgn`.

**Effort:** ~10 min
**Test:** Open `games.pgn.gz` → displays as "games.pgn .pgn" (or just
"games.pgn" if that's the desired display).

---

### 3.5 BC-24 — check-build.tcl fallback passes without exercising app layer

**File:** `tcl/check-build.tcl:6-13` (UNCOMMITTED)

If `::scidb::app::initialized?` is absent, "OK" is printed whenever
`::zlib::crc` exists. Also no `make check-build` target exists.

**Fix:**
1. Make the fallback stricter — if the app layer symbol is missing, fail
   with a clear message ("app layer not loaded — wrong interpreter?").
2. Add a `check-build` target to the Makefile.

**Effort:** ~15 min
**Test:** Run check-build under correct and wrong interpreters; verify pass/fail.

---

### 3.6 BC-25 — `tooltip::x11DropShadow` forwards to nonexistent proc (latent)

**File:** `tcl/end.tcl:112`

`::x11::dropShadow` doesn't exist; `namespace eval x11` (:89) defines only
makeFrameless/makeToolbar/changeDesktop. No in-tree caller found.

**Fix:** Either implement `::x11::dropShadow` (if the feature is desired) or
remove the forwarding proc (if it's dead code). Since no caller exists,
**remove** is safer. If keeping, make it a no-op with a comment.

**Effort:** ~5 min
**Test:** N/A (latent) — verify no regressions.

---

### 3.7 BC-26 — `genderbox` accelerator-collision path uses undefined mc vars

**File:** `tcl/widgets/genderbox.tcl:228,233`

`$mc::Female`/`$mc::Computer` undefined; `::genderbox::mc` defines only the
`Gender(…)` array. Locale-dependent (non-English accelerator collisions only).

**Fix:** Add the missing mc strings to `::genderbox::mc`, or change the derefs
to use `Gender(female)` / `Gender(computer)` array entries.

**Effort:** ~10 min
**Test:** Test with a locale where accelerator collision occurs (e.g. German).

---

### 3.8 BC-27 — gamebar exportGame extension value change (behavior note)

**File:** `tcl/widgets/gamebar.tcl:834` (UNCOMMITTED)

Now passes `pgn.gz` where old code passed `gz`; export.tcl treats both as
default. Likely intentional, no regression.

**Action:** No fix needed. Document for awareness.

---

## Execution Order

The recommended fix order minimizes context-switching and groups by
root-cause pattern:

### Sprint A — Extension + format mismatches (pattern d + BC-2)
1. **BC-1** — openBase extension (1-line delete, unblocks all DB opening)
2. **BC-23** — databaseName doubled suffix (same file: start.tcl)
3. **BC-22** — José theme encoding (same file: start.tcl)
4. **BC-2** — tree identity hex→decimal (C++, independent)

### Sprint B — Namespace escape fixes (pattern a)
5. **BC-6** — Opponent Dossier block (app-db-players.tcl, largest move)
6. **BC-17** — Search-presets block (app-db-games.tcl, latent)

### Sprint C — Missing proc definitions
7. **BC-3** — RatingDialogName (add proc)
8. **BC-4** — `::ui::message` (add proc)
9. **BC-5** — `::xcursor::supported?` + malformed switch

### Sprint D — mc namespace fixes (pattern b, batch by file)
10. **BC-7** — variation-window mc strings (app-variation.tcl)
11. **BC-8** — tree-panel mc strings + proc address (app-tree.tcl)
12. **BC-9** — repertoire mc strings + proc address (app-analysis.tcl + repertoire + players)
13. **BC-19** — cursor mc string (app-pgn.tcl)
14. **BC-18** — font mc string (fonts.tcl)
15. **BC-16** — trash files mc string (database-switcher.tcl)

### Sprint E — Wrong proc addresses / arity (pattern c)
16. **BC-10** — gamebar ThrowAwayChanges
17. **BC-11** — crosstable Next
18. **BC-12** — player-card Show*
19. **BC-13** — newAnalysisPane + active? arity
20. **BC-15** — ECO-table activeIndex

### Sprint F — C++ hardening (ThreadGroup)
21. **BC-14** — db_maintenance leak fix (call sites or API change)
22. **BC-20** — ~ThreadGroup terminate guard
23. **BC-21** — start() push_back leak

### Sprint G — Misc / latent / cosmetic
24. **BC-24** — check-build fallback
25. **BC-25** — x11DropShadow dead code
26. **BC-26** — genderbox mc vars
27. **BC-27** — no action (document only)

---

## Estimated Total Effort

| Sprint | Bugs | Est. Time |
|--------|------|-----------|
| A — Extension/format | 4 | ~45 min |
| B — Namespace escape | 2 | ~55 min |
| C — Missing procs | 3 | ~40 min |
| D — mc namespace | 6 | ~60 min |
| E — Wrong proc addresses | 5 | ~45 min |
| F — C++ hardening | 3 | ~65 min |
| G — Misc/cosmetic | 4 | ~30 min |
| **Total** | **27** | **~5.5 hrs** |

## Verification Checklist (post-fix)

- [ ] `source` all modified Tcl files without error on X11 and Win32
- [ ] Open `.sci`, `.si4`, `.pgn`, `.pgn.gz`, `.zip` databases (BC-1)
- [ ] Tree identity filter round-trips (BC-2)
- [ ] Rating Search dialog opens (BC-3)
- [ ] `::ui::message` calls don't error (BC-4)
- [ ] app-pgn.tcl sources on X11; board-setup cursors work (BC-5)
- [ ] Opponent Dossier opens from prep-report (BC-6)
- [ ] Variation-window right-click menu works (BC-7)
- [ ] Tree-panel right-click menu + AnalyzePosition works (BC-8)
- [ ] Repertoire pin/add works with and without repertoire bases (BC-9)
- [ ] Gamebar "Re-load current game" shows correct dialog (BC-10)
- [ ] Crosstable context menu "Next" appears (BC-11)
- [ ] Player-card "Show Log"/"Show HTML" appear (BC-12)
- [ ] Analysis pane opens from prep-report and tree menu (BC-13)
- [ ] "Find duplicates" on corrupt DB doesn't leak readers (BC-14)
- [ ] ECO table OK button returns correct code (BC-15)
- [ ] Rebuild `tcl/scidb-beta` (baked-in copy) with all Tcl fixes
- [ ] Full dangling-symbol sweep re-run to confirm zero new issues