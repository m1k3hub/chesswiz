# Pattern Index — plan and design

**Status:** proposed (2026-09-30). Nothing is implemented. It depends on the CQL 6.2 engine
work (`src/cql6`, branch `cql6-port`), which is in progress.
**Companions:** `PLAIN_LANGUAGE_SEARCH.md` (the vetted pattern library and the plain-language
front end this index would serve), `LONG_RANGE_PLAN.md` (workstream 10).

## 1. Goal

Searching a database for a chess idea ("smothered mate", "queen sacrifice then perpetual",
"opposite-coloured bishops") should take **milliseconds, not a scan**, for every pattern in
Scidb's vetted library, and the answer must be exactly what the engine would have found.

The way to get there is to **precompute, once per database, which games match which library
pattern**, keep that in a sidecar file next to the database, and answer library searches by
intersecting stored bitmaps with the ordinary header filters. No game is decoded to answer them.

## 2. Why this is the right shape (measured, not assumed)

Profile of the embedded CQL 6.2 engine, one thread, cheap script, 1,200 real games
(callgrind, `--toggle-collect=cql6_search`; instruction counts, not time):

* ~96% of the cost is **preparing each game** (building the game and its position tree);
  matching the script is ~3%.
* Of that preparation, per-position features that the script never asked for are computed
  eagerly (for example `MarkBoard::stalemate` runs full legal move generation on every
  position: ~21%), runtime assertions are ~27%, and the feed's own legal-move generation and SAN
  formatting are ~35% (the last two are being removed on the engine side).
* Therefore **evaluating N patterns on one prepared game costs about one preparation plus
  N small matchings**, not N searches. Building an index for a whole library should cost a small
  multiple of one query. (This is the assumption to verify first, see section 9.)

A pattern query that must scan 1.17M games (the `twic_complete` test database) is a minute
or more even on the fast engine; a bitmap intersection is instant.

## 3. What is indexed

* **The library**: the patterns in `tcl/ai-search.tcl` (`Patterns`: event and structure
  kinds), each with an id, a CQL 6.2 definition, and today's fixture tests. The index covers
  library patterns only. A user's own CQL still scans (section 7).
* **Per game, per pattern**: one bit (matches or not) and the **first matching mainline ply**
  (so the result can open at the moment). Whether variations are indexed is a per-library
  setting (default: main line only, like CQL's default); a game matching only in a variation is
  recorded separately (`first_ply = -1`, flag set).
* **Per pattern, per database**: the match count, so statistics ("how many Najdorf games have
  a queen sacrifice") are free.

## 4. Sidecar file

`<database>.scp` (name open) beside the database files, never inside them, so no database
format changes and a missing file only means "not indexed yet".

```
header   magic, format version, game count, database identity (see 5), library version
patterns table of {pattern id, definition hash, status, match count}
data     per pattern: a bitmap over game numbers (roaring or run-length compressed:
         library patterns are sparse), and a sorted {game, first ply} column
```

Size: 200 patterns x 1M games is ~25 MB as plain bitmaps and much less compressed. The file is
written atomically (temp file and rename) and read memory-mapped.

## 5. Validity: never serve a stale answer

The index is a cache of exact engine results, so it must be invalidated exactly when a game it
covers changes.

* A **database identity** (path plus a per-database change stamp; Scidb already tracks
  `lastChange` and notifies on edits, as `ai-simindex` relies on) and a **per-block checksum of
  the games' move data** (blocks of, say, 4096 games), so an edit or import re-indexes only the
  blocks that changed, and appended games are indexed incrementally.
* A **pattern's definition hash** plus the **engine version**: a changed pattern or engine is
  rebuilt for that pattern only; the others stay valid.
* Anything uncertain (stamp mismatch with no per-block proof, a read-only medium with a
  different stamp) means: do not use the index, scan, and say so in the UI. Correct and slow beats
  fast and stale.

## 6. Building it

* A **background job**: one multi-threaded pass over the database that, for each game, prepares
  it once and evaluates **all library patterns that are out of date** on that prepared game
  (the engine needs an API for "evaluate a set of scripts on one prepared game"; today it is
  one script per search, see section 9).
* **Resumable** (per-block commit points, progress via the existing async job model of
  `::scidb::cql6::*`), cancellable, at low priority so the GUI stays responsive, offered on
  database open for large databases ("index patterns for faster searches?"), never forced.
* Built from a **trusted, normalised feed**: Scidb already stores only legal moves, so the engine
  must not re-validate them (measured ~1.6x faster feed on one thread); the feed guards with
  cheap sanity checks and a validating mode for unvalidated sources.

## 7. Using it

* **Library pattern + header filters**: intersect the pattern bitmap with the header-filter result
  (the existing "header terms narrow the games first" rule of `BuildQuery`); open the first ply.
* **Plain-language search** and the assistant's `search_games` tool already map words to
  pattern ids: they get the fast path automatically when the id is indexed, and fall back to the
  scan otherwise. The result is identical either way (tested, section 10).
* **Statistics and features**: structure profile, training-puzzle candidates, trend and study
  plan read pattern counts and game lists directly instead of scanning.
* **User-written CQL**: still a scan. Later, patterns can serve as necessary conditions to
  pre-narrow the candidates (for example "queen sacrifice" implies a capture of a queen), which
  needs a hand-maintained implication table: deliberately not in the first version.

## 8. Growing the library

The library is the product. Each pattern is a CQL 6.2 script with an id, a label, a plain-language
description and aliases (as today), plus **fixture games that must match and must not match**.
The index build refuses a pattern that fails its fixtures. The assistant never writes patterns
(the rule of `PLAIN_LANGUAGE_SEARCH.md` stays); people do, with the engine's help for checking.

## 9. Risks and open questions

* **Multi-script evaluation on one prepared game** is not in the official CQL 6.2 program
  (one script per run, one parsed tree per thread). The embedded engine must grow this API; the
  gain in section 2 depends on it. Measure first: prepare once, evaluate 20 and 200 scripts,
  compare with 20 and 200 separate searches.
* **Index size and build time on the largest databases** (CCRL-4040 is ~2 GB of game data,
  Lumbras GigaBase millions of games): measure, and decide what runs automatically.
* **Eager per-position features** in the engine inflate preparation (stalemate detection per
  position, attack maps): make them lazy and demand-driven (needed by the whole pattern set, not
  by each script), otherwise a library of 200 patterns pays for the union of all features on every
  position.
* **Variation handling and `first_ply`** semantics must match the engine exactly; define them
  once and test them against the scan path.
* **Concurrency**: reading the index is trivial; building must not hold database locks, and the
  database may change while it runs (section 5 covers correctness, not wasted work).
* **Where does it live for the web front end** (`LONG_RANGE_PLAN.md` workstreams 1-4)? The
  sidecar fits a desktop database; a server would keep the same bitmaps in its store. Decide
  when the format is stable.
* There is **no existing persisted sidecar in Scidb to copy**: `ai-simindex` is an in-memory
  cache. The `.scp` file is new, so its format needs a version field from day one.

## 10. Tests (acceptance)

1. For every library pattern and several databases (fixtures and a few thousand real games):
   **scan result == index result**, as sets and with the same first plies.
2. Invalidation: edit a game, add games, delete games, replace the file, change the library or
   the engine version: the answer is correct in every case (re-indexed, or scanned and flagged).
3. Crash safety: kill the builder at random points; the sidecar is either absent or valid.
4. Build resumes after cancel and after restart and ends with the same file as an uninterrupted run.
5. Search latency with the index on 1M games under 100 ms for pattern plus header filters.
6. Sanitizer runs (ASan/UBSan/TSan) over the build and the reader, as for the engine.

## 11. Phases

1. **Engine support**: trusted normalised feed; lazy per-position features; multi-script
   evaluation on one prepared game; sanitizer-clean (the `cql6-port` work, in progress).
2. **Format and builder**: `.scp` reader/writer, background job, validity proofs, progress UI.
3. **Search integration**: library searches, plain-language search and the assistant use the index;
   scan fallback with identical results.
4. **Incremental maintenance** on edit/import and library/engine version changes.
5. **Library growth** with fixtures; per-database pattern statistics view.
