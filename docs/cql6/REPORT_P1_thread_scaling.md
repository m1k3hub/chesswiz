# REPORT_P1 — CQL6 multi-thread scaling analysis

Analysis-only study of why the CQL6 search engine scales badly with `--threads`.
All measurements were run in this working tree against the pristine build in `build/`
and against experimental copies under `/tmp/p1*`. No source file in the working tree
was modified (the experimental patches live in `/tmp/p1exp*` and are reproduced as
diffs in `analysis/patch*.diff`).

---

## 0. TL;DR

The engine does **not** run out of parallel work. Under load it does *more work per
game*, and the extra work is pure memory-system waste concentrated on **one shared
cache line** plus **per-thread setup done serially on the main thread**.

Measured on the 5538-game DB `g20k.pgn` (`check`, wall time, min of 7, cores 0-15):

| threads | pristine `build/bench` | all fixes | speedup |
|--------:|-----------------------:|----------:|--------:|
| 1       | 1.036 s                | 0.893 s   | 1.16x   |
| 2       | 0.768 s                | 0.464 s   | 1.66x   |
| 4       | 0.733 s                | 0.243 s   | 3.02x   |
| 8       | 0.868 s                | 0.131 s   | 6.63x   |
| 16      | 1.249 s                | 0.078 s   | 16.0x   |
| 24      | 1.584 s                | 0.072 s   | 22.0x   |
| 32      | 1.618 s                | 0.079 s   | 20.5x   |

CPU time per *identical* run stays flat from 1 to 32 threads with the fixes
(≈1.1 s), whereas the pristine build inflates CPU time roughly 1x → 2x → 3x →…
(see §2.2 and §5). Root causes, in order of impact:

1. **`numAsserts++` inside the `ASSERT()` macro** (`orig/myassert.h:34`) — a single
   global `int` incremented **~79 million times per run** by every thread. All
   workers fight over one cache line. *Removing it alone gives 2.5x at 8 threads.*
2. **`QGame` (38.4 MB) is constructed by the main thread, one per worker, before the
   worker starts** (`cql6_api.cpp`, worker setup). Cost is linear in thread count
   (~22 ms each ⇒ **1.07 s at 47 threads**). *Fixing it makes setup O(1).*
3. **`QPosPoolSize{50000}`** (`qgame.h:66`) makes every `QGame` 38.4 MB while the
   real maximum is **249** QPos per game — a 200x over-allocation that destroys
   per-thread cache locality. *Shrinking it alone gives 1.34x at 8 threads.*
4. **`QPos::visitRoot` runs an O(n²) assertion loop** (`qpos-visit.cpp`) that issues
   ~n² `uassert()` calls for n ≈ 250 positions per game. *O(n) version gives ~9%.*

A process-level control experiment (§3) proves this is **intra-process** contention,
not CPU oversubscription:

```
8 separate 1-thread processes, each pinned to cores 0..7 :  0.199 ms CPU / game  (each)
1 process with 8 threads,        pinned to cores 0..7    :  1.016 ms CPU / game
```

The 8 processes deliver the same wall-time work at **6.5x the throughput** of one
8-thread process, on the same cores, for the same total data. The engine is
self-defeating: the *more* threads you give it, the *more* CPU each game consumes.

---

## 1. What the program does (as understood from the source)

* `tests/bench.cpp` (and my CPU-instrumented clone `bench_cpu`) call
  `cql6_search(script, &opt, feedNextGame, &fc, &res, err, errlen)`.
* `cql6_api.cpp:cql6_search` builds the CQL node tree once, then, for
  `threads = opt.threads`, does `new QGame(&game_source, i, …)` **serially on the
  calling thread**, then spawns one worker per `QGame`.
* Each worker loop (`embedded_thread_worker`) pulls games through the shared
  `game_source.populateGame()` → `qgame->parseNextGame()` → `cqlnode->match_game()`
  and appends results to a per-thread vector.
* The shared `game_source` (a `ScidbGameSource`) hands out games; the per-move work
  (legality, SAN strings, move lists) happens inside each worker's own `QGame`.

So in principle every worker is independent. The question is why they interfere.

---

## 2. Baseline measurements (pristine `build/bench`)

### 2.1 Wall-time scaling (`check`, 5538 games)

| threads | wall (s) | games/s | 
|--------:|---------:|--------:|
| 1       | 1.077    | 5142    |
| 2       | 0.752    | 7364    |
| 4       | 0.968    | 5721    |
| 8       | 1.087    | 5095    |
| 16      | 1.010    | 5483    |
| 32      | 1.687    | 3283    |
| 47      | 2.165    | 2558    |

Best case is ~2 threads (~1.43x). At 8+ threads the program is **slower than
single-threaded**. This is the headline symptom.

### 2.2 CPU time inflation (identical work, `bench_cpu`, min of 3 runs)

`cpu` is `getrusage(RUSAGE_SELF)` user time; `eff = cpu / wall`.

| threads | wall   | cpu    | eff  |
|--------:|-------:|-------:|-----:|
| 1       | 0.693  | 0.678  | 0.98 |
| 2       | 0.473  | 0.858  | 1.81 |
| 4       | 0.464  | 1.481  | 3.19 |
| 8       | 0.716  | 4.155  | 5.80 |
| 16      | 0.914  | 8.497  | 9.30 |
| 32      | 1.331  | 16.745 | 12.6 |
| 47      | 1.822  | 19.568 | 10.7 |

The **same 5538 games** cost 0.68 s of CPU at 1 thread but 19.6 s at 47 threads —
a **29x CPU blow-up**. Effective parallelism peaks at 12.6 (of 48 logical CPUs) and
falls off. This is the diagnostic that drives the whole investigation: the engine is
not starved of parallelism, it *creates* wasteful work.

### 2.3 Start-up is serial and linear in threads

On a 5-game DB (`g5.pgn`), where there is nothing to compute, wall time still grows
linearly with threads: `1→0.020 s, 8→0.198 s, 16→0.388 s, 32→0.813 s, 47→1.193 s`
(≈25 ms/thread). A direct probe of the setup path:

```
parse 8 nodes:                     0.151 ms total
construct 8 QGames:              173.7 ms total (21.7 ms each)   <-- serial, main thread
create 7 worker threads:           0.6 ms
```

So per-thread start-up ≈ 21.7 ms, entirely `new QGame` (zero-filling 38.4 MB).
Parsing and `std::thread` creation are negligible.

---

## 3. Locating the interference

Three experiments narrowed it down.

**(a) Not CPU oversubscription.** Under `valgrind --tool=cachegrind` (which
serialises threads) the 4-thread CPU inflation nearly disappears:

| threads | native cpu | cachegrind cpu | cachegrind wall |
|--------:|-----------:|---------------:|----------------:|
| 1       | 0.678      | 0.574          | 0.592 |
| 4       | 1.481      | 0.674          | 0.775 |

With execution serialised, 4 threads cost almost the same CPU as 1 thread. So the
extra CPU is **memory-parallelism / cache-coherence stalls**, not extra instructions.

**(b) Not other tenants on the box.** 8 *separate* single-thread processes show **no**
per-game inflation, even while the box is loaded (load average ~25):

```
8 procs x 1 thread, each on g20k : per-proc cpu 1.07..1.15 s  (sum 8.87 s)
1 proc  x 8 threads,        g20k : cpu 7.15 s   (for 1/8th the games)
```

Same cores, same data, same concurrency — only the *process boundary* differs.

**(c) Not the `taskset` placement alone.** 2 threads on one CPU cost 1.075 s total;
2 threads on two physical cores cost 1.64–1.93 s. The waste appears only once threads
run *truly in parallel* and share an address space.

**Conclusion:** a shared, writable, contended memory location inside the process.

### 3.1 Pinpointing it with ThreadSanitizer

The brief states `-fsanitize=thread` builds and works, so a TSan build was made
(`/tmp/p1tsan`, all 300 translation units with `-fsanitize=thread`). Running
`bench_tsan` on 4 threads produced **1754 warnings**, and *every single one* was the
same location:

```
1713  Location is global 'numAsserts' at 0x5555558953c8 (bench_tsan+0x3413c8)
```

`orig/myassert.h`:

```c
extern int numAsserts;                 // orig/myassert.cpp:20
#define ASSERT(f)                      \
    numAsserts++;                      \
    if (f) {} else _MyAssert(__FILE__, __LINE__)
```

`numAsserts` is a **write-only global counter** (nothing anywhere reads it) that is
incremented on **every** `ASSERT()` in the codebase — and `ASSERT()` is used
throughout the hot path (`orig/movelist.h` `Add`/`Get`, `orig/position.cpp`
`AddPiece`, `GenerateMoves`, `MakeSANString`, …). Measured rate:

```
threads=1 games=5538 numAsserts=78914271  (14249.6 asserts/game)
```

**79 million `lock`-prefixed read-modify-writes to one cache line per run.** With N
threads each core must take ownership of that line to bump it, serialising the
workers and generating a coherence-miss storm. This is the dominant effect.

---

## 4. Fixes, each measured in isolation

All experiments were built in full (a fresh `build/`; see §7 for the Makefile trap
that invalidated a first, careless attempt) and correctness was re-checked after each
change against the pristine result (`check` ⇒ 4857 matches, `mate` ⇒ 521 matches).

### F1 — Remove the global `numAsserts++` counter  → **2.5x @ 8 threads**

`analysis/patch1_remove_numAsserts.diff`:

```diff
--- orig/myassert.h
+++ orig/myassert.h
@@
     #define ASSERT(f)               \
-        numAsserts++;               \
         if (f)                      \
             {}                      \
         else                        \
             _MyAssert(__FILE__, __LINE__)
```

`numAsserts` is never read, so the increment can be deleted outright (the external
definition may stay for ABI/back-compat). Interleaved A/B at 8 threads pinned to
cores 0-7:

```
base=0.853 fixed=0.347     base=0.888 fixed=0.349
base=0.844 fixed=0.358     base=0.884 fixed=0.350
base=0.894 fixed=0.354     base=0.837 fixed=0.350
```

**0.87 s → 0.35 s (2.5x).** At 1 thread it is neutral (1.020 s vs 1.010 s), exactly
as expected for a pure shared-write elimination.

### F2 — Construct `QGame` inside the worker thread  → **start-up O(1)**

`QGame` is 38400288 bytes (`sizeof(QPos)=768`, `50000*768 + 288`). It is allocated by
the main thread before the worker starts. Measuring serial vs. one-thread-per-`QGame`
construction of the same objects:

```
SERIAL   construct  8 QGames:  177.3 ms     PARALLEL (8 threads):  28.0 ms
SERIAL   construct 16 QGames:  355.6 ms     PARALLEL (16 threads): 28.7 ms
SERIAL   construct 47 QGames: 1066.0 ms     PARALLEL (47 threads): 67.3 ms
```

Moving the `new QGame(...)` into the worker (or a parallel construction phase)
removes ~1.0 s from the 47-thread start-up and makes it flat in thread count:
**1.07 s → 0.07 s at 47 threads**. The patch is structural, not a one-liner, so it is
described rather than diffed: in `cql6_api.cpp`, let each `std::thread` lambda do its
own `qgame->game = new Game; qgame->reset()` before entering
`embedded_thread_worker`, and construct the worker-thread `QGame` there.

### F3 — Shrink `QPosPoolSize` from 50000 to 1024  → **1.34x @ 8 threads**

`analysis/patch2_shrink_QPosPool.diff`:

```diff
--- qgame.h
+++ qgame.h
@@
-  static const int QPosPoolSize{50000};
+  static const int QPosPoolSize{1024};
   std::array<QPos,QPosPoolSize> QPosPool;
```

Instrumented max over the whole DB:

```
games=5000 maxQPos=249
```

249 is the true maximum; the pool is 200x oversized, giving every thread a 38.4 MB
scratch array when 191 KB suffices. `getNewQPos` already guards overflow
(`qgame.cpp:120`: `if (nextQPosIndex >= QPosPoolSize-10) error(...)`), so 1024 fails
loudly rather than silently if a pathological game exceeds it (raise to 4096 for
head-room). Interleaved A/B at 8 threads pinned:

```
base=0.870 poolonly=0.639    base=0.845 poolonly=0.630
base=0.843 poolonly=0.692    base=0.904 poolonly=0.647
```

**0.87 s → 0.65 s (1.34x).** The gain is cache/TLB locality: only ~249 of the 50000
slots are touched, so with the large pool the live `QPos` are spread across 38 MB and
every access misses cache; a small pool keeps them dense and L2-resident.

### F4 — Make `QPos::visitRoot` O(n) instead of O(n²)  → **~9% @ 8 threads**

`analysis/patch3_visitRoot_On2.diff`:

```diff
--- qpos-visit.cpp
+++ qpos-visit.cpp
@@
   int n=(int)(all.size());
-  for (int i=0;i<n;++i)
-    for(int j=0;j<n;++j){
-      auto iv=all[i];
-      auto jv=all[j];
-      uassert(iv->index==i&&jv->index==j,"visitroot ij");
-      //      bool isdesc= (i<=j && j<=iv->lastDescendantIndex);
-      //      uassert(isdesc == slowDescendant(iv,jv),"visitroot slowd");
-    }
+  for (int i=0;i<n;++i){
+      auto iv=all[i];
+      uassert(iv->index==i,"visitroot ij");
+  }
```

The O(n²) loop only checks `iv->index==i && jv->index==j`; the `j` iteration is
redundant (the `jv` checks are implied by the `i` checks). n≈250 ⇒ 62500 `uassert()`
calls/game ≈ **346 M calls per run** for no information. The inner commented-out
`slowDescendant` cross-check is itself O(n) and was disabled anyway. `p3b` (F1+F3)
0.146 s → `p6` (F1+F3+F4) 0.133 s:

```
p3b=0.157 p6=0.133    p3b=0.146 p6=0.133
p3b=0.146 p6=0.135    p3b=0.145 p6=0.131
```

---

## 5. Effect of the fixes

### 5.1 CPU time becomes flat (the point of the exercise)

Pinned to N distinct cores, `check`, `bench_cpu` run 2 (single measurement per point;
the box is shared, so treat each cell as ±10%):

| threads | BASE wall | BASE cpu | BASE eff | FIXED wall | FIXED cpu | FIXED eff |
|--------:|----------:|---------:|---------:|-----------:|----------:|----------:|
| 1       | 1.452     | 1.411    | 0.97     | 0.884      | 0.877     | 0.99      |
| 4       | 0.707     | 2.450    | 3.47     | 0.252      | 0.997     | 3.95      |
| 8       | 0.850     | 5.210    | 6.13     | 0.136      | 1.051     | 7.73      |
| 16      | 1.404     | 9.651    | 6.87     | 0.075      | 1.133     | 15.12     |
| 32      | 1.764     | 29.111   | 16.51    | 0.064      | 1.497     | 23.53     |

CPU time for the *same* 5538 games:

* **BASE**: 1.41 s → 29.1 s from 1 to 32 threads — a **20.6x** inflation.
* **FIXED**: 0.88 s → 1.50 s — a **1.7x** inflation, essentially flat (the ideal
  signature; the small residual is the still-shared `game_source` feed).

Effective parallelism rises from 16.5 (base, and *falling* past 8 threads) to 23.5
(fixed, and still climbing) at 32 threads on a 48-logical-CPU box with a loaded
neighbour.

### 5.2 Wall-time speedups contributed

At 8 threads pinned to cores 0-7, measured interleaved against the pristine binary:

| variant                       | wall   | speedup vs base |
|-------------------------------|-------:|----------------:|
| base                          | 0.87 s | 1.0x            |
| F1 only (numAsserts)          | 0.35 s | 2.5x            |
| F3 only (small pool)          | 0.65 s | 1.34x           |
| F1+F3                         | 0.146s | **5.9x**        |
| F1+F3+F4                      | 0.133s | **6.5x**        |

F1 and F3 are **superlinear** in combination (2.5 * 1.34 ≈ 3.3 < 5.9): the
`numAsserts` write and the cache-hostile 38 MB pool each make the other worse.

---

## 6. Recommended fixes (in priority order)

1. **Delete `numAsserts++` from `ASSERT()`** (`orig/myassert.h`). Largest single win
   (2.5x at 8 threads), trivially safe (write-only global). If the counter is wanted
   for diagnostics, make it `thread_local`, or count into a per-worker slot that is
   reduced once at the end.
2. **Move `QGame` construction into the worker** (`cql6_api.cpp`). Removes ~22 ms per
   thread of serial start-up (1.07 s at 47 threads) and removes the NUMA
   first-touch problem where worker threads on socket 1 touch memory allocated on
   socket 0.
3. **Cut `QPosPoolSize` to a realistic bound** (`qgame.h`, 4096 for head-room).
   Removes 36 MB of never-touched address space per thread and keeps the live `QPos`
   cache-resident.
4. **Make `QPos::visitRoot` O(n)** (`qpos-visit.cpp`).

Secondary observations (not confirmed to be on the critical path, but worth noting):

* `ASSERT()` also does a `char*`-formatting `_MyAssert` on failure only, so no other
  global is written per call — `numAsserts` is the only shared write.
* `Game` is never `Clear()`-ed between games; correctness is unaffected, and there is
  no shared allocator/static pool in `Game`/`MoveList` (checked), so no action needed.
* `libjemalloc` (`LD_PRELOAD`) gives only ~3% at 8 threads — the allocator is *not* a
  significant contention source here.
* **Latent trap:** `qgame.h` compiles the PGN buffer as `char pgnBuffer[1]` when
  `CQL6_EMBEDDED` is defined. Embedded mode never calls the parser path that fills it
  (`scidbParseNextGame`), so no overflow occurs today, but the loop
  `for (auto& c : pgnBuffer) c = 0;` in `qgame.cpp:24` is a tripwire. If the embedded
  path ever touches `pgnBuffer`, it overflows silently. `analysis/patch4_pgnBuffer_1MiB.diff`
  restores a real 1 MiB buffer as defensive hardening (correctness-neutral here).

---

## 7. Methodological trap worth flagging

`Makefile.scidb` has **no header dependencies**:

```
$(OBJ_DIR)/%.o: %.cpp
$(OBJ_DIR)/orig_%.o: orig/%.cpp
```

Changing a `.h` (e.g. `orig/myassert.h`, `qgame.h`) leaves every `.o` stale and
`make` reports *"Nothing to be done for 'lib'"*. My first attempt at F1 therefore
compiled **nothing** and produced a false negative. Every result in this report was
re-built from a clean `build/` directory, and each patch was verified *in the object
code* (`objdump -dr build/obj/orig_position.o | grep -c numAsserts` ⇒ 0 for the
patched build). Add `-MMD -MP` and `-include $(DEPS)` to the Makefile; otherwise
anyone iterating on headers will be misled exactly as I was.

---

## 8. Reproduction

```sh
cd src/cql6
# pristine reference
BENCH_RUNS=7 ./build/bench /tmp/claude-1000/t1exp_p1/data/g20k.pgn 8 check

# per-thread CPU accounting / proof that CPU inflates with threads
g++ -std=c++17 -pthread -O2 -w -DASSERTIONS -DCQL6_EMBEDDED -I. -I./orig -Itests \
    /tmp/p1work/bench_cpu.cpp build/obj/*.o -o /tmp/p1work/bench_cpu      # see §8.1
for t in 1 4 8 16 32 47; do /tmp/p1work/bench_cpu <pgn> $t check | grep '^run 2'; done

# intra-process vs cross-process control
for i in 0 1 2 3 4 5 6 7; do ( taskset -c $i /tmp/p1work/bench_cpu <pgn> 1 check ) & done; wait
taskset -c 0-7 /tmp/p1work/bench_cpu <pgn> 8 check

# TSan
make -f Makefile.scidb lib CXXFLAGS="... -fsanitize=thread ..."
g++ -std=c++17 -pthread -O1 -g -w -DASSERTIONS -DCQL6_EMBEDDED -fsanitize=thread \
    -I. -I./orig tests/bench.cpp build/obj/*.o -o /tmp/p1work/bench_tsan
TSAN_OPTIONS="log_path=/tmp/tsan" /tmp/p1work/bench_tsan <small pgn> 4 check
grep 'Location is' /tmp/tsan.* | sort | uniq -c   # => 'numAsserts'

# assert rate
# (bench_count.cpp sets numAsserts=0 before the search and prints it after)
```

### 8.1 Helper sources used (created under `/tmp/p1work`, not in the tree)

* `bench_cpu.cpp` — links `tests/pgn_driver.cpp` and prints `wall`, `cpu`
  (`getrusage`) and `eff` per run.
* `probe_startup.cpp` — times parse / `new QGame` / thread creation separately.
* `probe_parallel.cpp` — serial vs one-thread-per-`QGame` construction.
* `micro.cpp` — `sizeof` and zero-fill costs for `QPos`/`QGame`.
* `bench_count.cpp` — prints `numAsserts` after a run.

---

## 9. Caveats

* The machine is shared and loaded (load average 15-25 of 48 logical CPUs), so
  absolute wall times are noisy; conclusions rest on (a) min-of-N, (b) interleaved
  A/B, and (c) CPU-time accounting, which is far less sensitive to neighbours than
  wall time. The TSan race, the cachegrind serialisation result and the
  process-boundary control are all independent of machine noise.
* `bench_threads` shows 2x game-count imbalance across threads but all threads finish
  together, so load balancing by wall time is *not* the problem and was not changed.
* Correctness was checked on `check` (4857), `mate` (521), `stalemate` (0) and `true`
  (5538), single- and multi-threaded; every patched build reproduced the pristine
  match counts.
* No source file in this working tree was modified; patches are in `analysis/*.diff`
  and experiments under `/tmp`.
```