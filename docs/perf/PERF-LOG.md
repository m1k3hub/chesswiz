# Performance bottleneck log

Started 2026-11-24. Each entry: ID, area, measurement (how), cause, status.
Tools: docs/perf/wrap.tcl (wraps update/winfo/image/font/wm/... and times
them per caller; launch `src/tkchesswiz -encoding utf-8 docs/perf/wrap.tcl`,
dump with `send Chesswiz profdump`, env PROFOUT=file), docs/perf/poll.tcl
(time-to-mapped probe: `wish docs/perf/poll.tcl $(date +%s%3N)`).

## Summary (end of the 2026-11-24 session)
- Startup on the desktop is slow mostly because of GNOME: the app uses the same CPU as under Xvfb, while gnome-shell (Mutter, rootless Xwayland) burns ~4.5 s CPU during one start. Same GPU with rootful Xwayland+openbox: 2.5-3.0 s to the window vs 5.4 s. App fixes: one board build at startup instead of two; first-start window size bug fixed.
- Biggest app wins: CQL 6 search 2.4x (6.3 -> 2.5 s / 108k games), PGN import 2.4x (2.2 -> 0.9 s / 21.8k games, UI path 3.3 -> 1.55 s with the old C++), move stepping 2.2x (31 -> 14 ms/step), header wildcard search 4-10x, engine start -0.65 s.
- Needs your decision: engine default threads (cpus-1), HTTPS keepalive (20-26 ms UI block per request), assertions policy (full -DNREQ measured), CQL6 parallel decode, figurine leak.
- Regression check: full app suite on a worktree build, every failure identical on the pre-session build; later changes tested file by file.

## P1 Startup on the GNOME/Xwayland desktop (:0)
- Before the 2026-11-24 reboot: >45 s (each X window ~200 ms, degraded gnome-shell). After reboot: main window mapped at 4.8-5.4 s on :0 vs 2.0-2.3 s on Xvfb, same HOME.
- Plain X round-trip on :0 is 24 us, so not latency. Drawing is ~5x slower on :0: canvas image draw 0.9 ms vs 0.17 ms (Xvfb); semi-transparent photo 2.5 ms vs 0.75 ms (Tk reads the background back with XGetImage to blend alpha; GPU readback under Xwayland/glamor); text 1.4 ms vs 0.28 ms.
- gdb on _XReply during startup: 2506 synchronous replies: ~620 XGetImage from Tk_RedrawImage (alpha blending: canvas, labels, ttk tileimage), ~600 XSync from `update idletasks`, ~350 XSync from Tk_DeleteErrorHandler inside Xft font loading (Tk_MeasureChars), 256 XAllocColor from Tk_GetImage.
- Tcl-level (wrap.tcl), :0 vs Xvfb:
  - `update idletasks` in splash::print ("Opening main window..."): 1.3 s vs 83 ms total. This is the first paint of the whole main window.
  - switchTab -> RebuildBoard `::update`: 1.4-1.5 s vs 0.44 s (first board tab paint, during Startup2 tab selection).
  - GenerateTableMinSizeEvent `update idletasks` (app-db-games.tcl:375): 0.63 s vs 0.05 s.
  - font actual <- getFontFamilyName: 158 ms (26 calls); image create (1234 at load): 105 ms.
- Status: diagnosed. Levers: paint fewer times during startup (info tab painted, then board tab painted), fewer alpha images redrawn, avoid forced `update` in RebuildBoard / GenerateTableMinSizeEvent.

## Bugs found while driving (not perf)
- B1 First start: after the language chooser the main window shrinks from the 80% default (1536x864) to the board layout's natural size 1007x718: app-twm.tcl `geometry` (<<TwmGeometry>> {1005 689 605 451 0 0 none}) calls fitWindow+wm geometry. Mid-session language change does not shrink. Undoes b2dfb4cc6's first-start fix.

### P1 follow-up (same day): where the extra :0 time goes
- App CPU during startup is the same on :0 and Xvfb (2.3 s vs 2.1 s). On :0, Xwayland used 1.35-2.35 s of CPU and gnome-shell used **4.5 s of CPU** during one 14 s startup+settle.
- Rootful `Xwayland :5 -decorate` + openbox on the same GPU: mapped at 2.5-3.0 s, board tab switch 0.55 s (Xvfb: 2.0-2.3 s / 0.44 s). So glamor/NVIDIA rendering is not the cost. The cost is rootless Xwayland under Mutter (gnome-shell work per X damage/window), which agrees with the earlier memory notes (tk-xwayland-slow-dialogs).
- X request counts for a startup on :0 (gdb hit counters): XGetImage 375, XPutImage 927, XCreatePixmap 1175, XCopyArea 1890, XFillRectangle 4695, XCreateWindow 750, XSync 1327, XftFontOpenPattern 128.
- Tried: skip the `update idletasks` in splash::print "Opening main window..." so the first paint happens after map. Worse (mapped 6.7 s vs 5.4 s): painting while withdrawn is cheaper than painting a mapped window under Mutter. Reverted.
- False lead: the trace-based proc profiler (docs/perf/procprof.tcl) showed ai::provider::parseModels at 8.3 s; it is 36 ms without traces (recursive json procs inflate under execution traces). Use procprof only for call counts.
- Status: environment-bound. App code can only shave by drawing less; the large lever is the desktop (log out/in to reset gnome-shell, extension bisect outside ddterm, or an Xorg/other compositor session).

## Fix status (2026-11-24, unattended session)
Area reports: docs/perf/agy-A.md (database), docs/perf/agy-B.md (interactive GUI), by agy / Gemini 4 Neon. Every fix below was re-measured here (Xvfb, 3 runs) before commit.

| ID | Fix | Before -> after | Commit |
|---|---|---|---|
| B1 (bug) | first start: initial layout no longer shrinks the 80% window | 1007x718 -> 1536x864 | 1a7601f5a |
| A1 | PGN reader: no ftell/lseek per line; MoveList not zero-filled | import 21.8k games 2216 -> 1290 ms | 0ea259923 |
| A1 | import log/progress repaint throttled to 50 ms | UI import 3.3 s -> 1.55 s | 1732123e4 |
| A2/A8 | per-move isValidMove re-checks only with -DM_SLOW_CHECKS | CQL6 100k 6.3 -> 2.5 s; import 1.33 -> 0.91 s | 6fa64ea94 |
| B1 | stepping: toolbar label refresh, focuszoom snapshot, line snap, pin | 31 -> 14 ms/step | e47013f34 |
| B2 | UCI: skip options still at the engine default | first PV 1.50 -> 0.86 s (1T), 2.82 -> 2.13 s (47T) | 2b36e8d0c |
| B3 | notation: active game laid out once on font/style refresh | pgn::refresh 1: 570 -> 330 ms (300-move annotated game) | 1213eef1f |
| B6 | notation setup dialog: unchanged Cancel skips relayout | Cancel 1.1 s -> 0.4 s | 8bb34421b |
| B7 | assistant pane: no layout reload when already beside the board | re-show ~380 -> ~260 ms | aaf7f5b3e |
| A6 | header search: glob memo per name-table entry | player *sen* 78 -> 21 ms, event 33 -> 3 ms (108k) | cadd15bdb |
| A4 | game list sort: busy cursor only for 250k+ views | sort clicks -55 ms (e.g. 143 -> 91 ms, 108k) | 280373a04 |
| A5 | tree: pawn-structure set as 128 KB bitset | 12 cold searches 544k: ~1.27 -> ~1.20 s | 896e1c283 |
| P1 | startup: board built once (stale size dropped) | one board/piece build instead of two | da01dc831 |

Not changed (your call):
- Assertions stay on for the beta (configure). A full -DNREQ build measured: import 0.80 s, CQL6 2.6 s, i.e. the six slow checks above were nearly all of the cost.
- CQL6 -DASSERTIONS (worker AssertPos): only ~5% now; kept as a corruption guard.
- CQL6 producer still decodes on the Tcl thread (now ~2.5 s/100k). Parallel decoding needs a thread-safe codec per worker (agy-A A2 fix 3); medium/high risk.
- Engine default threads = cpus-1 (47 here): +1.3 s analysis start and 2x slower stepping while analysing vs 4 threads. A cap trades strength.
- Pre-existing failures (also on the pre-session build 853489efe): test_app_pane_zoom2.tcl pane-zoom2-user-events (full-file run), test_app_ask.tcl ask-field-present, test_app_board_media_layout.tcl (all 26).
- Figurine leak (agy-B B5): board-pieceset.tcl unregisterFigurines decrements an undeclared BoardSizeDict, so figurine photos are never freed (12 per board size used). Fixing it needs app-board.tcl's register/unregister bookkeeping fixed first (it would unregister a size it just registered). Not changed.
- Header search / A3 legacy CQL re-parse per game: deliberate (per-game counters); not changed.

### P1 re-measure after the fixes (08:45, desktop :0, real HOME, interleaved)
- Time to main window: current 7.6-8.2 s vs pre-session build 8.4-8.9 s (about -0.7 s). Absolute numbers are higher than at 06:08 (5.4 s) because the machine was loaded (agy runs) and gnome-shell is 7.5 h older (20 frames+map 189 -> 247 ms).
- Settled (last large repaint done): 11.0-13.9 s vs 13.3-13.8 s; noisy.
- Regression sweep: all 361 app test files (minus dialog_place/reachability) on a worktree build of cadd15bdb; the 11 files with failures fail identically on the pre-session build 853489efe (2 time out on both). Later commits were tested file by file.

## P2 Game load from the list (found 2026-11-24, after the agy reports)
- ::game::new + update for a plain game from a 108,850-game base: ~130 ms on Xvfb (8 loads). Per load: pgn::add 33 ms (gamebar entry + game::switch callbacks that render notation/board), MediaDestroy 32 ms + besideSettle 32 ms (also on close), Jev offer ranking 26 ms, game::switch 22 ms.
- Fixed: media Stop ran a full beside-dialog re-plan on every game switch even with no player and no inset (mediainset::hide now reports whether it hid anything). ~130 -> ~117 ms per load.
- Not changed: every HTTPS connection blocks the Tcl thread ~20-26 ms in tls::socket (OpenSSL context + CA store per connection; plain TCP is 0.8 ms; -cafile/-cadir don't help). ai::provider::request uses -keepalive 0 deliberately; reusing connections (keepalive) would remove it for the Jev offer ranking that runs on every game load. Network-behaviour change, left for you.
- Idle (C1): 60 s idle on the Board tab with a 100k base open: 130 ms CPU (0.2%), one 1 Hz timer (displayWatch). Fine.
- Memory (C2): 50 game loads, 50 tab switches, 10 open/close of a 100k base, 8 resizes: RSS 358 -> 367 MB; images +104, all created once on first use (no growth in later rounds); widgets and timers flat. No leak found besides the figurine one noted above.
- agy area C stalled (a hung shell command) and was stopped; C1/C2 above were measured here instead.
- Figurine leak measured: 40 distinct window sizes add 48 figurine photos and ~1 MB RSS; repeats add nothing. Bounded by distinct sizes; left as noted.
- B5 board resize: coordinate-font search memoised (family, size, border offset, tk scaling): 127-130 -> 120-123 ms per resize between cached sizes (Xvfb).

## A1.4 Import with many distinct names (open, recommended next)
- 100k synthetic games, 19 MB PGN each: names repeated (500 players, 300 events) 0.90 s; every player and event distinct (~200k players, 100k events) 5.5 s. gdb samples during the distinct-name import: 24/32 in memmove under mstl::vector::insert from Namebase::insertPlayer. Each new name is inserted into a sorted vector (src/db/db_namebase.cpp, insertPlayer/insertEvent/insertSite), so import time grows with distinct names squared: ~1M distinct players (a Lichess month) would take minutes.
- Design: keep m_list sorted for readers but buffer new entries during an import: a hash (name -> entry) for lookups plus an unsorted append list, merged into m_list with one sort+merge when the import finishes or before the first index-based read (every accessor in db_namebase.ipp/.cpp would call a flush). Touches ~90 uses of m_list and the id/order bookkeeping saved in .scn, so it needs a careful change and round-trip tests (import -> save -> reload -> byte compare). Not attempted unattended.
- Repro: `python3 docs/perf/gen-names-pgn.py DIR`, then docs/perf/bench-run.sh docs/perf/bench-import.tcl "set ::BPGN DIR/distinct.pgn" (and repeated.pgn).
