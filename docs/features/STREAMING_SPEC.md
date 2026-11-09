# Livestreaming — Spec

Status: draft, 2026-11-09. Stream Chesswiz to Twitch, YouTube, Kick and any
RTMP/SRT service, from any screen: analysis, a database game, a lesson, play
against the engine, or an online game in the Chesswiz Online window.

## 1. Why

Chess streaming is a big audience, and nearly every streamer runs the same
kit: OBS, a browser tab with Lichess or chess.com, a webcam, and a handful of
overlay websites for the eval bar, chat and alerts. Getting that kit to work
together takes hours, and no chess program feeds it directly. Chesswiz already
has the board, engines, databases, an assistant and online play, so it can be
that feed.

There are two kinds of user:

- **Streamers who already use OBS** want clean board/eval/clock/chat sources
  that follow the app, not a window capture of the whole program.
- **Newcomers** want one "Go live" button with no OBS at all.

We serve both from one design: Chesswiz draws a **stream scene** and can either
publish it as OBS sources or encode and send it itself.

## 2. Benchmark

| Tool | What it does well | What it lacks for chess |
|---|---|---|
| OBS Studio | Scenes, sources, webcam, filters, encoders, every service | Knows nothing about chess; overlays are web pages kept in sync by hand |
| Streamlabs / StreamElements | Alerts, chat box, goals | Same |
| Lichess broadcast/TV + "stream overlay" sites | Board and eval for Lichess games | Lichess only; separate site; no analysis or database |
| chess.com streamer mode | Hides ratings/names options, stream delay hint | chess.com only |
| ChessBase "Fritz Live"/Playchess | Commentary on live games | No streaming output |

## 3. What the viewer sees

A **stream scene** is a fixed 16:9 canvas (1920x1080, or 1280x720) laid out
from blocks the streamer picks:

| Block | Content | Notes |
|---|---|---|
| Board | Current position, last move, arrows/highlights the streamer draws | Large, theme follows the app |
| Eval bar + line | Engine score and best line | **Forced off during a live rated game** (§6) |
| Clocks + player cards | Names, titles, ratings, flags, clocks | From the Online view or game tags |
| Move list | Notation with the current move highlighted | |
| Chat | Merged chat from every connected platform | Twitch, YouTube, Kick; badges by platform |
| Webcam | Camera picked by the streamer | Optional |
| Caption / lower third | Text the streamer types, or the opening name | |
| Poll | Viewer move vote result (§5) | |
| Alerts | Follows, subs, raids | Phase 3 |

Built-in layouts: **Analysis** (board + eval + line + cam), **Playing**
(board + clocks + cards + chat + cam), **Lesson** (board + move list +
caption), **Just the board**. Each is editable by dragging blocks in a
preview; layouts are saved per user.

The scene follows the app, not the screen: dialogs, menus, private database
names, file paths and notifications never appear. That is the main reason to
render a scene instead of capturing the window.

## 4. Outputs

### 4.1 OBS mode (phase 1)

Chesswiz runs a local web server on `127.0.0.1` (port chosen in settings):

- `http://127.0.0.1:PORT/scene/<layout>` — the whole scene as a browser source.
- `/block/board`, `/block/eval`, `/block/chat`, … — single blocks, for
  streamers who arrange OBS themselves.
- Pages are static HTML + SVG; the app pushes state over a WebSocket
  (FEN, last move, arrows, eval, clocks, chat lines). No video passes through
  Chesswiz, so it costs almost nothing.
- Optional **obs-websocket** link (OBS 28+ ships it): Chesswiz switches OBS
  scenes on events ("game started" → Playing scene, "game over" → Analysis).
  The obs-websocket password is stored like other secrets (§7).

Why first: most streamers have OBS already, it works on every platform
(including GNOME Wayland, where our own capture is hard), and it needs no
video code in Chesswiz.

### 4.2 Built-in "Go live" (phase 2)

For users without OBS:

- Chesswiz renders the same scene off-screen and pipes frames to **ffmpeg**,
  which encodes (NVENC/QSV/VideoToolbox/AMF if present, else x264) and sends
  to one or more destinations at once (Twitch, YouTube, Kick, custom
  RTMP/RTMPS/SRT). Several destinations = ffmpeg `tee` muxer; no relay service.
- Audio: microphone (PipeWire/Pulse, WASAPI, CoreAudio) plus app sounds,
  with a level meter and mute.
- Webcam: V4L2 / DirectShow / AVFoundation through ffmpeg.
- Presets: 1080p30 6 Mb/s, 720p30 3.5 Mb/s, 720p60 4.5 Mb/s; a bandwidth
  test before the first stream.
- Record to disk at the same time (MP4), so the stream is also a video.
- Status bar while live: LIVE badge, elapsed time, bitrate, dropped frames,
  viewer count (from platform APIs), and a big Stop button.

Rendering the scene: draw the stream blocks in a hidden Tk toplevel of
exactly the stream size and grab it per frame (`image create photo -format
window` via tkimg, or our own X/Win32/Cocoa grab of our own window, which works
on Wayland because it is our own surface). This needs a spike (§10).

### 4.3 Clips and VOD

- "Clip last 30 s" key from a ring buffer (phase 2).
- After a game, offer to upload the recording to YouTube (we already have
  upload code for @chesswizapp; this would use the *user's* own channel and
  sign-in).

## 5. Viewer interaction

Read chat from each connected platform:

| Platform | Read | Send | Sign-in |
|---|---|---|---|
| Twitch | IRC over WebSocket (`irc-ws.chat.twitch.tv`) or EventSub | Yes | OAuth (device code flow, no redirect server needed) |
| YouTube | `liveChatMessages.list` polling (quota-bound) | Yes | Google OAuth, user's own project-less app consent |
| Kick | Public chat WebSocket *verify* | *verify* | *verify* |

Features built on chat:

- **Merged chat** in a dock in the app and as a scene block.
- **Viewer move vote** ("chat plays"): in analysis or vs-engine games, the
  app opens a poll, counts `!e4` / `!Nf3` (validated with
  `::scidb::ai::moveFacts`), shows a live bar block, and plays the winner.
  **Never in rated online games against people** — servers ban that.
- **Suggestion arrows**: `!arrow e2e4` draws a faded arrow for the streamer to
  accept or ignore (moderated, rate-limited per viewer).
- **Commands**: `!eval` (off during live games), `!opening`, `!game` (link
  to the Lichess/FICS game), `!pgn` (posts a paste link after the game).
- **Moderation**: per-platform mods are honoured; streamer can turn every
  command off; links and commands from new chatters ignored by default.

## 6. Fair play (non-negotiable)

Streaming an online game with engine help is cheating, and viewers can
leak help in chat. While an Online-window game against a person is in
progress:

- Eval bar, best line, `!eval`, opening explorer with stats, tablebase and
  move votes are **off in the scene and in the app**, whatever the layout says.
  They come back when the game ends.
- **Stream delay** setting (0–300 s; default 60 s during rated games, 0
  otherwise) so viewers cannot relay moves. In OBS mode we push the delay to
  the overlay pages and tell the user to set OBS's own render delay; in
  built-in mode we buffer encoded packets.
- The UI says why, in one sentence, when a block is blanked.

Lichess allows streaming its games; FICS has no rule against it. Both forbid
outside assistance, which is what this section enforces.

## 7. Accounts and secrets

Every user streams to their own channels with their own sign-in, the same
model as Lichess:

- Twitch and YouTube use OAuth in the system browser; tokens go to the OS
  keychain (`::lichess::api::OsStore` pattern), never to options files or
  logs.
- Stream keys (for custom RTMP or if the user prefers keys) are entered in a
  masked field, stored in the keychain, never displayed again (only "key set,
  ends …a3f"), and are redacted from the ffmpeg command line in logs.
- The local overlay server listens on 127.0.0.1 only, with a random path
  token so other local pages cannot read chat.

## 8. Privacy / streamer mode

One switch, "Streamer mode", on whenever a stream is live:

- Hide private database names and paths, recent-file lists, the user's real
  name from the assistant panel, email in sign-in dialogs.
- Hide opponent ratings/names option (chess.com-style) for those who want it.
- Suppress desktop notifications and the assistant's spoken replies unless
  allowed.

## 9. User-facing explanations (E-rules, as in the online spec)

| # | Where | Text (gist) |
|---|---|---|
| S1 | First open | "Chesswiz can show your board on Twitch, YouTube and others. If you use OBS, add Chesswiz as a source. If not, Chesswiz can go live by itself." |
| S2 | Sign-in | "You sign in with your own Twitch/YouTube account in your browser. Chesswiz keeps the sign-in in your system's keychain and never sees your password." |
| S3 | Stream key field | "A stream key lets anyone broadcast on your channel. Chesswiz stores it securely and won't show it again." |
| S4 | Live game started | "Engine help and move votes are off until this game ends. That's the fair-play rule on Lichess and FICS." |
| S5 | Delay | "Your stream is delayed 60 s so viewers can't pass you moves." |
| S6 | OBS link | Step list with a copy button for the source URL. |

## 10. Architecture

```
app state (board, engine, online view, chat)
        │  events
        ▼
 tcl/stream.tcl ── scene model (layout, blocks, fair-play gate, delay)
   ├── tcl/stream-server.tcl  127.0.0.1 HTTP + WebSocket → OBS browser sources
   ├── tcl/stream-render.tcl  hidden Tk toplevel → frames
   ├── tcl/stream-ffmpeg.tcl  ffmpeg child: encode, tee, record, stats
   ├── tcl/stream-chat.tcl    Twitch / YouTube / Kick readers → chat dock
   └── tcl/stream-window.tcl  "Chesswiz Stream" window: tabs Go live,
                              Layout, Chat, Accounts, Settings
```

- The fair-play gate lives in the scene model, so every output obeys it.
- The Online window (`::online::view`) publishes events the scene listens to;
  no streaming code in `lichess.tcl` / `ics.tcl`.
- ffmpeg: use the system one on Linux; bundle on Windows/macOS (LGPL build,
  no x264 → hardware encoders or openh264). *Licence check needed.*

## 11. Build order

1. Scene model + overlay server + board/eval/clock/move-list blocks; OBS
   instructions (S6). Test with OBS on Linux.
2. Fair-play gate + delay, wired to the Online window.
3. Twitch chat (read/send) + chat dock/block; then YouTube.
4. Layout editor.
5. Built-in Go live: render spike, ffmpeg pipeline, multi-destination,
   audio, webcam, recording.
6. Viewer votes, arrows, commands; obs-websocket scene switching.
7. Clips, YouTube upload, alerts, Kick.

## 12. Tests

- Unit: scene model JSON per event; fair-play gate blanks eval/votes for a
  rated game and restores after; delay buffer ordering; secret redaction in
  logs.
- Overlay server: headless browser (agent-browser) loads `/scene/playing`,
  checks the FEN shown after moves.
- Chat: recorded Twitch IRC transcripts replayed through the parser; vote
  counting with illegal/duplicate votes.
- Go live: stream to a local `ffmpeg -listen 1` RTMP sink, check
  ffprobe size/fps/audio and dropped frames.
- Live checks only with the user's own accounts, signed in by the user.

## 13. Open questions

1. Phase 2 frame grab: can Tk give us our own hidden toplevel's pixels at
   30 fps on Wayland, Windows and macOS? (Spike before committing to built-in
   streaming; fallback is OBS-only plus a "virtual camera" later.)
2. Bundle ffmpeg on Windows/macOS, or ask users to install it?
3. YouTube chat quota: polling one stream for hours may exhaust the default
   quota; may need a Chesswiz Google project and verification.
4. Kick API status.
5. Should the scene also be available as a virtual camera (for Zoom/Discord
   lessons)? Cheap once frames exist.
