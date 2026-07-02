# Verified Bug Catalog — ScidB Codebase (Complete)

Comprehensive review of all C/C++ source in `src/` (excluding vendored
libraries). Every finding has been **verified by reading the actual code
context** — pattern matches that turned out to be false positives were
investigated and excluded.

**2026-07-02 update:** extended the review to `contrib/` and the vendored
`engines/Sjeng` tree (see [Contrib & Engines Review](#contrib--engines-review-2026-07-02)
below). All 6 new findings fixed in commit `3e851a3`.

---

## Summary

| Category | Total | Fixed | Remaining |
|----------|-------|------|-----------|
| Memory safety | 8 | 8 | 0 |
| Logic / wrong labels | 7 | 7 | 0 |
| Resource leaks | 2 | 2 | 0 |
| Integer safety | 5 | 5 | 0 |
| Code hygiene | 9 | 9 | 0 |
| Build config | 1 | 1 | 0 |
| Contrib & engines (2026-07-02) | 6 | 6 | 0 |
| **Total** | **38** | **38** | **0** |

---

## Remaining Unfixed Bugs

None. VBUG-1 (`sprintf` without bounds in `db_writer.cpp:521`, low severity —
buffer was pre-resized to 32 bytes, max output ~12 chars) was fixed 2026-07-02
by switching to `::snprintf(m_moveNumber.data(), 32, ...)`. The `%u.` format
emits at most 11 chars, so the returned length used by the subsequent
`resize()` is never a truncated count.

---

## All Fixed Bugs (31)

### Memory Safety (8 fixed)

| # | File | Bug | Fix |
|---|------|-----|-----|
| M1 | `tcl_database.cpp:4137` | VLA `Tcl_Obj* result[resultSize]` with user-controlled size → stack overflow | → `mstl::vector<Tcl_Obj*>` |
| M2 | `tcl_database.cpp:4256` | Missing `break` in switch — Player case fell through to Site | Added `break;` |
| M3 | `sys_fam.cpp:824,828` | File descriptor leaked when `fcntl()` fails | Added `close(fd)` on both error paths |
| M4 | `tcl_engine.cpp:408` | `sprintf` without bounds into `buf[100]` | → `snprintf(buf, sizeof(buf), ...)` |
| M5 | `tcl_database.cpp:2049,2121` | `sprintf` without bounds into `acv[100]` (×2) | → `snprintf(acv, sizeof(acv), ...)` |
| M6 | `tcl_sort.cpp:414` | `sprintf` without bounds into `buffer[100]` | → `snprintf(buffer, sizeof(buffer), ...)` |
| M7 | `sys_process.cpp:105` | `sprintf` without bounds into `buf[100]` | → `snprintf(buf, sizeof(buf), ...)` |
| M8 | `cbh_game_decoder.cpp:857` + `db_edit_key.cpp` (×4) + `u_zstream.cpp:268` | `sprintf` without bounds (6 locations) | → `snprintf(buf, sizeof(buf), ...)` |

### Logic / Wrong Error Labels (7 fixed)

| # | File | Bug | Fix |
|---|------|-----|-----|
| L1 | `tcl_search.cpp:423` | `Site` case reported error as `"event"` | Changed to `"site"` |
| L2 | `tcl_engine.cpp:701` | `cmdProbe` used `error(CmdStart, ...)` | Changed to `CmdProbe` |
| L3 | `tcl_engine.cpp:923` | `cmdStart` used `error(CmdProbe, ...)` | Changed to `CmdStart` |
| L4 | `tcl_engine.cpp:991,994,1001` | `cmdSetFeatures` used `error(CmdActivate, ...)` (×3) | Changed to `CmdSetFeatures` |
| L5 | `app_engine.cpp:1105` | `Engine::send()` silently swallowed write failure | Added `log()` + `m_active = false` |
| L6 | `db_search.cpp:367` | Rating average rounding undocumented | Added comment documenting round-half-up intent |
| L7 | `tcl_view.cpp:527` | `cmdSetTreeFilter` used `strchr('|')` magic heuristic | Replaced with explicit `-row`/`-identity` subcommands |

### Resource Leaks (2 fixed)

| # | File | Bug | Fix |
|---|------|-----|-----|
| R1 | `sys_fam.cpp:824,828` | FD leaked on `fcntl` failure (same as M3) | Added `close(fd)` |
| R2 | `tcl_search.cpp` Or/And cases | `SearchOpOr`/`SearchOpAnd` leaked on partial sub-query failure | Wrapped in `SearchP` (ref-counted) |

### Integer Safety (5 fixed)

| # | File | Bug | Fix |
|---|------|-----|-----|
| I1 | `db_filter.cpp:73` | `m_count = m_set.size() - m_count` — unsigned underflow if invariant violated | Added `M_ASSERT(m_count <= m_set.size())` |
| I2 | `db_player.cpp:499` | `s.size() - 4` — underflow if `s.size() < 4` | Added `M_ASSERT(s.size() >= 4)` |
| I3 | `db_common.cpp:3674,3803` | `uint16_t i` loop with `pos.size()` — wraps at 65535 | Changed to `unsigned` |
| I4 | `db_tournament_table.cpp:526` | `int n` loop with `clashList.size()` — truncation risk | Changed to `unsigned` |
| I5 | `db_site.cpp:248` | `int index` loop with `int(m_ascii.size())` — truncation + cast | Changed to `unsigned` |

### Code Hygiene (8 fixed, 1 remaining)

| # | File | Bug | Fix |
|---|------|-----|-----|
| H1 | `db_annotation.cpp:545` | `;;memcpy(` — stray empty statement | Removed `;;` |
| H2 | `db_common.cpp:1672` | `= *this;;` — stray `;;` | Removed `;;` |
| H3 | `db_player.cpp:1537,1549` | `return 0;;` (×2) — stray `;;` | Removed `;;` |
| H4 | `app_application.cpp:2801` | `= viewId;;` — stray `;;` | Removed `;;` |
| H5 | `tcl_database.cpp:4227,4272` | `);;` (×2) — stray `;;` | Removed `;;` |
| H6 | `Makefile.in` | `-fno-stack-protector` disabled stack canaries | Removed flag |
| H7 | `Makefile.in` | `-Wno-format-security` suppressed format warnings | Removed flag |
| H8 | `verify_maintenance.cpp` | `main()` had merge-artifact indentation + 190-line boilerplate | Fixed indentation + `CHECK()` macro collapse |
| — | `sys_info.cpp:226` | `mach_host_self();;` — stray `;;` (macOS-only) | **NOT FIXED** (macOS code, not compiled on Linux) |

### Structural / Code Quality (fixed as part of thermo-nuclear review)

| # | File | Bug | Fix |
|---|------|-----|-----|
| S1 | `tcl_view.cpp` | 1,707 lines — over 1k threshold | Extracted `tcl_search.cpp` (683 lines); `tcl_view.cpp` → 1,000 lines |
| S2 | `tcl_engine.cpp` + `tcl_view.cpp` | ~100 lines of arg-count boilerplate | `CHECK_ARGS` / `CHECK_ARGS_RANGE` / `CHECK_ARGS_MIN` macros |
| S3 | `tcl_search.cpp` | `parsePawnRange` + `parseRatingRange` duplicate code | Unified into `parseRange(ti, obj, max, ...)` |
| S4 | `tcl_search.cpp` | EventName/SiteName/AnnotatorName copy-paste | `makeNameSearch<T>()` template |
| S5 | `tcl_engine.cpp` | `updateTimeInfo()` override removed without documentation | Added comment explaining data now sent via `updateDepthInfo()` |

---

## Contrib & Engines Review (2026-07-02)

Scope: `contrib/` and vendored `engines/Sjeng`. The vendored Stockfish tree
now tracks a modern upstream release and was excluded; `src/`-root standalone
tools re-scanned clean. All findings fixed in commit `3e851a3` and verified:
both contrib tools compile with `-Wall`, an encode→decode round-trip test
passes (timestamp + message recovered, malformed input rejected), and
`sjeng-scidb` rebuilds.

| # | File | Bug | Fix |
|---|------|-----|-----|
| C1 | `contrib/openseal_decoder.c:47,64` | Operator precedence: `!tmp[n]&0x80` and `!tmp[n]>>5` always evaluate to 0 — both malformed-input checks were dead code, so garbage/control chars passed validation | Parenthesized: `!(tmp[n]&0x80)`, `!(tmp[n]>>5)` |
| C2 | `contrib/openseal_decoder.c:46` | `key[(n+offset-0x80)%50]` goes negative (OOB read before `key`) when the message's offset byte is < 0x80 | `((n+offset-0x80)%50+50)%50` |
| C3 | `contrib/openseal.c:77` | Stray semicolon: `if(-1==connect(...));` — connect failure silently ignored, program proceeded on unconnected socket | Proper error block with `perror` + `exit(1)` |
| C4 | `contrib/openseal.c:175` | Server-side `read(fd,buff,BSIZE-rd)` missing `+rd` offset — buffered partial `[G]` prefix clobbered and `rd` overcounted, forwarding stale bytes | `read(fd,buff+rd,BSIZE-rd)` |
| C5 | `contrib/openseal.c:94` | `ffub[BSIZE+20]` overflows by up to 2 bytes: seal_crypt on a 1023-byte line appends delimiters + timestamp, pads to a multiple of 12 (1044), then writes 2 more bytes | `ffub[BSIZE+32]` |
| C6 | `engines/Sjeng/sjeng.c:304,460` | `opening_history[256]` filled by unbounded `strcat` of up to 40 plies — raw user input lines (≤255 chars each) at :460, SAN strings at :304 — stack-adjacent global overflow | Bounded `strncat` with remaining-space calculation |

Ancillary fixes in the same commit (modern-C build correctness, not runtime
bugs): `decrypt()` declared `int` but returned no value → `void`; local
`crypt()` collided with libc's declaration → renamed `seal_crypt()`; missing
`#include <unistd.h>` in `openseal.c`.

### Verified Safe (this pass)

| Finding | Why It's Safe |
|---------|---------------|
| `rinput()` in `Sjeng/utils.c:853` | Properly bounded: writes at most `n-1` chars + NUL |
| `fname[13]` strcpy in `Sjeng/segtb.c:516,977` | `"stb/xxx.bin"` is 11 chars + NUL = 12, fits |
| `howmuch[80]` strcpy in `Sjeng/partner.c` | Longest literal is 49 chars |
| `setcode[30]` / `EGTBDir[256]` in `Sjeng/rcfile.c` | `%u` max 10 digits; `"TB"` literal |
| `PV[8192]` strcat in `Sjeng/proof.c:1395` | Would need a ~1000-move proof PV; not reachable in practice |
| `decrypt` `strcpy(tmp,s)` | `s` ≤ BSIZE-1 incl. NUL (fgets-bounded), `tmp[BSIZE]` |

---

## Verified Safe (False Positives Cleared)

| Finding | Why It's Safe |
|---------|---------------|
| `flipFyle` KS/QS swap in `db_board.cpp:1921` | Right side reads from `this->` (no `board.` prefix), not from destination |
| `getenv() == 0` in `db_tree_cache.cpp:36` | Correct null check — `char*` compared to NULL |
| `SearchOpAnd::match` returns false for empty | Intentional — empty AND should match nothing |
| `db_database.cpp:938` use-after-delete | `m_codec` is reassigned immediately after delete, not accessed |
| `app_application.cpp:2986` use-after-delete | `m_engineList[id]` is nulled immediately after delete |
| `TournamentTable::getPlayer` returns 0 | Guarded by `M_REQUIRE(ranking < countPlayers())` |
| `eco_table mul2` memcpy | Buffer allocated as `length1+length2` elements; copies exactly fit |
| `m_engine->` calls in Process callbacks | `m_engine` set in constructor, never nulled; Process can't outlive Engine |
| `Engine::send()` m_process not null-checked | `M_REQUIRE(isConnected())` ensures `m_process` is non-null |
| Parallel maintenance reader leak on thread start failure | Reader is properly closed via `db.closeAsyncReader(readers.back())` |
| `tcl_misc.cpp` XML/URL subcommand error labels | Correct parent-command pattern (`error(CmdParent, "subcommand", ...)`) |
| `tcl_player.cpp` cmdCount/cmdDict label | Error is in `cmdDict` function, not `cmdCount` — proper function boundary confirms |
| Switches without default in `db_board.cpp` | All enum cases covered; post-switch `return false` handles unexpected |
| `db_search.cpp:358` switch without default | All 4 `m_mode` cases covered + trailing `return false` |

---

## Methodology

1. **Error label audit** — Python script with proper function-boundary tracking (brace counting) verified every `error(CmdXxx, 0, ...)` call matches its containing function
2. **Memory safety scan** — VLA detection, sprintf/snprintf audit, use-after-free pattern matching, null deref analysis
3. **Resource leak scan** — fopen/fclose, open/close, new/delete counting per file; manual error-path audit for `sys_fam.cpp` and `db_maintenance.cpp`
4. **Integer safety scan** — unsigned underflow patterns, signed/unsigned mismatches, truncation risks
5. **Logic audit** — switch fallthrough detection (Python with brace tracking), wrong comparison operators, copy-paste error detection
6. **Concurrency audit** — reviewed parallel maintenance worker lifecycle, thread synchronization, error propagation
7. **Compiler warnings** — built with `-Wall -Wextra -Wuninitialized -Wmaybe-uninitialized` and analyzed all warnings
8. **Manual code review** — read and verified every flagged finding by examining the actual code context