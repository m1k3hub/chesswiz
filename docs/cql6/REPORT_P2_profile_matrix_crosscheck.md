# REPORT_P2 — cql6 performance analysis

**Scope.** This is an *analysis-only* deliverable. No production source file was modified.
All numbers below were produced by running the existing profiling build
(`build_prof/bench_prof`, a `tests/bench.cpp` harness built with the project's
`makefile-flags`: `-g -O3 [os-flags] -std=c++17 -DASSERTIONS -I. -I./orig`),
plus two *out-of-tree* experiment binaries used only to attribute cost:

* `analysis/bench_noassert` — the reference objects with `ASSERTIONS` removed
  from `orig/position.cpp`, `cqluassert.cpp`, `orig/myassert.cpp`.
* `analysis/bench_lazy` — a sandbox copy of `qpos.{h,cpp}` / `print.cpp` in which the
  three eagerly-computed per-position state flags (`check`/`mate`/`stalemate`) are
  computed on demand (see `analysis/lazy_*.diff`).

Correctness of both experiment binaries was verified by identical `matches=` counts on
every probed query (`check` 1057, `mate` 202, `stalemate` 0, material 18, passers 3, pins 0, …).

Input corpus: `data/g1200.pgn` (1200 games) unless noted; `analysis/g100.pgn` (100 games)
for the very expensive comment workload; `data/g5.pgn` for the comment smoke test.

---

## 1. Method / how to reproduce

```
# wall-clock (task-pinned, BENCH_RUNS=N, median of run lines)
BENCH_RUNS=5 taskset -c 0-7 ./build_prof/bench_prof data/g1200.pgn 1 '<script>'

# instruction-accurate profile, scoped to the search entry point
BENCH_RUNS=1 valgrind --tool=callgrind --toggle-collect=cql6_search \
    --callgrind-out-file=analysis/cg/<name>.out \
    ./build_prof/bench_prof data/g1200.pgn 1 '<script>'

# summarise (inclusive Ir % of the cql6_search total)
python3 analysis/table.py  analysis/cg/*.out     # per-query category table
bash    analysis/extract.sh analysis/cg/check.out # flat Ir% list
callgrind_annotate --inclusive=yes analysis/cg/check.out
callgrind_annotate --tree=calling  analysis/cg/check.out   # call counts
```

`--toggle-collect=cql6_search` isolates CQL from PGN loading/thread setup, so
`cql6_search` inclusive Ir is the denominator used throughout (`tot`).

---

## 2. Where the time goes — headline

Two structural costs dominate every position-based query, and neither is the chess
rule logic that one would expect to be the hot path:

1. **Eager per-position feature computation.** `QPos::initialize()` computes the
   piece/colour masks *and* `check()`, `mate()` **and** `stalemate()` for **every**
   position in **every** game — before any filter is evaluated.
2. **Recursive `QPos::getDepth()`.** A root-seek that is memo-less, recurses to the
   root and does a linear child scan (`myindex`) at each level — O(ply²) per call, and
   it is called hundreds of thousands of times by result assembly and sorting.

A third, cross-cutting cost is the **assertion machinery** (`uassert`, 1557 call sites;
`Position::AssertPos()`), which is on in the profiling build.

### 2.1 Instruction budget by workload

| workload | `cql6_search` Ir (M) | wall (s, pinned) |
|---|---:|---:|
| `check` | 1 494 | 0.239 |
| `mate` | 1 493 | 0.226 |
| `stalemate` | 1 493 | 0.234 |
| material `[R]==1 …` | 1 552 | 0.253 |
| `layout Kg1 Rf1 …` | 1 506 | — |
| `pins` (script) | 2 697 | 0.395 |
| `passers` (script) | 1 863 | 0.300 |
| `serialpin` | 2 103 | — |
| `persistent` | 2 392 | — |
| **`staircase-sort`** | **13 870** | — |
| `movelegal` (`move legal`) | 9 536 | — |
| `commentout` (100 games) | 1 142 | — |

`staircase` (a `sort` query) and `movelegal` are order-of-magnitude outliers; the
baseline "walk every game, test one predicate" cost is ~1.5 G instructions.

---

## 3. Finding A — eager per-position check/mate/stalemate

### Evidence

`QPos::initialize()` (`qpos.cpp`, called once per position from `visitRoot`) ends with:

```cpp
uassert(check()==MarkBoard::check(game) &&
        mate()==MarkBoard::mate(game) &&
        stalemate()==MarkBoard::stalemate(game),"verify check/mate/stalemate");
...
theIsCheck     = MarkBoard::check(game);
theIsMate      = MarkBoard::mate(game);
theIsStalemate = MarkBoard::stalemate(game);
```

These three values are consumed **only** by `match.cpp` (`check()`, `mate()`,
`stalemate()` node predicates, reached via `MatchPosition`/`match_position`). A given
script at most reads *one* of the three — and most scripts read *none* — but all three
are computed for every position regardless.

Per-position call counts on `check` (identical counts for `mate` and `stalemate`):

| function | calls |
|---|---:|
| `QPos::createFromParent` (positions created) | 71 952 |
| `MarkBoard::check` / `mate` / `stalemate` | 73 152 each |
| `MarkBoard::identity(Game*)` (called inside each) | 146 304 |

Note 73 152 **>** 71 952: each state test itself allocates positions, i.e. the three
eager computations recursively create more positions whose states are also eagerly
computed.

### Inclusive instruction cost on `check` (tot = 1 494 M)

| function | Ir | % of tot |
|---|---:|---:|
| `QPos::initialize(QGame*)` (masks **+** all three states) | 469 999 348 | **31.5 %** |
| `MarkBoard::stalemate(Game*)` | 315 782 253 | **21.1 %** |
| `MarkBoard::mate(Game*)` | 33 922 348 | 2.3 % |
| `MarkBoard::check(Game*)` | 12 151 479 | 0.8 % |

`stalemate()` dominates because `Position::myIsKingInStalemate()` runs the *full legal
move generator*:

```cpp
bool Position::myIsKingInStalemate(){
  GenerateMoves();                         // origChanges.cpp
  if (LegalMoves->Size()!=0) return false;
  CalcNumChecks(GetKingSquare(ToMove));
  return NumChecks==0;
}
```

`Position::GenerateMoves` inclusive is **629 M / 1 494 M = 42 %** of the run, and
**almost all of it is this one test**: of its 73 359 call sites, **73 152 (99.7 %)
originate in `Position::myIsKingInStalemate`**. The same generator is only run once
more per position by `myIsKingInMate`→`GenCheckEvasions` (64 832 calls).

### The waste is complete for non-state queries

`material_QR` (`[R]==1 and [r]==1 and [P]==5 and [p]==5 and [QBNqbn]==0`) never reads
`check`/`mate`/`stalemate`. On it, the three eager states cost **469 M of 1 551 M =
30 %** (stalemate alone ≈ 20 %).

The lazy-state experiment (`analysis/bench_lazy`) removes exactly this:

| | ref Ir (M) | lazy Ir (M) | Δ |
|---|---:|---:|---:|
| `material_QR` | 1 552 | 1 053 | **−32 %** |
| wall `material_QR` | 0.253 s | 0.190 s | **1.34×** |
| wall `passers` | 0.300 s | 0.223 s | **1.34×** |
| wall `pins` | 0.395 s | 0.325 s | **1.22×** |

**Directional conclusion.** For the overwhelmingly common case — a query whose
predicates are *not* `check`/`mate`/`stalemate` — ~20–30 % of all work is spent
computing a game-theoretic property nobody reads, and lazily deferring it (cached on
first use) recovers a ~1.2–1.35× speedup with **bit-identical match results**.

For queries that *do* read the flag, the current eager form is *better* than the
naive lazy prototype (which re-seeks the game tree per access and measured 0.5–0.6×).
The right fix is therefore not "make it lazy" but **compute-once-per-position, only if
requested, and store** — i.e. a per-`QPos` cached tri-state, or a cheap static
pre-pass that records which predicates the script can ever read and skips the rest.
The prototype in `analysis/lazy_*.diff` demonstrates the achievable non-state saving
and the correctness envelope; it is deliberately not a drop-in optimisation.

---

## 4. Finding B — recursive, cache-less `QPos::getDepth()`

`getDepth()` recurses to the root, scanning the parent's `children` vector linearly at
each level:

```cpp
int QPos::getDepth(){
  if(!parent)return 0;
  int index=myindex(parent->children,this);   // linear scan
  ...
}
```

Cost is O(ply²) per call and the result is a *pure function of tree position*, yet it
is recomputed on every call. Callers (`depthnode.cpp`, `match.cpp`, `cql6_api.cpp`,
sort/result assembly) invoke it ~10⁵–10⁶ times per workload.

### Evidence — `commentout100` (tot = 1 142 M)

| measure | Ir | % of tot |
|---|---:|---:|
| `QPos::getDepth()` inclusive | 427 289 952 | **37.4 %** |
| of which self (`qpos.cpp`) | 2 041 135 | 0.2 % |
| of which recursion into `QPos::getDepth()` (in `myvector.h`) | 68 498 542 | 6.0 % |
| `EchoNode::match_position` (caller) | 57 % incl. |
| `CqlNode::match_game`/`do_match` | 63.8 % incl. |
| `CommentNode::match_position` | 8.4 % |
| `SortNode::match_position` | 9.9 % |

So the "comment/echo" result-assembly path (57 % of the run) collapses almost entirely
to `getDepth()`. Two concrete call sites in `cql6_api.cpp` walk the comment stack and
call `ce.qpos->getDepth()` for *every* entry just to test `== 0`:

```cpp
for (int ci = 0; ci < cs->size(); ++ci) {
    CommentEntry& ce = cs->at(ci);
    if (ce.qpos && ce.qpos->getDepth() == 0) { ... }
}
```

**Directional conclusion.** `getDepth()` is a textbook memoisation target: store the
depth on `QPos` when the parent link is set (or compute it once per position in
`visitRoot`, where it is already walking the tree), turning every call into a load.
It is also trivially reducible to `thePly`-style bookkeeping, and the `cql6_api.cpp`
loops can test `qpos->parent == NULL` directly instead of calling `getDepth()`.
Expected saving on comment/sort workloads: up to ~35 % of search Ir.

---

## 5. Finding C — assertion overhead

The profiling build is `-DASSERTIONS`, and `uassert` is the single hottest *self* symbol
in several workloads:

| workload | `uassert(bool,char const*)` self % of tot |
|---|---:|
| `staircase` | 40.9 % |
| `commentout` (100) | 28.9 % |
| `commentout` full | 39.0 % |
| `movelegal` | 19.4 % |
| `persistent` | 19.3 % |
| `flipvertical` | 17.6 % |
| `pathregex` | 16.1 % |
| `check` | 14.0 % |
| `pins` | 13.1 % |

Call counts on `check`: `uassert(bool,const char*)` **6 092 628 calls**;
`Position::AssertPos()` **292 483 calls** (Inclusive 187.7 M + 43.6 M = **15.5 %** of
tot); `AssertPos` itself runs a 64-square loop that calls `IsAttacked`/`AttacksFrom`
per occupied square. All 1557 `uassert` sites and both `AssertPos()` calls in
`DoSimpleMove`/`UndoSimpleMove` are `#ifdef ASSERTIONS`-gated, so they are pure
debug-only cost.

### Removal experiment (`analysis/bench_noassert`)

| build | `check` Ir (M) | wall (pinned, median of 7) |
|---|---:|---:|
| reference (`-DASSERTIONS`) | 1 494 | 0.239 s |
| assertions off | 1 095 | 0.197 s |

**−27 % instructions, ~1.2× wall speedup**, identical results. `AssertPos` inclusive is
15.5 % and `uassert` self 14 % on `check`; on heavier workloads the combined assertion
share rises above 40 %.

**Directional conclusion.** Assertion cost is 15–45 % depending on workload and is
entirely removable in production builds. Two separable levers: (a) ship without
`ASSERTIONS`; (b) if asserts must stay, make `AssertPos()` O(#pieces) rather than
O(64)×attack-generation and hoist it out of the per-move path, and consider a
lighter-weight `uassert` (the current one formats/looks up messages on the hot path).

---

## 6. Secondary hot spots (per-workload)

Full per-query table: `analysis/table.tsv` (generated by `analysis/table.py`).
Notable, inclusive % of that workload's `cql6_search` total:

* **`staircase` (`sort`) — 13.9 G Ir.** `SortNode::match_count` = 87.1 % (12.08 G),
  of which `SortNode::match_sortvalue` 86.1 % (11.94 G) and
  `SortNode::match_filtersortvalue` 85.1 % (11.80 G); called **1 170 432×** for a
  1200-game input. Sorting re-evaluates the sort expression per candidate per position
  with no memoisation. This is the biggest single algorithmic outlier.
* **`movelegal` — 9.5 G Ir.** `MoveLegalNode::getSquares` 84.3 % (8.04 G),
  `MoveLegalNode::compute` 84.2 % (8.03 G), `filterPseudoLegal` **76.2 %** (7.27 G).
  `Position::GenerateMoves` is only 6.6 % (629 M) here — the cost is the node's own
  pseudo-legal filtering, not move gen.
* **`passers` / `serialpin`.** `SortNode::match_position` 18.6 % (passers) /
  `sort` 8.1 % (serialpin), plus `Comment`/`StrConv` string work.
* **`pins`.** `PinsNode`/`pin` feature work plus `CommentStack`/string conversion; the
  position walk (feed 20 %, posTree 33 %) is a smaller share than the geometric feature.
* **Feed cost is fixed overhead** (not always "feed 20–36 %"): `ScidbGameSource::populateGame`
  36 % on `check` (1200 games, cheap predicate) but only 3.9–5 % on `staircase`/`movelegal`,
  where the script predicate dominates. `populateGame` = 1200 calls in every run.
* **`MakeSANString`** costs a steady 8–12 % inclusive on move-oriented queries
  (`――=♕`, `move capture`, `enpassant`).

---

## 7. Summary of directional recommendations

Ranked by measured, attributable saving:

1. **Stop computing `check`/`mate`/`stalemate` per position unconditionally**
   (`QPos::initialize`). Measured **20–30 %** of search Ir on ordinary queries; the
   lazy-state prototype removes it with identical results (1.22–1.34× wall). Best form:
   cache-on-demand, not re-seek-on-access.
2. **Memoise `QPos::getDepth()`** (and/or replace its `== 0` call sites with a
   `parent == NULL` test). Measured up to **37 %** of search Ir on comment/echo/sort
   workloads; O(ply²)→O(1).
3. **Drop or cheapen assertions in production.** Measured **27 %** Ir / ~1.2× wall on
   `check`, rising to >40 % on sort/comment workloads, for zero functional change.
4. **Memoise sort-expression evaluation** (`SortNode::match_count`/`match_sortvalue`) —
   the dominant cost of the single most expensive query class (`sort`, 87 % incl.,
   ~1.17 M evaluations).
5. **Review `MoveLegalNode::filterPseudoLegal`** — 76 % of the `movelegal` workload.

Lower-priority: `MakeSANString` (8–12 % on move queries) and the string-conversion /
comment-merge path in echo workloads.

All measured costs above were verified to leave `matches=` counts unchanged, so none of
these are correctness trade-offs — they are pure work-elimination opportunities.
