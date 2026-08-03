# Fixit Plan — 2026-07-25 bugcheck sweep

**STATUS 2026-07-25: all groups (A–G) implemented.** Group A additionally
required rewriting cbh::Consumer to buffer the game tree and emit in ChessBase
order (main continuation = first pushed variation, last alternative inline).
Verified: `src/verify_cbh_write` PASSED (incl. new variation/annotation test
game); libdb/libsys build clean; all edited Tcl files brace-checked.

**STATUS 2026-08-03: verify-only bugcheck re-run COMPLETE.** An independent
reviewer re-read the current file content at every cited location and confirmed
all 7 groups (A–G) are PRESENT in the current code. See the verification table
in the commit message. Residual notes: A4's secondary `M_ASSERT(number <= 2)`
guard is debug-only (the `encodeMove` guard at line 354 is the primary defense
and covers all call paths); F3's help files still contain untranslated German
in the English docs (content, not corruption).

Source: full-tree bugcheck (35 confirmed findings, all adversarially verified).
Grouped by root-cause pattern to minimize context-switching. Fix a group, run its
verification step, commit, move on. Re-run bugcheck in verify-only mode at the end.

---

## Group A — CBH encoder ↔ decoder contract mismatches (P1/P2, highest value)

All in `src/db/cbh/`, new encoder code. Root cause: the encoder invents its own
move/annotation numbering instead of matching the decoder's conventions
(monotone move counter, `0xffffff` game-level sentinel, wtm-relative symbols).

| # | Where | Bug | Fix |
|---|-------|-----|-----|
| A1 | `cbh_consumer.cpp:224,242` | `m_count` saved/restored across variations; decoder uses one monotone counter | Delete the `m_countStack` save/restore (P1) |
| A2 | `cbh_consumer.cpp:208` | Annotations keyed by ply index that goes non-monotone around variations | Key by the (now monotone, per A1) move counter, write `counter-1` |
| A3 | `cbh_consumer.cpp:144` | Pre-game comment written at moveNo 0, colliding with move 1 | Use game-level sentinel `0xffffff` |
| A4 | `cbh_encoder_position.cpp:255` | `queenBase[number]` etc. indexed with piece number up to 9; OOB read in release for 4th queen/rook/bishop/knight | Throw encoding-unsupported (or emit `0xEB` escape word) for `number > 2` |
| A5 | `cbh_encoder_position.cpp:147` | Promotion slot search falls through with `number == 10` → writes `pieces[10]`, OOB | Guard: `if (number == 10) throw` |
| A6 | `cbh_annotation_encoder.cpp:249` | `nagToColorPositionSymbol` ignores `whiteToMove`; unreachable Zugzwang cases | Return symbol only when NAG color matches `whiteToMove`; drop dead cases |

**Verify:** round-trip test — encode games with variations + annotations +
pre-game comments + promotions to CBH, decode with the existing decoder, diff
against source PGN. Fix A1 before A2 (A2's fix depends on A1's monotone counter).

## Group B — Tcl name/arity mismatches, live paths (P2, quick wins)

Root cause: refactor renamed or re-signed procs without updating all call sites.

| # | Where | Bug | Fix |
|---|-------|-----|-----|
| B1 | `app-pgn.tcl:2253` | `OpenMarksPalette` → proc is `openMarksPalette` | Lowercase the call |
| B2 | `app-tree.tcl:2710,2712,2724,2726` | 3rd arg `good`/`bad` passed to 2-arg `insertBody` (line 2137) | `proc insertBody {w text {tag normal}}`, insert with `$tag`, define good/bad text tags |
| B3 | `fsbox.tcl:2434` | `$Vars(fti:$ext)` read without `info exists` guard | Add guard + `document` icon fallback (mirror GetFileIcon) |

**Verify:** launch app; click a mark in PGN view (B1); open tree view bishop-pair
stats (B2); rename a file to an odd extension in fsbox (B3).

## Group C — Extension normalization (P2/P3)

Root cause: raw `[file extension]` vs. GetFileType-normalized switcher values.

| # | Where | Bug | Fix |
|---|-------|-----|-----|
| C1 | `app-database.tcl:492` | Dotless raw ext compared against normalized switcher ext → hard-link duplicate-open check never fires for compressed PGN | Normalize both sides via the same GetFileType mapping before comparing |
| C2 | `app-database.tcl:1567,1585` | `$ext eq "pgn.gz"` can never match (GetFileType collapses to `pgn`) | Drop dead alternatives (or stop collapsing in AddBase if gz must be distinguishable) |

**Verify:** open the same `.pgn.gz` via two hard links → second open must be detected.

## Group D — C++ exception-safety / leaks (P3, hardening)

Root cause: raw `new` + raw-pointer vectors + cleanup that only runs on the
happy path. Same pattern, five sites — fix with one RAII/scope-guard idiom.

| # | Where | Bug |
|---|-------|-----|
| D1 | `db_database.cpp:2222` | `new PlayerStatsWorker`/`new Thread` leak if subsequent alloc throws |
| D2 | `db_database.cpp:2241` | `stats.merge()` throw mid-loop → remaining threads never joined, workers leak |
| D3 | `db_maintenance.cpp:331` (+~414, ~474) | same merge-throw worker-leak pattern ×3 |
| D4 | `sys_thread.cpp:70` | `m_exception` never deleted (leak + stale exception on restart) |
| D5 | `sys_thread_group.cpp:62` | `push_back` throw leaks the not-yet-started `Thread` |
| D6 | `sys_thread_group.cpp:88` | `joinNoThrow` can throw (mstl::string alloc) mid-loop |

Fix idiom: hold workers/threads in auto_ptr-style owners until ownership passes
to the container; split join loops into join-all-then-merge (merge in try/catch
that joins+deletes the remainder before rethrow); `delete m_exception` in
`doStart`/`~Thread`; build `failMsg` without allocating inside the join loop.

**Verify:** compile + existing tests; these are error-path-only changes.

## Group E — Latent dead-guarded Tcl (P3, decide: fix or delete)

Root cause: unfinished features behind `if {0 && ...}` / `if {0}` guards with
references that would error the moment the guard is enabled. Fix now (cheap) or
delete the dead code; do NOT enable the guards.

| # | Where | Bug |
|---|-------|-----|
| E1 | `exec.tcl:219` | `$::util::photos::mc::TimeoutOut` → defined name is `TimeOut` (typo) |
| E2 | `exec.tcl:220,226,234` | `mc::UpdateAborted` undefined anywhere |
| E3 | `exec.tcl:225,233` | `mc::ErrorOccurred` undefined anywhere |
| E4 | `exec.tcl:231` | `::util::photos::updateFiles` doesn't exist (API is checkForUpdate/downloadFiles) |
| E5 | `player-card.tcl:382-385` | `DeletePlayer`/`SavePlayer`/`NewPlayer`/`CloseSetup` all undefined; dialog unreachable via disabled `menu.tcl:311` entry |
| E6 | `entrybuttonbox.tcl:76` | `ComboboxSelected` resolves to wrong namespace (proc lives in `::theme`) |

Recommendation: fix E1 (pure typo) and E6 (qualify to `::theme::`); for E2–E5
either stub the missing procs/strings or delete the guarded blocks with a note.

## Group F — Encoding corruption (P2 for code, P3 for docs)

| # | Where | Bug | Fix |
|---|-------|-----|-----|
| F1 | `db_site.cpp:198` | U+FFFD in `Exclude` literal where U+00B4 belongs → `Site::normalize` broken for ´ | Use explicit escape `"\xb4"` (P2) |
| F2 | `cbh_codec.cpp:909` | U+FFFD in comment only | Rewrite comment |
| F3 | `tcl/help/en/{Clipbase,CQL-Piece-Designators,CQL-Position-List}.html` | Double-encoded UTF-8 German mojibake | Re-decode once (iconv utf-8→latin1 on affected spans); ideally translate leftover German in en/ files |

**Verify F1:** unit check that `Site::normalize` strips `´` again.

## Group G — Repo debris (trivial)

- `rm EOF SCRIPT` at repo root (empty executable heredoc artifacts, untracked, unreferenced).

---

## Order of execution

1. **B + C1** — small, live, user-visible; one commit.
2. **A** — the CBH encoder cluster with round-trip test; one commit (A1→A2 dependency).
3. **F1 + F2** — encoding in code; fold into A's commit or standalone.
4. **D** — exception-safety hardening; one commit.
5. **E, C2, F3, G** — cleanup commit(s).

Then re-run bugcheck verify-only mode against this catalog before closing.
Remember: `chmod 644` touched files before committing (no mode churn).
