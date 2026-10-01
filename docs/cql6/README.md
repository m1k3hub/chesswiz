# CQL 6.2 analysis reports

Produced 2026-09-30 by delegated analysis agents on one machine (48 cores, shared with other jobs, so timings
are noisy: always compare best-of-N). Instruction counts are from callgrind (`--toggle-collect=cql6_search`).
They were checked against each other: the two independent profile-matrix reports (P2 and P3, different models and
harnesses) agree, and my own profile of the cheap `check` script reproduces their first row exactly.

| File | Subject |
|---|---|
| `REPORT_P1_thread_scaling.md` | why the embedded engine did not scale with threads; four causes with measured fixes (the first two are in `cql6-port`, `de2cfaa`) |
| `REPORT_P3_profile_matrix.md` | where the time goes for 20 script kinds; measured savings of assertions off, lazy position state and early exit |
| `REPORT_P2_profile_matrix_crosscheck.md` | an independent repeat of the same analysis (fewer scripts) |

Plan: `../../CQL6_INTEGRATION_PLAN.md`. Index design these numbers support: `../../PATTERN_INDEX_PLAN.md`.
