# CCG — Correspondence Chess Game Format

**Status:** design (2026-08-23). A PGN superset for complete correspondence
game record-keeping. Backward-compatible with standard PGN readers.

## 0. Design goals

1. **Complete correspondence record**: per-move sent date/time, elapsed
   time, remaining time allowance, and game-level correspondence metadata.
2. **PGN-compatible**: standard PGN readers ignore the extra tags/comments.
3. **Human-readable**: a text editor can read, edit, and diff the file.
4. **Self-contained**: one `.ccg` file = one correspondence game, with all
   metadata needed to resume, analyze, or archive the game.
5. **Interoperable**: scidb's PGN reader/writer handles the format; the
   `[%ccsnt ...]` move info is already supported.
6. **No new binary format**: reuses PGN text format with extended tags.

## 1. File format

A `.ccg` file is a UTF-8 text file containing exactly one PGN game with
correspondence-specific header tags and per-move annotations. The file
extension `.ccg` (Correspondence Chess Game) is recommended; `.pgn` is
also acceptable (the content is valid PGN).

### 1.1 Header tags

All standard PGN tags are supported. The following correspondence-specific
tags are defined:

| Tag | Required | Example | Description |
|-----|----------|---------|-------------|
| `TimeControl` | Yes | `"correspondence"` or `"10/40"` or `"30/move"` | Marks this as a correspondence game. `"correspondence"` = unspecified; `"N/D"` = N moves in D days; `"D/move"` = D days per move |
| `CorrType` | No | `"server"` | Correspondence type: `"postal"`, `"email"`, `"server"`, `"xfcc"` |
| `WhiteICCF` | No | `"2580"` | ICCF rating of white player |
| `BlackICCF` | No | `"2520"` | ICCF rating of black player |
| `WhiteTitle` | No | `"CGM"` | Correspondence title (CGM, CIM, CLGM, CILM, CSIM) |
| `BlackTitle` | No | `"CIM"` | Correspondence title |
| `ICCFGameID` | No | `"1234567890"` | ICCF game identifier |
| `ICCFEvent` | No | `"World Championship Final"` | ICCF event name |
| `WhiteTimeLeft` | No | `"P28DT12H30M"` | Remaining time for white (ISO 8601 duration) |
| `BlackTimeLeft` | No | `"P15DT3H0M"` | Remaining time for black (ISO 8601 duration) |
| `CorrStatus` | No | `"ongoing"` | Game status: `"ongoing"`, `"finished"`, `"adjudicated"`, `"abandoned"` |

**ISO 8601 duration format** for time values: `P[n]DT[n]H[n]M[n]S`
- `P28DT12H30M` = 28 days, 12 hours, 30 minutes
- `P40DT0H0M0S` = 40 days exactly
- `P0DT0H0M0S` = no time remaining (flagged)

### 1.2 Per-move annotations

Each move may have the following PGN comment annotations:

| Annotation | Description | Example |
|------------|-------------|---------|
| `[%ccsnt YYYY.MM.DD, HH:MM:SS]` | When the move was sent | `[%ccsnt 2024.01.15, 14:30:00]` |
| `[%cclk P28DT12H30M]` | Remaining clock time after this move | `[%cclk P28DT12H30M]` |
| `[%cemt P2DT4H30M]` | Elapsed time for this move (time used) | `[%cemt P2DT4H30M0S]` |

**Note**: `[%ccsnt ...]` is already supported by scidb's `MoveInfo::CorrespondenceChessSent`.
`[%cclk ...]` and `[%cemt ...]` are new correspondence-specific clock annotations
that use ISO 8601 durations instead of the `HH:MM:SS` format used by real-time games.

### 1.3 Example

```
[Event "ICCF World Championship Final"]
[Site "ICCF"]
[Date "2024.01.01"]
[Round "1"]
[White "Player A"]
[Black "Player B"]
[Result "*"]
[WhiteICCF "2580"]
[BlackICCF "2520"]
[WhiteTitle "CGM"]
[BlackTitle "CIM"]
[TimeControl "10/40"]
[CorrType "server"]
[ICCFGameID "1234567890"]
[CorrStatus "ongoing"]
[WhiteTimeLeft "P38DT5H15M0S"]
[BlackTimeLeft "P34DT8H45M0S"]
[PlyCount "4"]

1. e4 {[%ccsnt 2024.01.01, 10:00:00][%cemt P0DT0H0M0S][%cclk P40DT0H0M0S]}
    e5 {[%ccsnt 2024.01.03, 14:30:00][%cemt P2DT4H30M0S][%cclk P37DT19H30M0S]}
2. Nf3 {[%ccsnt 2024.01.05, 09:15:00][%cemt P1DT18H45M0S][%cclk P38DT5H15M0S]}
    Nc6 {[%ccsnt 2024.01.08, 20:00:00][%cemt P3DT10H45M0S][%cclk P34DT8H45M0S]} *
```

## 2. Implementation in scidb

### 2.1 What scidb already supports

- ✅ `[%ccsnt YYYY.MM.DD, HH:MM:SS]` — `MoveInfo::CorrespondenceChessSent`
  (parsed by `parseCorrespondenceChessSent`, printed by `MoveInfo::print`,
  encoded/decoded in SCI binary format)
- ✅ `WhiteICCF` / `BlackICCF` — ICCF ratings in the tag set
- ✅ `WhiteTitle` / `BlackTitle` — including correspondence titles (CGM, CIM, etc.)
- ✅ `TimeControl` tag — read by PGN reader, sets `time::Corr`
- ✅ `TimeMode` tag — scidb-specific, written by PGN writer
- ✅ ICCF player IDs — stored in namebase
- ✅ ICCF ratings — stored in rating system
- ✅ Correspondence game type — `Correspondence_Chess` database type
- ✅ `hasCorrHeader` flag — CBH correspondence header
- ✅ ICCF Numeric Notation — output format

### 2.2 What this design adds

1. **New PGN tags**: `CorrType`, `ICCFGameID`, `ICCFEvent`, `WhiteTimeLeft`,
   `BlackTimeLeft`, `CorrStatus` — stored as extra tags in the tag set
2. **New move annotations**: `[%cclk ...]` and `[%cemt ...]` — correspondence
   clock and elapsed time using ISO 8601 durations
3. **TimeControl values**: `"10/40"` (N moves in D days) and `"30/move"`
   (D days per move) — parsed to determine the correspondence time control
4. **PGN writer**: outputs all correspondence tags when the game is a
   correspondence game (time mode = `Corr`)
5. **Clock extension**: the `Clock` class needs to support days (currently
   limited to 23 hours via `uint8_t m_hour`)

### 2.3 Clock class extension

The current `Clock` class uses `uint8_t` for hours (max 255, but parse
limits to 23). For correspondence, we need to represent durations of
up to 40+ days.

**Option A**: Add a `uint16_t m_day` field to `Clock` (breaking change
to the binary format).

**Option B**: Use a separate `CorrClock` class for correspondence time
that stores days separately. This avoids changing the existing `Clock`
class and its binary encoding.

**Recommended**: Option B — `CorrClock` as a separate class, used only
for `[%cclk ...]` and `[%cemt ...]` annotations. The existing `Clock`
class and `CorrespondenceChessSent` (which stores time-of-day, not
duration) remain unchanged.

### 2.4 Tag storage

The new tags (`CorrType`, `ICCFGameID`, `ICCFEvent`, `WhiteTimeLeft`,
`BlackTimeLeft`, `CorrStatus`) are stored as **extra tags** in the
`TagSet`. This is the existing mechanism for non-standard PGN tags —
no changes to the tag enum are needed.

The PGN reader already stores unknown tags as extra tags. The PGN
writer outputs extra tags in the default case of the tag loop. So
these tags will be automatically imported and exported without code
changes to the tag handling.

### 2.5 Move annotation storage

`[%cclk ...]` and `[%cemt ...]` need new `MoveInfo` types or extension
of existing types:

- `[%cclk P28DT12H30M]` — a new `CorrespondenceClock` move info type
  (remaining time after the move)
- `[%cemt P2DT4H30M]` — reuse `ElapsedMoveTime` with day support, or
  a new `CorrespondenceElapsed` type

**Recommended**: Add two new `MoveInfo::Type` values:
- `CorrespondenceClock` — remaining time (ISO 8601 duration)
- `CorrespondenceElapsed` — elapsed time for this move (ISO 8601 duration)

These use the `CorrClock` class (days + hours + minutes + seconds) and
are encoded/decoded in the SCI binary format alongside existing move
info types.

### 2.6 PGN writer changes

When the time mode is `Corr`:
1. Output `TimeControl` with the correspondence value (e.g., `"10/40"`)
2. Output `CorrType`, `ICCFGameID`, `ICCFEvent` if present (extra tags)
3. Output `WhiteTimeLeft`, `BlackTimeLeft` if present (extra tags)
4. Output `WhiteICCF`, `BlackICCF` (already fixed in this session)
5. Output `CorrStatus` if present (extra tags)
6. Output `[%ccsnt ...]`, `[%cclk ...]`, `[%cemt ...]` per move

### 2.7 PGN reader changes

1. Parse `CorrType`, `ICCFGameID`, `ICCFEvent`, `WhiteTimeLeft`,
   `BlackTimeLeft`, `CorrStatus` as extra tags (already handled)
2. Parse `[%cclk P28DT12H30M]` — new move info parser
3. Parse `[%cemt P2DT4H30M]` — new move info parser
4. Parse `TimeControl` values `"10/40"` and `"30/move"` — already
   handled by `getTimeModeFromTimeControl` (sets `time::Corr`)

## 3. Comparison with existing formats

| Feature | Standard PGN | ChessBase CBH | CCG (this design) |
|---------|-------------|---------------|-------------------|
| Per-move sent date | `[%ccsnt ...]` | `.cba` binary | `[%ccsnt ...]` |
| Per-move clock | `[%clk HH:MM:SS]` | N/A | `[%cclk P28DT12H30M]` |
| Per-move elapsed | `[%emt HH:MM:SS]` | N/A | `[%cemt P2DT4H30M]` |
| ICCF ratings | `WhiteICCF` tag | Namebase | `WhiteICCF` tag |
| ICCF game ID | `ICCFGameID` tag | N/A | `ICCFGameID` tag |
| Time allowance | `TimeControl` tag | `time::Corr` | `TimeControl "10/40"` |
| Game status | `Result` tag | N/A | `CorrStatus` tag |
| Days support | No (HH:MM:SS) | No | Yes (ISO 8601) |
| Human-readable | Yes | No | Yes |
| Backward-compatible | N/A | No | Yes (standard PGN readers ignore extra tags) |

## 4. File naming convention

- `.ccg` — Correspondence Chess Game (recommended)
- `.pgn` — also valid (content is standard PGN with extra tags)

A `.ccg` file contains exactly one game. For multi-game collections,
use `.pgn` with multiple games.