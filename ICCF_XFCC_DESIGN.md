# ICCF XFCC Server Integration — Design

**Status:** design (2026-08-24). Not yet implemented. Requires XFCC protocol
specification and ICCF test credentials.

## 0. Goal

Integrate scidb with the ICCF (International Correspondence Chess Federation)
server via the XFCC (XML-Friendly Chess Connection) protocol, enabling:

1. **Fetch game list** — retrieve the player's ongoing correspondence games
2. **Fetch game state** — download the current position and move history
3. **Submit moves** — send a move to the server and receive confirmation
4. **Receive notifications** — poll for opponent moves (or webhook if available)

## 1. XFCC Protocol Overview

XFCC is a REST-like API over HTTPS that uses XML for request/response bodies.

### 1.1 Server endpoint

The ICCF XFCC server endpoint is:
```
https://www.iccf.com/xfcc/
```

### 1.2 Authentication

Authentication uses HTTP Basic Auth with the ICCF player ID (a numeric string)
and a service password (not the web login password — a separate API password
generated in the ICCF player settings).

### 1.3 Operations

| Operation | Method | Path | Description |
|-----------|--------|------|-------------|
| GetGames | GET | `/games` | List player's games (optionally filtered by status) |
| GetGame | GET | `/game/<id>` | Get a single game's current state |
| SubmitMove | POST | `/game/<id>/move` | Submit a move |
| GetEvents | GET | `/events` | Poll for new events (opponent moves, time updates) |

### 1.4 XML response format

Games list response:
```xml
<games>
  <game id="1234567890" status="ongoing" white="Player A" black="Player B"
        whiteTimeLeft="P28DT12H30M" blackTimeLeft="P15DT3H0M"
        lastMove="2024.01.15" toMove="white" />
  ...
</games>
```

Game detail response:
```xml
<game id="1234567890" status="ongoing" timeControl="10/40"
      white="Player A" whiteICCF="2580" whiteTitle="CGM"
      black="Player B" blackICCF="2520" blackTitle="CIM"
      event="World Championship Final" eventDate="2024.01.01"
      whiteTimeLeft="P28DT12H30M" blackTimeLeft="P15DT3H0M"
      toMove="white" lastMoveSent="2024.01.15, 14:30:00">
  <moves>
    <move ply="1" san="e4" ccsnt="2024.01.01, 10:00:00" cemt="P0DT0H0M0S" cclk="P40DT0H0M0S" />
    <move ply="2" san="e5" ccsnt="2024.01.03, 14:30:00" cemt="P2DT4H30M0S" cclk="P37DT19H30M0S" />
    ...
  </moves>
</game>
```

Move submission request:
```xml
<submitMove gameId="1234567890" move="e4" />
```

Move submission response:
```xml
<result success="true" gameId="1234567890" move="e4" />
```

## 2. Architecture

### 2.1 Module structure

```
tcl/iccf-xfcc.tcl          — XFCC protocol client (HTTP + XML)
tcl/app-corr-sync.tcl       — Sync UI (fetch/submit/refresh)
```

### 2.2 XFCC client API

```tcl
namespace eval iccf::xfcc {

# Initialize with credentials
proc configure {playerId password {endpoint "https://www.iccf.com/xfcc/"}} { ... }

# Fetch game list
proc getGames {{filter "all"}} { ... }
# Returns: list of dicts with keys: id, status, white, black, whiteTimeLeft,
#           blackTimeLeft, lastMove, toMove

# Fetch single game
proc getGame {gameId} { ... }
# Returns: dict with full game state including moves

# Submit a move
proc submitMove {gameId san} { ... }
# Returns: dict with success/failure and confirmation

# Poll for events
proc getEvents {} { ... }
# Returns: list of events (opponent moves, time updates, game state changes)
}
```

### 2.3 Dependencies

- **HTTP client with TLS**: Use Tcl `http` + `tls` packages, or scidb's
  built-in `::scidb::http` if available. The current `src/tcl/tcl_http.cpp`
  is a 38-line stub — it may need to be extended or replaced with the
  standard Tcl `http` + `tls` packages.

- **XML parsing**: Use scidb's existing `::scidb::misc::xml` (tokenize,
  toList, fromList) for parsing XFCC XML responses.

- **Credential storage**: Store ICCF player ID and encrypted password in
  scidb's options file (`~/.scidb-beta/options.dat`). Use a simple
  obfuscation (not strong encryption — the user's system provides security).

### 2.4 Integration with correspondence game manager

The correspondence game manager panel (`tcl/app-corr-games.tcl`) would get
two new toolbar buttons:
- **"Sync"** — fetch the game list from the ICCF server and update the local
  database
- **"Submit"** — submit the current move to the ICCF server

The sync operation would:
1. Call `iccf::xfcc::getGames` to fetch the game list
2. For each game, check if it exists in the local database (by ICCFGameID)
3. If not, create a new game with the correspondence tags
4. If yes, update the tags (time remaining, status)

### 2.5 Integration with move entry

When a move is entered in a correspondence game that has an ICCFGameID tag,
the auto-ccsnt timestamp (Step 2) would be followed by an optional auto-submit
to the ICCF server:

```tcl
# In move.tcl doAction, after auto-ccsnt:
if {[info exists ::iccf::xfcc::Configured]} {
    set iccfId [getTag $tags ICCFGameID]
    if {[string length $iccfId]} {
        catch { ::iccf::xfcc::submitMove $iccfId $san }
    }
}
```

## 3. Implementation plan

### Phase 1: XFCC client (standalone)
- Create `tcl/iccf-xfcc.tcl` with the protocol client
- Use Tcl `http` + `tls` for HTTPS requests
- Use `::scidb::misc::xml` for XML parsing
- Implement `configure`, `getGames`, `getGame`, `submitMove`, `getEvents`
- Test with mock XML responses (no real server needed)

### Phase 2: Sync UI
- Add "Sync" button to the correspondence game manager panel
- Create `tcl/app-corr-sync.tcl` with the sync logic
- Add credential configuration dialog (ICCF ID + password)
- Store credentials in options file

### Phase 3: Auto-submit
- Wire auto-submit into `move.tcl doAction`
- Add preference toggle for auto-submit
- Handle submit failures gracefully (show error, keep the move locally)

### Phase 4: Event polling
- Add background polling for opponent moves
- Show notifications when opponent moves
- Auto-refresh the game list and open games

## 4. Security considerations

- **Credential storage**: The ICCF API password should be stored securely.
  Use the system's keyring if available, or a simple obfuscation in the
  options file with a warning that it's not strongly encrypted.
- **TLS**: Always use HTTPS for ICCF server communication.
- **Rate limiting**: The ICCF server may have rate limits; implement
  exponential backoff for failed requests.
- **Error handling**: Never crash or lose local data due to server
  communication failures. All network operations should be wrapped in
  `catch` with user-visible error messages.

## 5. Testing

- **Unit tests**: Test XML parsing with sample XFCC responses
- **Integration tests**: Requires ICCF test credentials and a test game
- **Mock server**: Create a simple Tcl HTTP server that serves sample XFCC
  responses for development testing

## 6. Prerequisites

Before implementation can begin:
1. **XFCC protocol specification** — obtain the official ICCF XFCC API docs
2. **ICCF test credentials** — a player ID and API password for testing
3. **TLS package** — verify that `tls` is available in the scidb Tcl environment
4. **HTTP client** — verify that `http` works or extend `tcl_http.cpp`