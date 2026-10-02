# Task 2b: stop the CQL 6 glue from starving the GUI event loop (prefetch buffer)

Same tree, same rules as `CQL6_TASK2.md` (read it: the API, the stub engine, the tests). You wrote
`src/tcl/tcl_cql6.cpp`: each engine worker calls `nextGame`, which queues ONE Tcl event per game
(`Tcl_ThreadQueueEvent`, TCL_QUEUE_TAIL), waits on a condition variable while the main thread decodes that
one game in `eventProc`/`requestGame`, then returns. The owner measured the consequence: during a search the
largest gap of a 20 ms Tcl timer is 97-110 ms (your own idle run saw 55 ms), because Tcl services queued events
BEFORE timers, idle callbacks (redraw) and window events, so a steady stream of one-game events starves them. It
also limits throughput to one thread-wakeup round trip per game while the engine's other workers wait on the
engine's callback mutex.

## Required design

* A bounded prefetch queue of owned game snapshots per job (capacity about 2048 games or a memory cap, whichever
  comes first; expose the capacity as a constant).
* The main thread fills it in BOUNDED SLICES: one queued event decodes games until either the queue is full,
  the database ends, or about 2 ms of wall time have passed, then returns. After a slice, if the queue is below
  half full and the job is running, schedule the next slice so that OTHER events get their turn in between: use a
  zero-delay timer handler (`Tcl_CreateTimerHandler(0, ...)`) or an idle handler, NOT another tail-queued
  event. Workers take snapshots from the queue under a mutex and never wait on the GUI thread except when the
  queue is empty and the database is not finished (then they wait on a condition variable with the job's other
  end conditions: cancel, close, dead).
* Keep every safety property of the current design: database access only on the Tcl thread; cancel/close/reopen
  handling (`database closed` result, identity check of the database object); results delivered through the main
  thread; no Tcl/Tk calls from workers; nothing leaks when a job is cancelled or the interpreter is deleted
  (free the queued snapshots).
* The synchronous form (no `-command`) must not deadlock: it may fill the queue on the calling thread while
  the engine runs on its own thread, running slices itself.
* `progress` keeps meaning "games handed to the engine so far".

## Tests (add to `tests/test_app_cql6.tcl`, keep all 22 existing ones passing)

1. Responsiveness: a 20 ms timer during a 20000-game search with the `SLOW` stub raised to a fixed cost per
   game that keeps the search running for several seconds: the largest gap must be under 40 ms (report the
   number; run it three times).
2. Throughput: with the stub `MATCH_ALL` (no per-game sleep) over 20000 games, report games per second for
   `-threads 1`, 4, 16; it must be at least 5 times the round-trip design's rate, which you measure first on the
   current code and report. Also report the rate when the GUI thread is kept busy by a competing 1 ms timer loop.
3. Cancel during a slice, close during a slice, reopen during a slice, interpreter deletion during a job: all
   deliver the right result and leave no job behind (check the job table and memory with a loop of 200 such
   jobs and compare `ps` RSS before/after).
4. Order: the stub's `DUMP` output for 500 games is identical to before (the queue must not reorder or drop games)
   for `-threads 1`; with more threads the set of games examined is complete and each exactly once.
5. The complete existing app test suite still passes.

Then run the glue under AddressSanitizer and ThreadSanitizer: build the stub engine and the Tcl glue with
`-fsanitize=address,undefined` (and separately `-fsanitize=thread`) if the whole application can be linked that
way, otherwise build a small standalone harness that compiles `tcl_cql6.cpp` against a minimal fake of the few
Scidb calls it uses and a real Tcl interpreter, and run tests 1-4 there. Zero reports allowed; fix real findings.

Finish with an honest report: design, numbers, what you could not verify. Do not weaken a test to pass.
