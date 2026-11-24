# Chesswiz Performance Diagnosis — Area A: Database Operations

**Scope**: Opening large databases (`.sci`, `.pgn`, `.pgn.gz`, `.cbh`), PGN import, filling/scrolling the game list and DB sub-tabs, column sorting, the opening tree pane, header/position/CQL search, switching databases, and closing databases.  
**Diagnosis only**: No code, build, or config files were modified.  
**Note on Jev**: `~/.config/jev-kb/JEV-REQUIRED-READING.md` was read; no feature code was written.

---

## Environment & Test Datasets

- **Display**: Headless `Xvfb :91 -screen 0 1920x1080x24 -nolisten tcp` + `openbox` (never touching `:0`).
- **Launch**: `HOME=$(mktemp -d ...) PULSE_SINK=cwtests SCIDB_AI_UNCALIBRATED=1 src/tkchesswiz -encoding utf-8 tcl/chesswiz --single-process`, driven via `wish` Tk `send Chesswiz {...}`.
- **Profiling tools**: In-app `clock microseconds` (3 runs, medians reported), `docs/perf/wrap.tcl`, GDB Python multi-thread `SIGUSR2` stack sampling (25 ms interval against unstripped DWARF `src/tkchesswiz`), and `strace -c` syscall accounting.
- **Machine noise baseline**: 20–45 ms background stalls every 10–15 s are excluded by taking 3-run medians. Note that Xvfb understates real `:0` Xwayland / compositor paint latency (~3–5x higher for `update`/`update idletasks` and alpha-composited Tk photos, per `docs/perf/PERF-LOG.md`).
- **Datasets** (all public repo data or scaled copies built from `share/sample/twic1667.pgn.gz` in scratchpad; no user-private DBs touched):
  - `share/sample/Sample games.sci`: 2,177 games
  - `share/sample/twic1667.pgn.gz`: 2,177 games (628 KB `.pgn.gz`; 2.3 MB uncompressed `twic1667_2k.pgn`)
  - `fix-sci.sci`: 7,965 games; `opening-report/tests/fixtures/twic1639.cbh`: 8,571 games
  - `bench_20k.{pgn,sci}`: 21,770 games (22.3 MB PGN; 1.2 MB `.sci`, 4.8 MB `.scg`, 139 KB `.scn`)
  - `bench_100k.{pgn,sci}`: 108,850 games (111.8 MB PGN; 6.1 MB `.sci`, 24.0 MB `.scg`, 235 KB `.scn`)
  - `bench_500k.sci`: 544,250 games (30.5 MB `.sci`, 120.0 MB `.scg`, 235 KB `.scn`)

---

## Ranked Summary of Bottlenecks

| Rank | ID | User Action | Measured Median (Data Size) | Primary Bottleneck | Expected Gain |
|---:|---|---|---|---|---|
| 1 | **A1** | PGN Import & Direct PGN Open | **12.0–13.1 s** (108.9k / 112 MB PGN); **3.1 s** UI vs **2.3 s** C++ (21.8k) | `m_stream.tellg()` `lseek64` per line (21.3% CPU), `MoveBuffer<522>` 4 KB zero-init per move (20.5% CPU), unthrottled `update idletasks` in `::import::Log` & `::progress::DoCmd` (+806 ms UI overhead on 20k) | **2.0–2.5×** faster C++ import; **~90%** less UI overhead |
| 2 | **A2** | CQL 6.2 Pattern / Position Search | **6.0–6.1 s** (108.9k, 8 threads — *slower* than 1-thread legacy CQL!); ~3 min on 1.2M | Main-thread single-threaded `db.exportGame` + 2 ms timer slices starves 8 workers (**74%** worker idle/lock wait on `ScidbGameSource::m_mutex`), `trusted_moves=0` forces full `GenerateMoves` + `MakeSANString` per move, `-DASSERTIONS` runs `Position::AssertPos()` every move (**#1 worker leaf**) | **5–12×** speedup (6 s → ~0.5–1.2 s on 100k; 3 min → ~15–30 s on 1.2M) |
| 3 | **A3** | Legacy CQL Search (`::scidb::view::search {cql ...}`) | **4.29 s** (108.9k, blocks UI thread); **834 ms** (21.8k) | Re-parses CQL script on every game (`108,850×`), builds + `qsort`s `n`-element pointer map, binary-searches per game, single-threaded blocking UI | **25–40%** single-threaded, or **4–8×** if threaded / routed to fixed CQL 6.2 |
| 4 | **A4** | Sorting Game List Columns | **223–452 ms** (544.3k); **71–95 ms** (108.9k); **70.6 ms** even on `Cancel Sort` | `bits::qsort` (`qsort_r`) indirect callbacks + random 96-byte `GameInfo` cache misses + repeated `strcmp` on strings + `-DNREQ` missing (`chunk_vector::released` = 9% CPU) + **70–130 ms** `busyCursor`/UI overhead | **3–5×** faster (452 ms → ~80–120 ms on 544k) |
| 5 | **A5** | Opening Tree Pane (Cold Position Search & Redraw) | **185–195 ms** cold (544.3k; scales to ~700 ms+ on 2M) + **250 ms** debounce + **29–36 ms** UI redraw on Xvfb | Single-threaded scan, `pawnStructureHash` 1.5 MB chained hash table vs 128 KB bitset, `fast` mode still decodes games, 255 progress pipe ticks, `bar:transparent=1` creates alpha-channel Tk photos (severe `XGetImage` penalty on `:0`) | **3–6×** faster cold search (multi-thread + bitset); **2–4×** faster redraw on `:0` |
| 6 | **A6** | Header Wildcard & Surname Search (Advanced Search) | **151–254 ms** (544.3k); **53–79 ms** (108.9k) — vs **2–6 ms** for numeric/exact | Evaluates UTF-8 glob `util::Pattern::match` per game row (up to 6 globs/game for plain surname `OR`-3 × W/B = 3.2M globs on 544k) instead of filtering the Namebase once into an ID bitset | **10–30×** faster (254 ms → ~10–15 ms on 544k) |
| 7 | **A7** | Closing, Opening (`.sci`), and Switching Databases — Fixed UI & Load Overhead | **Close**: **102–123 ms** (C++ `db::close` = **4.8 ms**); **Open 544k `.sci`**: **230 ms** (`db::load` = 127 ms); **Switch**: **63–67 ms** | `::widget::busyCursor` executes **3× `::update`** and recursively walks all **694 widgets** under `.application`; `DeleteBase` triggers redundant `UpdateAfterSwitch`; `.sci` `decodeIndex` does 544k 56-byte `fstream::read` calls with `M_REQUIRE` enabled | Close **123 ms → ~20 ms**; Open 544k **230 ms → ~110 ms**; Switch **63 ms → ~25 ms** |
| 8 | **A8** | Cross-Cutting Release Build Misconfiguration (`-DNREQ` / `-DASSERTIONS` / `USE_POPCNT`) & Game List Per-Row Overhead | **~10–25%** tax across all C++ DB paths; **15.4 ms/page** scroll (544k) | `Makefile.in` omits `-DNREQ` (all `M_REQUIRE`/`M_ASSERT` run in hot loops) and `USE_POPCNT`; `src/cql6/Makefile.scidb` hardcodes `-DASSERTIONS`; `tcl::db::getGameInfo` builds all 51 column `Tcl_Obj`s per visible row | **10–25%** free C++ speedup across all DB operations |

---

## Detailed Bottleneck Reports

### A1. PGN Import and Direct PGN Open

- **User action**: Importing a large `.pgn` file into a `.sci` database (`::import::import` / `::scidb::db::import`) or directly opening a `.pgn`/`.pgn.gz` file (`File → Open` / `::application::database::openBase`).
- **Measured time (3× medians)**:
  - Open `twic1667_2k.pgn` (2,177 games, 2.3 MB): **385.2 ms** (`[378.7, 385.2, 410.6]`)
  - Open `twic1667.pgn.gz` (2,177 games, 628 KB gz): **415.3 ms** (`[427.2, 415.3, 357.8]`)
  - Open `bench_20k.pgn` (21,770 games, 22.3 MB): **2,596.1 ms** (`[2599.9, 2596.1, 2490.5]`)
  - Open `bench_100k.pgn` (108,850 games, 111.8 MB): **11,980.3 ms** (`[11938.9, 12033.2, 11980.3]`)
  - Import `bench_20k.pgn` → new `.sci`: quiet C++ = **2,284.2 ms** (+ **36.3 ms** save); full UI `::import::import` = **3,126.2 ms** (**+806 ms pure UI overhead** on Xvfb).
  - Import `bench_100k.pgn` → new `.sci`: quiet C++ = **13,032.1 ms** (+ **58.5 ms** save). Per-game cost rises 14% from 104.9 µs/game (20k) to 119.7 µs/game (100k).
- **Where the time goes**:
  - **C++ GDB stack profile (`1_pgn_import_20k`, 127 samples) & `strace -c` syscall proof (`bench_20k.pgn`)**:
    1. **`__lseek64` (`lseek64.c:40`) — 21.3% self (27/127)**, called from `db::PgnReader::get()` at `src/db/db_pgn_reader.cpp:1904` (`m_lineOffset = m_stream.tellg();`). Confirmed via `strace -c` on `bench_20k.pgn` (21,770 games): **`689,456` `lseek` syscalls** (**85.29%** of all I/O syscall time, **31.7 `lseek` calls/game**, vs only `13,461` `read` and `2,107` `write` syscalls) — scaling to **~3.45 million `lseek` syscalls** for `bench_100k.pgn`!
    2. **`db::Move::Move` (`src/db/db_move.ipp:37`) — 14.2% self (18/127)** + **`db::MoveBuffer<522u>::MoveBuffer` (`src/db/db_move_list.ipp:33`) — 6.3% self (8/127)** = **20.5% self**! Called from `db::Board::parseMove()` at `src/db/db_board.cpp:5192` (`MoveList validList;`).
    3. `memcpy` (`4.7%`), `db::Board::doMove` (`src/db/db_board.cpp:5906`, `3.1%`), `db::EcoTable::lookup` (`src/db/db_eco_table.cpp:1140`, `3.1%`), `db::Board::parseMove` (`src/db/db_board.cpp:4708`, `2.4%`).
    4. `db::Namebase::insertPlayer` / `insertEvent` / `insertSite` (`src/db/db_namebase.cpp:352, 381, 415, 439, 489, 611`): O(U) vector `m_list.insert` shift on every new unique name (explaining the 14% per-game slowdown from 20k → 100k) plus `M_REQUIRE(::sys::utf8::validate(name))` on every call.
  - **Tcl UI `wrap.tcl` profile (`bench_20k.pgn` via `::import::import`)**:
    1. **`update idletasks <- ::import::Log` (`tcl/import.tcl:1280`) — 320.2 ms across 400 calls** (0.80 ms/call on Xvfb; ~3–5× worse on `:0` Xwayland).
    2. **`update idletasks <- ::progress::DoCmd` (`tcl/progress.tcl:141`, `interrupted?` branch) — 84.0 ms across 624 calls**.
    3. `update <- ::progress::DoCmd` (`tcl/progress.tcl:132`) — 27.5 ms across 63 calls (already throttled to 50 ms).
    4. `BusyCursor` (`tcl/widgets/misc.tcl:759-768`) — 2,786 `winfo children` + 2,786 `winfo toplevel` calls.
- **Root cause**:
  1. **Per-line `lseek64` syscall**: `PgnReader::get()` (`src/db/db_pgn_reader.cpp:1904`) unconditionally calls `m_stream.tellg()` before reading EVERY line of the PGN file (millions of syscalls on a 100k-game file) to update `m_lineOffset`. During `db::import`, `m_fileOffsets` is unused; even when opening a PGN archive directly, byte offsets can be tracked in userspace by accumulating `bytesRead` per line instead of calling `lseek(fd, 0, SEEK_CUR)` on every line.
  2. **4 KB zero-initialization on every piece move**: In `Board::parseMove()` (`src/db/db_board.cpp:5192`), `MoveList validList;` is constructed on EVERY non-pawn move (`N`, `B`, `R`, `Q`, `K`). Because `MoveList` is `MoveBuffer<522>` and `Move::Move()` (`src/db/db_move.ipp:37`) is non-trivial (`: m(0), u(0)`), C++ loops 522 times zeroing **4,176 bytes** on the stack just to hold 1 candidate move (>90% of piece moves have only 1 bit set in `match`!).
  3. **Unthrottled `update idletasks` in import log & progress polling**: `tcl/progress.tcl:129-133` carefully throttles `update` to 50 ms, but `interrupted?` at line 141 calls `update idletasks` on **every** progress tick without throttling, and `::import::Log` at `tcl/import.tcl:1280` calls `update idletasks` after **every single warning/error line**.
  4. **Namebase O(U²) insertion**: `Namebase::insertPlayer/Event/Site` (`src/db/db_namebase.cpp:381, 439, 611`) keeps `m_list` sorted by shifting the vector with `m_list.insert(...)` on every unique name and grows capacity by only 10% (`size + (size + 9)/10` at line 226).
- **Proposed fix**:
  1. Replace `m_stream.tellg()` at `src/db/db_pgn_reader.cpp:1904` with a userspace byte counter maintained by `m_stream.getline()` (or only call `tellg()` at game start when `m_fileOffsets != nullptr`). **Expected gain: −21% C++ import/open time.**
  2. In `src/db/db_board.cpp:5192`, add a fast path when `(match & (match - 1)) == 0` (single candidate piece — zero list construction!) and replace `MoveList validList` with a tiny fixed array `Move validBuf[16]` (or make `MoveBuffer` store `aligned_storage` / uninitialized buffer until `push()`). **Expected gain: −20% C++ import/open time.**
  3. Throttle `update idletasks` in `tcl/import.tcl:1280` and `tcl/progress.tcl:141` to the same 50 ms cadence as `tcl/progress.tcl:130` (flush on finish). **Expected gain: −400 ms on Xvfb / −1.5–2 s on `:0` per 20k PGN import.**
  4. For bulk PGN import, keep a side hash table (`mstl::hash<Key, Entry*>`) or append unsorted + sort once at `Namebase::update()`, and grow capacity by 1.5–2×. **Expected gain: eliminates O(U²) scaling on 500k+ PGNs with many unique players/events.**
- **Risk**: Low for (1)–(3) (preserve `m_lineOffset` accounting for `\r\n` vs `\n` and keep `Cancel` responsive within 50 ms); Medium for (4) (must preserve sorted `m_list` invariant before any UI/lookup access).
- **Repro commands**:
  ```bash
  # Generate 108.9k PGN from share/sample/twic1667.pgn.gz (or use twic1667.pgn.gz directly)
  # Measure direct PGN open:
  send Chesswiz {
      set t0 [clock microseconds]
      ::application::database::openBase .application /path/to/bench_100k.pgn no -progress 0
      update
      expr {([clock microseconds] - $t0)/1000.0}
  }
  # Profile UI PGN import with wrap.tcl:
  src/tkchesswiz -encoding utf-8 docs/perf/wrap.tcl --single-process
  # Drive ::import::import .application $dstSci $pgn20 -encoding utf-8 -illegal 1
  ```

---

### A2. CQL 6.2 Pattern and Position Search

- **User action**: Running a CQL 6.2 search (`Database → Search → CQL 6 Search...` or AI Pattern Search / Pattern Index build calling `::scidb::cql6::search`).
- **Measured time (3× medians, `bench_100k.sci`, 108,850 games)**:
  - `bench_20k.sci` (21,770 games, 8 threads): `cql() mate` = **1,281.1 ms** (`[1357.5, 1076.6, 1281.1]`); `cql() fen ...` = **1,239.3 ms** (`[1315.8, 1108.2, 1239.3]`).
  - `bench_100k.sci` (108,850 games, 8 threads): `cql() mate` = **5,975.7 ms** (`[6086.3, 5975.7, 5745.1]`); `cql() fen "rnbqkbnr/pp2pppp/3p4/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 0 3"` = **6,098.2 ms** (`[6118.2, 6064.1, 6098.2]`).
  - **Thread-scaling curve on `bench_100k.sci` (108,850 games, `cql() mate`, 3× medians)**:
    - `1 thread` (async): **19,551.7 ms** `[19532.1, 19551.7, 27924.5]` (~180 µs/game — **4.56× slower** than 1-thread legacy CQL's 4,285.3 ms!)
    - `4 threads` (async): **5,415.5 ms** `[7911.3, 5415.5, 5409.8]` (3.61× speedup — already hits the single-threaded main-thread decode ceiling!)
    - `8 threads` (async): **5,812.6 ms** `[5812.6, 6036.2, 5638.4]` (**negative scaling: +397 ms slower than 4 threads** due to mutex contention on `ScidbGameSource::m_mutex`!)
    - `8 threads` (SYNC): **5,455.5 ms** `[5123.2, 5662.1, 5455.5]` (−357 ms vs async by eliminating 2 ms timer jitter, still pinned to the ~5.4 s single-threaded `db.exportGame()` wall)
    - `8 threads` with `-view` pre-filtered to 146 games: **13.0 ms** `[14.8, 13.0, 12.8]`
  - **Paradox**: 8-thread CQL 6.2 (**5,813–5,976 ms**) is **~38% SLOWER** than 1-thread legacy CQL (**4,285 ms**)! On 1.2M games, `tcl/ai-pattern-index.tcl:5` notes this scales to **~3 minutes**.
- **Where the time goes (GDB multi-thread profile `2_cql6_100k_8thr`, 650 samples × 9 threads)**:
  - **Thread utilization**:
    - Main Tcl thread: **99.7% pegged (`648/650` samples RUN)** inside `requestGame()` → `db.exportGame()` (`db::Board::doMove` 56 self, `memcpy` 64 self).
    - 8 CQL6 worker threads (`5,200` worker-samples total):
      - **`2,759` samples (53.1%)** blocked in `futex_wait <- __GI___lll_lock_wait` on `ScidbGameSource::m_mutex` (`src/cql6/scidb_feed.h:21`).
      - **`1,088` samples (20.9%)** sleeping in `__futex_abstimed_wait_cancelable64` on `job->changed` (`src/tcl/tcl_cql6.cpp:390`).
      - **Total worker starvation: 74.0% of 8-core capacity idle waiting on the main-thread producer!**
  - **Active worker CPU leaf hotspots** (while actually running `ScidbGameSource::populateGame` [1,046 incl.] and `QPos::visitRoot` [787 incl.]):
    1. **`Position::AssertPos()` (`src/cql6/orig/position.cpp:148, 1935, 2025`) — 258 self samples** (#1 worker CPU leaf!) + **`uassert()` — 103 self samples** = **361 samples (~20% of active worker CPU)** spent in debug assertions!
    2. **`Position::CalcAttacks` (199) + `GenSliderMoves` (168) + `GenPawnMoves` (114) + `GenPieceMoves` (83) + `GenerateMoves` (73) = 637 self samples (~35% of active worker CPU)** from `trusted_moves = 0` forcing full legal move generation + `MakeSANString` on every move!
    3. **`QPos::initialize(QGame*)` (`src/cql6/qpos.cpp:253`, 223 self) + `QPos::clear()` (`src/cql6/qpos.cpp:248, 254`, 56 self)** = **279 self samples**, calling `clear()` TWICE per ply (`createQPos:248` then `initialize:254`).
- **Root cause (4 compounding bottlenecks)**:
  1. **Single-threaded main-thread producer starving 8 workers (`src/tcl/tcl_cql6.cpp:165, 261-383`, `src/cql6/scidb_feed.h:21`)**: `requestGame()` decodes games on the main Tcl thread in **2 ms `SliceTime` timer slices** (`Tcl_CreateTimerHandler(0/1, prefetchTimer)`). When `job->ready` drains, worker #1 holds `ScidbGameSource::m_mutex` (`scidb_feed.h:21`) while sleeping on `job->changed.wait(...)` (`tcl_cql6.cpp:390`), causing the other 7 workers to pile up on `m_mutex`.
  2. **Per-game `Exporter` / `utf8::Codec` / PGN tag & comment allocation storm (`src/tcl/tcl_cql6.cpp:63-158, 296, 311`)**: For every game, `requestGame()` constructs a brand-new `Exporter` → `Consumer` → **`new sys::utf8::Codec("utf-8")`** (`src/db/db_consumer.cpp:74`), calls full `db.exportGame()`, allocates 15–30 heap `std::string` tag pairs, runs an O(7 × tags) linear scan for mandatory PGN tags, and pushes an empty `std::string` into `data.comments` on every ply — even when the CQL script never inspects tags or comments!
  3. **`trusted_moves = 0` forces full move generation + SAN formatting on every move (`src/tcl/tcl_cql6.cpp:775`, `src/cql6/cql6_api.cpp:349`, `src/cql6/scidb_feed.cpp:220-268`)**: Because `trusted_moves = 0`, `wantSan = !opt->trusted_moves || opt->want_pgn` becomes `true` even when `-pgn 0`. Every move of every game runs `position->GenerateMoves(&mlist)` AND `position->MakeSANString(chosen, sanStr, SAN_CHECKTEST)` (even though `.sci` already records `GameInfo::Flag_Illegal_Move` / `Flag_Illegal_Castling` per game, so 99.9%+ of games are known legal!).
  4. **Production `libcql6.a` compiled with `-DASSERTIONS` (`src/cql6/Makefile.scidb:10`)**: Enables `Position::AssertPos()` in `DoSimpleMove` (`orig/position.cpp:1935`) and `UndoSimpleMove` (`orig/position.cpp:2025`), scanning all piece lists and material counts twice per ply!
- **Proposed fix**:
  1. **Remove `-DASSERTIONS` from release `BASE_FLAGS` in `src/cql6/Makefile.scidb:10`** (keep in `TEST_BASE_FLAGS` / debug builds). **Expected gain: −20% worker CPU immediately.**
  2. **Use `trusted_moves` per game (or when `!info.containsIllegalMoves() && !info.containsIllegalCastlings()`) and decouple `wantSan` from `trusted_moves`** (`wantSan = (opt->want_pgn != 0)`): skips `GenerateMoves` and `MakeSANString(SAN_CHECKTEST)` on every move of every clean `.sci` game (`scidb_feed.cpp:220` already checks board invariants!). **Expected gain: −35–50% worker CPU.**
  3. **Eliminate the main-thread bottleneck**: Give each CQL6 worker its own `util::BlockFileReader` (just as `TreeAdmin` uses `openAsyncTreeSearchReader()`), or at minimum reuse a single `Exporter`/`Consumer` per slice, skip exporting PGN tags/comments when the script doesn't reference tags/comments, raise `SliceTime` from 2 ms to 8–10 ms, and pop a batch of 16–32 snapshots per `m_mutex` acquisition (releasing `m_mutex` before waiting on `job->changed`!). **Expected gain: eliminates 74% worker starvation → 4–8× wall-clock speedup on 8 cores.**
  4. **Remove duplicate `clear()`** in `QPos::createQPos` (`src/cql6/qpos.cpp:248` vs `254`).
  - **Combined expected gain**: **5–12× faster** (100k: **6.0 s → ~0.5–1.2 s**; 1.2M pattern index build: **~3 min → ~15–30 s**).
- **Risk**: Low for (1), (2) (per-game `Flag_Illegal_Move` guard preserves exact illegal-move truncation semantics), and (4); Medium for parallel `BlockFileReader` in (3) (must verify thread-safety of `sci::Decoder` and `Position::s_startCacheLock`, plus pin database lifetime against concurrent `db::close`).
- **Repro commands**:
  ```tcl
  # Inside wish connected to Chesswiz with bench_100k.sci open:
  send Chesswiz {
      set ::done 0
      set t0 [clock microseconds]
      ::scidb::cql6::search /path/to/bench_100k.sci Normal "cql() mate" \
          -threads 8 -variations 0 -paged 1 \
          -command {apply {{res} { set ::r $res; set ::done 1 }}}
      vwait ::done
      set ms [expr {([clock microseconds] - $t0)/1000.0}]
      ::scidb::cql6::release [dict get $::r results]
      set ms
  }
  ```

---

### A3. Legacy CQL Position Search (`::scidb::view::search {cql ...}`)

- **User action**: Executing a legacy CQL query via `::scidb::view::search ... {cql "..."}`.
- **Measured time (3× medians)**:
  - `bench_20k.sci` (21,770 games): **833.8 ms** (`[833.8, 829.1, 836.9]`, 2,000 matches)
  - `bench_100k.sci` (108,850 games): **4,285.3 ms** (`[4206.2, 4285.3, 4464.0]`, 10,000 matches) — **blocks the UI thread for >4 seconds**!
- **Where the time goes (GDB profile `3_legacy_cql_100k`, 208 samples)**:
  - `db::SearchCql::match` (`src/db/db_search.cpp:462`) — **96.6% inclusive** (`201/208`):
    - `cql::matchGame` (`src/db/cql/cql_game_matcher.cpp:274`) — **94.2% inclusive** (`196/208`) → `db::Database::exportGame` (`85.6%`) → `db::sci::Decoder::doDecoding` (`77.9%`).
    - Leaf hotspots: `memcpy` (`10.6%`), `db::Board::doMove` (`17%+` across lines `5499, 5502, 5504, 5801, 5903, 5906, 5913, 5914`), `queenAttacks`/`rookAttacks` (`4.3%`), `__libc_malloc2` (`1.4%`), `msort_with_tmp` (`1.0%` from `SearchCql` constructor `qsort`).
- **Root cause**:
  1. **Re-parses the entire CQL script on every single game**: `SearchCql::match()` (`src/db/db_search.cpp:471-476`) constructs a fresh `cql::Match` and calls `match.parse(m_script.c_str(), error)` **108,850 times** per 100k search (causing heap alloc/free churn on every game) solely because `cql::Match` lacks a `reset()` method for per-game counters.
  2. **O(n log n) pointer map + O(log n) binary search per game**: `SearchCql::SearchCql()` (`src/db/db_search.cpp:442-458`) allocates an `n`-element `{GameInfo*, index}` vector and `::qsort`s it, then `SearchCql::match()` runs `mstl::lower_bound` on every game just to recover `unsigned index` — even though `Filter::search` (`src/db/db_filter.cpp:162-164`) literally ALREADY HAS `unsigned i` as its loop variable!
  3. **Synchronous single-threaded execution on the main Tcl thread**: Freezes the entire GUI for 4.3 s on 100k (~22 s on 544k) and uses full `exportGame` (including tags/comments) instead of a lightweight move-only decoder.
- **Proposed fix**:
  1. Pass `unsigned gameIndex` into `Query::match(GameInfo const&, unsigned index)` (eliminating `m_index`, `qsort`, and `lower_bound`).
  2. Parse `m_script` once in `SearchCql`'s constructor and add `cql::Match::reset()` to clear per-game match counts instead of re-parsing per game. **Expected gain: −15–25% single-threaded.**
  3. Long-term: run `SearchCql` across worker threads with per-thread `BlockFileReader` (or route position searches through fixed CQL 6.2). **Expected gain: 4–8× and non-blocking UI.**
- **Risk**: Low for (1)–(2); Medium for (3) (requires verifying `cql::Match::reset()` clears all nested position-list state).
- **Repro commands**:
  ```tcl
  send Chesswiz {
      set db /path/to/bench_100k.sci
      set v [::scidb::view::new $db Normal unused unused unused unused master slave]
      set t0 [clock microseconds]
      ::scidb::view::search $db Normal $v null none {cql "(match (position :terminal :mate))"}
      set ms [expr {([clock microseconds] - $t0)/1000.0}]
      ::scidb::view::close $db Normal $v
      set ms
  }
  ```

---

### A4. Sorting Game List Columns on Large Databases

- **User action**: Clicking any column header in the Games tab (`::gamestable::SortColumn` → `::scidb::db::sort gameInfo`).
- **Measured time (3× medians, unsorted → sorted each run, `bench_500k.sci` = 544,250 games; plus 108.9k & 21.8k)**:
  | Column | 544.3k UI Median (runs) | 544.3k Pure C++ Median | Tcl UI Overhead | 108.9k UI Median |
  |---|---:|---:|---:|---:|
  | `white ascending` | **451.9 ms** `[475.9, 433.9, 451.9]` | **320.4 ms** | **131.5 ms** | **95.0 ms** (1st: 124.2) |
  | `black descending` | **412.6 ms** `[402.2, 412.6, 432.3]` | **327.9 ms** | **84.7 ms** | **77.6 ms** (1st: 102.0) |
  | `eco ascending` | **348.5 ms** `[348.5, 349.9, 347.8]` | **279.3 ms** | **69.2 ms** | **91.1 ms** (1st: 110.3) |
  | `whiteRating1 descending` | **332.7 ms** `[292.5, 337.5, 332.7]` | **209.7 ms** | **123.0 ms** | **78.2 ms** |
  | `whiteRating1 average` | **329.4 ms** `[329.4, 352.4, 329.3]` | **267.3 ms** | **62.1 ms** | **86.7 ms** |
  | `length descending` | **280.2 ms** `[280.2, 265.4, 313.3]` | **207.6 ms** | **72.6 ms** | **80.7 ms** |
  | `date descending` | **261.0 ms** `[261.0, 259.4, 270.4]` | **190.7 ms** | **70.3 ms** | **94.5 ms** (1st: 129.4) |
  | `event ascending` | **224.0 ms** `[199.9, 226.9, 224.0]` | **119.5 ms** | **104.5 ms** | **83.1 ms** |
  | `result ascending` | **222.7 ms** `[225.4, 222.7, 206.4]` | **139.8 ms** | **82.9 ms** | **84.6 ms** |
  | `site ascending` | **192.0 ms** `[188.8, 216.2, 192.0]` | **122.4 ms** | **69.6 ms** | **71.4 ms** |
  | `number cancel` (reset) | **70.6 ms** `[72.8, 70.6, 67.7]` | **1.1 ms** | **69.5 ms** | **58.2 ms** |
- **Where the time goes (GDB profile `4_sort_544k`, 56 samples)**:
  - **C++ sort (`src/db/db_selector.cpp:624-788`, `src/mstl/m_algorithm.ipp:596, 1039`)**:
    - **96.4% inclusive** in glibc `msort_with_tmp` (`__GI___qsort_r` via `mstl::bits::qsort`), calling non-inlined function pointers `compWhitePlayer` / `compLength` / `compUserEco` / `compDate` / `compRatingWhite` ~10.4M times on 544k.
    - Top leaf frames: `mstl::compare` / `__strcmp_avx2` (`12.5%`), `chunk_vector<GameInfo,16>::released` (`m_chunk_vector.ipp:435`, `5.4%`) + `chunk_vector::at` (`m_chunk_vector.ipp:458, 460`, `7.2%`) + `Database::gameInfo` (`3.6%`) = **16.2% just indexing `GameInfo` + `M_REQUIRE` checks!**, plus `msort_with_tmp` (`9.0%`), `compLength` (`7.1%`), `compWhitePlayer` (`5.4%`), `compUserEco`/`compDate`/`findElo` (`10.8%`).
  - **Tcl UI overhead (`69.5–131.5 ms` on every sort, even `Cancel Sort` where C++ is 1.1 ms!)**:
    - `::gamestable::SortColumn` wraps the sort in `::widget::busyCursor on` / `off` (`tcl/widgets/misc.tcl:544-590`, **~40–65 ms** from 3× `::update` + walking all 694 widgets twice) + table refresh + `update`.
- **Root cause**:
  1. **Indirect `qsort_r` + random-access 96-byte `GameInfo` cache misses**: Sorting 544k `uint32_t` indices via `qsort_r` performs ~10.4M comparisons, each making an indirect function-pointer call and two random lookups into a **~52 MB** `chunk_vector<GameInfo, 16>` (`~96 bytes/entry`, exceeding L3 cache!).
  2. **Redundant `strcmp` on already-sorted Namebases**: `compWhitePlayer`, `compBlackPlayer`, `compEvent`, `compSite` (`src/db/db_selector.cpp:365-370`) dereference `NamebaseEntry*` and run `strcmp` on every comparison (~10M `strcmp` calls), even though `Namebase::m_list` is ALREADY sorted in alphabetical order!
  3. **No radix/counting sort for small-key integer columns**: `result` (3 bits), `length` (11 bits), `eco` (12 bits), `rating` (12 bits), `date` (20 bits) are all small integers that can be extracted sequentially in one cache-friendly linear pass (544k × 8-byte `{key, idx}` = 4.3 MB — fits in L3!) and sorted via 2-pass LSD radix sort in **~15–25 ms** instead of 140–328 ms!
  4. **Missing `-DNREQ`** leaves `M_REQUIRE(!released(...))` active on every `gameInfo(idx)` access inside the comparator (~9% of sort CPU).
  5. **`busyCursor` overhead** adds ~70 ms even on instant sorts (and on 20k DBs makes sorting feel sluggish at ~60–67 ms when C++ takes <5 ms).
- **Proposed fix**:
  1. **Schwartzian transform + LSD radix sort** in `Selector::sort` (`src/db/db_selector.cpp:639-788`): For integer keys (`length`, `result`, `date`, `eco`, `rating`), extract compact `uint32_t` keys in one linear pass and LSD-radix-sort `(key, index)` pairs (or counting sort for `result`/`length`/`eco`). For string columns (`White`, `Black`, `Event`, `Site`), assign each `Namebase` entry its sorted ordinal `rank[entry->id()]` in O(U) (~0.5 ms), then radix-sort games by `uint32_t` rank! **Expected gain: C++ sort 320 ms → ~25–45 ms on 544k (7–10× faster!).**
  2. **Fix `::widget::busyCursor` (see A7)** and only activate busy cursor if a sort is expected to exceed ~50 ms (e.g., `countGames > 100000`). **Expected gain: −60–100 ms UI overhead per sort.**
  3. **Build with `-DNREQ`** (see A8).
- **Risk**: Low. Must verify tie-breaking stability (LSD radix sort is naturally stable, matching `qsort_r` mergesort; `compWhitePlayer` uses `mstl::compare` = byte/ASCII `strcmp` — verify collation matches `Namebase::m_list` order).
- **Repro commands**:
  ```tcl
  send Chesswiz {
      set db /path/to/bench_500k.sci
      ::application::database::switchToBase $db; update
      set tbl $::application::database::Vars(games)
      ::gamestable::SortColumn $tbl number cancel; update
      set t0 [clock microseconds]
      ::gamestable::SortColumn $tbl white ascending; update
      expr {([clock microseconds] - $t0)/1000.0}
  }
  ```

---

### A5. Opening Tree Pane (Cold Position Search & Table Redraw)

- **User action**: Stepping through moves on the Board tab with the Opening Tree pane active (`::application::tree::Search` → `::scidb::tree::update` / `TreeAdmin` → `FetchResult` + `FillTable`).
- **Measured time (cold `inst=0` runs & 3× medians)**:
  - Cold search (`::scidb::tree::update` → `isUpToDate?` → `finish`, `inst=0`):
    - **21.8k (`bench_20k.sci`)**: `exact` ply 2 = **45.9 ms** `[60.2, 45.9, 43.4]`, ply 6 = **41.4 ms** `[59.7, 41.4, 37.9]`, ply 12 = **36.7–42.4 ms**.
    - **108.9k (`bench_100k.sci`)**: `exact` ply 2 = **55.5–73.8 ms**, ply 6 = **52.4–74.2 ms**; `fast` ply 2 = **57.7–75.9 ms**, ply 6 = **63.2–76.0 ms**.
    - **544.3k (`bench_500k.sci`)**:
      - `exact`: ply 0 = **173.8 ms**, ply 2 = **185.2 ms** `[162.8, 244.6, 185.2]`, ply 6 = **195.4 ms** `[195.4, 226.7, 188.6]`, ply 12 = **128.7–165.1 ms**, ply 16 = **158.8 ms**.
      - `fast`: ply 2 = **155.0–212.6 ms**, ply 6 = **196.5–219.5 ms**, ply 12 = **147.5–160.8 ms** (**virtually no speedup over `exact`!**).
      - `exact + IncludeVariations`: ply 2 = **163.4–248.7 ms**, ply 6 = **184.7–228.4 ms**.
      - Scales linearly with DB size, projecting to **~650–800 ms** on a 2M-game mega database — PLUS a fixed **250 ms debounce** (`tcl/app-tree.tcl:671, 759`) before starting search.
      - Even warm cache hits (`inst=1`) take **8.4–11.6 ms** on 544k (vs **1.2–1.6 ms** on 20k/100k) due to tree-filter decompression/update.
  - **UI redraw (`FetchResult` + `FillTable` + `update`, 3× medians on Xvfb, 15 rows)**:
    - `bar:transparent = 1` (default): cold bars = **29.4 ms** `[31.1, 29.1, 29.4]`, warm bars = **36.0 ms** `[27.0, 55.2, 36.0]`.
    - `bar:transparent = 0`: cold bars = **30.3 ms** `[30.5, 30.3, 29.9]`, warm bars = **26.5 ms** `[26.2, 28.8, 26.5]` (**−9.5 ms / −26% faster even on Xvfb**, and avoids `XGetImage` framebuffer readback on `:0` Xwayland, where transparent photos cost **~100+ ms**).
- **Where the time goes (GDB profile `6_tree_cold_544k`, 89 worker samples in `Tree::makeTree`)**:
  - `db::Tree::makeTree` (`src/db/db_tree.cpp:723`) runs on **1 single background thread** (`app::TreeAdmin`, `src/app/app_tree_admin.cpp:219`).
  - Top worker leaf frames: `db::GameInfo::idn` (`db_game_info.ipp:67`, **14.6%** of worker — memory-bandwidth/cache misses streaming 52 MB of `GameInfo` + `chunk_vector::at` `M_REQUIRE`), `memcpy` (**7.9%**, copying `Board` in `sci::decoder::Position::setup`), `db::Board::notToMove` (**6.7%**), `db::HomePawns::checkIfReachable` (**4.5%**), `mstl::hash<unsigned int, bool>::find_node` (`m_hash.ipp:399`, **2.2%** — `pawnStructureHash`!), `db::Board::doMove` (`2.2%`).
- **Root cause**:
  1. **Single-threaded scan (`src/app/app_tree_admin.cpp:75-100, 219`)**: `TreeAdmin` spawns only 1 worker thread to scan all 544k games sequentially, even though each game's position check is completely independent and `BlockFileReader` supports independent readers per thread!
  2. **1.5 MB chained hash table (`pawnStructureHash`) queried 4× per game (`src/db/db_signature.cpp:56, 116, 248`)**: `Signature::isReachablePawnStructure` queries a **1.5 MB `mstl::hash<uint32_t, bool>`** 4 times per game (2.1M random lookups on 544k — thrashing L2 cache). Yet the key `hash` is only **20 bits** (`4 * BitLength = 20`, $2^{20}$ values): a flat `uint64_t[16384]` bitset takes **128 KB** (12× smaller, fits in L2, zero pointer chasing!).
  3. **No-op "prefetch" (`src/db/db_tree.cpp:271, 339, 430`)**: `base.gameInfo(m_index + 1); /* trigger prefetch */` discards the reference (not `__builtin_prefetch`), adding extra `M_REQUIRE` bounds checks in non-`NREQ` builds without prefetching!
  4. **255 progress pipe updates per search**: `Tree::makeTree` sends ~255 progress ticks through `PipedProgress`, waking the Tcl main thread to call `place $Vars(progress)` 255 times even when a search finishes in 150 ms.
  5. **UI full table rebuild + alpha-channel photo bars (`tcl/app-tree.tcl:1157-1160, 1375-1410`)**: `FetchResult` clears and recreates every treectrl item on every ply (`::table::clear` + `setHeight 0` + `setHeight $nrows`). Worse, `Options(bar:transparent) = 1` sets `alpha 0.0` on every `MakeBar` and `MakeThreeBar` photo (`tcl/app-tree.tcl:1376, 1400`) — even in `MakeThreeBar` where lines 1405–1410 immediately overwrite the entire interior with opaque colors! Any Tk photo with an alpha channel forces synchronous `XGetImage` framebuffer readback on X11/Xwayland.
- **Proposed fix**:
  1. **Parallelize `Tree::makeTree`** across `min(4..8, nCores)` worker threads partitioning `[0, numGames)` with per-thread `BlockFileReader` and per-thread `moveCache` merged at the end (no lock per game). **Expected gain: 4–6× faster cold tree search (170 ms → ~35 ms on 544k; 700 ms → ~120 ms on 2M).**
  2. **Replace `pawnStructureHash` (1.5 MB) with a 128 KB flat bitset** (`uint64_t[1 << 14]`) in `src/db/db_signature.cpp:56, 116`. **Expected gain: −10–15% scan CPU + faster startup.**
  3. **Replace fake prefetch** at `db_tree.cpp:271, 339, 430` with `__builtin_prefetch(&base.gameInfo(m_index + 8))` and throttle progress pipe notifications to every 30–50 ms (instead of 255 fixed ticks).
  4. **In `tcl/app-tree.tcl:1399-1410`**: Never call `alpha 0.0` in `MakeThreeBar` (all pixels are opaque!) and default `bar:transparent` to `0` (matching table row background color instead of alpha transparency); update existing treectrl rows in-place when `nrows` is unchanged. **Expected gain: eliminates `XGetImage` stall on `:0` (cuts UI redraw by 2–4× on Xwayland).**
- **Risk**: Low for (2)–(4); Medium for (1) (must ensure `moveCache` is thread-local instead of file-static `::moveCache` at `db_tree.cpp:150`, and guard cancellation via `std::atomic<bool>`).
- **Repro commands**:
  ```tcl
  send Chesswiz {
      set db /path/to/bench_500k.sci
      ::game::new .application -base $db -variant Normal -view 0 -number 0
      ::scidb::tree::set $db
      ::scidb::game::go 0 start; for {set k 0} {$k < 6} {incr k} { ::scidb::game::go 1 }
      set t0 [clock microseconds]
      if {![::scidb::tree::update Elo exact 0]} {
          while {![::scidb::tree::isUpToDate?]} { after 1; update }
      }
      ::scidb::tree::finish Elo exact 0 -sort 2
      expr {([clock microseconds] - $t0)/1000.0}
  }
  ```

---

### A6. Header Wildcard and Surname Search (Advanced Search)

- **User action**: Searching by player surname, player wildcard (`*sen*`), event wildcard (`*Open*`), or site wildcard in Advanced Search (`tcl/app-database-search-advanced.tcl`) or `::scidb::view::search`.
- **Measured time (3× medians)**:
  - **544.3k games (`bench_500k.sci`, Advanced Search end-to-end)**:
    - `player=*sen*`: **254.1 ms** `[269.3, 252.5, 254.1]` (17,250 matches)
    - `event=*Open*`: **186.0 ms** `[178.7, 194.1, 186.0]` (91,500 matches)
    - `player=Tabatabaei` (plain surname): **150.8 ms** `[171.2, 150.8, 149.6]` (1,000 matches)
    - `player=*a*` (high match): **102.6 ms** `[102.6, 109.7, 94.0]` (532,250 matches)
  - **108.9k games (`bench_100k.sci`)**:
    - Advanced Search UI: `player=*sen*` = **79.0 ms**, `player=Tabatabaei` = **62.1 ms**, `event=*Open*` = **52.8 ms**.
    - Pure C++ `view::search`: `playername *sen*` = **51.3 ms**, `eventname *Open*` = **33.9 ms**, surname `OR`-3 = **31.4–33.1 ms**, `sitename *Budva*` = **24.2 ms** — **compared to only 1.7–6.6 ms** for rating (`2.7 ms`), date (`2.9 ms`), ECO (`2.5 ms`), exact player (`4.3 ms`), material (`6.1 ms`), or IDN (`1.7 ms`)!
  - Scales linearly with total game count `N` (even when unique players `U << N`), reaching **~500–900 ms** on 1–2M games.
- **Where the time goes (GDB profile `5_header_wildcard_544k`, 88 samples)**:
  - `db::Filter::search` (`db_filter.cpp:164`) → `db::Query::match` (`96.6%`) → `db::SearchPlayerName::match` (`db_search.cpp:296`, `53.4%`) → `util::Pattern::match` (`u_match.cpp:1043`, `46.6%`) & `db::SearchOpOr::match` (`db_search.cpp:84`, `40.9%`).
  - Leaf frames: `sys::utf8::caseMatchChar` (`12.5%`), `db::SearchPlayerName::match` (`11.4%`), `__GI_toupper` (`9.0%`), `u_match.cpp::match` (`7.9%`), `sys::utf8::nextChar` (`5.7%`), `_int_free_chunk` + `mstl::string::init` (`5.7%`).
- **Root cause**:
  1. **Per-game glob matching instead of Namebase pre-filtering (`src/db/db_search.cpp:274-328`)**: `SearchPlayerName::match`, `SearchEventName::match`, `SearchSiteName::match`, and `SearchAnnotatorName::match` run `util::Pattern::match()` on `info.playerName(...)` / `info.event()` / `info.site()` for **every single game** (e.g. 544k × 2 sides = 1.09M glob matches), even though the database stores normalized `Namebase` tables with far fewer unique entries (e.g., a few thousand to tens of thousands of unique players/events/sites)!
  2. **3× OR expansion for plain surnames (`tcl/app-database-search-advanced.tcl:184-187`)**: Searching a plain surname like `Tabatabaei` builds `[OR {playername any Tabatabaei} {playername any Tabatabaei,*} {playername any "Tabatabaei *"}]`, multiplying the work to **6 glob evaluations per non-matching game** (~3.26M UTF-8 glob calls on 544k)!
  3. **Recursive backtracking glob (`src/util/u_match.cpp:316-325`)**: `*sen*` calls `sys::utf8::caseMatchChar` + `toupper` per character across every position of every game's White and Black name string.
- **Proposed fix**:
  1. **Namebase-first ID bitset filter**: Add an optional `prepare(DatabaseContent const&)` hook on `Search` (called once at the start of `Filter::search` in `src/db/db_filter.cpp:140`). `SearchPlayerName` / `SearchEventName` / `SearchSiteName` / `SearchAnnotatorName` scan the corresponding `Namebase` ONCE (size `U << N`), populate a compact `mstl::bitset` indexed by `entry->id()`, and `match(GameInfo const&)` becomes an **O(1) bitset test** (`m_matchedIds.test(info.playerEntry(White)->id())`)!
  2. Bonus: For `SearchEventName`/`SearchSiteName`/`SearchPlayerName` with plain prefix/surname (`Tabatabaei`, `Tabatabaei,*`, `Tabatabaei *`), `Namebase::m_list` is sorted, allowing even faster prefix/range scans if desired.
  - **Expected gain**: On 544k (`U ≈ 2k–50k`), C++ search drops from **150–254 ms → ~5–15 ms** (**10–30× faster!**), matching numeric search speed!
- **Risk**: Very low. `NamebaseEntry::id()` is unique and bounded by `namebase.nextId()`; exact same semantics as per-game `match()`.
- **Repro commands**:
  ```tcl
  send Chesswiz {
      set db /path/to/bench_500k.sci
      set v [::scidb::view::new $db Normal unused unused unused unused master slave]
      set t0 [clock microseconds]
      ::scidb::view::search $db Normal $v null none {playername any *sen*}
      set ms [expr {([clock microseconds] - $t0)/1000.0}]
      ::scidb::view::close $db Normal $v
      set ms
  }
  ```

---

### A7. Closing, Opening (`.sci`), and Switching Databases — Fixed UI & Index-Load Overhead

- **User action**: Closing any database (`CloseBase`), opening a `.sci` database (`openBase`), or switching between open databases in the database switcher (`switchToBase`).
- **Measured time (3× medians)**:
  - **Close (`CloseBase`)**: **80.8–101.7 ms** on 2k–108.9k DBs; **122.6 ms** `[97.8, 122.8, 122.6]` on 544.3k `.sci` — **constant ~100 ms even for tiny 2k DBs!**
    - Phase breakdown on 544.3k (`tree_bd_results.txt`):
      - `::scidb::db::close` (C++): **4.8 ms** (`[4.8, 4.8, 3.6]`)
      - `::widget::busyCursor on`: **20.2 ms** (`[22.8, 20.2, 19.9]`)
      - `$Vars(switcher) remove`: **32.5 ms** (`[32.5, 32.7, 26.9]`)
      - `::widget::busyCursor off`: **40.6 ms** (`[40.0, 43.2, 40.6]`)
      - Final `update`: **9.6 ms**
      - **96% of `CloseBase` time (~103 ms) is pure Tcl/Tk UI overhead!**
  - **Open `.sci` (`openBase` + `update`)**:
    - `Sample games.sci` (2.2k): **80.9 ms**; `bench_20k.sci` (21.8k): **91.6 ms**; `bench_100k.sci` (108.9k): **112.0 ms**; `bench_500k.sci` (544.3k): **229.6 ms** `[230.0, 170.4, 229.6]`.
    - Phase breakdown on 544.3k: `::scidb::db::load` = **126.5 ms** `[140.6, 126.5, 126.3]`, `switcher add` = **5.7 ms**, `switchToBase` = **43.3 ms**, `update` = **45.3 ms** (**~94 ms fixed UI overhead** on every open!).
  - **Switch database (`switchToBase` + `update`, 20k ↔ 544k)**: **~60–67 ms** per switch (`swCurrent` **2.2 ms**, `::scidb::db::switch` **20.1 ms**, `UpdateAfterSwitch` **2.8 ms**, `update` **34.8 ms**).
- **Where the time goes**:
  1. **`::widget::busyCursor` (`tcl/widgets/misc.tcl:544-590, 759-768`)**: Measured standalone at **32.0 ms** (`on`) + **7.5 ms** (`off`) = **39.5 ms** (and **60.8 ms** inside `CloseBase` where `busyCursor off` flushes pending redraws via `::update`).
     - Calls **`::update` THREE TIMES** per on/off pair: line 574 on `on`, line 588 on `on`, and line 574 on `off`!
     - `BusyCursor` (`tcl/widgets/misc.tcl:759-768`) recursively walks **ALL 694 widgets** under `.application`, calling `winfo toplevel` and `winfo children` on every widget twice (2,786 calls during a single import!) just to locate nested child toplevel windows!
  2. **Redundant switch/update in `DeleteBase` (`tcl/widgets/database-switcher.tcl:582-639`)**: `$Vars(switcher) remove` calls `LayoutSwitcher` (line 626), then `$Vars(switchcmd) $file` (line 635 → full `switchToBase` + `UpdateAfterSwitch`), AND THEN `$Vars(updatecmd) $Vars(variant)` (line 638) immediately after, contributing **32.5 ms** before `::scidb::db::close` even runs!
  3. **`.sci` `Codec::decodeIndex` (`src/db/sci/sci_codec.cpp:1382-1397`)**: Reads 544,250 index entries one 56-byte `fstrm.read(buf, 56)` call at a time, constructing a `ByteStream` per entry, initializing `GameInfo` (`db_game_info.cpp:180`), and running `M_REQUIRE` checks on every lookup.
  4. **Synchronous subscriber fanout in `::scidb::db::switch` (`src/app/app_application.cpp:1234-1253`, 20 ms) + `gamestable::TableFill` (`tcl/gametable.tcl:1136-1188`, 35 ms `update`)**: On every DB switch, C++ synchronously invokes all Tcl subscribers (`updateDatabaseInfo`, `databaseSwitched`, `updateList` across all views), and `TableFill` fetches all 51 columns per visible row (`tcl_database.cpp:2240`) and mutates Tk photo alpha channels for the `acv` column (`tcl/gametable.tcl:1167-1176`) on every visible row!
- **Proposed fix**:
  1. **Fix `::widget::busyCursor` (`tcl/widgets/misc.tcl:544-590, 759-768`)**:
     - Track active toplevels (or query `winfo children .` + a small registered list) instead of recursively descending 694 non-toplevel widgets under `.application`.
     - Replace the 3 full `::update` calls with a single `update idletasks` (only on `on`, and defer `busyCursor on` by 50 ms via `after 50` for short operations like `CloseBase`/`SortColumn`, cancelling it if the operation finishes sooner!). **Expected gain: −60 ms on `CloseBase`, −40–65 ms on `SortColumn` / `newBase` / `RunAdvancedSearch` (even larger on `:0`!).**
  2. **Remove redundant `$Vars(updatecmd)`** in `DeleteBase` (`tcl/widgets/database-switcher.tcl:638`) when `$Vars(switchcmd)` already ran, and defer hidden sub-tab updates on `::scidb::db::switch`. **Expected gain: −20–30 ms on `CloseBase` & `switchToBase`.**
  3. **Bulk-read `.sci` index chunks** in `sci::Codec::decodeIndex` (`src/db/sci/sci_codec.cpp:1382`): read 64 KB–256 KB blocks (`~4,500 IndexEntry` records per `read()`) directly into a buffer and decode in a tight loop (skipping per-record `fstrm.read` + `ByteStream` ctor). **Expected gain: −30–40% of `db::load` (127 ms → ~80 ms on 544k).**
- **Risk**: Low for (1)–(3). Care needed in (1) only to ensure modal dialogs still get busy-cursor coverage if registered or found via `winfo children .`.
- **Repro commands**:
  ```tcl
  send Chesswiz {
      set db /path/to/bench_500k.sci
      set t0 [clock microseconds]
      ::application::database::CloseBase .application $db; update
      expr {([clock microseconds] - $t0)/1000.0}
  }
  ```

---

### A8. Cross-Cutting Build Flags (`-DNREQ`, `-DASSERTIONS`, `USE_POPCNT`) & Game List Per-Row Overhead

- **Observed impact**:
  - **`Makefile.in:12-14, 27`**: `src/tkchesswiz` is compiled with `-O2 -g` **without `-DNREQ`** (so `M_REQUIRE` and `M_ASSERT` in `src/mstl/m_assert.h:36-45` are active everywhere in production!) and with `USE_POPCNT` empty.
    - Verified directly in GDB profile `4_sort_544k`: `mstl::chunk_vector<db::GameInfo, 16u>::released` (`src/mstl/m_chunk_vector.ipp:435`) + `at` (`m_chunk_vector.ipp:458`, which ONLY exist for `M_REQUIRE(!released(chunk_index(n)))`) consume **9.0% of total CPU time during sorting**!
    - Also runs `M_REQUIRE(::sys::utf8::validate(name))` on every `Namebase::insert*` during PGN import (`db_namebase.cpp:352, 415, 489`) and `M_REQUIRE`/`M_ASSERT` inside `Board::doMove` on every move.
  - **`src/cql6/Makefile.scidb:10`**: Hardcodes `-DASSERTIONS`, causing `Position::AssertPos()` to be the #1 worker leaf hotspot in CQL 6.2 (see A2).
  - **Game list fill & scroll (`tcl/gametable.tcl:1102-1188`, `src/tcl/tcl_database.cpp:2240-2384`)**:
    - Scrolling 20 pages down on 108.9k takes **307.8 ms** (~15.4 ms/page on Xvfb).
    - Every visible row calls `::scidb::db::get gameInfo`, which unconditionally constructs **all 51 column `Tcl_Obj`s** (even though only ~10 columns are visible), AND `TableFill` runs 3 `::scidb::tk::image alpha` mutations per row on the `acv` photo image (`tcl/gametable.tcl:1167-1176`) even when `acv` is `0 0 0` (sets alpha 0 on all 3 areas before discarding the image at line 1185!).
- **Proposed fix**:
  1. Add `-DNREQ` (and `-DNDEBUG`, `-DUSE_POPCNT` on x86_64) to release builds in `Makefile.in` (keep debug target without `-DNREQ`), and drop `-DASSERTIONS` from `BASE_FLAGS` in `src/cql6/Makefile.scidb:10`. **Expected gain: 10–25% across all C++ DB operations.**
  2. In `tcl/gametable.tcl:1166-1177`, check `if {$item eq "0 0 0"} { lappend text [list @ {}]; continue }` BEFORE mutating 3 alpha regions on `$image` (skips 3 Tk image calls per unannotated game, which is >95% of games in TWIC/mega DBs!). Optionally pass visible column mask to `getGameInfo` so hidden columns aren't formatted into `Tcl_Obj`s.
- **Risk**: Low (`M_REQUIRE` only checks internal programming invariants; check if any Tcl-facing boundary relies on `M_REQUIRE` throwing `precondition_violation_exception` instead of explicit validation before turning on `-DNREQ` globally — or at minimum guard hot-path `chunk_vector::at` / `Board::doMove` checks under `#ifdef DEBUG`).

---

## Appendix: Fast / Non-Bottleneck Areas Verified

- **Numeric / exact header search (`view::search` on 108.9k)**: Elo rating (**2.7–2.8 ms**), Date (**2.9 ms**), ECO range (**2.5 ms**), Position IDN (**1.7 ms**), Exact player name `=...` (**4.3 ms**), Material (**6.1–6.6 ms**), `filter=players` propagation (**4.7 ms**).
- **`::playerdata::link` on 108.9k**: **0.1 ms** median.
- **`.sci` → `.sci` import**: Merging 5× 108.9k = 544,250 games into a new `.sci` took only **1,232 ms** (~2.3 µs/game — 50× faster than PGN import!).
- **Database sub-tab switching (`player`/`event`/`site`/`annotator`/`position`, 108.9k)**: First activation **32–77 ms**, subsequent switches **0.1 ms**.
