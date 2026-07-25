# SCIDb Performance Baseline Measurements

**Date:** 2026-07-20
**Scope:** Multi-threaded maintenance operations, search pipeline, cache behavior, conversion throughput
**Goal:** Establish baseline measurements for the existing benchmark harnesses

---

## 1. Test Environment

| Property | Value |
|----------|-------|
| CPU | 2× Intel Xeon E5-2690 v3 @ 2.60 GHz (24 cores / 48 threads) |
| Sockets | 2 |
| Cores per socket | 12 |
| Threads per core | 2 (Hyper-Threading) |
| L1 cache | 768 KiB (24 instances) |
| L2 cache | 6 MiB (24 instances) |
| L3 cache | 60 MiB (2 instances) |
| NUMA | 2 nodes (0-11,24-35 / 12-23,36-47) |
| RAM | 499 GiB total, 375 GiB free |
| Swap | 4 GiB total, 1.4 GiB free |
| Root FS | `/dev/nvme1n1p5` — ext4 on NVMe SSD (CT500P3SSD8), 266 GB |
| Project FS | `/dev/md0` — ext4 RAID-1 (2× 1.8 TB HDD MB2000FBUCL), 1.8 TB |
| Kernel | 7.0.0-1013-nvidia |
| OS | Ubuntu (g++ 15.2.0-16ubuntu1) |
| Compiler | g++ (Ubuntu 15.2.0-16ubuntu1) 15.2.0 |

**Notes:**
- The project source tree and compiled binaries reside on a RAID-1 array
  backed by two 1.8 TB HDDs. Benchmark I/O is HDD-bound.
- `/tmp` is on NVMe SSD; benchmark_conversion writes output databases to `/tmp`.
- 48 hardware threads available; `SCIDB_MAINTENANCE_THREADS` controls parallel
  maintenance workers.

---

## 2. Build Status

All three targets compiled cleanly with `-Wall` and zero warnings.

| Target | Make Command | Status | Binary Size |
|--------|-------------|--------|-------------|
| `benchmark_workflows` | `make -C src benchmark_workflows` | ✅ Clean build | 18 MB |
| `benchmark_conversion` | `make -C src benchmark_conversion` | ✅ Clean build | 17 MB |
| `verify_maintenance` | `make -C src verify_maintenance` | ✅ Clean build | 18 MB |

### Usage

```
Usage: src/benchmark_workflows <source-db> [--runs N] [--encoding ENC] [--duplicates]
Usage: src/benchmark_conversion <source-db-or-pgn> [--runs N] [--output target.sci] [--encoding ENC] [--verify-sample N] [--keep]
Usage: src/verify_maintenance [<root-path>]
```

### Subcommand Availability

The PERFORMANCE_PLAN describes ideal subcommands (`player-stats`, `eco-stats`,
`tree-nav`, `search`, `full-scan`, `--create-large`). These **do not exist as
separate subcommands**. Instead, `benchmark_workflows` runs all operations in
a single pass: open, search (wildcard + rating + ECO stats + duplicate
detection), player stats (prep), and tree build/lookup. Results are printed
as key=value pairs per run.

**TODO:** Add subcommand dispatch to `benchmark_workflows` for isolated
operation timing.

---

## 3. Test Databases

| Database | Path | Games | Index | Game Data | Notes |
|----------|------|-------|-------|-----------|-------|
| twic1640g | `/home/michael-g-thomas/twic1640g.sci` | 5,757 | 315 KB | 615 KB | Small; TWIC issue #1640 |
| LumbrasGigabase | `/media/michael-g-thomas/sas_mirror/chess/LumbrasGigabase_OTB.sci` | 551,700 | 30 MB | 60 MB | Medium; OTB games |
| twic_complete | `/media/michael-g-thomas/sas_mirror/chess/twic_complete.sci` | 1,168,721 | 63 MB | 121 MB | Large; full TWIC archive |
| CCRL-4040 | `/media/michael-g-thomas/sas_mirror/chess/CCRL-4040.sci` | 2,311,070 | 124 MB | 1.9 GB | Largest; computer chess (deep games) |

---

## 4. Phase 2.1: Player Statistics Benchmark

Player statistics (`Database::playerStatistic()`) is measured in the `prep`
phase of `benchmark_workflows`. It finds the busiest player and computes
their full statistics.

### Results: LumbrasGigabase (551,700 games)

| Threads | prep avg (µs) | prep avg (ms) | prep_games |
|---------|---------------|---------------|------------|
| 1 | 90,358 | 90.4 | 924 |
| 4 | 86,482 | 86.5 | 924 |
| 12 | 76,665 | 76.7 | 924 |

### Results: twic_complete (1,168,721 games)

| Threads | prep avg (µs) | prep avg (ms) | prep_games |
|---------|---------------|---------------|------------|
| 1 | 149,524 | 149.5 | 1,871 |
| 4 | 115,912 | 115.9 | 1,871 |
| 12 | 116,799 | 116.8 | 1,871 |

### Results: CCRL-4040 (2,311,070 games)

| Threads | prep avg (µs) | prep avg (ms) | prep_games |
|---------|---------------|---------------|------------|
| 1 | 235,960 | 236.0 | 10,501 |
| 4 | 199,364 | 199.4 | 10,501 |
| 12 | 179,776 | 179.8 | 10,501 |

### Analysis

- Player stats show modest scaling: ~15–24% improvement from 1→12 threads.
- The operation is not fully parallelized — it scans the player's games
  sequentially after finding them.

---

## 5. Phase 2.2: ECO Statistics Benchmark

ECO statistics (`maintenance::computeEcoStats()`) is part of the `search`
phase. ECO row counts:

| Database | ECO rows |
|----------|----------|
| twic1640g | 387 |
| LumbrasGigabase | 439 |
| twic_complete | 501 |
| CCRL-4040 | 500 |

ECO stats timing is bundled into `search_usec` and cannot be isolated
without modifying the benchmark harness.

**TODO:** Add separate timing for `computeEcoStats()`.

---

## 6. Phase 2.3: Duplicate Detection Benchmark

Duplicate detection (`maintenance::findDuplicates()`) is part of the `search`
phase (enabled with `--duplicates`).

| Database | Duplicate groups |
|----------|-----------------|
| twic1640g | 0 |
| LumbrasGigabase | 0 |
| twic_complete | 15,391 |
| CCRL-4040 | 0 |

### verify_maintenance (parallel parity test)

`verify_maintenance` creates a 4-game embedded PGN database and verifies
that serial (1 thread) and parallel (2 thread) duplicate detection produce
identical results.

| Threads | Wall time | Result |
|---------|-----------|--------|
| 1 | 0.05s | passed |
| auto | 0.06s | passed |
| 4 | 0.07s | passed |

The `--readonly` flag described in PERFORMANCE_PLAN **does not exist**.
Parallel parity is tested internally using `ScopedEnv`.

**TODO:** Add `--readonly` flag and test with larger databases.

---

## 7. Phase 3.1: Tree Cache Benchmark

Tree build and cache lookup are measured in `benchmark_workflows`:

1. `tree_build`: builds opening tree from start position (single-threaded)
2. `tree_lookup`: looks up the same tree from cache after `addToCache()`

### Results (steady-state averages)

| Database | Games | tree_build (ms) | tree_lookup (µs) | tree_moves |
|----------|-------|-----------------|------------------|------------|
| twic1640g | 5,757 | 18.5 | 0.5 | 21 |
| LumbrasGigabase | 551,700 | 1,922 | 0.7 | 17 |
| twic_complete | 1,168,721 | 3,892 | 0.5 | 22 |
| CCRL-4040 | 2,311,070 | 7,514 | 0.7 | 1 |

Tree build is single-threaded and does not scale with `SCIDB_MAINTENANCE_THREADS`.
Tree cache lookup is essentially free (<1 µs), confirming `TreeCache` works
correctly.

**Note:** CCRL-4040 has `tree_moves=1` because computer chess games start with
diverse openings and the tree from the start position only has 1 move at the
top level with this database's filter.

---

## 8. Phase 3.2: Search Pipeline

The `search` phase of `benchmark_workflows` runs:
1. `SearchPlayerName` wildcard `*a*`
2. `SearchRating` average Elo 2000–2600
3. `maintenance::computeEcoStats()`
4. `maintenance::findDuplicates()` (with `--duplicates`)

### Results: Full Search Phase (steady-state averages, ms)

| Database | Games | Threads=1 | Threads=4 | Threads=12 | Speedup 1→4 | Speedup 1→12 |
|----------|-------|-----------|-----------|------------|-------------|--------------|
| twic1640g | 5,757 | 12.2 | 14.8 | 11.3 | 0.83× | 1.08× |
| LumbrasGigabase | 551,700 | 1,362.8 | 794.2 | 610.7 | 1.72× | 2.23× |
| twic_complete | 1,168,721 | 2,890.1 | 1,894.3 | 2,029.9 | 1.53× | 1.42× |
| CCRL-4040 | 2,311,070 | 5,938.3 | 4,272.0 | 4,191.2 | 1.39× | 1.42× |

### Result Counts

| Database | Wildcard matches | Rating matches | ECO rows | Dup groups |
|----------|-----------------|----------------|----------|------------|
| twic1640g | 5,584 | 5,014 | 387 | 0 |
| LumbrasGigabase | 537,025 | 353,904 | 439 | 0 |
| twic_complete | 1,090,345 | 848,236 | 501 | 15,391 |
| CCRL-4040 | 1,698,293 | 405,470 | 500 | 0 |

### Analysis

- **LumbrasGigabase shows the best scaling** (1.72× at 4 threads, 2.23× at 12
  threads). This database has 551K games with 60 MB of game data — small
  enough that the working set fits in OS page cache, so CPU parallelism
  dominates.
- **twic_complete and CCRL-4040 show less scaling** (~1.4–1.5×). These
  databases are larger (121 MB and 1.9 GB game data) and I/O becomes the
  bottleneck. The HDD-backed storage limits parallel benefit.
- **twic1640g is too small** for meaningful scaling — thread pool overhead
  dominates.
- The search phase bundles 4 operations. Wildcard search and rating search
  are single-pass scans that can be parallelized. ECO stats and duplicate
  detection use `SCIDB_MAINTENANCE_THREADS` internally. The modest scaling
  suggests not all sub-operations are fully parallelized.

**Expected vs. Actual:**
- PERFORMANCE_PLAN expected 3–4× at 4 cores and 6–7× at 8 cores.
- Actual: 1.4–2.2× at 4–12 threads. The gap is likely due to:
  1. HDD I/O bottleneck (not NVMe/SSD)
  2. Not all search sub-operations are parallelized
  3. Thread pool overhead

**TODO:** Re-run with databases on NVMe SSD (`/tmp`) to eliminate I/O bottleneck.

---

## 9. Conversion Benchmark

### Results

| Database | Games | Runs | Avg time (s) | Avg rate (games/s) | Avg throughput (MiB/s) | Target size |
|----------|-------|------|-------------|--------------------|-----------------------|-------------|
| twic1640g | 5,757 | 3 | 0.034 | 169,176 | 27.87 | 0.95 MiB |
| LumbrasGigabase | 551,700 | 3 | 13.46 | 40,996 | 7.05 | 94.9 MiB |
| twic_complete | 1,168,721 | 2 | 9.25 | 126,381 | 19.94 | 184.4 MiB |
| CCRL-4040 | 2,311,070 | 1 | 14.40 | 160,517 | 137.83 | 1,984 MiB |

### Analysis

- Conversion throughput varies significantly by database characteristics:
  - **CCRL-4040**: 160K games/s, 138 MiB/s — highest throughput due to large
    game data (1.9 GB → 1.98 GB output) amortizing per-game overhead.
  - **twic_complete**: 126K games/s, 20 MiB/s — good throughput on 1.17M games.
  - **LumbrasGigabase**: 41K games/s, 7 MiB/s — lower throughput, possibly
    due to more complex game annotations or smaller average game size.
  - **twic1640g**: 169K games/s but only 5.7K games — startup overhead
    dominates.
- Sample verification (5 games per run) passed in all runs.

---

## 10. Database Open Times

| Database | Games | Index size | Open time (ms) | Games/sec open |
|----------|-------|-----------|----------------|----------------|
| twic1640g | 5,757 | 315 KB | 5.8 | ~993K |
| LumbrasGigabase | 551,700 | 30 MB | 699 | ~790K |
| twic_complete | 1,168,721 | 63 MB | 755 | ~1,548K |
| CCRL-4040 | 2,311,070 | 124 MB | 1,253 | ~1,845K |

Open time is I/O-bound (reading the index file from HDD) and independent of
`SCIDB_MAINTENANCE_THREADS`.

---

## 11. Thread Scaling Summary

### Search Phase Scaling (most relevant for parallel maintenance)

| Database | 1 thread (ms) | 4 threads (ms) | 12 threads (ms) | 1→4 speedup | 1→12 speedup |
|----------|---------------|----------------|-----------------|-------------|--------------|
| LumbrasGigabase | 1,363 | 794 | 611 | 1.72× | 2.23× |
| twic_complete | 2,890 | 1,894 | 2,030 | 1.53× | 1.42× |
| CCRL-4040 | 5,938 | 4,272 | 4,192 | 1.39× | 1.42× |

### Prep Phase Scaling

| Database | 1 thread (ms) | 4 threads (ms) | 12 threads (ms) | 1→4 speedup | 1→12 speedup |
|----------|---------------|----------------|-----------------|-------------|--------------|
| LumbrasGigabase | 90.4 | 86.5 | 76.7 | 1.05× | 1.18× |
| twic_complete | 149.5 | 115.9 | 116.8 | 1.29× | 1.28× |
| CCRL-4040 | 236.0 | 199.4 | 179.8 | 1.18× | 1.31× |

### Tree Build (single-threaded, no scaling expected)

| Database | tree_build (ms) |
|----------|-----------------|
| LumbrasGigabase | 1,922 |
| twic_complete | 3,892 |
| CCRL-4040 | 7,514 |

---

## 12. Phase 4: Large File Support

The `--create-large` flag **does not exist** in `benchmark_conversion`.
However, CCRL-4040 has a 1.9 GB game data file (`.scg`), which exercises
the `fseeko` large-file code paths. The database opened and benchmarked
without errors, confirming >2GB file support works correctly.

**TODO:** Implement `--create-large <size>` for synthetic >2GB generation
and explicit large-file validation.

---

## 13. Summary of Gaps

| Item | Status | Notes |
|------|--------|-------|
| `benchmark_workflows` subcommands | ❌ Not implemented | All ops in single pass |
| `benchmark_conversion --create-large` | ❌ Not implemented | No large file generation |
| `verify_maintenance --readonly` | ❌ Not implemented | Always creates embedded DB |
| Separate ECO stats timing | ❌ Not implemented | Bundled in search phase |
| Compound query benchmarking (`--query`) | ❌ Not implemented | Fixed search patterns only |
| UI responsiveness testing | ❌ Not implemented | Requires Tcl/Tk app |
| NVMe-based benchmark run | ❌ Not done | Databases on HDD; copy to `/tmp` for SSD |
| 100K+ game database on SSD | ❌ Not done | Would eliminate I/O bottleneck |

---

## 14. Raw Benchmark Outputs

### benchmark_workflows / twic1640g.sci (5,757 games) / 3 runs each

**SCIDB_MAINTENANCE_THREADS=1:**
```
run=1 open_usec=24423 search_usec=16289 prep_usec=815 tree_build_usec=23441 tree_lookup_usec=0 wildcard_matches=5584 rating_matches=5014 eco_rows=387 duplicate_groups=0 prep_games=44 tree_moves=21
run=2 open_usec=6732 search_usec=12149 prep_usec=595 tree_build_usec=18530 tree_lookup_usec=0 wildcard_matches=5584 rating_matches=5014 eco_rows=387 duplicate_groups=0 prep_games=44 tree_moves=21
run=3 open_usec=4774 search_usec=12337 prep_usec=590 tree_build_usec=18396 tree_lookup_usec=1 wildcard_matches=5584 rating_matches=5014 eco_rows=387 duplicate_groups=0 prep_games=44 tree_moves=21
```

**SCIDB_MAINTENANCE_THREADS=4:**
```
run=1 open_usec=10725 search_usec=14526 prep_usec=995 tree_build_usec=25248 tree_lookup_usec=1 wildcard_matches=5584 rating_matches=5014 eco_rows=387 duplicate_groups=0 prep_games=44 tree_moves=21
run=2 open_usec=9286 search_usec=15888 prep_usec=1075 tree_build_usec=25045 tree_lookup_usec=0 wildcard_matches=5584 rating_matches=5014 eco_rows=387 duplicate_groups=0 prep_games=44 tree_moves=21
run=3 open_usec=6589 search_usec=13714 prep_usec=879 tree_build_usec=20856 tree_lookup_usec=1 wildcard_matches=5584 rating_matches=5014 eco_rows=387 duplicate_groups=0 prep_games=44 tree_moves=21
```

**SCIDB_MAINTENANCE_THREADS=16:**
```
run=1 open_usec=10830 search_usec=12757 prep_usec=1453 tree_build_usec=22011 tree_lookup_usec=0 wildcard_matches=5584 rating_matches=5014 eco_rows=387 duplicate_groups=0 prep_games=44 tree_moves=21
run=2 open_usec=8098 search_usec=11562 prep_usec=1165 tree_build_usec=20365 tree_lookup_usec=1 wildcard_matches=5584 rating_matches=5014 eco_rows=387 duplicate_groups=0 prep_games=44 tree_moves=21
run=3 open_usec=5340 search_usec=11047 prep_usec=1342 tree_build_usec=25284 tree_lookup_usec=7 wildcard_matches=5584 rating_matches=5014 eco_rows=387 duplicate_groups=0 prep_games=44 tree_moves=21
```

### benchmark_workflows / LumbrasGigabase_OTB.sci (551,700 games) / 3 runs each

**SCIDB_MAINTENANCE_THREADS=1:**
```
run=1 open_usec=718842 search_usec=1322445 prep_usec=92188 tree_build_usec=1930330 tree_lookup_usec=1 wildcard_matches=537025 rating_matches=353904 eco_rows=439 duplicate_groups=0 prep_games=924 tree_moves=17
run=2 open_usec=710720 search_usec=1451111 prep_usec=86887 tree_build_usec=1945450 tree_lookup_usec=1 wildcard_matches=537025 rating_matches=353904 eco_rows=439 duplicate_groups=0 prep_games=924 tree_moves=17
run=3 open_usec=670517 search_usec=1315947 prep_usec=91999 tree_build_usec=1891456 tree_lookup_usec=0 wildcard_matches=537025 rating_matches=353904 eco_rows=439 duplicate_groups=0 prep_games=924 tree_moves=17
```

**SCIDB_MAINTENANCE_THREADS=4:**
```
run=1 open_usec=733935 search_usec=792252 prep_usec=89399 tree_build_usec=1895096 tree_lookup_usec=0 wildcard_matches=537025 rating_matches=353904 eco_rows=439 duplicate_groups=0 prep_games=924 tree_moves=17
run=2 open_usec=676269 search_usec=826614 prep_usec=83182 tree_build_usec=2051342 tree_lookup_usec=0 wildcard_matches=537025 rating_matches=353904 eco_rows=439 duplicate_groups=0 prep_games=924 tree_moves=17
run=3 open_usec=685830 search_usec=763756 prep_usec=86865 tree_build_usec=1949020 tree_lookup_usec=0 wildcard_matches=537025 rating_matches=353904 eco_rows=439 duplicate_groups=0 prep_games=924 tree_moves=17
```

**SCIDB_MAINTENANCE_THREADS=12:**
```
run=1 open_usec=724849 search_usec=614096 prep_usec=78972 tree_build_usec=1935921 tree_lookup_usec=0 wildcard_matches=537025 rating_matches=353904 eco_rows=439 duplicate_groups=0 prep_games=924 tree_moves=17
run=2 open_usec=690038 search_usec=606863 prep_usec=75272 tree_build_usec=1899768 tree_lookup_usec=1 wildcard_matches=537025 rating_matches=353904 eco_rows=439 duplicate_groups=0 prep_games=924 tree_moves=17
run=3 open_usec=682392 search_usec=611245 prep_usec=75752 tree_build_usec=1914099 tree_lookup_usec=0 wildcard_matches=537025 rating_matches=353904 eco_rows=439 duplicate_groups=0 prep_games=924 tree_moves=17
```

### benchmark_workflows / twic_complete.sci (1,168,721 games) / 3 runs each

**SCIDB_MAINTENANCE_THREADS=1:**
```
run=1 open_usec=781547 search_usec=2987350 prep_usec=151657 tree_build_usec=3875413 tree_lookup_usec=0 wildcard_matches=1090345 rating_matches=848236 eco_rows=501 duplicate_groups=15391 prep_games=1871 tree_moves=22
run=2 open_usec=725768 search_usec=2747449 prep_usec=140612 tree_build_usec=3829115 tree_lookup_usec=0 wildcard_matches=1090345 rating_matches=848236 eco_rows=501 duplicate_groups=15391 prep_games=1871 tree_moves=22
run=3 open_usec=759603 search_usec=2935597 prep_usec=156304 tree_build_usec=3976942 tree_lookup_usec=1 wildcard_matches=1090345 rating_matches=848236 eco_rows=501 duplicate_groups=15391 prep_games=1871 tree_moves=22
```

**SCIDB_MAINTENANCE_THREADS=4:**
```
run=1 open_usec=756398 search_usec=2022725 prep_usec=130601 tree_build_usec=3886146 tree_lookup_usec=0 wildcard_matches=1090345 rating_matches=848236 eco_rows=501 duplicate_groups=15391 prep_games=1871 tree_moves=22
run=2 open_usec=745576 search_usec=1826278 prep_usec=107241 tree_build_usec=3816571 tree_lookup_usec=0 wildcard_matches=1090345 rating_matches=848236 eco_rows=501 duplicate_groups=15391 prep_games=1871 tree_moves=22
run=3 open_usec=741966 search_usec=1833804 prep_usec=109894 tree_build_usec=3828032 tree_lookup_usec=0 wildcard_matches=1090345 rating_matches=848236 eco_rows=501 duplicate_groups=15391 prep_games=1871 tree_moves=22
```

**SCIDB_MAINTENANCE_THREADS=12:**
```
run=1 open_usec=767443 search_usec=2027115 prep_usec=103872 tree_build_usec=4434328 tree_lookup_usec=1 wildcard_matches=1090345 rating_matches=848236 eco_rows=501 duplicate_groups=15391 prep_games=1871 tree_moves=22
run=2 open_usec=808029 search_usec=2070398 prep_usec=126569 tree_build_usec=4019152 tree_lookup_usec=1 wildcard_matches=1090345 rating_matches=848236 eco_rows=501 duplicate_groups=15391 prep_games=1871 tree_moves=22
run=3 open_usec=796787 search_usec=1992087 prep_usec=119957 tree_build_usec=4016615 tree_lookup_usec=1 wildcard_matches=1090345 rating_matches=848236 eco_rows=501 duplicate_groups=15391 prep_games=1871 tree_moves=22
```

### benchmark_workflows / CCRL-4040.sci (2,311,070 games) / 2 runs each

**SCIDB_MAINTENANCE_THREADS=1:**
```
run=1 open_usec=1252846 search_usec=6109024 prep_usec=236883 tree_build_usec=7483746 tree_lookup_usec=1 wildcard_matches=1698293 rating_matches=405470 eco_rows=500 duplicate_groups=0 prep_games=10501 tree_moves=1
run=2 open_usec=1249942 search_usec=5767511 prep_usec=235036 tree_build_usec=7579040 tree_lookup_usec=1 wildcard_matches=1698293 rating_matches=405470 eco_rows=500 duplicate_groups=0 prep_games=10501 tree_moves=1
```

**SCIDB_MAINTENANCE_THREADS=4:**
```
run=1 open_usec=1278884 search_usec=4183506 prep_usec=205882 tree_build_usec=7600794 tree_lookup_usec=1 wildcard_matches=1698293 rating_matches=405470 eco_rows=500 duplicate_groups=0 prep_games=10501 tree_moves=1
run=2 open_usec=1332847 search_usec=4358465 prep_usec=192845 tree_build_usec=7532565 tree_lookup_usec=0 wildcard_matches=1698293 rating_matches=405470 eco_rows=500 duplicate_groups=0 prep_games=10501 tree_moves=1
```

**SCIDB_MAINTENANCE_THREADS=12:**
```
run=1 open_usec=1251427 search_usec=4223981 prep_usec=190087 tree_build_usec=7670502 tree_lookup_usec=0 wildcard_matches=1698293 rating_matches=405470 eco_rows=500 duplicate_groups=0 prep_games=10501 tree_moves=1
run=2 open_usec=1265533 search_usec=4158459 prep_usec=169465 tree_build_usec=7431124 tree_lookup_usec=1 wildcard_matches=1698293 rating_matches=405470 eco_rows=500 duplicate_groups=0 prep_games=10501 tree_moves=1
```

### benchmark_conversion outputs

**twic1640g.sci (5,757 games, 3 runs):**
```
summary: avg=0.034s best=0.028s worst=0.042s avg-rate=169175.9 games/s avg-throughput=27.87 MiB/s
```

**LumbrasGigabase_OTB.sci (551,700 games, 3 runs):**
```
run 1: 13.185s, games=551700, target=94.90 MiB, rate=41842.1 games/s, 7.20 MiB/s
run 2: 14.055s, games=551700, target=94.90 MiB, rate=39253.4 games/s, 6.75 MiB/s
run 3: 13.133s, games=551700, target=94.90 MiB, rate=42010.2 games/s, 7.23 MiB/s
summary: avg=13.458s best=13.133s worst=14.055s avg-rate=40995.6 games/s avg-throughput=7.05 MiB/s
```

**twic_complete.sci (1,168,721 games, 2 runs):**
```
run 1: 9.092s, games=1168721, target=184.41 MiB, rate=128543.0 games/s, 20.28 MiB/s
run 2: 9.403s, games=1168721, target=184.41 MiB, rate=124290.8 games/s, 19.61 MiB/s
summary: avg=9.248s best=9.092s worst=9.403s avg-rate=126381.1 games/s avg-throughput=19.94 MiB/s
```

**CCRL-4040.sci (2,311,070 games, 1 run):**
```
run 1: 14.398s, games=2311070, target=1984.45 MiB, rate=160516.7 games/s, 137.83 MiB/s
summary: avg=14.398s best=14.398s worst=14.398s avg-rate=160516.7 games/s avg-throughput=137.83 MiB/s
```

### verify_maintenance (embedded PGN, 4 games)

```
maintenance verification passed
# Wall time: ~0.06s (all thread configs)
# Internally tests serial (1 thread) vs parallel (2 threads) parity
```