# Changelog

## Unreleased — ChessBase (.cbh) Per-Game Media via tag_game Anchors

### Overview

`::scidb::db::mediaFiles` now maps a REGULAR game of a ChessBase `.cbh`
database onto its tournament report's media, closing the last open row of
the CBM capability table (CBM_FORMAT_DESIGN.md §7.7).

### Details
- Reports (guiding-text entries) anchor games in their HTML bodies via
  `CBLink(tag_game,White,Black,Event,Site,Year,Round,…)`; anchors match
  game headers on (lastname, lastname, event-key, year, round) — fixture:
  Topalov–Anand/Bilbao 2008 r4 = game 12038, exact match
- Guiding-text CBH index records carry no usable tournament reference
  ("? (illegal reference)" for all 11 reports) — the anchors are the only
  per-game route (so the CBH event table cannot link them)
- Media association = section ownership: each reference belongs to the
  game of the last anchor at-or-before it (report-header art lands on the
  first anchored game — documented approximation)
- New: `tcl_media::scanGuidingTextMediaRefs/extractGuidingTextMediaRange/
  extractGuidingTextGameBlocks` + `GuidingTextLinkCache` in `cmdMediaFiles`
- `tcl_media_extract` unit tests extended to 577 structural checks
- E2E (CB Light Database): 35 games carry media (10 reports + 25 mapped),
  125 refs, all mapped pictures on disc; probe-gamemap + run-e2e PASS
- `src/probe_cbllight` extended: event semantics, per-report block counts,
  cache simulator (dev tool)

## Unreleased — ChessBase 17+ (2CBH) Move Decoding

### Overview

The ChessBase 17+ `.2cbg` move encoding (used by Mega Database 2026,
Corr Database 2024 and LumbrasGigaBase) is fully reverse engineered and
decoded in scidb.  Full `cb2::Codec` integration is the next step.

### Details
- The move data is plaintext 16-bit "Move16" codes (not encrypted)
- The runtime-built ChessBase decode table was extracted from a live
  CBase26 process under Wine, packed and embedded in `src/db/2cbh/`
- Validated on 200,000 games of the LumbrasGigaBase fixture: 100% of
  mainlines decode, replay legally, and carry the correct player names
  (the .2lid namebase mapping: player ID == namebase slot ordinal)
- The game result decoded: index byte 0x58 low 2 bits (0 = 0-1,
  1 = draw, 2 = 1-0), validated on 2,748 games with zero mismatches
- `2cbh2pgn` converts complete databases to PGN (names included)
- Standalone validation tool `2cbh_probe`; reproducible table-dump
  script in `scripts/`
- See `2CBH_FORMAT_DESIGN.md` section 3.8

## Unreleased — Correspondence Chess Support

### Overview

Full correspondence chess support added to scidb-beta, including live
clock display, automatic move timestamps, a game manager panel, and
ICCF XFCC server integration.

### Features

#### Correspondence Clock Widget
- Live countdown display showing remaining time as `28d 12h 30m`
- Parses `WhiteTimeLeft` / `BlackTimeLeft` PGN tags (ISO 8601 durations)
- Side-to-move player's clock ticks down in real time
- Active player highlighted with bold font and accent color
- Auto-shows in the gamebar area when a correspondence game is loaded
- Auto-hides for non-correspondence games

#### Automatic ccsnt Timestamps
- When a move is entered in a correspondence game (TimeMode = `corr`),
  the move is automatically stamped with `[%ccsnt YYYY.MM.DD, HH:MM:SS]`
- New C++ Tcl subcommand: `::scidb::game::update moveinfo <key> <type> <value>`
  supports `ccsnt`, `cclk`, and `cemt` move info types
- New `Game::addMoveInfo()` C++ method with full undo tracking

#### Correspondence Game Manager Panel
- Accessible via **Tools → Correspondence Games...**
- Lists all correspondence games from the current database
- 10 columns: #, White, Black, ICCF ID, Status, White Time, Black Time,
  Last Move, Event, Result
- Filter by status (All / Ongoing / Finished)
- Detail area shows ICCF ID, status, and remaining time for selected game
- Double-click to open a game in the editor

#### ICCF XFCC Server Integration
- Full SOAP client for the ICCF XFCC Basic web service
- Endpoint: `https://www.iccf.com/XfccBasic.asmx`
- Operations: `GetMyGames`, `MakeAMove`, `MakeAMove2`
- **Tools → ICCF Settings...** — configure username and password
- **Sync** button in the game manager — fetches games from ICCF server
- **Auto-submit** — when a move is entered in a game with an `ICCFGameID`
  tag, the move is automatically submitted to the ICCF server
- Credentials stored in the options file with simple obfuscation
- TLS 1.8.0 required (auto-loaded from system package paths)

#### PGN Format Support
- `[%cclk P28DT12H30M]` — correspondence clock (remaining time)
- `[%cemt P2DT4H30M]` — correspondence elapsed move time
- `[%ccsnt 2024.01.15, 14:30:00]` — correspondence chess sent timestamp
  (pre-existing, now with auto-timestamping)
- `TimeControl` tag auto-exported from `TimeMode` for PGN compatibility
- ICCF ratings (`WhiteICCF` / `BlackICCF`) always exported alongside Elo
- Move info display menu includes cclk and cemt (enabled by default)

#### CCG Format Design
- `CCG_FORMAT_DESIGN.md` — design spec for `.ccg` (Correspondence Chess
  Game) files, a PGN superset with complete correspondence metadata

### Technical Details

- **C++ changes**: `MoveInfo` class extended with `CorrespondenceClock`
  and `CorrespondenceElapsed` types, `CorrDuration` struct
  (days+hours+minutes+seconds), ISO 8601 duration parser, PGN printer
  with proper `[%cclk]` / `[%cemt]` annotation format
- **Tcl changes**: 4 new Tcl files (`corrclock.tcl`, `app-corr-games.tcl`,
  `iccf-xfcc.tcl`, `test_corr_moveinfo.cpp`), modifications to `move.tcl`,
  `app-pgn.tcl`, `menu.tcl`, `pgn-setup.tcl`, `app-database.tcl`
- **Build**: 3 new files registered in `tcl/Makefile` SOURCES list
- **Tests**: 29 C++ unit tests (parsing, printing, roundtrip),
  111 Tcl tests, 335 Python tests, 220 frontend tests — all pass

### Files Added

| File | Lines | Description |
|------|-------|-------------|
| `tcl/widgets/corrclock.tcl` | 307 | Live correspondence clock widget |
| `tcl/app-corr-games.tcl` | 417 | Game manager panel |
| `tcl/iccf-xfcc.tcl` | 560 | ICCF XFCC SOAP client |
| `src/test_corr_moveinfo.cpp` | 130 | C++ unit test for MoveInfo parsing |
| `CCG_FORMAT_DESIGN.md` | 210 | CCG format specification |
| `ICCF_XFCC_DESIGN.md` | 210 | XFCC integration design document |

### Files Modified

| File | Description |
|------|-------------|
| `src/db/db_move_info.h` | `CorrespondenceClock`/`Elapsed` types, `CorrDuration` struct, public accessor |
| `src/db/db_move_info.cpp` | ISO 8601 parser, PGN printer (fixed double-`]` bug), encode/decode |
| `src/db/db_move_info_set.cpp` | `[%cclk]` / `[%cemt]` extraction from PGN comments |
| `src/db/db_game.h` | `addMoveInfo()` method, `AddMoveInfo` undo command |
| `src/db/db_game.cpp` | `addMoveInfo()` implementation with undo tracking |
| `src/db/db_writer.cpp` | `TimeControl` auto-export, ICCF rating export |
| `src/db/db_common.h` | `moveinfo::CorrClock` / `CorrElapsed` flags |
| `src/tcl/tcl_game.cpp` | `moveinfo` subcommand, `getMoveInfoTypes` cclk/cemt, `AddMoveInfo` toString |
| `tcl/move.tcl` | Auto-ccsnt timestamp + auto-submit to ICCF |
| `tcl/app-pgn.tcl` | Corrclock widget in gamebar, `UpdateCorrClock` proc |
| `tcl/menu.tcl` | Tools menu entries for corr games and ICCF settings |
| `tcl/pgn-setup.tcl` | cclk/cemt in ShowMoveInfo defaults |
| `tcl/app-database.tcl` | corrClock/corrElapsed in move info display |
| `tcl/Makefile` | 3 new source files in SOURCES list |

### Getting Started with ICCF Integration

1. Register at [iccf.com](https://www.iccf.com) if you haven't already
2. In your ICCF player settings, set an API password (separate from your
   web login password)
3. In scidb-beta, go to **Tools → ICCF Settings...**
4. Enter your ICCF username and API password
5. Go to **Tools → Correspondence Games...**
6. Click **Sync** to fetch your games from the ICCF server
7. Open a game, make a move — it will be auto-timestamped and
   auto-submitted to the ICCF server