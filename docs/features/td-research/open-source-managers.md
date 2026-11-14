# Open-source chess tournament managers — P0 research report (full, source-path edition)

Read-only research for the Tournament Director (TD) mission. No Chesswiz repo files edited,
no code copied, no agents spawned by the research child. The four projects were shallow-cloned
to `/tmp/td-res` (outside the worktree) and inspected at the exact commits below; all cited paths
are relative to each clone root. Ideas only — the brief restricts code reuse to bbpPairings.

Parent review note: the bundled Chesswiz interpreter could not find Tcl's `sqlite3` package,
so this mission uses the brief's permitted append-only, checksummed journal rather than claiming
an SQLite backend. The migration/crash-boundary ideas below still apply to the journal's explicit
schema version and recovery records.

Plan context read: `docs/features/TOURNAMENT_DIRECTOR_PLAN.md` §1b (product principle: every
screen/field/button is a registry action with typed arguments, assistant parity at command
level), §1c (reference table of existing managers), §6 (storage = versioned transactional
event store, TRF16+TRF26 as edge adapters, tiebreak breakdowns, preview/commit commands,
unplayed-game categories), and `tests/tmp-app/td/BRIEF.md`.

Conventions used below:
- **[E]** = evidence (file/line inspected in the clone at the cited commit)
- **[I]** = inference drawn from that evidence

---

## 0. Identification summary

| Project | Canonical GitHub URL | Full inspected commit SHA | Language/stack | Licence |
|---|---|---|---|---|
| Chessament | https://github.com/KDE/chessament (mirror; canonical dev repo https://invent.kde.org/games/chessament per README) | `c122b4cd4d94a62d63bc7fda375f5875c1ee7428` | C++ (Qt6/QML, QtSql, QCoro) | GPL-3.0-or-later |
| Gambit Pairing | https://github.com/gambit-devs/gambit-pairing | `be027169e2ec263e22fe1349b514825e1007894a` | Python 3.9+ / PyQt6 | GPL-3.0-or-later |
| Pawn | https://github.com/grok-rs/pawn | `f25e9e97c9768ec928632b4fa4174184196f7e01` | Rust (Tauri 2) + React 19 (TypeScript) | claims MIT; **no licence file present — unresolved** |
| PonzianiSwiss | https://github.com/guentherc/PonzianiSwiss | `ee1474c834d1b13f4726fae0c641bbacb8ad01a7` | C# / .NET WPF (MVVM) | GPL-3.0 |

**Plan mistake to correct [E]:** `docs/features/TOURNAMENT_DIRECTOR_PLAN.md` §1c lists
"Ponziani Swiss (Java)". PonzianiSwiss is C#/WPF (`.xaml` views, `PonzianiSwiss.csproj`,
`Directory.Packages.props`, MSBuild solution). No Java anywhere in the tree.
**Plan entry to annotate [E]:** "Pawn (Tauri/Rust)" is correct but the repo is undiscoverable
by GitHub name/topic search; it was identified via web search for `grok-rs/pawn` and confirmed
by `README.md` ("Built with Tauri, React, and Rust") and `src-tauri/Cargo.toml` (`tauri = "2.7.0"`).
Disambiguation performed: `TonyErazo/Gambit` (gaming LFG) and `Pawn-Appetit/pawn-appetit`
(analysis toolkit, not a TD) were rejected as the wrong projects [E].

---

## 1. Chessament

- **URL:** https://github.com/KDE/chessament (canonical: https://invent.kde.org/games/chessament)
- **Commit:** `c122b4cd4d94a62d63bc7fda375f5875c1ee7428` (master HEAD at inspection).
  Release declared in `org.kde.chessament.metainfo.xml` line 216: version 1.0.0, 2026-11-08 [E].

### Licence
- **[E]** Per-file SPDX headers, e.g. `src/tournament/trf/trf.h:2`
  `SPDX-License-Identifier: GPL-3.0-or-later`; licence texts in `LICENSES/`
  (includes GPL-3.0-or-later.txt, Apache-2.0.txt, BSD-2/3, CC0, CC-BY-SA, LGPL). README.md is
  CC0-1.0. **No ambiguity** for the app code (GPL-3.0-or-later); dependency licences vary.

### Stack / architecture
- **[E]** C++/Qt6 with a pure-library layer `src/tournament/` ("libtournament") and a QML
  frontend in `src/qml/` + per-tab C++ models in `src/` (`playersmodel.cpp`, `standingsmodel.cpp`,
  `pairingmodel.cpp`, `roundmodel.cpp`, `byesmodel.cpp`, `tiebreakmodel.cpp`,
  `arbitersmodel.cpp`, `ratinglistmodel.cpp`, `searchplayersmodel.cpp`, `documents.cpp`).
  Async via QCoro (`pairingengine.cpp` uses `qCoro(process)`). Error handling throughout is
  `std::expected<T, QString>` — no exceptions [E, e.g. `src/tournament/trf/reader.cpp:27`].

### Data model and storage
- **[E]** Storage is SQLite via QtSql: `src/tournament/event.cpp` (`openDatabase` line 128,
  `QSqlDatabase::addDatabase(u"QSQLITE"_s, ...)`); schema DDL in `src/tournament/db.h`
  (lines 26–110: tables `tournaments`, `event_options`, `options`, `players`, `rounds`,
  `pairings`) plus a separate rating-lists DB in
  `src/tournament/ratinglists/ratinglistsmanager.h` (lines 21–59, tables `ratinglists`,
  `players`, with playerId/nationalId/list indexes). No numbered migrations — DDL is
  `CREATE TABLE IF NOT EXISTS` style.
- **[E]** Entities: `Tournament` (`src/tournament/tournament.h:39`), `Player`
  (`src/tournament/player.h:18`, Q_PROPERTYs: startingRank, title, rating, nationalRating,
  playerId, nationalId, birthDate, federation, origin, gender; Title enum GM..WCM),
  `Pairing` (`src/tournament/pairing.h:18`: board, whitePlayer, blackPlayer, and **two
  independent `PartialResult` values** — white/black result are separate, so unplayed and
  forfeit halves are representable), `Round`, `Standing`, `Arbiter`, `TimeControl`,
  `State` (`src/tournament/state.h` — per-round `points()` vs `pointsForTiebreaks()` are
  distinct methods, i.e. "points for tiebreaks ≠ points" is explicit model state).
  An `Event` document can hold multiple tournaments.
- **[I]** `State::pointsForTiebreaks` separation anticipates exactly our §6 requirement that
  unplayed-game categories score differently for standings vs tiebreaks; our model should keep
  that distinction as a named policy, not an implicit branch.

### Pairing
- **[E]** Swiss via external bbpPairings: `src/tournament/pairingengine.cpp` — locates the
  `bbpPairings` executable (QStandardPaths, app-dir fallback on Windows), writes the current
  round's TRF to a `QTemporaryFile`, runs `bbpPairings --dutch file -p`, waits with a hard
  **3-second timeout** (`co_await proc.waitForFinished(3s)`), maps non-zero exit codes to
  i18n error strings. Round-robin is **absent** at this commit [E: README "supports individual
  Swiss-system tournaments"; no RR code under `src/tournament/`].

### TRF import/export
- **[E]** `src/tournament/trf/trf.h` (Field enum for all TRF header fields, lines 11–40;
  `RoundDateFormat = "yy/MM/dd"`; `Option::InitialColorWhite/Black` flags — writes `012 W` so
  the pairing engine knows the colour of pairing number 1); `trf/reader.cpp` (full parser:
  skips blanks, `0000 - H` bye records, unknown-result rejection, players sorted by starting
  rank, rounds rebuilt from pairing lines); `trf/writer.h/.cpp`
  (`writeTournamentInformation`, `writeArbiters`, `writeTiebreaks`,
  `writePairingEngineInformation`, `writePlayers`). TRF is import/export only — the save
  format is SQLite [E].
- **[I]** `InitialColor` is persisted tournament state (`Tournament::InitialColor`,
  `tournament.h:300`), matching C.05 "colours of pairing number 1 decided by lot" as *event
  state*, not derived data. Our P1 RR should persist it the same way.

### Tiebreaks
- **[E]** Plug-in architecture `src/tournament/tiebreaks/`: base `Tiebreak`/`tiebreak.cpp`
  (options, TRF option string, JSON) + concrete: `buchholz`, `sb`, `progressive`, `points`,
  `playedblack`, `numberwins`, `won`, `rep`, `bwg`, `aob`; ordering container `tiebreaks.cpp`
  (`addTiebreak`, `swapTiebreaks`, `toJson/fromJson`, `tiebreakFromTrf(code)` maps TRF codes
  to objects). **No breakdown machinery** (values only, with a "precision" test column).
  Float-based [I from `tiebreakstest.cpp` precision column].

### UI workflow
- **[E]** `src/qml/`: `Main.qml`, `Sidebar.qml`, `WelcomePage.qml`, `NewTournamentDialog.qml`,
  `PlayersPage.qml`, `PairingsPage.qml`, `StandingsPage.qml`, `PairRoundDialog.qml`,
  `UpdateRatingsDialog.qml`, `SortPlayersDialog.qml`, delete dialogs, `ResultButton.qml`;
  settings wizard pages in `src/tournament/qml/` (`SettingsFormatPage.qml`,
  `SettingsInformationPage.qml`, `SettingsCalendarPage.qml`, `SettingsCloudPage.qml`,
  `SettingsDialog.qml`, `AddTiebreakDialog.qml`, `TiebreakDialog.qml`). A cloud sync module
  exists (`src/tournament/sync/`: `account.cpp`, `accountmanager.cpp`, `syncengine.cpp`).

### Test vectors worth reimplementing
- **[E]** `autotests/data/tournament_1.trf`, `tournament_2.trf` — full 100-player, 9-round
  TRF16 files (reimplement: import → compute Buchholz variants → compare against
  independently calculated values). `autotests/data/buchholz_1.trf` … `buchholz_4.trf` —
  targeted Buchholz edge cases. `autotests/data/arbiters.trf`.
- **[E]** `autotests/tiebreakstest.cpp` lines 63–78: a data-driven harness — each row is
  (file, TRF tiebreak code, precision, tiebreak string), e.g. `tournament_1.trf` ×
  `pts,bh` / `pts,bh/c1` / `pts,sb` / `pts,sb/c1` / `pts,sb/c2` / `pts,win` / `pts,won` /
  `pts,bpg` / `pts,aob` / `pts,ps` / `pts,bwg` / `pts,rep` — the TRF tiebreak-code vocabulary
  itself is reusable as our fixture matrix.
- **[E]** `autotests/tournamenttest.cpp`: `testExportTrf`/`testImportTrf` (round-trip),
  `testRemovePairings_data` (rows "keepByes = false/true" with expected starting-rank lists,
  lines 201–202 — the keep/annul-bye semantics when re-pairing), `testTimeControl_data`
  (lines 232–235: `600`, `600+10`, `40/600+10`, `40/600+10:120+10` — TRF `212`-style
  time-control parsing vectors).
- **[I]** Vectors to build for us: TRF16 round-trip byte-comparison, Buchholz Cut1/Cut2
  edge series, time-control string parser, and "remove pairings with/without keeping byes".

### P1-relevant lessons
- `std::expected<T,QString>` everywhere → every `td.*` command should return
  `{ok, result|error}` with localisable messages [I].
- bbpPairings invocation needs a timeout + stderr capture + exit-code mapping [E → I].
- TRF initial-colour flag persisted as event state [E → I].
- SQLite is their storage, TRF the edge adapter — independent corroboration of §6 draft-2 [I].

---

## 2. Gambit Pairing

- **URL:** https://github.com/gambit-devs/gambit-pairing (org: gambit-devs; DeepWiki badge
  references `Chickaboo/gambit-pairing` — older org name [E]).
- **Commit:** `be027169e2ec263e22fe1349b514825e1007894a` (main HEAD). Latest release
  v0.7.0 (2026-01-23) [E via API]. README self-describes as **alpha**.

### Licence
- **[E]** `licenses/LICENSE` is GNU GPL v3 (verbatim); `pyproject.toml:20`
  `license = {text = "GPL-3.0-or-later"}`; README badge "GPL v3".
- **[I]** GitHub's API reports no licence object (probably no standard LICENSE at root), so
  there is minor ambiguity "GPL-3.0-only vs or-later"; treat as GPL-3.0-family, ideas only.

### Stack / architecture
- **[E]** Python 3.9+ / PyQt6. Layout (from `docs/program-structure.md` + tree):
  `src/gambitpairing/pairing/` (pure algorithms), `src/gambitpairing/tournament/`
  (orchestration: `tournament.py` facade over `round_manager.py`, `result_recorder.py`,
  `tiebreak_calculator.py`, `models.py` dataclasses), `src/gambitpairing/player/`
  (`base_player.py`, `fide_player.py`, `cfc_player.py`, `factory.py` — per-federation player
  adapters), `src/gambitpairing/gui/views/...` (PyQt6 views), `utils/` (printing, validation,
  CTR builder), `update/` (updater). PyInstaller packaging (`*.spec`, `make_msi.py`).
- **[E]** Persistence is **JSON** (`.json` files; `to_dict`/`from_dict` on every model,
  `models.py` lines 49–179).

### Data model
- **[E]** `tournament/models.py` dataclasses: `TournamentConfig`, `MatchResult` (with
  `black_score` property), `RoundData`, `PairingHistory` (`have_played(p1,p2)` for rematch
  avoidance). Player state on the player object: score, `color_history`, `opponent_ids`,
  `results`, `running_scores`, `has_received_bye`, `num_black_games`, `float_history`,
  `match_history`, `tiebreakers` [E: `test_data/tournaments/test_32_player_tournament.json`].

### Pairing
- **[E]** Swiss: `src/gambitpairing/pairing/dutch_swiss.py` — a **3,220-line from-scratch FIDE
  Dutch implementation**: permutation enumeration with lexicographic ordering by player BSN
  (C.04 transpositions), `_colors_satisfy_preferences_unified` with an explicit
  FIDE-vs-Dutch flag, `_is_topscorer` (C.04 §1.7, final round only), `_compute_psd_list` /
  `_compare_psd_lists` (C.04 §1.8 Pairing Score Difference lists, **compared with
  `eps = 1e-9` float epsilon**). No external pairing engine.
- **[E]** Round-robin: `src/gambitpairing/pairing/round_robin.py` — precomputed
  `BERGER_TABLES` keyed "3-4" … "15-16" (hard size limit 3–16 players), per-size table
  selection, `RoundRobin` class with all-rounds generation and per-round extraction.
- **[I]** The eps-float PSD comparison and heuristic structure are precisely the failure
  modes §6 warns about (exact rational arithmetic); Gambit is the cautionary example, not a
  pairing authority. No bbpPairings involvement at all.

### TRF import/export
- **[E]** **Absent.** A repo-wide grep for TRF outside the license text finds nothing
  (`src/` has no trf module; save/load is JSON; player import is CSV/text per README).
  No FIDE rating-report capability.

### Tiebreaks
- **[E]** `src/gambitpairing/tournament/tiebreak_calculator.py`: `calculate_all_tiebreaks`,
  per-player calculation, `_calculate_median`, `_set_zero_tiebreaks`,
  `calculate_head_to_head`. Tiebreak set (constants at lines 26–32): CUMULATIVE,
  CUMULATIVE_OPP, MEDIAN (Modified Median), SOLKOFF (Buchholz), SONNENBORN_BERGER,
  MOST_BLACKS — **USCF-flavoured naming** [I]. Order is user-configurable with
  drag-and-drop (README "Full tiebreaker configuration with drag-and-drop order in settings").
  **No breakdowns.** Float arithmetic.

### UI workflow
- **[E]** `src/gambitpairing/gui/` (program-structure.md tree): tabs Players / Tournament
  Control / Standings / Cross-Table / History Log (`crosstable_tab.py`, `history_tab.py`,
  `players_tab.py`); dialogs `manual_pairing_dialog.py`, `new_tournament_dialog.py`,
  `player_edit_dialog.py`, `settings_dialog.py`, `printing.py`.
  `gui/views/tournament/` MVC split: `tournament_view.py`, `tournament_controller.py`,
  `tournament_state.py`, `components/`, `utils/pairings_printer.py`.
- **[E]** `docs/manual-pairing-guide.md` (lines 63–65): manual pairing dialog with
  **real-time validation warnings** (repeat pairings flagged in a validation panel) *before*
  results are entered. README: "auto-set results for inactive players", "undo last round's
  results", print preview for pairings/standings, exportable history log.

### Test vectors worth reimplementing
- **[E]** `test_data/tournaments/test_32_player_tournament.json` (32-player Swiss, all player
  state pre-seeded), `test_open_2025.json`, `winter_chess_championship_2025.json`.
- **[E]** `src/gambitpairing/test/core/pairing_round_robin.py` (28 tests, lines 26–526):
  `test_bye_assignment_odd_players`, `test_no_bye_even_players`,
  `test_all_players_paired_each_round`, `test_no_duplicate_matches_in_round`,
  `test_round_robin_completeness` (every pair meets exactly once),
  `test_player_plays_correct_number_of_games`, `test_berger_table_coverage`,
  `test_small_tournament_complete_cycle`, `test_medium_tournament_bye_handling`,
  `test_large_tournament_pairing_quality`. These are **RR structural invariants** — perfect
  as our P1 C.05 invariant tests, independent of any pairing engine.
- **[E]** `tournament.py:367` `_get_eligible_bye_player`: bye priority = active, no prior bye,
  lowest score → lowest rating → name; second bye only as last resort.
- **[I]** Vectors for us: 32-player multi-round Swiss with a withdrawal and a manual
  re-pair; RR invariants (completeness, no duplicates, bye handling, per-player game count);
  bye-eligibility ordering as an explicitly specified policy test.

### P1-relevant lessons
- Manual pairing with live validity warnings + "undo last round" is the cheap cousin of our
  preview/commit + revisions; Gambit has **no revision numbers and undo covers only the last
  round** — our event-revision model is strictly stronger [I].
- Their action history log (exportable) maps to our immutable audit entries [I].
- Federation-specific player adapters (FIDE/CFC) validate the per-rating-list reader module
  design [I].
- A 3.2k-line own-Dutch implementation with float eps is the strongest argument for keeping
  bbpPairings as the single pairing authority [I].

---

## 3. Pawn

- **URL:** https://github.com/grok-rs/pawn
- **Commit:** `f25e9e97c9768ec928632b4fa4174184196f7e01` (main HEAD). Releases from v1.0.0.

### Licence
- **[E]** `README.md:7` badge "License: MIT"; `README.md:152` "MIT License - see [LICENSE]
  file". **A repo-wide `find . -iname "LICENSE*"` at this commit returns nothing** — the
  referenced file does not exist in the tree. No licence field in `package.json` or
  `tauri.conf.json` either.
- **[I]** Licence is **unresolved** despite the MIT claim. Treat as unlicensed for our
  purposes: ideas only, no code. (Even MIT would be compatible, but the missing file blocks
  verification.)

### Stack / architecture
- **[E]** `src-tauri/Cargo.toml`: Tauri 2.7.0, sqlx 0.8.6 (sqlite), uuid, chrono, and
  **tauri-specta 2.0.0-rc.21 + specta-typescript + ts-rs** with a `generate_bindings.rs`
  binary — TypeScript command bindings are *generated from the Rust backend*, giving one
  typed command surface shared by UI and any automation. Frontend: React 19 + Vite +
  TypeScript (`package.json`, `src/app/`, `src/pages/`, `src/widgets/`), Playwright e2e +
  Vitest unit tests (`playwright.config.ts`, `vitest.config.ts`).
- **[E]** `CLAUDE.md` documents the architecture accurately (widgets with extracted hooks:
  `usePlayerManagement`, `useResultsGrid`, `useRoundManager`).

### Data model and migrations
- **[E]** SQLite via sqlx with **15 numbered up/down migrations**:
  `src-tauri/migrations/0001_init_schemas.up.sql` … `0015_add_application_settings.up.sql`
  (+ matching `.down.sql`). `0001` creates `tournaments`; `0002_add_players_games.up.sql`
  creates `players` (tournament_id FK, rating, country_code) and `games` (round_number,
  white/black player ids, `result TEXT CHECK IN ('1-0','0-1','1/2-1/2','*')`, created_at)
  with indexes; later migrations add tournament settings, rounds management, bye player,
  enhanced game results, player management, knockout, time controls, advanced tournament
  settings, player seeding, enhanced round states, team tournaments, application settings
  (`0015`: `application_settings` with category/setting_key/JSON value/validation_schema).
- **[E]** DB access layer `src-tauri/src/db/sqlite/` (`game.rs`, `knockout.rs`, `player.rs`,
  `round.rs`, `mod.rs`) behind traits in `src-tauri/src/db/mod.rs`
  (get/create/update tournaments, settings…).
- **[I]** Numbered up/down migrations + a `result` enum CHECK is exactly the pattern for our
  event store; the CHECK constraint documents the result vocabulary at the schema level.

### Pairing
- **[E]** `src-tauri/src/modules/competition/pairing/dispatcher.rs` selects by
  `PairingMethod`: Swiss / RoundRobin / Scheveningen / Knockout.
- **[E]** Swiss: `pairing/swiss/mod.rs` (660 lines, "FIDE-compliant Swiss pairing
  implementation / Based on FIDE Handbook C.04") with score groups, float management,
  `bye_and_float.rs` (366), `color.rs` (292), `team_avoidance.rs` (219), `types.rs`;
  plus `pairing/optimizer.rs` (743) — a greedy/heuristic matcher with **weighted pairing
  scores** (`calculate_pairing_score`, `calculate_float_penalty`, `calculate_bye_bonus`,
  `calculate_standing_factor`). `validate_pairings` at `swiss/mod.rs:657` takes `&[String]`
  errors and is only partially implemented (early `_pairings` unused pattern).
- **[E]** Round-robin: `pairing/round_robin.rs` (487) — Berger table generated in code
  (`generate_berger_table`, `determine_berger_colors`), `generate_balanced_round_robin` with
  colour-balance checking, `generate_scheveningen_pairings`. Analysis services:
  `competition/service/round_robin_analysis.rs`, `swiss_analysis.rs`, `validation.rs`.
- **[I]** The heuristic optimiser (bye bonus, standing factor) is **not** C.04-exact; Pawn's
  "FIDE-compliant" claim is aspirational. Corroborates keeping bbpPairings as authority and
  writing our own override checker.

### TRF
- **[E]** **Absent.** `grep -rn "trf|TRF" src-tauri/src src` → 0 matches. Export formats are
  `enum ExportFormat { Csv, Pdf, Html, Json, Xlsx, Txt }`
  (`src-tauri/src/modules/export/model.rs:28-35`), implemented in
  `modules/export/service.rs`. No FIDE rating report, no chess-results support.

### Tiebreaks
- **[E]** `src-tauri/src/modules/standings/service/tiebreak.rs` (1,733 lines) — the most
  complete set of the four: `calculate_buchholz_full/cut1/cut2/median`,
  `calculate_sonneborn_berger`, `calculate_progressive_score`,
  `calculate_direct_encounter`, `calculate_aro`, `calculate_aro_cut1/2`,
  `calculate_performance_rating`, `calculate_tournament_performance_rating`,
  `calculate_koya_system`, `calculate_cumulative_score`, `calculate_match_points`/
  `game_points`/`board_points`, wins/wins-with-black, rating change + K-factor.
- **[E]** **Breakdowns exist**: `generate_tiebreak_breakdown` plus per-tiebreak breakdown
  functions — `generate_buchholz_breakdown`, `generate_sonneborn_berger_breakdown`,
  `generate_direct_encounter_breakdown`, `generate_aro_breakdown`, `generate_tpr_breakdown`,
  `generate_wins_breakdown` (lines ~1087–1718). Values formatted via
  `format_tiebreak_value(f64)` — float arithmetic [E]. Related services:
  `standings/service/norm.rs` (FIDE title norms) and `realtime.rs`.

### UI workflow
- **[E]** `src/pages/`: `new-tournament/`, `tournament-info/` (TournamentInfo, TournamentEdit,
  TournamentSettings), `tournaments/`, `settings/`. `src/widgets/`: `new-tournament-form`,
  `player-management` (+ hook), `results-grid` (+ hook, batch validation + audit trail per
  README), `round-manager` (+ hook, round-status utils), `standings-table`,
  `export-dialog`, `tournament-list`, `tournament-sidebar`. i18n EN/RU/UK (README).

### Test vectors worth reimplementing
- **[E]** `src/test/` suite categories (19 vitest files): `error-recovery/`
  (`crash-boundaries.test.tsx`), `database/migration-integrity.test.tsx`,
  `e2e/tournament-flow.spec.ts` and
  `e2e/complex-tournament-workflows.spec.ts` (Playwright), plus api, integration, i18n,
  accessibility, cross-browser, mobile, offline, real-time, performance, stress, security,
  validation, visual, mocks, reporting, utils, chess. No Rust `#[test]`s found in
  `src-tauri/src`.
- **[I]** Vectors/categories to adopt: a **migration-integrity** test (apply all migrations
  up, run down, re-up, assert schema identity); **crash-boundaries / error-recovery** tests
  (pairs with our "interrupt at every persistence boundary" acceptance test); an e2e
  "complex tournament workflow" script covering create → register (CSV bulk) → pair →
  enter results → standings → export.

### P1-relevant lessons
- Specta-generated typed command bindings = the strongest existing realisation of §1b's
  UI/assistant parity at command level; in Tcl, generate/verify registry action signatures
  from one source of truth [I].
- Numbered up/down SQL migrations for our SQLite event store [I].
- Per-tiebreak breakdown functions show breakdowns are tractable and best built per
  tiebreak [I].
- Licence hygiene: claim vs missing file — check licence evidence, not badges [I].

---

## 4. PonzianiSwiss

- **URL:** https://github.com/guentherc/PonzianiSwiss
- **Commit:** `ee1474c834d1b13f4726fae0c641bbacb8ad01a7` (master HEAD). Latest release 0.6
  (2026-08-01); README calls the current version **alpha**.
- **Plan correction [E]:** C#/.NET WPF (MVVM), **not Java** — see §0.

### Licence
- **[E]** README "## License: GNU GENERAL PUBLIC LICENSE Version 3". No separate licence
  file found in the tree [I from `find`]; GPLv3 per README. Bundled bbp binaries
  (`PonzianiSwissLib/bbpPairings/bbpPairings{32,64}[.exe]`) carry bbpPairings' own licence
  — relevant to our separate bbpPairings licence check [I].

### Stack / architecture
- **[E]** Solution `PonzianiSwiss.sln` with three projects: `PonzianiSwissLib` (core logic),
  `PonzianiSwiss` (WPF UI: `MainWindow.xaml`, `Round.xaml`, dialogs
  `ParticipantDialog.xaml`, `PlayerSearchDialog.xaml`, `ForbiddenPairingsDialog.xaml`,
  `AdditionalRankingDialog.xaml`, `TiebreakDialog.xaml`, `TournamentDialog.xaml`,
  `HTMLViewer.xaml`), `PonzianiSwissTest` (MSTest + FlaUI UI automation). Persistence:
  JSON save/load (`Tournament` is JSON-serialisable, `ICloneable.Clone()` round-trips via
  JSON, `Tournament.cs`). `Export.cs` produces HTML standings/cross tables/round results and
  `RatingCalculator`/`DWZEvaluation` computes German DWZ ratings.
  `FederationUtil.cs` fetches/holds the FIDE federation list.

### Data model
- **[E]** `PonzianiSwissLib/Tournament.cs`: `Tournament` (Name, City, Federation, dates, Type,
  CountPlayer/CountRatedPlayer, arbiters, TimeControl, `PairingSystem {Dutch, Burstein}`,
  `ScoringScheme`, `List<TieBreak>`, `ForbiddenPairingRules`, `AvoidPairingsFromSameFederation/
  Club`, `BakuAcceleration`, `TeamSize`, `TournamentRatingDetermination {Max,Average,
  National,Elo}`, `AdditionalRankings`). `Rating()` (Tournament.cs ~line 645) resolves FIDE vs
  alternative (national) rating per that policy.
- **[E]** `PonzianiSwissLib/Entities.cs`: `Pairing`, `Round`, `TeamScoreCard`, `Scorecard`
  with per-round `Entry` list, `ScoringScheme` (points per win/draw configurable —
  3-1-0 etc.), and the decisive piece: `Tournament.cs:56`
  `enum Result { Open, Forfeited, Loss, UnratedLoss, ZeroPointBye, PairingAllocatedBye, Draw,
  UnratedDraw, HalfPointBye, Win, UnratedWin, ForfeitWin, FullPointBye, DoubleForfeit }` —
  14 unplayed/played categories, near 1:1 with our §6 mandate.
- **[E]** Tiebreak enum `Entities.cs:323`: Score, Buchholz, BuchholzMedian, BuchholzCut1,
  RefinedBuchholz, SonnebornBerger, CountWin, CountWinWithBlack, CumulativeScore.
  Implementations on `Scorecard` (Buchholz/BuchholzMedian/BuchholzCut1, each with a
  round-parameterised variant for per-round standings; float arithmetic).
  **No breakdowns.**

### Pairing
- **[E]** Entirely delegated to bundled bbpPairings via `PonzianiSwissLib/PairingTool.cs`:
  `DrawAsync` writes TRF and runs `--dutch {input} -p` or `--burstein {input} -p`
  (lines ~95–118); board numbers assigned afterwards; pairings where black == `Participant.BYE`
  get `Result.PairingAllocatedBye`; requested byes merged as extra pairings; pairings then
  sorted by joint score (`Tournament.cs:590-610`). No round-robin (Swiss-only program).
- **[E — important for the §6 disagreement]** `PairingTool.CheckAsync` (lines ~165–190) runs
  `bbpPairings --dutch {input} -c` (or `--burstein ... -c`) and returns stdout as a
  **compliance-check report**; `GenerateTRFAsync` (lines ~120–151) runs
  `bbpPairings --{system} -g {config} -o {trfname}` with optional `-s {seed}` — a **seeded
  random-tournament generator**. `Extensions.TestTRFGeneration` (Extensions.cs:235) chains
  generate → load → re-export → `CheckAsync` on the re-export, i.e. a self-verification
  round-trip through the checker.
- **[I]** This is third-party *usage* evidence that bbpPairings exposes `-c` (check) and
  `-g/-o/-s` (generate) modes; the bbpPairings README/LICENSE themselves must still be read
  directly in our bbpPairings P0 task. If `-c` is confirmed, we may only need an
  override-logger, not a full C.04 checker.

### TRF
- **[E]** Full support: `Tournament.CreateTRF(round, official, xxc, byes, forbidden)`
  (Tournament.cs:353 — note `xxc` = the `XXC` initial-colour field and byes/forbidden
  passed as pairing-time parameters), `ExportTRF` (line 618), `ExportPGN` (line 626),
  and `Extensions.LoadFromTRF`/`LoadFromTRFAsync`/`ProcessPlayerTRF`
  (Extensions.cs:12–98). TRF round-trip tested in `TestTournament.TestLoadTRF`.

### UI workflow
- **[E]** Wizard flow per `docs/` HTML manual: `CreateaTournament.html` →
  `AddParticipants.html` (search dialog over a FIDE player base,
  `PonzianiPlayerBase/`) → `DrawandExecuteaRound.html` (`Round.xaml`) → standings/cross
  tables via HTML export (`HTMLViewer.xaml`, `Export.cs`). FlaUI-driven UI tests
  (`PonzianiSwissTest/TestUI.cs`).

### Test vectors worth reimplementing
- **[E]** `PonzianiSwissTest/TestTournament.cs`:
  - `TestLoadTRF` (line 28) loads three remote TRF samples — FIDE
    (`https://tec.fide.com/wp-content/uploads/2025/01/GrandMommysCup03_trf.txt`),
    Lichess swiss (`https://lichess.org/swiss/j8rtJ5GL.trf`), and
    `https://raw.githubusercontent.com/erral/fidetournament/master/tests/test_demo.trf`
    (lines 22–24) — real-world TRF dialects to use as import fixtures.
  - `TestScorecard` (52) with a **commented-out expected-value block** (lines 76–86:
    Score 8, Buchholz 33, BuchholzCut1 29.5, SB 30, Cumulative 27 for a specific player) —
    ready-made exact tiebreak expectations for one of the loaded files.
  - `TestDraw` / `TestGenerateTournament` (91/102): generate with a seed via
    `PairingTool.GenerateTRFAsync(seed, config)`, then **draw round after round and check**,
    extracting `XXC` from the generated file (lines 180–210) — reproducible seeded torture
    tournaments.
  - `CheckDutchDefaultScorescheme` / `CheckDutchOtherScorescheme` /
    `CheckBursteinDefaultScorescheme` / `CheckBursteinOtherScorescheme` (116–167) —
    **pairings must be invariant under the scoring scheme** (1-1-0 vs 3-1-0 etc.), a strong
    invariant test.
  - `TestDutchAccelerated` (170) — Baku acceleration round-by-round check.
- **[E]** `PonzianiSwissTest/Resources/`: `Tournament_100P_3R_ForbiddenPairings.json.txt`
  (100 players, 3 rounds, forbidden-pairing rules) and
  `Tournament_100_Participants_0_Rounds.tjson.txt` — ready scenario fixtures.
- **[I]** Vectors for us: seed-driven generated tournaments as C.04 torture input; scoring-
  scheme invariance; forbidden-pairings scenario; the three real TRF dialects (FIDE/Lichess/
  GitHub demo) as import tests.

### P1-relevant lessons
- Bundling bbpPairings binaries per platform is one packaging option; our plan pins a release
  instead [I].
- `XXC` initial-colour is a *pairing-time parameter* of `CreateTRF` here vs Chessament's
  persisted option — both designs work; persisting is safer for audit [I].
- The 14-value Result enum validates our unplayed-game category list; the round-parameterised
  tiebreak variants show how per-round standings are computed without recomputation [I].
- Rating-determination policy (Max/Average/National/Elo of FIDE vs national) belongs in event
  settings [I].

---

## 5. Cross-cutting conclusions (evidence vs inference)

Evidence-backed facts:
1. Two of the four (Chessament and PonzianiSwiss) delegate Swiss pairing to bbpPairings;
   the two that reimplement it (Gambit and Pawn) are float-based and/or heuristic, with no
   compliance verification. [E]
2. Storage split: SQLite (Chessament QtSql `db.h`; Pawn sqlx + 15 numbered migrations) vs
   JSON (Gambit, Ponziani). Only the two SQLite ones have migration machinery. [E]
3. TRF exists only in Chessament (full read/write, InitialColor option) and PonzianiSwiss
   (CreateTRF/LoadFromTRF, `XXC` parameter, checker round-trip). Both use TRF as an edge
   format, never as storage. [E]
4. Tiebreak breakdowns exist only in Pawn; every project uses floating point. [E]
5. bbpPairings `-c` and `-g/-o/-s` modes are *used in the wild* by PonzianiSwiss (secondary
   evidence). [E — usage; primary README still to be read in the bbpPairings task]
6. Typed command parity between backend and UI exists only in Pawn (specta). [E]

Inferences for P1:
- Keep bbpPairings as the single pairing authority; write our own override logger and, if
  `-c` is confirmed, lean on it rather than a full C.04 checker.
- SQLite with numbered up/down migrations matches §6's event-store decision; Pawn is the
  template, Chessament's `CREATE IF NOT EXISTS` approach is the anti-template (no migration
  history).
- Build tiebreak breakdowns per tiebreak (Pawn's structure), with exact rational arithmetic
  (nobody does this — differentiator).
- Generate/verify typed registry-action signatures from one source of truth (Pawn's specta
  pattern translated to Tcl).
- Adopt as tests: RR structural invariants (Gambit), scoring-scheme invariance + seeded
  generated tournaments + real TRF dialects (Ponziani), Buchholz edge series + TRF round-trip
  + time-control parser (Chessament), migration integrity + crash-boundaries (Pawn).
- Licence posture: all four are GPL-3.0-family (verified files) except Pawn (MIT claimed,
  no file — unresolved). With Chesswiz's GPL-2+ base, ideas-only is correct for all four;
  code reuse stays restricted to bbpPairings.

Residual identification notes: all four projects are positively identified; no unresolved
project identifications remain. The only unresolved items are (a) Pawn's missing licence
file and (b) bbpPairings' own README/LICENSE, both flagged for the separate bbpPairings P0
task.
