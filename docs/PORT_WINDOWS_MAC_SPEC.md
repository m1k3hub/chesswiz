# Windows / macOS port and rename — design decisions

**Rename done (2026-10-09): the product is Chesswiz.** Programs `chesswiz`/`tkchesswiz`/`tclchesswiz` (`PROGRAM` in Makefile.in, `--program=` in configure), share dir `/usr/share/chesswiz`, user dir `~/.chesswiz` (first start copies `~/.scidb-beta` or `~/.scidb` and rewrites the paths in its settings), desktop entry and icon `chesswiz`, Debian package `chesswiz` (Provides/Replaces/Breaks `scidb-beta`). Kept: `::scidb::*` code names, Tk class `Scidb` of dialogs, font families `Scidb *`, the `.sci` format and its name, upstream URLs and credits. Open: the help pages (`tcl/help/*`) still say Scidb.

Status: proposal, 2026-10-09. Facts below were surveyed from the tree at `bb30e5e`.

## 1. What the tree already gives us

| Area | State | Port impact |
|---|---|---|
| `src/sys` (process, pipe, file, thread, mutex, timer, signal, vfs) | Abstraction layer exists; 296 `_WIN32` / 72 `__APPLE__` branches tree-wide (legacy, untested) | Revive, don't rewrite |
| Engine processes | `sys_process.cpp` uses `Tcl_OpenCommandChannel` | Portable as-is (Tcl handles CreateProcess) |
| File watching | `sys_fam.cpp` = inotify only | Needs ReadDirectoryChangesW / FSEvents, or a no-op fallback |
| File locking | `fcntl` in `sys_file.cpp` | Needs `LockFileEx` branch |
| tkdnd | `src/tk/tkdnd/{unix,win,macosx}` vendored | Build the right backend per platform |
| X11-only Tk extensions | `tk_x11.cpp`, `tk_busy.cpp`, `tk_window_manager.cpp`, `tk_fixes.cpp`, `tk_selection.cpp`, `tk_xcursor.cpp`, `X11/` (~4 kLOC) | Biggest risk; see §3 |
| `tk_twm.cpp` (9 kLOC docking manager) | Pure Tk C API, no Xlib | Portable; floating/undock behaviour must be retested per WM |
| 3D board | `tk_glboard.cpp` dlopens `libTogl.so`; WebGL path runs `python3 web3d/server.py` | Togl for Win/Mac or drop to WebGL-only |
| Reckless engine | Rust (`engines/reckless`) | cargo cross-builds fine; ship prebuilt |
| Network (assistant, downloads) | `http::geturl` + `tls::` (tcltls) | Bundle tcltls with OpenSSL (Win) / use it on Mac too |

## 2. Decisions to make (recommendation first)

### D1. Toolkit version — **Tcl/Tk 8.6.x, bundled**
- 8.6 is what Linux builds use (`TCL_VERSION = 8.6`). 8.7/9.0 change the C API (Tcl_Size, UTF-8) and would add churn across 410 files.
- Ship a private Tcl/Tk (not the system one): macOS system Tk is deprecated/ancient; Windows has none.

### D2. Build system — **keep make, add CMake only if MSVC is required**
- Recommended: **MSYS2/MinGW-w64 (UCRT64)** on Windows, clang + make on macOS. The existing `configure`/`Makefile.in` survive with platform blocks; GCC-isms (`__attribute__`, `-Wl,-rpath`) keep working on MinGW.
- MSVC would need a CMake port of every Makefile — weeks of work for no user-visible gain.
- Known gotcha: `configure` splits `OPTIMIZE=` at the second `=`; fix that parser while touching it.

### D3. X11-only extensions — **stub per platform, then replace feature by feature**
Order of work:
1. Compile-time gate: `#ifdef __unix__` around Xlib in the six files; provide no-op/Tk-native fallbacks so the app *starts*.
2. `tk_busy` → Tk 8.6 has `tk busy` built in; delete ours on non-X11.
3. `tk_selection` / clipboard → Tk native `clipboard`/`selection` are adequate on Win/Mac.
4. `tk_window_manager` / `wm frameless` → Tk `wm attributes -toolwindow` (Win), `::tk::unsupported::MacWindowStyle` (Mac).
5. `tk_xcursor` → Tk's built-in cursors or `.cur`/`.ico` files on Windows.
Rule: every stub logs once to the error log so missing features are visible, not silent.

### D4. 3D board — **WebGL path only on Win/Mac at first**
- Togl is unmaintained on modern macOS (OpenGL deprecated). The WebGL path already exists; it needs Python only for its static server — replace that with a tiny in-process Tcl HTTP server (`socket -server`) to remove the Python dependency on all platforms.

### D5. File watching (`sys_fam`) — **polling fallback first**
- A 2 s stat-poll of open database files is enough for "file changed on disk" prompts. Native ReadDirectoryChangesW/FSEvents later, only if needed.

### D6. Unix-only `exec` calls in Tcl — **replace with Tcl/C equivalents**
Found: `exec nproc` (ai-engine.tcl:137), `exec kill` (ai-modelfit.tcl:107, app-voice.tcl:622/640), `exec pgrep` (app-diagnose.tcl:344), `exec readlink /proc/...` (exec.tcl:84), `exec yes | xdg-…` (menu.tcl:1222), `exec espeak-ng` (app-voice.tcl:1001), `exec python3` (board-3d.tcl:1961).
- Add a small `::scidb::sys` C command set: `cpus`, `kill pid ?signal?`, `alive pid`, `children`. Windows: `TerminateProcess`; `-INT` → `GenerateConsoleCtrlEvent` or terminate.
- URL/file open: `start ""` (Win, via `cmd /c`), `open` (Mac), `xdg-open` (Linux) — one helper.
- TTS: Windows SAPI via PowerShell, macOS `say`, Linux espeak-ng.

### D7. Per-user directories — **platform-native, decided explicitly, not from argv0**
- **Done:** the name is now set at build time (`USERDIRNAME`, default `.` + basename of `DATADIR`, i.e. `.scidb-beta`), and `SCIDB_USERDIR` overrides it. The launcher no longer derives its binary from its own name either: the binary name is substituted at build time (`TKPROGRAM`, default `tkscidb$(SUFFIX)`) and symlinks are followed to the real script.
- Before: `start.tcl:63` derived the user dir from the *executable name*: `~/.` + name minus the `tk` prefix (`tkscidb-beta` → `~/.scidb-beta`). A rename or a `.exe` suffix silently moves everyone's settings, keys and layouts. Fix this **before** the rename.
- Proposed:
  - Linux: `$XDG_CONFIG_HOME/<app>` (fall back to the legacy dotdir if it exists).
  - Windows: `%APPDATA%\<App>` (config), `%LOCALAPPDATA%\<App>` (logs, caches, pattern indexes).
  - macOS: `~/Library/Application Support/<App>`, logs in `~/Library/Logs/<App>`.
- Share dir: Windows = beside the exe (already coded); macOS = `<App>.app/Contents/Resources`.
- Engines dir: Windows/macOS = inside the install; user-added engines under the user dir.

### D8. Packaging
- Windows: Inno Setup installer (or MSIX later); bundle Tcl/Tk, tcltls+OpenSSL, fonts installed privately (`AddFontResourceEx` FR_PRIVATE at startup — no admin rights), engines (Stockfish, Reckless, Sjeng `.exe`).
- macOS: `.app` bundle, universal2 (arm64+x86_64), codesigned + notarized (needs an Apple Developer ID — a cost/account decision for you). Fonts via `CTFontManagerRegisterFontsForURL` at startup.
- Engines must be signed inside the bundle on macOS or Gatekeeper blocks spawn.

### D9. Credentials — **OS keychain**
- API keys currently live in `user/config/ai-keys` (plain file). On Win/Mac use Credential Manager / Keychain (via a tiny C shim), file fallback on Linux (or libsecret).

### D10. CI — **GitHub Actions matrix** (ubuntu, windows-latest + MSYS2, macos-14)
- Run `make -C tests tcl cpp` on all three; app tests under Xvfb on Linux only at first, then natively.
- The app suite has fixed-time waits; `bb30e5e` started converting them to `waitUntil` polls — finish that before CI, slow runners will otherwise flake.

## 3. Rename — decisions

| Decision | Recommendation |
|---|---|
| Scope | Rename user-visible strings, binaries, package, dirs. **Keep** internal Tcl namespaces `::scidb::*` and C++ `scidb` identifiers for now (5,200 occurrences in 410 files); rename them later mechanically, if ever. |
| Single source of truth | One `APP_NAME` / `APP_ID` in `Makefile.version` → generated into C (`tcl_misc.cpp` `SCIDB_VERSION`), Tcl (`start.tcl`), desktop file, debian/control, Info.plist, Inno script. |
| Binary names | `tk<name>` convention ties the user dir to argv0 (D7) — drop the coupling, then name binaries freely. |
| Settings migration | On first start, if the new user dir is missing and `~/.scidb*` exists, copy (not move) it and record `migratedFrom`. |
| File formats | **Do not rename** `.sci/.scg/.scn` extensions or magic bytes — they are the data format; renaming breaks every existing database and Scid interop. |
| Debian package | New source name; add `Replaces/Breaks/Provides: scidb` so upgrades are clean. |
| Licence/credits | GPL notices and upstream Scidb (Gregor Cramer) credit must remain in About/COPYRIGHT. |
| Trademark | Check the new name against chess-software trademarks and app stores before committing to it. |

## 4. Suggested order
1. D7 (user dir decoupled from argv0) + settings migration — needed by both port and rename.
2. Rename via `APP_NAME` single source.
3. MSYS2 build compiles with X11 stubs (D2, D3 step 1) → app starts on Windows.
4. D6 exec replacements, D5 polling, D4 WebGL server in Tcl.
5. macOS `.app` build; signing/notarization.
6. Installers, CI matrix, keychain.

## 6. Replace Tcl/Tk? Move C++ to Rust?

Size today: **~260 k lines of Tcl** (UI and app logic), **~490 k lines of C++** (db 177 k, tk extensions 133 k, cql6 59 k, util 47 k, mstl 34 k, tcl bindings 31 k).

### Tcl/Tk — recommendation: do **not** make replacing it a precondition of the port
- Tk *is* the cross-platform layer: it already runs natively on Windows and macOS. Most port cost is in our X11 extensions (§D3), not in Tk itself.
- Replacing Tk means rewriting all 260 k Tcl lines plus the 9 kLOC docking manager — a multi-year rewrite with nothing shippable until it's finished, and the fuzz/test corpus (all Tcl-driven) would be lost.
- If the UI is to be replaced, the target I'd pick is **Tauri (Rust shell + web UI)**:
  - it fits a Rust core;
  - the repo already has `web3d/` and a web front-end plan;
  - it gives native Win/Mac/Linux packaging and signing for free.
  Migrate it **screen by screen** behind the same core API, not in one go.
- So: port on Tk first (months), and make the UI replacement a separate project that can start after.

### C++ → Rust — recommendation: **strangler, not rewrite**
1. Freeze a C ABI around the core (the Tcl bindings in `src/tcl` already outline it: db, game, pos, engine).
2. Write new code in Rust from now on, linked via `cxx`/C ABI (cargo is already in the build for Reckless).
3. Port first the modules where Rust buys the most: **untrusted-input parsers**.
   - These are where the fuzzers find bugs: PGN reader, CBH/CBV/CBM codecs, `.sci` index reader, zip/gzip (use the `zip`/`flate2` crates).
   - For each module, the existing C++ tests plus the file-mutation fuzzer (`cargo-fuzz` after porting) are the acceptance gate.
4. Leave for last, or for never:
   - `mstl` (replaced by std as callers move);
   - `tk` extensions (gone if the UI moves to Tauri);
   - `cql6` (port of the upstream C++ — keep tracking upstream).
5. Ordering with the port: the Rust work does not block the Windows/macOS port; each ported module simply drops a platform `#ifdef` set.

### Combined end state (if you go all the way)
Rust core (db, formats, engines, search) → C ABI → (a) existing Tk UI during transition, (b) Tauri web UI as the target. Both UIs run against the same core, so users are never left without a working app.

## 5. Open questions for you
- Is MSVC a hard requirement (e.g. for a Store listing), or is MinGW acceptable?
- Apple Developer account for notarization — yes/no?
- Keep the 3D Togl board on Linux only, or drop Togl everywhere in favour of WebGL?
- Ship Sjeng (non-free licence terms?) in Win/Mac installers?
