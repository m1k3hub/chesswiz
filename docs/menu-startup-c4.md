# Menu startup follow-up measurement (2026-10-26)

Assignment W3k-fix-c4 follow-up, items 1–6: the startup item permits profiling
and documenting a quiet measurement. This records that option; it does not
claim that the wider mission's 5% settled-startup gate passes.

Measured candidate: feat/menu-w3-eval at 0a462ff6, shipped pack 703 actions.
Baseline: unchanged pre-mission worktree at 1db42e68.
Native SHA-256: candidate c761d1a3f4e19ca3a8054580ae56fbcca725ce65a1df6d3df4f6bad1377a7c55;
baseline cefe2e2edb99fcc85b0b29a72e67d47cc86ce279d5e8952251534fda51c80329.

Nine alternating before/after pairs, first pair excluded, median of eight.
Both use isolated HOME, assistant startup disabled, Xvfb 1920×1080/Openbox,
PULSE_SINK=cwtests, and `bwrap --dev-bind / / --unshare-net`.
All worker builds and app tests had finished before measurement; unrelated
host workloads were left alone. Each sample records host load in results.json.
Settled time uses the existing runner's 200 ms timer following ready, including
synchronous work that delays that timer. All 18 launches exited 0.

| Metric | Baseline median (ms) | Candidate median (ms) | Change |
| --- | ---: | ---: | ---: |
| source_ms | 2454.0 | 2178.0 | -11.25% |
| map_ms | 2307.5 | 2043.5 | -11.44% |
| ready_ms | 2307.5 | 2044.0 | -11.42% |
| settled_ms | 2691.5 | 2839.0 | +5.48% |

Settled startup remains +5.48%; the earlier +5.74% observation was not eliminated.
No acceptance threshold or startup timer was changed. A separate traced launch
measured FillAll=106048 μs, Ensure=109644 μs, Startup2=297374 μs (inclusive).
The trace is diagnostic and is excluded from the paired measurements.

Rerunnable scripts and raw evidence are under the assigned worktree's
`tests/tmp-app/w3k-fix-c4/`: `run-startup-quiet.py`, `startup-timing.tcl`,
`run-with-wm.sh`, `profile.tcl`, `profile.log`, and `timing-quiet/`.
Run from that worktree with:

```sh
PULSE_SINK=cwtests bwrap --dev-bind / / --unshare-net   python3 tests/tmp-app/w3k-fix-c4/run-startup-quiet.py
```

Retained settled samples (milliseconds):

```json
{
  "before": [
    2725,
    2835,
    2740,
    2585,
    2650,
    2658,
    2933,
    2565
  ],
  "after": [
    2952,
    3095,
    2836,
    2842,
    2753,
    2775,
    2798,
    2857
  ]
}
```

## Settled-startup fix (2026-10-26)

The follow-up candidate on `feat/menu-w3-eval` (parent `fecce61d`) now
meets the +5% target against the exact `1db42e68` baseline. This measurement
supersedes the above +5.48% result for the current implementation.

Startup still registers every surface action, wires native operations and
exposes all assistant operators synchronously. It defers descriptive knowledge
synthesis until the first help, search or pack-enumeration request. Explicit
`knowledge::Ensure` calls still refresh the full knowledge. Sibling lookup also
filters registry keys in Tcl's dictionary implementation, preserving insertion
order and results. No timer, metric, native binary, generated pack or acceptance
threshold changed. First knowledge use pays the synthesis cost once.

The method is unchanged: nine alternating pairs, warmup pair dropped, medians
of eight retained launches per phase; isolated HOME, assistant startup disabled,
Xvfb 1920×1080/Openbox, PULSE_SINK=cwtests, network denied by bubblewrap.
All worker builds, app tests, parity probes and diagnostic profiling finished
before measurement. No foreign workloads or processes were changed. Per-launch
host load is retained in results.json. All 18 launches exited 0.

| Metric | Baseline median (ms) | Candidate median (ms) | Change |
| --- | ---: | ---: | ---: |
| source_ms | 2502.0 | 2108.5 | -15.73% |
| map_ms | 2359.5 | 1980.0 | -16.08% |
| ready_ms | 2359.5 | 1980.5 | -16.06% |
| settled_ms | 2737.0 | 2673.5 | -2.32% |

Separate diagnostic launch: `Startup2` = 204968 μs, compared with the prior
297374 μs; no `FillAll` ran at startup. Profile data is excluded from the paired
measurement. First-use tests prove operators can run before synthesis, and that
help, search and pack enumeration initialize complete knowledge on demand.
All 707 registered actions have identical sibling results against the original
procedure; all four generated knowledge files are byte-identical.

Required regression suites remain green: knowledge 18, coverage 6, lifecycle 1,
pane reflow 29, plus three dialog deadline runs (maximum placement 225 ms,
unchanged 500 ms limit). New first-use suite: four tests pass; separately selecting
first search and first pack enumeration in fresh apps adds two passing checks.

Raw evidence and rerunnable scripts: `tests/tmp-app/w3k-startup-c5/`, including
`checks.sh`, `check-first-use.sh`, `profile-final.log`, `parity-final.log`, and
`timing-quiet/{results.json,summary.json}`. Runner and timing script are identical
to c4 except for the evidence output directory. Run from the worktree:

```sh
PULSE_SINK=cwtests bwrap --dev-bind / / --unshare-net python3 tests/tmp-app/w3k-startup-c5/run-startup-quiet.py
```

Retained settled samples (milliseconds):

```json
{
  "before": [
    2691,
    2640,
    2783,
    2871,
    2804,
    2667,
    2546,
    2934
  ],
  "after": [
    2865,
    2785,
    2680,
    2710,
    2587,
    2667,
    2608,
    2626
  ]
}
```

An earlier sibling-only candidate measured +6.15%, so it was insufficient;
its complete run is retained as `timing-siblings-only/`. The successful final
measurement includes deferred synthesis. Both native SHA-256 values are
unchanged from the c4 record above.
