# REPORT_P2 — Where does the time go, per kind of CQL script?

All measurements are on this scratch tree (`/tmp/claude-1000/t1exp_p3/src/cql6`), analysis-only, artefacts under `analysis/`.
Command form (1 thread, 1200 games from `data/g1200.pgn`, `BENCH_RUNS=1`):

```
BENCH_RUNS=1 valgrind --tool=callgrind --toggle-collect=cql6_search \
  --callgrind-out-file=analysis/prof/<id>.out \
  ./build_prof/bench_prof data/g1200.pgn 1 '<script>'
```

* `build_prof/bench_prof` — unmodified profiling build (all objects built with `-DASSERTIONS`, brief's flags).
* `analysis/build/bench_var` — same but a copy of `tests/bench.cpp` with `opt.variations = 1` (`analysis/bench_var.cpp`).
* Costs below are **inclusive** instruction counts (`callgrind_annotate --inclusive=yes`), so nested
  functions are double-counted (e.g. `visitRoot` contains `qpos_init` which contains `MB_stalemate`).
  This is intentional and matches the brief's own accounting; columns therefore do not sum to 100%.
* Each profile's total is the `cql6_search` total (toggle-collect), which equals the whole run here.

## Scripts profiled

20 scripts of different kinds, all run to completion (`rc=0`):

| id | kind | script body (file under `analysis/scripts/`) |
|----|------|----------------------------------------------|
| t01 | position test | `check` |
| t02 | position test | `mate` |
| t03 | position test | `stalemate` |
| t04 | material count | `[R]==1 and [r]==1 and [P]==5 and [p]==5 and [QBNqbn]==0` |
| t05 | fixed layout | `Kg1 Rf1 Pf2 Pg2 Ph2` |
| t06 | attack | `⬓ ▦←♕ == 27` |
| t07 | pin (+sort) | `⬓{ sort "number of pinned pieces"{ pin through △ ≥ 3 } }` |
| t08 | xray | `⬓ xray(♕ ♚ ♜)` |
| t09 | flip | `flip(check)` |
| t10 | flipcolor | `flipcolor(mate)` |
| t11 | shift | `⬓ shifthorizontal ♙b2-7≥4` |
| t12 | sort | `sort "npieces" ◭ ≥ 4` |
| t13 | echo (variations) | enpassant echo (see `t13_echo.cql`), run with `bench_var` |
| t14 | regex path `⊢` | `⊢ ―― check ―― check ―― check ―― stalemate` |
| t15 | function + find all | averagedistance body (see `t15_function.cql`) |
| t16 | persistent counters | `if initial/if stalemate/if mate/persistent … false` |
| t17 | comment | `check /// "hi"` |
| t18 | move filter | `legal ――(castle)` |
| t19 | variations + promotion | Babson-like promotion body, run with `bench_var` |
| t21 | move filter | `――=♕` (promotion) |

One candidate (`――x`, capture) was dropped: it errors standalone (needs a path context).

---

## Table 1 — script × cost shares (inclusive % of `cql6_search`)

`total (M Ir)` = millions of instructions. `feed` = `ScidbGameSource::populateGame`,
`visitRoot` = `QPos::visitRoot`, `qpos_init` = `QPos::initialize`, `MB_*` = `MarkBoard::{stalemate,mate,check}`,
`CalcAtt` = `Position::CalcAttacks`, `uassert` = `cqluassert.cpp:uassert`, `AssertPos` = `Position::AssertPos`,
`match_game` = `CqlNode::match_game`, `match_pos` = all `*::match_position` (the deepest filter node).

| id | kind | total (M) | feed | visitRoot | qpos_init | MB_stale | MB_mate | MB_check | CalcAtt | uassert | AssertPos | match_game | match_pos |
|----|------|----------:|-----:|----------:|----------:|---------:|--------:|---------:|--------:|--------:|----------:|-----------:|----------:|
| t01 | check | 1494.4 | 36.0 | 59.3 | 31.5 | 21.1 | 2.27 | 0.81 | 9.1 | 14.0 | 12.6 | 2.6 | 0.0 |
| t02 | mate | 1492.9 | 36.0 | 59.4 | 31.5 | 21.2 | 2.27 | 0.81 | 9.2 | 14.0 | 12.6 | 2.6 | 0.0 |
| t03 | stalemate | 1493.0 | 36.0 | 59.4 | 31.5 | 21.2 | 2.27 | 0.81 | 9.2 | 14.0 | 12.6 | 2.6 | 0.0 |
| t04 | material counts | 1551.8 | 34.7 | 57.1 | 30.3 | 20.3 | 2.19 | 0.78 | 8.8 | 13.7 | 12.1 | 6.2 | 8.8 |
| t05 | fixed layout | 1505.8 | 35.7 | 58.9 | 31.2 | 21.0 | 2.25 | 0.81 | 9.1 | 13.9 | 12.5 | 3.4 | 0.8 |
| t06 | attack (queen squares) | 1896.1 | 28.4 | 46.8 | 24.8 | 16.7 | 1.79 | 0.64 | 7.2 | 14.8 | 9.9 | 23.3 | 21.3 |
| t07 | pin (sort) | 1783.1 | 30.2 | 49.7 | 26.4 | 17.7 | 1.90 | 0.68 | 7.7 | 14.2 | 10.5 | 18.4 | 15.6 |
| t08 | xray | 2211.6 | 24.3 | 40.1 | 21.3 | 14.3 | 1.53 | 0.55 | 6.2 | 21.8 | 8.5 | 34.2 | 32.5 |
| t09 | flip(check) | 1504.0 | 35.8 | 59.0 | 31.2 | 21.0 | 2.26 | 0.81 | 9.1 | 14.1 | 12.5 | 3.2 | 0.6 |
| t10 | flipcolor(mate) | 1502.6 | 35.8 | 59.0 | 31.3 | 21.0 | 2.26 | 0.81 | 9.1 | 14.1 | 12.5 | 3.2 | 0.6 |
| t11 | shift (shifthorizontal) | 2007.7 | 26.8 | 44.2 | 23.4 | 15.7 | 1.69 | 0.61 | 6.8 | 12.0 | 9.3 | 27.5 | 25.6 |
| t12 | sort npieces | 1613.8 | 33.3 | 54.9 | 29.1 | 19.6 | 2.10 | 0.75 | 8.5 | 15.0 | 11.6 | 9.5 | 6.2 |
| t13 | echo (enpassant) | 1632.3 | 33.0 | 56.5 | 29.3 | 19.7 | 2.14 | 0.76 | 8.5 | 15.6 | 11.6 | 8.6 | 5.0 |
| t14 | regex path (4-ply) | 1630.8 | 33.0 | 54.4 | 28.8 | 19.4 | 2.08 | 0.75 | 8.4 | 16.1 | 11.5 | 10.8 | 8.4 |
| t15 | function + find all | 2082.4 | 25.8 | 42.6 | 22.6 | 15.2 | 1.63 | 0.58 | 6.6 | 13.4 | 9.0 | 29.8 | 24.2 |
| t16 | persistent counters | 1565.5 | 34.4 | 56.6 | 30.0 | 20.2 | 2.17 | 0.78 | 8.7 | 14.0 | 12.0 | 7.0 | 2.0 |
| t17 | comment | 1522.9 | 35.3 | 58.2 | 30.9 | 20.7 | 2.23 | 0.80 | 9.0 | 14.3 | 12.3 | 3.6 | 1.0 |
| t18 | move legal (castle) | 1623.3 | 33.1 | 54.6 | 29.0 | 19.5 | 2.09 | 0.75 | 8.4 | 14.5 | 11.6 | 10.3 | 7.9 |
| t19 | variations + promotion | 1732.6 | 31.0 | 53.2 | 27.6 | 18.6 | 2.02 | 0.71 | 8.0 | 16.4 | 10.9 | 13.9 | 10.4 |
| t21 | move promotion | 1570.2 | 34.3 | 56.5 | 29.9 | 20.1 | 2.16 | 0.77 | 8.7 | 14.9 | 12.0 | 7.4 | 4.9 |

Observations:

* **`MB_stalemate` is a constant ~315.8 M Ir (≈21 %) for every non-variation script** and ~321.5 M (18.6 %)
  for the variation scripts — whether or not the script ever asks for stalemate. This is the single most
  obvious eager-but-rarely-needed feature.
* `MB_mate` is a constant ~33.9 M (≈2.3 %), `MB_check` ~12.2 M (≈0.8 %). Both are also computed for every
  position regardless of need.
* `feed` is a near-constant ~538 M (24–36 %) for every script: it does not depend on the filter at all.
* `uassert` is a near-constant ~209–284 M (12–22 %); it is highest (21.8 %) exactly where the total is
  largest (t08) — i.e. it is proportional to per-position work, not to the filter.
* `match_game` grows with filter complexity: 2.6 % for `check`, 18–34 % for attack/pin/xray/shift,
  30 % for function+`find all`.

### Table 1b — where the matching time goes, per script kind

Deepest inclusive costs inside `match_game` (from `callgrind_annotate --inclusive=yes`):

| script | top matching functions (inclusive) |
|--------|-------------------------------------|
| t06 attack | `OrbitNode::match_position` 21.3 %, `RelationalNode::match_position` 20.7 %, `AttackNode::getSquares` 17.3 %, `AttackNode::compute` 17.1 %, `Attack::attacksquare` 14.2 % |
| t07 pin | `OrbitNode::match_position` 15.7 %, `SortNode::match_position` 15.1 %, `SortNode::match_sortvalue` 14.1 %, `PinNode::getSquares` 10.9 %, `PinNode::computexrays` 9.3 % |
| t08 xray | `OrbitNode::match_position` 32.5 %, `RayNode::match_position` 32.0 %, `RayNode::getSquares` 31.8 %, `RayNode::compute` 31.5 %, `RayNode::match_starting` 21.8 % |
| t11 shift | `OrbitNode::match_position` 25.6 %, `RelationalNode::match_position` 24.6 %, `SquareMask::size` 7.5 %, `PieceLoc::getSquares` 2.0 % |
| t15 function/find | `CompoundNode::match_position` 24.2 %, `FindNode::match_position` 23.6 %, `FindNode::match_count` 22.6 %, `LambdaCallNode::match_count` 14.0 %, `AssignNumericNode::match_position` 14.8 % |
| t14 regex path | `PathNode::match_position` 8.4 %, `QMove::invalidMove` 3.6 %, `QMove::validMove` 3.6 %, `QMove::smartFrom` 3.4 % |
| t18 move legal | `MoveLegalNode::match_position` 7.9 %, `MoveLegalNode::compute` 7.7 %, `Attack::castle` 3.5 % |
| t12 sort | `SortNode::match_position` 6.2 %, `SortNode::match_sortvalue` 5.7 %, `handle_new_value` 2.3 % |
| t04 material | `AndNode::match_position` 8.8 % (6.2 % outer), `RelationalNode::match_position` 2.5 % |
| t05 layout | only 3.4 % total matching (pure piece-location tests are cheap) |
| t13 echo / t19 variations | `match_game` 8.6 % / 13.9 %, dominated by position-pair comparison (`MatchNode`) and dash/move filters |

---

## Table 2 — measured savings (patched copies, same 1200 games)

All patched builds produced **identical `nmatches`** to the unmodified build on every script they were run on
(assertions-off and early-exit: all 20; lazy-position-state: the 12 scripts that do not use check/mate/stalemate).

| id | base (M) | noassert (M) | save | lazy (M) | save | early (M) | save |
|----|---------:|-------------:|-----:|---------:|-----:|----------:|-----:|
| t01 check | 1494.4 | 1131.8 | **24.3 %** | – | – | 1476.4 | 1.2 % |
| t02 mate | 1492.9 | 1130.3 | **24.3 %** | – | – | 1496.0 | −0.2 % |
| t03 stalemate | 1493.0 | 1130.4 | **24.3 %** | – | – | 1496.1 | −0.2 % |
| t04 material | 1551.8 | 1189.2 | **23.4 %** | 1189.2 | **23.4 %** | 1553.8 | −0.1 % |
| t05 layout | 1505.8 | 1143.2 | **24.1 %** | 1143.2 | **24.1 %** | 1488.5 | 1.2 % |
| t06 attack | 1896.1 | 1533.5 | **19.1 %** | 1533.4 | **19.1 %** | 1898.8 | −0.1 % |
| t07 pin | 1783.1 | 1420.5 | **20.3 %** | 1420.5 | **20.3 %** | 1785.9 | −0.2 % |
| t08 xray | 2211.6 | 1841.0 | **16.8 %** | 1849.2 | **16.4 %** | 2204.8 | 0.3 % |
| t09 flip(check) | 1504.0 | 1141.4 | **24.1 %** | – | – | 1481.2 | 1.5 % |
| t10 flipcolor(mate) | 1502.6 | 1140.0 | **24.1 %** | – | – | 1505.7 | −0.2 % |
| t11 shift | 2007.7 | 1645.0 | **18.1 %** | 1645.0 | **18.1 %** | 2010.7 | −0.2 % |
| t12 sort | 1613.8 | 1251.2 | **22.5 %** | 1251.2 | **22.5 %** | 1465.1 | (9.2 %)* |
| t13 echo (var) | 1632.3 | 1266.7 | **22.4 %** | 1262.8 | **22.6 %** | 1635.4 | −0.2 % |
| t14 regex path | 1630.8 | 1268.2 | **22.2 %** | – | – | 1633.8 | −0.2 % |
| t15 function | 2082.4 | 1719.7 | **17.4 %** | 1720.0 | **17.4 %** | 2085.5 | −0.1 % |
| t16 persistent | 1565.5 | 1202.9 | **23.2 %** | – | – | 1568.5 | −0.2 % |
| t17 comment | 1522.9 | 1160.3 | **23.8 %** | – | – | 1482.6 | 2.6 % |
| t18 move legal | 1623.3 | 1260.6 | **22.3 %** | 1261.0 | **22.3 %** | 1508.4 | **7.1 %** |
| t19 variations+promo | 1732.6 | 1367.1 | **21.1 %** | 1363.2 | **21.3 %** | 1735.8 | −0.2 % |
| t21 promotion | 1570.2 | 1207.6 | **23.1 %** | 1207.8 | **23.1 %** | 1571.9 | −0.1 % |

\* t12's early-exit saving is **not a valid optimisation**: `sort` needs all positions, so the sort value can
change. It is shown only to bound the effect. The safe early-exit wins are the existence-only scripts
(t18 7.1 %, t17 2.6 %, t09 1.5 %, t01 1.2 %, t05 1.2 %); scripts whose filters rarely match (t06 3 matches,
t11 0 matches) gain nothing.

### Result assembly (only when PGN output is requested)

The default bench passes `want_pgn = 0`, so result assembly is ~0 % of Table 1. I built `analysis/build/bench_pgn`
(`analysis/bench_pgn.cpp`, `opt.want_pgn = 1`) and re-profiled:

| script | want_pgn=0 (M) | want_pgn=1 (M) | `util::game_to_string` | `QGame::mergeComments` | `QPos::mergeComments` |
|--------|---------------:|---------------:|-----------------------:|-----------------------:|----------------------:|
| t01 (1057 matches) | 1494.4 | 2358.4 | 680.4 M (28.9 % of 2358) | 181.9 M (7.7 %) | 180.6 M (7.7 %) |
| t12 (1200 matches) | 1613.8 | 2575.4 | 765.2 M (29.7 % of 2575) | 192.9 M (7.5 %) | 191.3 M (7.4 %) |

So when the caller wants matched games as PGN, result assembly adds ~0.86–0.96 G Ir (~37 % of the new total),
almost all of it re-serialising the game (`util::game_to_string` → `Game::WriteMoveList`) and merging comments
back into the move tree.

---

## Ranked bottlenecks per script kind

1. **Every script (the floor): feed + position-tree + assertions + eager position state.**
   `parseNextGame` is 95–96 % of the run for cheap filters. Inside it:
   * `populateGame` (`scidb_feed.cpp`) 24–36 %: **one full `Position::GenerateMoves` per move**
     (73 359 calls, 315.2 M / 21.1 % for `check`) **plus `Position::MakeSANString` per move**
     (73 359 calls, 130.5 M / 8.7 %).
   * `QPos::visitRoot` 40–59 %: builds the whole position tree and **one `Position::GenerateMoves` per
     position** via `myIsKingInStalemate` (73 152 calls, 314.1 M / 21.0 %), plus board/mask copying in
     `QPos::initialize`.
   * `uassert` 12–22 % (unconditional), `Position::AssertPos` 8.5–12.6 % (only when `-DASSERTIONS`).

2. **Cheap position/piece tests** (`check`, `mate`, `stalemate`, material counts, fixed layout, `flip`,
   `flipcolor`): matching is only 2.6–6 %; the work is the floor above. `flip`/`flipcolor` add essentially
   nothing over the base (`flip(check)` 1504 M vs `check` 1494 M).

3. **Attack / pin / xray / shift:** matching now matters — 18–34 % — and it is *algorithmic*, not per-position
   infrastructure:
   * **xray** is the worst (t08: 34.2 % matching, total 2.21 G): `RayNode::compute`/`match_starting` is 31.5 %.
   * **shift** (t11: 27.5 %): `RelationalNode` over the shifted orbit, 24.6 %; `SquareMask::size` alone 7.5 %.
   * **attack** (t06: 23.3 %): `AttackNode::compute` → `Attack::attacksquare`, 14.2 %.
   * **pin** (t07: 18.4 %): `PinNode::computexrays` + the surrounding `SortNode` (15.1 %) which forces a
     full per-position sort-value evaluation.

4. **`sort`:** `SortNode::match_position` 6.2 %, but `handle_new_value` and sort-value construction add up;
   matching 9.5 %. Combined with the floor, sort scripts are ~1.6 G.

5. **Regex paths (`⊢`):** `PathNode::match_position` 8.4 % plus `QMove::validMove/invalidMove/smartFrom`
   (≈10 % combined) — the path machinery walks move lists and rebuilds square masks.

6. **`function` + `find all`:** the most expensive matching (t15: 29.8 %): `FindNode::match_count` 22.6 %
   and `LambdaCallNode::match_count` 14.0 % (re-entering the function body for every candidate), plus
   `AssignNumericNode` 14.8 %.

7. **Move filters** (`move legal`, promotions): `MoveLegalNode::compute` 7.7 % (t18), which itself calls
   `Attack::castle` (3.5 %) and re-derives attack masks; promotion dash (t21) `DashNode::match_position`
   4.9 % + `QMove::smartFrom` 3.5 %.

8. **`echo` / `variations`:** `visitRoot` rises to 53–57 % because every variation position is materialised;
   `match_game` 8.6–13.9 % on top. `persistent` is cheap matching (7 %) but the whole game is still parsed
   and every position built, even though no game is ever output.

9. **`comment`/`message`:** indistinguishable from the base floor (3.6 % matching).

---

## Eager features that few scripts need (lazy candidates) — with evidence

All of these are computed in `QPos::initialize` / `ScidbGameSource::populateGame` **before** the filter runs,
for every position/move, independent of the script. Evidence = constant inclusive cost across scripts
(`callgrind_annotate --inclusive=yes`, `--tree=caller`).

| eager feature | where | cost (t01) | actually needed by | lazy candidate? |
|---------------|-------|-----------:|--------------------|-----------------|
| `myIsKingInStalemate` → full `GenerateMoves` | `QPos::initialize` (via `MarkBoard::stalemate`) | 314.1 M / **21.0 %** | scripts containing `stalemate`: t03, t14, t16 | **Yes, strongest** — 85 % (17/20) of profiled scripts never use it |
| `populateGame` `GenerateMoves` (all legal moves per move) | `scidb_feed.cpp` | 315.2 M / **21.1 %** (73 359 calls) | every script (to map feed from/to → `simpleMoveT`), but a direct from/to→move lookup would avoid generating all moves | **Yes** — replace with targeted move construction |
| `MakeSANString` per move | `scidb_feed.cpp` | 130.5 M / **8.7 %** (73 359 calls) | only when the caller wants PGN / SAN comments (`want_pgn`, `///` annotation output) | **Yes** — matching never reads SAN |
| `theIsMate` (`myIsKingInMate`) | `QPos::initialize` | 33.9 M / **2.3 %** | scripts containing `mate`: t02, t06, t10, t16 | Yes |
| `theIsCheck` (`myIsKingInCheck`) | `QPos::initialize` | 12.2 M / **0.8 %** | scripts containing `check`: t01, t09, t14, t17 | Yes (cheap) |
| `thePieceMasks` / `theColorMasks` | `QPos::initialize` | part of `QPos::initialize` self ≈75.6 M / ≈5 % (board copy + masks + strings) | `pinnode`, `attacknode`, `pieceloc`, `matchnode` (lrcompare): t04–t08, t11, t12, t14, t19, t21 | Not useful — almost every non-trivial filter uses them |
| `Position::CalcAttacks` | inside check/mate/stalemate and move gen | 136.6 M / 9.1 % | needed wherever attack/check/legal-move logic runs | Indirect — removing the stalemate call removes ~half of it |

`--tree=caller` confirms the call counts are exactly one per position/move:
`GenerateMoves` ← `myIsKingInStalemate` = 73 152 calls; `GenerateMoves` ← `populateGame` = 73 359 calls;
`MakeSANString` ← `populateGame` = 73 359 calls (total positions = 73 152 for 1200 games, ≈61/game).

### Measured saving of switching the eager position state off

Patch `analysis/patch/qpos_lazy.diff` (guards the three lines in `QPos::initialize` with
`#ifndef CQL_LAZY_SKIP_POSSTATE`). Built as `analysis/build/bench_lazy` and `bench_var_lazy`. Run only on the
12 scripts that do not read check/mate/stalemate; **all produced identical `nmatches`**.

Result: **~362.5 M Ir saved per run (16–24 %)** for non-variation scripts, ~369.5 M (21–23 %) for variation
scripts. The saving is essentially constant (the feature cost is per-position, not per-filter), so it is a
larger relative win for cheap scripts (t04 23.4 %) and a smaller one for matching-heavy scripts (t08 16.4 %).
This is the *ceiling*: it assumes the script needs none of the three; a real lazy implementation would pay
back the stalemate cost for t03/t14/t16 and the mate/check cost for the scripts that use them.

```diff
--- qpos.cpp
+++ qpos.cpp
@@ -270,9 +270,11 @@
   }
    for(int i=0;i<64;++i)squares_to_marks[i]=markT(); //for debugging
    for(int i=0;i<markTMax;++i)marks_to_squares[i]=0; // for debugging
+#ifndef CQL_LAZY_SKIP_POSSTATE
   theIsCheck=MarkBoard::check(game);
   theIsMate=MarkBoard::mate(game);
   theIsStalemate=MarkBoard::stalemate(game);
+#endif
 }
```

---

## Assertions: two distinct costs, only one is controlled by `-DASSERTIONS`

Rebuilt **all 295 objects without `-DASSERTIONS`** into `analysis/build/noassert/obj` (same flags otherwise:
`-O2 -g -fno-omit-frame-pointer -DCQL6_EMBEDDED -fPIC`), linked `analysis/build/noassert/bench_noassert` /
`bench_var_noassert`. All 20 scripts produced identical `nmatches`.

* Saving: **~362.6 M Ir, i.e. 16.8–24.3 %** (largest relative for the cheap scripts, smallest for xray).
* Decomposition (`callgrind_annotate`, base vs noassert, t01):
  * `Position::AssertPos` disappears: **187.7 M / 12.6 %** (self: 144.1 M + 43.6 M inlined).
  * `Position::GenerateMoves` inclusive drops 629.4 M → 473.1 M (**≈156 M**), i.e. the `ASSERT(...)` /
    `numAsserts++` statements inside `DoSimpleMove`/`UndoSimpleMove` and friends. This is the move-generation
    hot path, so it is worth ~10 % by itself.
* **`uassert` is *not* controlled by `-DASSERTIONS`** and survives the noassert build at **~187–255 M
  (12.6–16.6 % of the noassert total)** — in t01 it is 14.0 % of the base and 16.6 % of the reduced total.
  It is the single largest self-cost function in the base profile (209.6 M self in t01). Its callers are the
  per-position checks in `QPos::visitRoot` / `QPos::createFromParent` / `QPos::initialize` (72 k–73 k calls
  per site). A release mode that makes these compile-time no-ops (or at least removes them from the
  per-position loops) is a second, independent ~12–16 % win that `-DASSERTIONS` does **not** deliver.

The assertion change is a compile flag, not a source diff:

```
# analysis/build/noassert/obj/*.o: same command as build_prof/obj/*.o with  -DASSERTIONS  removed
g++ -std=c++17 -pthread -O2 -g -fno-omit-frame-pointer -w -DCQL6_EMBEDDED -fPIC -I. -I./orig -c <file> -o analysis/build/noassert/obj/<file>.o
```

---

## Does the engine keep visiting a game's positions after the first match? — **Yes**

Evidence:

* `QPos::visitRoot` builds **all** positions of a game during `parseNextGame`, before any matching starts.
* `CqlNode::match_game` (`cqlnodematch.cpp`) then loops unconditionally:

  ```cpp
  for(QPos*current:qgame->allQPos)
      do_match(filter,current);
  ```

  There is no `break`, and `matched` is only decided afterwards from `matchCountRange->valid(nmatches)` or
  `nmatches>0`. `allQPos` is exactly `73 152` for the 1200-game set, and `CqlNode::do_match` is called
  **73 152 times in every script** (verified with callgrind call counts for t01, t02, t03, t06, t08, t11,
  t12, t18) — including t01 where 1057/1200 games match and t02 where only 202/1200 do.

Measured early-exit experiment: patch `analysis/patch/early_exit.diff` breaks out of the loop once
`matchcount > 0` when `CQL_EARLY` is set (flag cached once; the first attempt that called `getenv` per
position was slower, so the numbers below use the cached version). All 20 scripts gave identical `nmatches`.
Savings are modest and only material for existence scripts that match often:

* t18 `legal ――(castle)`: 1623.3 → 1508.4 M (**7.1 %**)
* t17 `check /// "hi"`: 1522.9 → 1482.6 M (2.6 %)
* t09 `flip(check)`: 1504.0 → 1481.2 M (1.5 %)
* t01 `check`: 1494.4 → 1476.4 M (1.2 %)
* t05 layout: 1505.8 → 1488.5 M (1.2 %)
* t06/t08/t11/t15 (filters that rarely match): no gain (branch overhead ≈ +3 M).
* **t12 `sort` shows 9.2 % but is invalid** — `sort` needs every position, so early exit changes the sort
  value. The same caveat applies to `matchcount` ranges with min>1 and to annotated/`consecutive` output.

So early exit is worth doing only when the script is a pure existence test (no sort variables, no output
that depends on all matches), and even then the ceiling is the `match_game` share (≤10 % for the cheap
filters; for the expensive filters the matches are too rare for it to help).

```diff
--- cqlnodematch.cpp
+++ cqlnodematch.cpp
@@ -38,8 +38,15 @@
 	return true;
       else
 	return false;}
-  for(QPos*current:qgame->allQPos)
+#ifdef CQL_EARLY_EXIT
+  static const bool cql_early = (getenv("CQL_EARLY")!=NULL);
+#endif
+  for(QPos*current:qgame->allQPos){
     do_match(filter,current);
+#ifdef CQL_EARLY_EXIT
+    if (cql_early && mc->getValue()>0) break;
+#endif
+  }
```

---

## Summary of the biggest levers, ranked

1. **Stop generating all legal moves twice per position.** `myIsKingInStalemate` (21 %) and the
   `populateGame` move lookup (21 %) are independent full generations. Making stalemate demand-driven saves
   ~21 % on the 17/20 scripts that do not use it; a from/to→move lookup in the feed would remove most of the
   other 21 %.
2. **Do not build SAN strings unless output is requested** — 8.7 % for every script, 0 for matching.
3. **Release assertions properly**: `-DASSERTIONS`-off saves ~17–24 % (`AssertPos` 12.6 % + move-gen
   `ASSERT` ~10 %); additionally make `uassert` a no-op in release to recover another ~12–16 %, which the
   `-DASSERTIONS` flag does not touch.
4. **Algorithmic work only for the heavy filters**: xray (`RayNode`), shift (`RelationalNode`/`SquareMask::size`),
   attack (`Attack::attacksquare`), pin (`computexrays`), `find all`/`function` (`FindNode`/`LambdaCallNode`).
   These are the scripts where matching itself dominates (18–34 %).
5. **Early exit on first match** for pure existence scripts (up to ~7 %, verified), with the sort/matchcount
   caveat above.

---

## What I could not determine / did not measure

* I did not implement a *true* per-position lazy check/mate/stalemate (the cached value is computed from the
  `Game` while it is positioned at that node; after `visitRoot` the game is back at the initial position, so
  lazy evaluation would need to work from the stored `QPos::board`/`toMove` or a re-positioned game). The
  `CQL_LAZY_SKIP_POSSTATE` patch therefore measures the **ceiling** (skip entirely) on scripts that do not
  use the features, not the cost of a correct lazy implementation.
* I did not split the `thePieceMasks`/`theColorMasks` cost from the rest of `QPos::initialize` self time
  (~75.6 M); every non-trivial script uses them, so a skip-patch would change results.
* I did not measure the feed cost of a from/to→move lookup (only the current all-moves generation, 315 M).
* I did not profile the `g1200` set with more than one thread; the brief fixes 1 thread.
* "Result assembly" was only measured with `want_pgn=1` for t01/t12; the default bench has it at ~0.
* I did not test the `variations` header via the real CQL parser (options like `gamenumber`, `quiet`,
  `result` in example headers are skipped); `variations` was exercised via `opt.variations=1` in a bench copy,
  as the brief allows.
* Callgrind reports instruction counts, not cycles; branch/cache effects (e.g. the ~3 M branch overhead of
  the early-exit patch) are not modelled.

## Artefacts

* `analysis/scripts/t*.cql` — the 20 script bodies.
* `analysis/prof/*.out`, `*.log` — raw callgrind profiles (base, `_noassert`, `_lazy`, `_early`, `_pgn`).
* `analysis/prof/summary_base.csv`, `summary_noassert.csv`, `summary_lazy.csv` — extracted cost shares.
* `analysis/summarize.py`, `analysis/mktable.py` — extraction / table generation.
* `analysis/patch/qpos_lazy.diff`, `analysis/patch/early_exit.diff` — the experimental patches.
* `analysis/patch/compile_noassert.sh` — the 295-object rebuild without `-DASSERTIONS`.
* `analysis/build/bench_lazy`, `bench_var_lazy`, `bench_noassert` (in `analysis/build/noassert/`), `bench_early`,
  `bench_pgn` — patched benchmark binaries (all built from copies; no existing source file was modified).
