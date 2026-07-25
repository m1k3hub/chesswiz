# Thermo-Nuclear Code Quality Review — Remedy Implementation Plan

## Overview

10 remedies in priority order. Each remedy is self-contained and can be
committed independently. Dependencies between remedies are noted where they
exist.

**Codebase:** ScidB chess database (`src/`, C++/Tcl, autotools build)

---

## Remedy 1: Extract `buildSearch()` + parsing helpers from `tcl_view.cpp`

**Goal:** Reduce `tcl_view.cpp` from 1,707 → under 1,000 lines by moving all
search-query parsing into a new translation unit.

### Files to create

#### `src/tcl/tcl_search.cpp` (new, ~650 lines)

Move these symbols from `tcl_view.cpp`:

| Symbol | Type | Current line |
|--------|------|-------------|
| `buildSearch()` | function | 174–596 |
| `decodeLiteralPattern()` | static function | 600–612 |
| `parseMaterialPart()` | static function | 617–700 |
| `parseMaterialSignature()` | static function | 702–751 |
| `parsePawnRange()` | static function | 753–783 |
| `parseRatingRange()` | static function | 785–816 |
| Forward declarations (lines 153–160) | — | removed from tcl_view.cpp |

`buildSearch()` must be callable from `tcl_view.cpp`, so it needs a public
declaration.

#### `src/tcl/tcl_search.h` (new, ~15 lines)

```cpp
#ifndef _tcl_search_included
#define _tcl_search_included

#include <tcl.h>

namespace db { class Database; }
namespace mstl { template <typename T> class ref_counted_ptr; }
namespace db { class Search; }
typedef mstl::ref_counted_ptr<db::Search> SearchP;

namespace tcl {
namespace search {

SearchP buildSearch(db::Database const& db, Tcl_Interp* ti, Tcl_Obj* query);

} // namespace search
} // namespace tcl

#endif
```

### Changes to `tcl_view.cpp`

1. **Remove** lines 152–160 (forward declarations of parse helpers).
2. **Remove** lines 174–816 (`buildSearch` + all parsing helpers + the second
   anonymous namespace block at line 597).
3. **Remove** the `SearchP` typedef at line 152 — it moves to `tcl_search.h`.
4. **Add** `#include "tcl_search.h"` to the include block.
5. **Change** the call site in `cmdSearch()` (line ~1180):
   ```cpp
   // Before:
   search = buildSearch(cursor.database(), ti, objv[5 + n]);
   // After:
   search = tcl::search::buildSearch(cursor.database(), ti, objv[5 + n]);
   ```
6. **Remove** now-unused includes that were only needed by the search code:
   `db_search.h` can stay (needed for `SearchP` in `cmdSearch`), but
   `u_match.h` may become unused — verify with a compile test.

### Changes to `src/tcl/Makefile`

Add `tcl_search.cpp` to `SRC_CXX`:
```makefile
SRC_CXX = \
    tcl_application.cpp \
    tcl_base.cpp \
    ...
    tcl_search.cpp \      # <-- new
    tcl_view.cpp \
    ...
```

After adding, run `make depend` in `src/tcl/` to regenerate dependency lines.

### Verification

- `wc -l src/tcl/tcl_view.cpp` must be < 1,000.
- `make -C src/tcl` compiles clean.
- `make -C src verify-maintenance` still passes (exercises search paths).

### Estimated tcl_view.cpp after: ~900 lines (removed ~800, added ~5)

---

## Remedy 2: Fix `verify_maintenance.cpp` `main()` indentation

**Goal:** Eliminate merge-artifact indentation that makes `main()` unreadable.

### Current state

Inside the `try` block, many lines have one extra leading tab. The pattern
looks like a 3-way merge that shifted indentation on some hunks but not
others. Example:

```cpp
	try
	{
		TclInterpreter tcl;
		initializeStatics();
		// ... some lines at correct indent (2 tabs) ...
			unsigned imported = created.importGames(reader, progress);  // 3 tabs!
			if (reader.errors != 0 || imported != 4)                      // 3 tabs!
		{                                                              // 2 tabs!
```

### Fix

Re-indent the entire `main()` function body. The correct indentation is:

- `try` body: 2 tabs
- `if` body: 3 tabs
- Nested `if` body: 4 tabs

Run `indent` or manually fix all lines from the `try {` through the closing
`}` of the try block. The catch blocks should be at 1 tab (same as `try`).

### Verification

- Visual inspection: all braces align at their matching indent level.
- Compile: `make -C src verify-maintenance` still builds.

### No behavioral change — pure formatting fix.

---

## Remedy 3: Collapse `verify_maintenance.cpp` `main()` boilerplate

**Goal:** Reduce `main()` from ~190 lines to ~50 lines by extracting a
verification helper.

### New helper (add above `main()`, in the anonymous namespace)

```cpp
// Runs a verification function, prints a labeled failure message, and
// cleans up both database files before returning 1. Returns 0 on success.
static int
runCheck(char const* label, bool (*fn)(), mstl::string const& file1,
         mstl::string const& file2)
{
    if ((*fn)())
        return 0;
    ::fprintf(stderr, "%s failed\n", label);
    cleanup(file1);
    cleanup(file2);
    return 1;
}
```

But the verify functions take different argument types (some take `Database&`,
some take `Database const&`, some take `mstl::string const&`). So use a
lambda-based approach instead:

```cpp
// Helper macro that reduces the 6-line boilerplate to 1 line.
// Assumes `filename` and `compactedFilename` are in scope.
#define CHECK(label, expr) \
    do { \
        if (!(expr)) { \
            ::fprintf(stderr, label " failed\n"); \
            cleanup(filename); \
            cleanup(compactedFilename); \
            return 1; \
        } \
    } while (0)
```

### Refactored `main()` body (inside try block)

```cpp
    CHECK("PGN import",
          reader.errors == 0 && created.importGames(reader, progress) == 4);
    // Note: importGames has side effects, so need slightly different pattern:
    // See "Alternative" below for the import case.
```

Actually, `importGames` returns the count and must be called even when we
check the result. So the import check stays inline, and everything else uses
`CHECK`:

```cpp
    {
        unsigned imported = created.importGames(reader, progress);
        CHECK("PGN import", reader.errors == 0 && imported == 4);
    }
    CHECK("Initial state", verifyInitialState(created));
    CHECK("Material search", verifyMaterialSearch(created));
    CHECK("Rating search", verifyRatingSearch(created));
    CHECK("Pattern search", verifyPatternSearch(created));
    CHECK("Custom-FEN decode round-trip", verifyDecodeRoundTrip(filename));
    CHECK("Parallel parity", verifyParallelParity(created));

    created.deleteGame(1, true);
    CHECK("Post-delete maintenance", verifyAfterDeletion(created));
    CHECK("Compaction flag", created.shouldCompact());

    Database compacted(compactedFilename, sys::utf8::Codec::utf8(),
                       storage::OnDisk, variant::Normal);
    created.compact(compacted, progress);
    compacted.close();
    created.close();

    Database reopened(filename, sys::utf8::Codec::utf8(),
                       permission::ReadWrite, progress);
    CHECK("Reopen index header", verifyIndexHeader(filename, 95, 4)
                               && verifyAttributes(filename, 4));
    CHECK("Reopen verification", verifyAfterDeletion(reopened));
    CHECK("Reopen material search", verifyMaterialSearch(reopened));
    CHECK("Reopen rating search", verifyRatingSearch(reopened));
    CHECK("Reopen pattern search", verifyPatternSearch(reopened));
    CHECK("Reopen parallel parity", verifyParallelParity(reopened));
    CHECK("Reopen compaction flag", reopened.shouldCompact());

    Database reopenedCompacted(compactedFilename, sys::utf8::Codec::utf8(),
                               permission::ReadWrite, progress);
    CHECK("Compacted index header", verifyIndexHeader(compactedFilename, 95, 3)
                                   && verifyAttributes(compactedFilename, 3));
    CHECK("Compacted database", verifyCompactedState(reopenedCompacted));
    CHECK("Compacted material search", verifyMaterialSearch(reopenedCompacted));
    CHECK("Compacted rating search", verifyRatingSearch(reopenedCompacted));
    CHECK("Compacted pattern search", verifyPatternSearch(reopenedCompacted));
    CHECK("Compacted should not need compaction", !reopenedCompacted.shouldCompact());

    reopenedCompacted.close();
    reopened.close();
    cleanup(filename);
    cleanup(compactedFilename);
    ::puts("maintenance verification passed");
    return 0;
```

**Note:** Some checks that need both `filename` and `compactedFilename`
cleanup use the macro as-is (both are always cleaned). Checks that only
need `filename` (before `compactedFilename` is created) also work because
`cleanup()` on a non-existent file is a no-op (verify this).

### Verification

- `main()` drops from ~190 lines to ~45 lines.
- All error messages preserved.
- `make -C src verify-maintenance` still passes.

### Depends on: Remedy 2 (fix indentation first, then refactor).

---

## Remedy 4: Create `requireArgs()` helper for `tcl_engine.cpp`

**Goal:** Eliminate ~25 repetitions of the 4-line arg-count guard pattern.

### New helper (add to anonymous namespace in `tcl_engine.cpp`)

```cpp
// Returns TCL_ERROR if objc doesn't match expected, with a proper usage
// message. Otherwise returns TCL_OK. Use as:
//   if (requireArgs(ti, objc, 2, "<engine-id>") != TCL_OK)
//       return TCL_ERROR;
static int
requireArgs(Tcl_Interp* ti, int objc, int expected, char const* usage)
{
    if (objc != expected)
    {
        Tcl_WrongNumArgs(ti, 1, ti->objv /* or use objv param */, usage);
        // Note: Tcl_WrongNumArgs needs objv; see signature below.
        return TCL_ERROR;
    }
    return TCL_OK;
}
```

**Problem:** `Tcl_WrongNumArgs` needs `objv`, which is a parameter of each
command handler but not available to a standalone helper. Two approaches:

#### Approach A: Pass `objv` through

```cpp
static int
requireArgs(Tcl_Interp* ti, int objc, Tcl_Obj* const objv[],
            int expected, char const* usage)
{
    if (objc != expected)
    {
        Tcl_WrongNumArgs(ti, 1, objv, usage);
        return TCL_ERROR;
    }
    return TCL_OK;
}
```

Usage in each handler:
```cpp
if (requireArgs(ti, objc, objv, 2, "<engine-id>") != TCL_OK)
    return TCL_ERROR;
```

This is 2 lines per handler vs the current 5 lines. Still verbose.

#### Approach B (preferred): Combined guard macro

```cpp
#define CHECK_ARGS(ti, objc, objv, expected, usage) \
    do { \
        if (objc != expected) { \
            Tcl_WrongNumArgs(ti, 1, objv, usage); \
            return TCL_ERROR; \
        } \
    } while (0)
```

Usage:
```cpp
CHECK_ARGS(ti, objc, objv, 2, "<engine-id>");
```

One line per handler. **This is the recommended approach.**

### For variable-arg commands (ranges like `objc != 4 && objc != 5`):

Extend the macro:
```cpp
#define CHECK_ARGS_RANGE(ti, objc, objv, min, max, usage) \
    do { \
        if (objc < (min) || objc > (max)) { \
            Tcl_WrongNumArgs(ti, 1, objv, usage); \
            return TCL_ERROR; \
        } \
    } while (0)
```

### Changes to each `cmd*` function in `tcl_engine.cpp`

Replace every block like:
```cpp
if (objc != 2)
{
    Tcl_WrongNumArgs(ti, 1, objv, "<engine-id>");
    return TCL_ERROR;
}
```
with:
```cpp
CHECK_ARGS(ti, objc, objv, 2, "<engine-id>");
```

Replace every block like:
```cpp
if (objc != 4 && objc != 5)
{
    Tcl_WrongNumArgs(ti, 1, objv, "<engine-id> ...");
    return TCL_ERROR;
}
```
with:
```cpp
CHECK_ARGS_RANGE(ti, objc, objv, 4, 5, "<engine-id> ...");
```

### Affected handlers (all in `tcl_engine.cpp`)

| Handler | Current guard | Replacement |
|---------|--------------|------------|
| `cmdLog` | `if (objc < 2)` | `CHECK_ARGS_RANGE(ti, objc, objv, 2, INT_MAX, ...)` — needs special handling |
| `cmdLog`/open | `if (objc != 4)` | `CHECK_ARGS(ti, objc, objv, 4, ...)` |
| `cmdLog`/close | `if (objc != 2)` | `CHECK_ARGS(ti, objc, objv, 2, ...)` |
| `cmdLog`/send | `if (objc != 3)` | `CHECK_ARGS(ti, objc, objv, 3, ...)` |
| `cmdProbe` | `if (objc != 4 && objc != 5)` | `CHECK_ARGS_RANGE(...)` |
| `cmdStart` | `if (objc != 8)` | `CHECK_ARGS(...)` |
| `cmdActivate` | `if (objc != 2)` | `CHECK_ARGS(...)` |
| `cmdSetFeatures` | `if (objc != 3)` | `CHECK_ARGS(...)` |
| `cmdSetOptions` | `if (objc != 4)` | `CHECK_ARGS(...)` |
| `cmdStop` | `if (objc != 2)` | `CHECK_ARGS(...)` |
| `cmdAnalyze` | `if (objc != 3 && objc != 5)` | `CHECK_ARGS_RANGE(...)` |
| `cmdList` | `if (objc != 1)` | `CHECK_ARGS(...)` |
| `cmdInfo` | `if (objc != 2)` | `CHECK_ARGS(...)` |
| `cmdInvoke` | `if (objc != 3)` | `CHECK_ARGS(...)` |
| `cmdClearHash` | `if (objc != 2)` | `CHECK_ARGS(...)` |
| `cmdCountLines` | `if (objc != 2)` | `CHECK_ARGS(...)` |
| `cmdKill` | `if (objc != 2)` | `CHECK_ARGS(...)` |
| `cmdPause` | `if (objc != 2)` | `CHECK_ARGS(...)` |
| `cmdResume` | `if (objc != 2)` | `CHECK_ARGS(...)` |
| `cmdOrdering` | `if (objc != 3)` | `CHECK_ARGS(...)` |
| `cmdMultiPV` | `if (objc != 3)` | `CHECK_ARGS(...)` |
| `cmdPriority` | `if (objc != 3)` | `CHECK_ARGS(...)` |
| `cmdActive` | `if (objc != 2)` | `CHECK_ARGS(...)` |
| `cmdVariant` | `if (objc != 2)` | `CHECK_ARGS(...)` |
| `cmdEmpty` | `if (objc != 3)` | `CHECK_ARGS(...)` |
| `cmdSnapshot` | `if (objc < 2 \|\| objc > 4)` | `CHECK_ARGS_RANGE(...)` |
| `cmdBind` | `if (objc != 2)` | `CHECK_ARGS(...)` |
| `cmdBound` | `if (objc != 2)` | `CHECK_ARGS(...)` |

Also apply the same pattern to `tcl_view.cpp` handlers:
| Handler | Current guard | Replacement |
|---------|--------------|------------|
| `cmdNew` | `if (objc != 8 && objc != 9)` | `CHECK_ARGS_RANGE(...)` |
| `cmdSearch` | `if (objc < 5)` + `if (objc < int(5 + n))` | Keep inline (n-dependent) |
| `cmdSetTreeFilter` | `if (objc != 4 && objc != 5)` | `CHECK_ARGS_RANGE(...)` |
| `cmdMap` | `if (objc != 5 && objc != 6)` | `CHECK_ARGS_RANGE(...)` |
| `cmdSubscribe` | `if (objc != 4 && objc != 5)` | `CHECK_ARGS_RANGE(...)` |
| `cmdUnsubscribe` | `if (objc != 4 && objc != 5)` | `CHECK_ARGS_RANGE(...)` |
| `cmdCopy` | `if (objc != 10)` | `CHECK_ARGS(...)` |
| `cmdPrint` | already has complex arg checking | Keep inline |

**Note:** `cmdLog` with `objc < 2` is a minimum-args check, not an exact
match. Use `CHECK_ARGS_MIN(ti, objc, objv, 2, ...)`:
```cpp
#define CHECK_ARGS_MIN(ti, objc, objv, min, usage) \
    do { \
        if (objc < (min)) { \
            Tcl_WrongNumArgs(ti, 1, objv, usage); \
            return TCL_ERROR; \
        } \
    } while (0)
```

### Where to define the macros

Add to `src/tcl/tcl_base.h` (in the `namespace tcl` block) so both
`tcl_engine.cpp` and `tcl_view.cpp` can use them. Or define them as
`static` functions in each file's anonymous namespace. Since they use
`return TCL_ERROR` (which is a function return, not a value), macros are
cleaner than functions here.

### Verification

- `wc -l src/tcl/tcl_engine.cpp` decreases by ~75 lines.
- Compile: `make -C src/tcl`.
- Behavioral: all arg-count error messages preserved.

---

## Remedy 5: Unify `parsePawnRange` and `parseRatingRange` into `parseRange`

**Goal:** Eliminate ~40 lines of duplicate range-parsing code.

### Current state

Both functions (in `tcl_view.cpp`, soon to be in `tcl_search.cpp`) parse
`"N"` or `"N-M"` into `(minValue, maxValue)`. They differ only in the max
allowed value: 15 for pawns, 4000 for ratings.

### New unified function

```cpp
static bool
parseRange(Tcl_Interp* ti, Tcl_Obj* obj, unsigned max,
            unsigned& minValue, unsigned& maxValue)
{
    mstl::string text(Tcl_GetString(obj));
    mstl::string::size_type sep = text.find('-');

    if (sep == mstl::string::npos)
    {
        int value;
        if (Tcl_GetIntFromObj(ti, obj, &value) != TCL_OK
            || value < 0 || value > int(max))
            return false;
        minValue = maxValue = unsigned(value);
        return true;
    }

    mstl::string lhs(text, 0, sep);
    mstl::string rhs(text, sep + 1);
    if (lhs.empty() || rhs.empty())
        return false;

    int low = ::atoi(lhs.c_str());
    int high = ::atoi(rhs.c_str());

    if (low < 0 || high < 0 || low > high || high > int(max))
        return false;

    minValue = unsigned(low);
    maxValue = unsigned(high);
    return true;
}
```

### Call site changes

In `buildSearch()` (or `tcl::search::buildSearch()`):

```cpp
// Material/pawns case — was:
if (!parsePawnRange(ti, rangev[0], whiteMin, whiteMax)
    || !parsePawnRange(ti, rangev[1], blackMin, blackMax))
// Becomes:
if (!parseRange(ti, rangev[0], 15, whiteMin, whiteMax)
    || !parseRange(ti, rangev[1], 15, blackMin, blackMax))

// Rating case — was:
if (!parseRatingRange(ti, objv[3], minA, maxA))
// Becomes:
if (!parseRange(ti, objv[3], 4000, minA, maxA))
```

### Delete

Remove `parsePawnRange()` and `parseRatingRange()` entirely.

### Depends on: Remedy 1 (these functions move to `tcl_search.cpp` first, then
are unified there).

---

## Remedy 6: Extract `EventName`/`SiteName`/`AnnotatorName` pattern into a helper

**Goal:** Collapse 3 copy-paste cases into one helper call.

### Current pattern (repeated 3× in `buildSearch()`)

```cpp
case EventName:
    if (objc != 2 || *Tcl_GetString(objv[1]) == '\0')
    {
        error(CmdSearch, "eventname", 0, "invalid query");
        return search;
    }
    {
        bool exact = false;
        mstl::string decoded = decodeLiteralPattern(Tcl_GetString(objv[1]), exact);
        search = new SearchEventName(decoded, exact);
    }
    break;
```

The only things that vary are:
- The error label string (`"eventname"`, `"sitename"`, `"annotatorname"`)
- The search class constructor (`SearchEventName`, `SearchSiteName`,
  `SearchAnnotatorName`)

### New helper

```cpp
// Returns a new SearchXxxName, or null on error (caller checks and returns).
// The `construct` lambda creates the specific search type.
template <typename T>
static SearchP
makeNameSearch(char const* label, Tcl_Obj* obj)
{
    char const* name = Tcl_GetString(obj);
    if (*name == '\0')
        return SearchP();  // signal error to caller

    bool exact = false;
    mstl::string decoded = decodeLiteralPattern(name, exact);
    return SearchP(new T(decoded, exact));
}
```

Usage:
```cpp
case EventName:
    if (objc != 2)
    {
        error(CmdSearch, "eventname", 0, "invalid query");
        return search;
    }
    search = makeNameSearch<SearchEventName>("eventname", objv[1]);
    if (!search)
        error(CmdSearch, "eventname", 0, "empty name");
    break;

case SiteName:
    if (objc != 2)
    {
        error(CmdSearch, "sitename", 0, "invalid query");
        return search;
    }
    search = makeNameSearch<SearchSiteName>("sitename", objv[1]);
    if (!search)
        error(CmdSearch, "sitename", 0, "empty name");
    break;

case AnnotatorName:
    if (objc != 2)
    {
        error(CmdSearch, "annotatorname", 0, "invalid query");
        return search;
    }
    search = makeNameSearch<SearchAnnotatorName>("annotatorname", objv[1]);
    if (!search)
        error(CmdSearch, "annotatorname", 0, "empty name");
    break;
```

This reduces each case from 10 lines to 8 and eliminates the inline
`decodeLiteralPattern` + `new T(...)` duplication. The `error` + `return`
still needs to be in the case (because `buildSearch` returns `search` which
is now null, and the caller checks).

**Alternative (cleaner):** Have `makeNameSearch` call `error()` directly:

```cpp
template <typename T>
static SearchP
makeNameSearch(char const* cmd, char const* label, int objc, Tcl_Obj* const objv[])
{
    if (objc != 2 || *Tcl_GetString(objv[1]) == '\0')
    {
        error(cmd, label, 0, "invalid query");
        return SearchP();
    }
    bool exact = false;
    mstl::string decoded = decodeLiteralPattern(Tcl_GetString(objv[1]), exact);
    return SearchP(new T(decoded, exact));
}
```

Usage:
```cpp
case EventName:
    search = makeNameSearch<SearchEventName>(CmdSearch, "eventname", objc, objv);
    break;

case SiteName:
    search = makeNameSearch<SearchSiteName>(CmdSearch, "sitename", objc, objv);
    break;

case AnnotatorName:
    search = makeNameSearch<SearchAnnotatorName>(CmdSearch, "annotatorname", objc, objv);
    break;
```

Each case is now 3 lines. **This is the recommended version.**

### Depends on: Remedy 1 (helper lives in `tcl_search.cpp`).

---

## Remedy 7: Replace `strchr('|')` heuristic in `cmdSetTreeFilter` with explicit subcommand

**Goal:** Make the API explicit instead of magic-string-dispatched.

### Current state (`tcl_view.cpp`, lines ~1199–1230)

```cpp
static int
cmdSetTreeFilter(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
    if (objc != 4 && objc != 5) { ... }

    unsigned n = objc == 5 ? 1 : 0;
    char const* database = stringFromObj(objc, objv, 1);
    variant::Type variant = n ? tcl::game::variantFromObj(objv[2]) : variant::Undetermined;
    unsigned view = unsignedFromObj(objc, objv, 2 + n);
    char const* rowOrIdentity = stringFromObj(objc, objv, 3 + n);
    Cursor& cursor = scidb->cursor(database, variant);

    if (::strchr(rowOrIdentity, '|'))
        // treat as identity string
    else
        // treat as row number
}
```

### Proposed API change

```
::scidb::view::setTreeFilter <database> ?<variant>? <view> -row <n>
::scidb::view::setTreeFilter <database> ?<variant>? <view> -identity <string>
```

### Refactored handler

```cpp
static int
cmdSetTreeFilter(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
    // setTreeFilter <database> ?<variant>? <view> -row <n>
    // setTreeFilter <database> ?<variant>? <view> -identity <string>
    if (objc != 6 && objc != 7)
    {
        Tcl_WrongNumArgs(ti, 1, objv,
            "<database> ?<variant>? <view> -row <n> | -identity <string>");
        return TCL_ERROR;
    }

    unsigned n = objc == 7 ? 1 : 0;
    char const* database    = stringFromObj(objc, objv, 1);
    variant::Type variant   = n ? tcl::game::variantFromObj(objv[2])
                                 : variant::Undetermined;
    unsigned view           = unsignedFromObj(objc, objv, 2 + n);
    char const* mode        = stringFromObj(objc, objv, 3 + n);
    char const* value       = stringFromObj(objc, objv, 4 + n);
    Cursor& cursor          = scidb->cursor(database, variant);

    if (::strcmp(mode, "-row") == 0)
    {
        unsigned row = unsignedFromObj(objc, objv, 4 + n);
        if (!scidb->setCurrentTreeRowFilter(cursor, view, row))
            return error(CmdSetTreeFilter, nullptr, nullptr,
                         "unable to apply tree row %u to view %u", row, view);
    }
    else if (::strcmp(mode, "-identity") == 0)
    {
        if (!scidb->setCurrentTreeRowFilter(cursor, view, mstl::string(value)))
            return error(CmdSetTreeFilter, nullptr, nullptr,
                         "unable to apply tree identity '%s' to view %u",
                         value, view);
    }
    else
    {
        return error(CmdSetTreeFilter, nullptr, nullptr,
                     "unknown mode '%s', expected -row or -identity", mode);
    }

    setResult(true);
    return TCL_OK;
}
```

### Tcl-side impact

Any Tcl code calling `setTreeFilter` must be updated to pass `-row` or
`-identity` instead of relying on the `|` heuristic. Search for callers:

```bash
grep -rn 'setTreeFilter' tcl/ src/ --include='*.tcl' --include='*.cpp'
```

### Verification

- Compile: `make -C src/tcl`.
- Test: find and run any Tcl tests that exercise setTreeFilter.
- Grep for all Tcl-side callers and update them.

---

## Remedy 8: Handle write failure in `app_engine.cpp` `send()`

**Goal:** Don't silently swallow `puts()` failures.

### Current code (`src/app/app_engine.cpp`, ~line 993)

```cpp
void
Engine::send(mstl::string const& msg)
{
    if (m_logStream && !msg.empty())
    {
        m_buffer.assign("> ", 2);
        m_buffer.append(msg);
        m_buffer.append('\n');
        m_logStream->write(m_buffer);
    }
    if (m_process->puts(msg) == -1)
    {
        m_process->close();
    }
}
```

### Proposed fix

```cpp
void
Engine::send(mstl::string const& msg)
{
    if (m_logStream && !msg.empty())
    {
        m_buffer.assign("> ", 2);
        m_buffer.append(msg);
        m_buffer.append('\n');
        m_logStream->write(m_buffer);
    }
    if (m_process->puts(msg) == -1)
    {
        // The write failed (pipe broken, engine crashed). Close the
        // process and log the failure so the caller knows the message
        // was not delivered.
        log(mstl::string("send failed: broken pipe"));
        m_process->close();
    }
}
```

The `log()` method already exists on `Engine` (line ~982) and writes to
`m_logStream` with a `! ` prefix. If `m_logStream` is null, the log is
silently dropped, which is acceptable — the `close()` itself is the
important side effect, and callers that check `isConnected()` will see
the process is gone.

**Alternative (more robust):** Also set `m_active = false`:

```cpp
    if (m_process->puts(msg) == -1)
    {
        log(mstl::string("send failed: broken pipe"));
        m_process->close();
        m_active = false;
    }
```

This ensures that subsequent `send()` calls don't attempt to write to a
closed pipe, and that `isConnected()` / `isActive()` return false
immediately rather than waiting for the async `exited()` callback.

### Verification

- Compile: `make -C src`.
- Manual test: kill an engine process mid-analysis, verify the log
  shows the failure and the UI doesn't hang.

---

## Remedy 9: Verify `updateTimeInfo()` override removal

**Goal:** Confirm the base class default is the intended behavior.

### Current state

- `tcl_engine.cpp`: The `updateTimeInfo()` override was removed (it sent
  time/depth/nodes info to Tcl via `sendInfo`).
- `app_engine.h` line 446: `virtual void updateTimeInfo();` — base class
  declares it virtual with a default.
- `app_engine.cpp` line 481: `void Engine::updateTimeInfo() {}` — default
  is a no-op.
- `app_uci_engine.cpp` line 863 and `app_winboard_engine.cpp` lines
  1364/1377/1388/1439: These call `updateTimeInfo()` on the base class,
  which now resolves to the no-op instead of the Tcl override.

### What to verify

1. **Is time info still sent to Tcl?** The removed override called
   `sendInfo(m_time, ...)` with depth/nodes/nps/tbhits. If there's another
   mechanism (e.g., `updateDepthInfo()` or `updateCurrMove()`) that
   sends this information, the removal is safe. If not, the Tcl UI loses
   real-time time/depth/nodes display.

   ```bash
   # Check if m_time is used elsewhere in tcl_engine.cpp:
   grep -n 'm_time' src/tcl/tcl_engine.cpp
   ```

2. **Is the override replaced by a different callback?** Check if any
   new `sendInfo` call was added that covers the same data.

3. **If the removal was intentional** (e.g., time info is now sent via a
   different mechanism, or the feature was removed): document it in a
   commit message or code comment.

4. **If the removal was accidental:** restore the override.

### Action

This is a verification task, not a code change. Check the git history:

```bash
git log --oneline -- src/tcl/tcl_engine.cpp | head -5
git show HEAD -- src/tcl/tcl_engine.cpp | grep -A5 -B5 'updateTimeInfo'
```

If intentional, add a comment near the base class declaration explaining
why the Tcl override was removed. If accidental, restore the 13-line
override block.

---

## Remedy 10: Use `SearchP` for `SearchOpOr`/`SearchOpAnd` to prevent leaks

**Goal:** Prevent memory leaks when a sub-query fails after siblings have
already been appended.

### Current code (`tcl_view.cpp` / `tcl_search.cpp`, `buildSearch()`)

```cpp
case Or:
{
    if (objc < 3) { ... }

    SearchOpOr* op = new SearchOpOr;    // raw pointer — leaks if a sub-query fails

    for (int i = 1; i < objc; ++i)
    {
        SearchP item(buildSearch(db, ti, objv[i]));
        if (!item)
            return SearchP();  // ← op and all appended items leak here

        op->append(item.release());
    }

    search = op;
    break;
}
```

`SearchOpOr` and `SearchOpAnd` both store children as `mstl::vector<SearchP>`
(ref-counted pointers). When `op` is raw `new` and a sub-query fails, `op`
is never deleted — the already-appended `SearchP` children leak (though
the `SearchP` objects themselves are ref-counted, the `SearchOpOr` wrapper
is not).

### Fix

Wrap the operator in `SearchP` from the start:

```cpp
case Or:
{
    if (objc < 3)
    {
        error(CmdSearch, Tcl_GetString(objv[0]), 0, "at least two queries expected");
        return SearchP();
    }

    SearchP op(new SearchOpOr);

    for (int i = 1; i < objc; ++i)
    {
        SearchP item(buildSearch(db, ti, objv[i]));
        if (!item)
            return SearchP();  // op goes out of scope, ref count drops to 0,
                                // SearchOpOr destructor cleans up appended children

        static_cast<SearchOpOr*>(op.get())->append(item.release());
    }

    search = op;
    break;
}
```

Same pattern for `And`:

```cpp
case And:
{
    if (objc < 3)
    {
        error(CmdSearch, Tcl_GetString(objv[0]), 0, "at least two queries expected");
        return SearchP();
    }

    SearchP op(new SearchOpAnd);

    for (int i = 1; i < objc; ++i)
    {
        SearchP item(buildSearch(db, ti, objv[i]));
        if (!item)
            return SearchP();

        static_cast<SearchOpAnd*>(op.get())->append(item.release());
    }

    search = op;
    break;
}
```

### Verification

- Compile: `make -C src/tcl`.
- Run `verify_maintenance` — exercises search paths (Material, Rating,
  Pattern) which may use Or/And.
- If available, run under Valgrind to confirm no leaks:
  ```bash
  valgrind --leak-check=full ./src/verify_maintenance
  ```

### Depends on: Remedy 1 (this code lives in `tcl_search.cpp` after
extraction).

---

## Dependency Graph

```
Remedy 1 (extract tcl_search.cpp)
├── Remedy 5 (unify parseRange)          [depends on 1]
├── Remedy 6 (makeNameSearch helper)     [depends on 1]
└── Remedy 10 (SearchP for Or/And)       [depends on 1]

Remedy 2 (fix verify_maintenance indent)  [independent]
└── Remedy 3 (collapse verify boilerplate) [depends on 2]

Remedy 4 (requireArgs macro)              [independent]
Remedy 7 (setTreeFilter subcommand)       [independent]
Remedy 8 (send() error handling)           [independent]
Remedy 9 (updateTimeInfo verification)    [independent]
```

## Recommended Commit Order

1. **Commit 1:** Remedy 2 — Fix `verify_maintenance.cpp` indentation
   (mechanical, no behavioral change, unblocks Remedy 3)

2. **Commit 2:** Remedy 3 — Collapse `verify_maintenance.cpp` `main()`
   boilerplate (depends on Commit 1)

3. **Commit 3:** Remedy 4 — Add `CHECK_ARGS` / `CHECK_ARGS_RANGE` /
   `CHECK_ARGS_MIN` macros to `tcl_base.h`, apply to `tcl_engine.cpp`
   and `tcl_view.cpp` (independent, mechanical)

4. **Commit 4:** Remedy 8 — Handle write failure in `Engine::send()`
   (independent, small, safety-critical)

5. **Commit 5:** Remedy 9 — Verify/document `updateTimeInfo()` removal
   (independent, investigation + possibly a comment or revert)

6. **Commit 6:** Remedy 1 — Extract `tcl_search.cpp` from `tcl_view.cpp`
   (structural, unblocks 5/6/10)

7. **Commit 7:** Remedy 5 — Unify `parseRange` in `tcl_search.cpp`
   (depends on Commit 6)

8. **Commit 8:** Remedy 6 — Extract `makeNameSearch` template helper
   in `tcl_search.cpp` (depends on Commit 6)

9. **Commit 9:** Remedy 10 — Use `SearchP` for `SearchOpOr`/`SearchOpAnd`
   in `tcl_search.cpp` (depends on Commit 6)

10. **Commit 10:** Remedy 7 — Replace `strchr('|')` heuristic with
    explicit `-row`/`-identity` subcommand (independent, but requires
    Tcl-side caller updates — do last to minimize disruption)

## Verification After All Commits

```bash
# Build everything
make -C src/tcl clean && make -C src/tcl
make -C src clean && make -C src

# Run test suite
make -C src verify-maintenance
make -C src verify-conversion

# Check file sizes are under thresholds
wc -l src/tcl/tcl_view.cpp    # target: < 1,000
wc -l src/tcl/tcl_engine.cpp  # should decrease ~75 lines
wc -l src/tcl/tcl_search.cpp  # new file, ~650 lines
wc -l src/verify_maintenance.cpp  # main() should be ~50 lines

# Check for Tcl-side callers of setTreeFilter
grep -rn 'setTreeFilter' tcl/ --include='*.tcl'

# Memory check (if Valgrind available)
valgrind --leak-check=full ./src/verify-maintenance
```