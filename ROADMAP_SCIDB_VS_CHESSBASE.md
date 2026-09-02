# SCIDb Feature Gap Roadmap

This document turns the current SCIDb vs. ChessBase gap analysis into an implementation roadmap for this repository.

It is intentionally pragmatic:
- focus first on features that change daily usability
- avoid trying to clone all of ChessBase
- keep SCIDb a strong database application rather than a cloud-service clone

## Working Format Strategy

SCIDb should treat `.sci` as the primary working format for large databases and repeated analysis.

- optimize heavy workflows for `.sci`: maintenance, reports, prep, search, and compaction
- treat `.si4`, `.si3`, ChessBase, and large PGN files primarily as import or source formats
- prefer direct conversion/export to `.sci` instead of chasing equal performance on every legacy backend
- make the UI explicit about this with direct `Convert to .sci` entry points and performance recommendations before slow workflows


## Priorities

## Current Progress Snapshot

- `P1` is well underway:
  - unified advanced search is implemented
  - material and rating search are implemented as dedicated workflows
  - advanced search name fields now support wildcard matching
  - filtered search results can be materialized into the switcher
  - filtered result sets can be saved as named working sets
  - move-level opening prep is implemented
  - opening prep can materialize selected ECOs into the switcher or save them as working sets
- `P2` has started:
  - opening database types are first-class in the UI
  - current game and current line can be added to repertoire databases
  - repertoire report exists with ECO drill-down and switcher handoff
  - player prep report exists and can hand off to repertoire tools
  - player prep now compares open repertoire databases against opponent top ECOs and surfaces gaps
- `P3` has started:
  - ECO statistics can already use multiple workers
  - duplicate detection now uses safe per-thread async readers on async-capable database formats
  - player prep / dossier statistics now use multicore full-database scans
  - a headless workflow benchmark now measures open/search/prep/tree scans on real databases
  - a headless conversion benchmark harness exists for `.sci` workflow measurements
- `P4` has started:
  - command-line converters now emit per-source import summaries with format/range and warning/error counts
  - the headless conversion benchmark now reopens output databases and sample-checks per-game checksums for database imports
  - native HTML support is implemented end to end (read/render/publish): safe HTML intake via the sanitizer in `src/html`, a built-in report viewer on the bundled HTML widget (ChessBase magazine reports with navigation, diagrams, video stills; clickable game and media links), and standalone HTML publishing from the export dialog (whole views or single games) with tag tables, variations, language-selected comments, and inline-SVG diagrams; HTML documents can also be opened directly (File > Open > HTML documents)
  - ChessBase media is surfaced in the UI: `.cbm` manifests feed the media gallery, the redesigned media panel groups pictures/audio/video/reports with embedded playback, and board-synced playback (Chess Media System semantics) plus interactive `.cms` lessons are wired to the board
  - the HTML corpus gate (`tests/corpus_html_export.tcl`) passes on the full CBM168 magazine set (27/27), and the user-facing help pages (Welcome, What's New, Development Roadmap) reflect the current capabilities
- `P5` has started:
  - player cards and crosstables can now hand off directly into the player prep report workflow
  - crosstable player rows can now export a player's games to the switcher or a working set
  - maintenance duplicate reports can now open selected duplicate games directly for review
  - maintenance opening summaries can now open selected ECO result sets in the switcher or save them as working sets
  - event and site index popups can now open their game sets in the switcher or save them as working sets
  - annotator and position index popups can now export their current result sets to the switcher or a working set
- `.sci`-first workflow guidance is implemented in the UI for heavy analysis paths
- maintenance, compaction, duplicate detection, and `.sci` conversion safety have already been strengthened

### P1: Search And Opening Prep

Goal: make SCIDb competitive for the core database-preparation loop.

Scope:
- richer search criteria
- stronger opening reference workflows
- better drill-down from report -> move tree -> games

Planned features:
- advanced search dialog with material/endgame and richer position-pattern criteria
- stronger move-level opening report, not just ECO buckets
- novelty or low-frequency move surfacing in the tree/reference workflow
- saved search presets for recurring prep tasks

Implemented so far:
- advanced search dialog with combined player/event/site/annotator/position/material/rating criteria
- wildcard-capable matching for player, event, site, and annotator name fields
- material search dialog and rating search dialog
- switcher promotion for filtered result sets
- named working-set save path for search/report result sets
- move-level opening prep report driven by the current position
- selected ECO handoff from opening prep into the switcher or a saved working set

Likely files:
- [src/db/db_selector.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_selector.cpp)
- [src/db/db_tree.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_tree.cpp)
- [src/db/db_tree_info.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_tree_info.cpp)
- [src/tcl/tcl_view.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/tcl/tcl_view.cpp)
- [src/tcl/tcl_database.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/tcl/tcl_database.cpp)
- [src/tcl/tcl_tree.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/tcl/tcl_tree.cpp)
- [tcl/app-db-games.tcl](/home/michael-g-thomas/src/chess/scidb-code.codex/tcl/app-db-games.tcl)
- [tcl/app-tree.tcl](/home/michael-g-thomas/src/chess/scidb-code.codex/tcl/app-tree.tcl)
- [tcl/app-tree-games.tcl](/home/michael-g-thomas/src/chess/scidb-code.codex/tcl/app-tree-games.tcl)

Risk:
- medium

Why first:
- this is the biggest practical gap in everyday use
- it benefits every serious user, not only edge cases

Test strategy:
- add headless search fixtures where possible
- build small sample DBs for material and position-pattern cases
- manual GUI verification of search -> result list -> tree drill-down


### P2: Repertoire And Opponent Prep

Goal: add the strongest missing preparation workflows without changing SCIDb’s core identity.

Scope:
- repertoire databases
- add-to-repertoire actions
- opponent prep and player tendency reports

Planned features:
- repertoire database flag/type
- add current game/line to repertoire from board/game contexts
- opponent dossier window
- white/black opening tendency summaries by player
- recent-game and preferred-line prep summaries

Implemented so far:
- quick retagging of databases as `Openings`, `Openings White`, or `Openings Black`
- `Add Current Game to Repertoire`
- `Add Current Line to Repertoire`
- repertoire report with ECO coverage, recent games, ECO filtering, and switcher handoff
- first opponent prep report with top openings, recent games, repertoire shortcuts, overlap counts, and gap surfacing

Likely files:
- [src/db/db_database.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_database.cpp)
- [src/db/db_database.h](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_database.h)
- [src/db/db_player.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_player.cpp)
- [src/db/db_player_stats.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_player_stats.cpp)
- [src/tcl/tcl_database.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/tcl/tcl_database.cpp)
- [src/tcl/tcl_player.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/tcl/tcl_player.cpp)
- [tcl/app-database.tcl](/home/michael-g-thomas/src/chess/scidb-code.codex/tcl/app-database.tcl)
- [tcl/game.tcl](/home/michael-g-thomas/src/chess/scidb-code.codex/tcl/game.tcl)
- [tcl/player-card.tcl](/home/michael-g-thomas/src/chess/scidb-code.codex/tcl/player-card.tcl)
- [tcl/player-dict.tcl](/home/michael-g-thomas/src/chess/scidb-code.codex/tcl/player-dict.tcl)

Risk:
- medium-high

Why second:
- this is one of the clearest ChessBase advantages
- it builds directly on P1’s stronger search and opening data

Test strategy:
- fixture DBs with known player repertoires
- report validation for color/result splits
- manual add-to-repertoire and reopen persistence checks


### P3: Performance On Large Databases

Goal: reduce the “ChessBase feels faster on huge databases” gap.

Scope:
- parallel full-database scans
- safer async-reader-based concurrency
- better caching and open-time behavior

Planned features:
- parallel duplicate detection using per-thread async readers
- more multicore scan paths beyond ECO stats
- startup/open/search benchmarks
- targeted improvements in tree and index caching

Implemented so far:
- parallel ECO statistics
- parallel duplicate detection using per-thread async readers where the codec supports them
- parallel player-prep statistics over full-database scans
- headless workflow benchmark for open/search/prep/tree timing
- headless conversion benchmark harness for `.sci` workflows

Likely files:
- [src/db/db_maintenance.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_maintenance.cpp)
- [src/db/db_tree_cache.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_tree_cache.cpp)
- [src/db/db_database.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_database.cpp)
- [src/db/sci/sci_codec.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/sci/sci_codec.cpp)
- [src/sys/sys_thread.h](/home/michael-g-thomas/src/chess/scidb-code.codex/src/sys/sys_thread.h)
- [src/app/app_move_list_thread.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/app/app_move_list_thread.cpp)

Risk:
- high

Why third:
- performance matters once the right workflows exist
- the repo now has a good starting point for maintenance parallelism

Test strategy:
- add benchmark harnesses with generated DB sizes
- ensure all parallel scan outputs are bit-for-bit identical to serial results
- keep headless verifier coverage for maintenance operations


### P4: Format Compatibility And Import/Export

Goal: reduce interoperability friction for users living in mixed ecosystems.

Scope:
- stronger ChessBase compatibility
- better metadata preservation
- more confidence in import/export paths

Planned features:
- compatibility corpus for newer ChessBase databases
- safer import path and better diagnostics
- improved export fidelity and metadata preservation

Implemented so far:
- safer command-line import summaries for `cdb2sci` and `cbh2si4`
- stronger headless verification in the conversion benchmark for database-to-`.sci` runs
- ChessBase media manifests (`.cbm`) parsed and surfaced in the media gallery; media folders of a release resolve across sibling sections
- interactive lesson indexes (`.cms`) decoded enough to drive position-keyed playback
- the native HTML stack (read/render/publish) is complete for the profile documented in `SCIDB_HTML_PROFILE.md`; the export path passes the CBM168 corpus gate
- single-game PDF/TeX export: the print-game game-window accessor bug (uninitialized entry) is FIXED in printGame; the PdfWriter foundation (format::Pdf, page flow, printPdf commands) is landed — remaining: the writer's font-loading model (empty-message exception at construction) and the layout completion before the export dialog exposes PDF; TeX export needs the TeXt print script

Likely files:
- [src/db/db_database_codec.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_database_codec.cpp)
- [src/db/cbh](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/cbh)
- [src/db/cbf](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/cbf)
- [src/app/app_chessbase_book.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/app/app_chessbase_book.cpp)
- [src/db/db_pgn_writer.h](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_pgn_writer.h)
- [src/db/db_html_writer.h](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_html_writer.h)
- [src/db/db_pdf_writer.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_pdf_writer.cpp)
- [tcl/export.tcl](/home/michael-g-thomas/src/chess/scidb-code.codex/tcl/export.tcl)

Risk:
- high

Why fourth:
- strategically important, but less differentiating than prep workflows

Test strategy:
- maintain sample import corpus
- reopen and roundtrip tests
- explicit regression tests for variant-sensitive imports


### P5: Database Browser Completeness

Goal: make SCIDb feel more complete as a database workstation.

Scope:
- broader first-class indexes
- richer reports
- stronger pane-to-pane navigation

Planned features:
- add first-class or pseudo-index support for teams and sources where feasible
- richer report panes for players, events, sites, openings, maintenance
- better cross-links from indexes to game lists and from reports to games

Likely files:
- [src/db/db_namebases.h](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_namebases.h)
- [src/db/db_game_info.h](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_game_info.h)
- [src/tcl/tcl_database.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/tcl/tcl_database.cpp)
- [tcl/app-db-players.tcl](/home/michael-g-thomas/src/chess/scidb-code.codex/tcl/app-db-players.tcl)
- [tcl/app-db-events.tcl](/home/michael-g-thomas/src/chess/scidb-code.codex/tcl/app-db-events.tcl)
- [tcl/app-db-sites.tcl](/home/michael-g-thomas/src/chess/scidb-code.codex/tcl/app-db-sites.tcl)
- [tcl/app-db-annotators.tcl](/home/michael-g-thomas/src/chess/scidb-code.codex/tcl/app-db-annotators.tcl)

Risk:
- medium

Why fifth:
- useful, but not as decisive as search/prep/performance

Test strategy:
- GUI navigation checks
- index consistency after import, delete, compact, and sort operations


### P6: Analysis Integration

Goal: improve engine-assisted prep without drifting into training-suite or cloud-product territory.

Scope:
- tighter analysis-to-database loop
- better actions from tree/report/board views

Planned features:
- analyze this line / novelty / report row
- pin analysis candidates into repertoire workflow
- smoother analysis and tree interaction

Likely files:
- [tcl/app-analysis.tcl](/home/michael-g-thomas/src/chess/scidb-code.codex/tcl/app-analysis.tcl)
- [src/tcl/tcl_engine.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/tcl/tcl_engine.cpp)
- [src/app/app_uci_engine.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/app/app_uci_engine.cpp)
- [src/app/app_winboard_engine.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/app/app_winboard_engine.cpp)
- [tcl/app-tree.tcl](/home/michael-g-thomas/src/chess/scidb-code.codex/tcl/app-tree.tcl)
- [tcl/game.tcl](/home/michael-g-thomas/src/chess/scidb-code.codex/tcl/game.tcl)

Risk:
- medium

Why sixth:
- important, but it should build on the stronger prep pipeline above

Test strategy:
- manual engine-loop verification
- regression tests for analysis panes where possible


## Recommended Order

1. P1: Search And Opening Prep
2. P2: Repertoire And Opponent Prep
3. P3: Performance On Large Databases
4. P4: Format Compatibility And Import/Export
5. P5: Database Browser Completeness
6. P6: Analysis Integration


## Immediate Backlog

These are the first concrete implementation targets worth starting now.

### B1: Advanced Search / Material Search

Target:
- add material and richer position criteria to search/filter workflows

Depends on:
- existing search/view infrastructure only

Good first files:
- [src/db/db_selector.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_selector.cpp)
- [src/tcl/tcl_view.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/tcl/tcl_view.cpp)
- [tcl/app-db-games.tcl](/home/michael-g-thomas/src/chess/scidb-code.codex/tcl/app-db-games.tcl)


### B2: Move-Level Opening Report

Target:
- upgrade opening report from ECO totals to tree-backed report with actionable rows

Depends on:
- tree/reference code

Good first files:
- [src/db/db_tree.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_tree.cpp)
- [src/tcl/tcl_tree.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/tcl/tcl_tree.cpp)
- [tcl/app-tree.tcl](/home/michael-g-thomas/src/chess/scidb-code.codex/tcl/app-tree.tcl)


### B3: Repertoire Database Flag And Add-To-Repertoire

Target:
- first-class repertoire DB support

Depends on:
- B2 is helpful but not strictly required

Good first files:
- [src/db/db_database.h](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_database.h)
- [src/db/db_database.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_database.cpp)
- [src/tcl/tcl_database.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/tcl/tcl_database.cpp)
- [tcl/game.tcl](/home/michael-g-thomas/src/chess/scidb-code.codex/tcl/game.tcl)


### B4: Opponent Prep Report

Target:
- player dossier / opening tendencies / recent games prep view

Depends on:
- existing player stats and indexes

Good first files:
- [src/db/db_player.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_player.cpp)
- [src/db/db_player_stats.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_player_stats.cpp)
- [tcl/player-card.tcl](/home/michael-g-thomas/src/chess/scidb-code.codex/tcl/player-card.tcl)


### B5: Parallel Duplicate Detection

Target:
- safe multicore duplicate scan using per-thread async readers

Depends on:
- current maintenance framework

Good first files:
- [src/db/db_maintenance.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_maintenance.cpp)
- [src/db/db_database.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/db_database.cpp)
- [src/db/sci/sci_codec.cpp](/home/michael-g-thomas/src/chess/scidb-code.codex/src/db/sci/sci_codec.cpp)

Status:
- implemented


## Not Recommended As Near-Term Goals

- cloud engine parity
- cloud database hosting/sync
- Lichess / Chess.com parity
- full training-suite parity
- broad “ChessBase clone” goals with no scoped workflow target

These features are expensive, service-heavy, and misaligned with SCIDb’s stated scope unless the project direction changes.
