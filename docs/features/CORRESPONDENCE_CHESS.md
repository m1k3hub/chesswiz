# Correspondence Chess in Scidb-beta

Scidb-beta includes full support for correspondence chess games,
including ICCF (International Correspondence Chess Federation)
server integration.

## Quick Start

1. **Open a correspondence game** — any game with `TimeMode` tag set to
   `corr` is treated as a correspondence game. The live clock widget
   automatically appears below the gamebar.

2. **Enter moves** — moves are automatically timestamped with
   `[%ccsnt YYYY.MM.DD, HH:MM:SS]` (the date/time the move was sent).

3. **Manage your games** — go to **Tools → Correspondence Games...**
   to see all correspondence games in the current database.

4. **Sync with ICCF** — configure your ICCF credentials in
   **Tools → ICCF Settings...**, then use the **Sync** button in the
   correspondence games panel to fetch your games from the ICCF server.

## Features

### Live Clock Display

When a correspondence game is loaded, a clock widget appears between
the gamebar and the notation panel. It shows:

- **White's remaining time** (e.g., `28d 12h 30m`)
- **Black's remaining time** (e.g., `15d 3h 0m`)
- The side-to-move player's clock is highlighted in bold with an
  accent color and ticks down in real time

The clock reads `WhiteTimeLeft` and `BlackTimeLeft` PGN tags, which
use ISO 8601 duration format (`P28DT12H30M` = 28 days, 12 hours,
30 minutes).

### Automatic Move Timestamps

When you enter a move in a correspondence game, scidb automatically
adds a `[%ccsnt ...]` annotation with the current date and time:

```
1. e4 {[%ccsnt 2024.01.15, 14:30:00]}
```

This happens automatically — no manual action required. The timestamp
uses the format `YYYY.MM.DD, HH:MM:SS`.

### Correspondence Game Manager

**Tools → Correspondence Games...** opens a panel showing all
correspondence games in the current database:

| Column | Description |
|--------|-------------|
| # | Game number in the database |
| White | White player name |
| Black | Black player name |
| ICCF | ICCF game ID (from `ICCFGameID` tag) |
| Status | Game status (ongoing, finished, etc.) |
| White Time | White's remaining time |
| Black Time | Black's remaining time |
| Last Move | Date of the last move |
| Event | Event name |
| Result | Game result (1-0, 0-1, 1/2-1/2, *) |

**Toolbar buttons:**
- **Refresh** — reload the game list from the local database
- **Sync** — fetch games from the ICCF server
- **Open Game** — open the selected game in the editor
- **Filter** — filter by status (All / Ongoing / Finished)
- **Close** — close the panel

Double-click a game to open it in the editor.

### ICCF XFCC Server Integration

Scidb can communicate directly with the ICCF server using the XFCC
(XML-Friendly Chess Connection) protocol.

#### Setup

1. Register at [iccf.com](https://www.iccf.com)
2. In your ICCF player settings, set an **API password** (this is
   separate from your web login password)
3. In scidb-beta, go to **Tools → ICCF Settings...**
4. Enter your ICCF username and API password
5. Click OK — your credentials are saved in the options file

#### Syncing Games

1. Open **Tools → Correspondence Games...**
2. Click **Sync**
3. Scidb connects to the ICCF server, fetches your games, and
   displays them in the panel

#### Auto-Submit Moves

When you enter a move in a correspondence game that has an
`ICCFGameID` tag, scidb automatically:

1. Adds the `[%ccsnt ...]` timestamp
2. Submits the move to the ICCF server via the `MakeAMove` SOAP
   operation

If the submission fails (e.g., network error, not your turn), the
error is silently caught — your local move is not affected. Check
the ICCF website to confirm the move was received.

### PGN Format Support

Scidb supports the following correspondence-specific PGN annotations:

| Annotation | Description | Example |
|------------|-------------|---------|
| `[%ccsnt ...]` | When the move was sent | `[%ccsnt 2024.01.15, 14:30:00]` |
| `[%cclk ...]` | Remaining clock time (ISO 8601) | `[%cclk P28DT12H30M]` |
| `[%cemt ...]` | Elapsed time for this move | `[%cemt P2DT4H30M]` |

And the following PGN header tags:

| Tag | Description |
|-----|-------------|
| `TimeMode` | Set to `corr` for correspondence games |
| `TimeControl` | Auto-exported from TimeMode (e.g., `correspondence`) |
| `WhiteICCF` / `BlackICCF` | ICCF ratings |
| `WhiteTitle` / `BlackTitle` | Correspondence titles (CGM, CIM, etc.) |
| `ICCFGameID` | ICCF game identifier |
| `CorrStatus` | Game status (ongoing, finished, adjudicated, abandoned) |
| `CorrType` | Correspondence type (postal, email, server, xfcc) |
| `WhiteTimeLeft` / `BlackTimeLeft` | Remaining time (ISO 8601 duration) |

### CCG Format

Scidb also defines the **CCG** (Correspondence Chess Game) format — a
PGN superset that contains all metadata needed to resume, analyze, or
archive a correspondence game. See `CCG_FORMAT_DESIGN.md` for the
full specification.

### ICCF Numeric Notation

Scidb supports ICCF Numeric Notation as a move notation format —
select it from the notation panel options. This is the official
notation format for ICCF correspondence games.

## Technical Notes

- The ICCF XFCC client uses SOAP over HTTPS with TLS 1.8.0
- Credentials are stored in the options file with simple obfuscation
  (not encryption — your system's file permissions provide security)
- The XFCC endpoint is `https://www.iccf.com/XfccBasic.asmx`
- The XFCC protocol specification is at
  [bennedik.de/xfcc](http://www.bennedik.de/xfcc/)
- See `ICCF_XFCC_DESIGN.md` for the full integration design