# Online Play Client — Spec

Status: draft, 2026-11-08. Replaces the play dialogs in `tcl/lichess.tcl` and
`tcl/ics.tcl` with one Online view. Our own server stays "build later"
(`docs/plans/ONLINE_PLAY_PLAN.md`). chess.com is out of scope.

## 1. Why

A live test (Lichess game OjRCm4tD, `~/Videos/chesswiz-lichess-live-2026-11-08.mp4`)
works but looks like a utility: a small dialog over the analysis board, tiny
clocks and status line, an empty notation pane, and no opponent identity, chat,
lobby list, challenges, watching or game history. The best clients make the
game the whole screen.

## 2. Benchmark clients

| Client | Servers | What they do best |
|---|---|---|
| lichess.org (web/mobile) | Lichess | Quick-pairing grid, seek graph, clocks with low-time colouring, premove, takeback, rematch, chat, post-game analysis, TV |
| chess.com app | chess.com | Player cards with flags/titles/ratings, move confirmation option, captured material, result screen with rating change |
| BabasChess | FICS/ICC | Seek graph, multiple observed boards in tabs, consoles per channel, finger/history panes |
| Jin / Thief / Raptor | FICS/ICC | Seek graph, premove, auto-flag, per-channel chat, examine mode, game lists |
| eboard | FICS | Lightweight board, clocks, seek list, lag compensation display |

## 3. Current state (Chesswiz, commit b4847976)

| Area | Lichess | FICS |
|---|---|---|
| Sign-in | OAuth PKCE once, token kept | Guest or handle+password |
| Lobby | One seek form (Rapid+), one "play computer" form | Seek list (computer seeks marked), seek, watch by number |
| Game | Moves on the analysis board, two small clock labels, resign/draw/abort/claim | Same, plus raw command line |
| After game | Game imported into the clipboard base | Same |
| Missing | Everything in §4 marked new | Everything in §4 marked new |

## 4. Required features

`L` = Lichess, `F` = FICS. "API" names the endpoint or command; anything not
verified live is marked *verify*.

### 4.1 Game screen (new layout, highest priority)

| # | Feature | L | F | API / command |
|---|---|---|---|---|
| G1 | Board fills the window's main area; analysis panes hidden while playing | ✓ | ✓ | client |
| G2 | Player card above and below the board: name, title, rating, flag, online dot | ✓ | ✓ | L: gameFull `white`/`black`; F: style12 + `finger` |
| G3 | Large clocks on the cards; seconds tenths under 10 s; colour change and optional sound under a user-set threshold | ✓ | ✓ | L: `wtime`/`btime`; F: style12 |
| G4 | Captured pieces / material difference on each card | ✓ | ✓ | client |
| G5 | Live move list beside the board (SAN, clock per move); click to view an earlier position without leaving the game; a "back to live" button | ✓ | ✓ | client |
| G6 | Premove (one queued move, cancel by right-click) | ✓ | ✓ | client |
| G7 | Auto-queen option; promotion picker otherwise | ✓ | ✓ | client |
| G8 | Move sounds, check, low-time, game start/end; respect the mute setting | ✓ | ✓ | client |
| G9 | Buttons: resign (confirm), offer/accept/decline draw, takeback request/answer, abort (first moves), claim victory when opponent left, flip board | ✓ | ✓ | L: `/api/board/game/{id}/{resign,draw/yes\|no,takeback/yes\|no,abort,claim-victory}`; F: `resign`, `draw`, `takeback`, `abort` |
| G10 | Chat panel with the opponent (and spectators on Lichess) | ✓ | ✓ | L: `GET/POST /api/board/game/{id}/chat`; F: `say`, `whisper`, `kibitz` |
| G11 | Result banner with reason and rating change; buttons: rematch, new game same settings, analyse, back to lobby | ✓ | ✓ | L: rematch *verify* (challenge `rematchOf`); F: `rematch` |
| G12 | Connection/lag indicator; reconnect resumes the game | ✓ | ✓ | L: stream reconnect + gameFull; F: `refresh`, `moretime` |
| G13 | Engine and opening book locked during a rated game (fair play) | ✓ | ✓ | client |
| G14 | Status text at normal UI size, never clipped | ✓ | ✓ | client |

### 4.2 Lobby

| # | Feature | L | F | API / command |
|---|---|---|---|---|
| B1 | Quick-pairing grid (10+0, 10+5, 15+10, 30+0, 30+20; FICS adds 1+0, 3+0, 3+2, 5+0) | ✓ | ✓ | L: `/api/board/seek`; F: `seek` |
| B2 | Custom seek: time, increment, rated, colour, rating range, variant | ✓ | ✓ | as above |
| B3 | Seek list with filters (speed, rated, computer/human); click to accept | — | ✓ | F: `<s>`/`<sr>` stream, `play n` |
| B4 | Seek graph (rating × time) | — | ✓ | F: same data |
| B5 | Challenge a player by name; incoming challenges list with accept/decline | ✓ | ✓ | L: `/api/challenge/{user}`, `/api/challenge/{id}/accept\|decline` (scope `challenge:read/write`); F: `match`, `accept`, `decline` |
| B6 | Play the computer (Lichess levels 1–8) | ✓ | — | L: `/api/challenge/ai` |
| B7 | My games in progress, including correspondence; open any | ✓ | — | L: `/api/account/playing` |
| B8 | Friends / notify list with online status; challenge from the list | ✓ | ✓ | L: `/api/rel/following` (scope `follow:read`), `/api/users/status`; F: `=notify`, `+notify` |
| B9 | Profile and recent games; import my recent games into a database | ✓ | ✓ | L: `/api/games/user/{name}`; F: `history`, `smoves` |
| B10 | Speed rule shown inline: Lichess allows seeks from this kind of app only at Rapid or slower; Blitz/Bullet only by direct challenge | ✓ | — | client |

### 4.3 Watching

| # | Feature | L | F | API / command |
|---|---|---|---|---|
| W1 | Lichess TV channels and FICS game list; open any game | ✓ | ✓ | L: `/api/tv/channels`, `/api/tv/{channel}/feed`; F: `games`, `observe` |
| W2 | Several watched games in tabs; each tab its own board, clocks, move list | ✓ | ✓ | L: `/api/stream/game/{id}` *verify*; F: multiple `observe` |
| W3 | Follow a player (auto-switch to their next game) | — | ✓ | F: `follow` |
| W4 | Kibitz/spectator chat | ✓ | ✓ | L: spectator chat room; F: `kibitz`, `whisper` |

### 4.4 Correspondence (Lichess)

| # | Feature | API |
|---|---|---|
| C1 | List of my correspondence games, whose turn, time left | `/api/account/playing` |
| C2 | Notification when it is my move (tray/desktop) | `/api/stream/event` |
| C3 | Days-per-move seeks and challenges | `/api/board/seek` `days`, challenge `days` |

### 4.5 After the game

| # | Feature |
|---|---|
| A1 | Save every finished game automatically to a database the user picks once (default: "Online games" base), with server, game id, ratings and clocks in tags |
| A2 | "Analyse" opens the saved game on the analysis board with the engine ready |
| A3 | Game history pane: date, opponent, result, time control; reopen any |

### 4.6 Explaining it to the user

Every Chesswiz user plays with their own account; nothing is tied to the
Chesswiz developers. The app must say so in plain words where it matters:

| # | Where | What it says |
|---|---|---|
| E1 | Lichess sign-in screen (done 2026-11-08) | Your own Lichess account; the browser opens once; Chesswiz never sees the password; games are played in Chesswiz; the sign-in is saved on this computer (keychain on Windows/macOS, private file on Linux) until sign-out; no Chesswiz server, only lichess.org |
| E2 | FICS connect screen (done 2026-11-08) | Free server; guest or own account; direct connection to freechess.org |
| E3 | Extra Lichess permissions (B5, B8) | Before reopening the browser: which feature needs it and what Lichess will ask |
| E4 | Lobby speed rule (B10) | Why seeks must be Rapid or slower, and that challenges allow Blitz/Bullet |
| E5 | Sign-out | That it removes the saved sign-in from this computer; revoking it on lichess.org (Preferences → Security) is optional |
| E6 | User guide page and assistant knowledge | Same facts, so "how do I play on Lichess?" gets the right answer |

## 5. Layout

```
+---------------------------------------------------------------+
| [Lobby] [Game: vs Opponent] [Watch: TV] [Watch: #15]   ● Lichess|
+-------------------------------------+-------------------------+
| ▣ Opponent (2041) FM 🇩🇪   ♙♙♘ +3   04:52 |  1. e4    e5            |
|                                     |  2. Nf3   Nc6           |
|                                     |  3. Bc4   ...           |
|              BOARD                  |-------------------------|
|                                     |  chat                   |
|                                     |                         |
| ▣ You (1850)                  09:58 |-------------------------|
| [Resign] [Draw] [Takeback] [Flip]   |  [ message…      ][Send]|
+-------------------------------------+-------------------------+
| status: Your move.                                    lag 80 ms|
+---------------------------------------------------------------+
```

- One top-level window (or a main-window mode, decided in step 2), tabbed:
  Lobby, each live game, each watched game.
- Board widget: reuse the main board drawing code, not the analysis board
  itself, so the user's analysis session is untouched while playing.
- Same layout for Lichess and FICS; a server switch in the tab bar.

## 6. Architecture

- `tcl/online.tcl` (new): the window, tabs, game screen, lobby, watch,
  history. Server-neutral.
- `tcl/lichess-api.tcl`, `tcl/ics.tcl`: become protocol back ends behind one
  interface: `connect`, `seek`, `cancelSeek`, `challenge`, `accept`,
  `decline`, `move`, `offer`, `answer`, `resign`, `abort`, `chat`, `watch`,
  `unwatch`, and events `gameStart`, `gameState`, `gameEnd`, `chat`,
  `seekList`, `challengeList`, `presence`.
- `tcl/lichess.tcl`: shrinks to the Lichess back end's event mapping.
- Lichess sign-in requests the extra scopes needed for B5/B8
  (`challenge:read challenge:write follow:read`); existing tokens with only
  `board:play` keep working and prompt once when those features are used.

## 7. Tests

- Fake servers: extend `tests/lichess_fake_server.tcl` (chat, takeback,
  challenges, TV feed, playing list) and add a scripted FICS fake.
- Per feature: one app test against the fakes; layout tests at 1280×800 and
  1920×1080 (no clipped text, board ≥ 60 % of window height).
- Live checks (recorded, user signed in): Lichess vs computer and a cancelled
  seek; FICS guest vs a computer account. Never seek or challenge people in
  automated runs.

## 8. Build order

1. Game screen (G1–G14) with Lichess + FICS back ends behind the interface.
2. Lobby (B1–B10).
3. Watching (W1–W4).
4. Correspondence and after-game (C1–C3, A1–A3).

Each step: fake-server tests, all three platforms, recorded live check.

## 9. Open questions

- Separate window vs a main-window mode (decide after a mock-up in step 1).
- Lichess rematch through the Board API: confirm `rematchOf` works for
  board:play tokens.
- Variants (Chess960, Crazyhouse on FICS): later, unless asked.
