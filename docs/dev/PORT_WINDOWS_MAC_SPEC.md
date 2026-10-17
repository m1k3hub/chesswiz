# Windows / macOS port and rename — design decisions

**Rename done (2026-10-09): the product is Chesswiz.** Programs `chesswiz`/`tkchesswiz`/`tclchesswiz` (`PROGRAM` in Makefile.in, `--program=` in configure), share dir `/usr/share/chesswiz`, user dir `~/.chesswiz` (first start copies `~/.scidb-beta` or `~/.scidb` and rewrites the paths in its settings), desktop entry and icon `chesswiz`, Debian package `chesswiz` (Provides/Replaces/Breaks `scidb-beta`). Kept: `::scidb::*` code names, Tk class `Scidb` of dialogs, font families `Scidb *`, the `.sci` format and its name, upstream URLs and credits. Open: the help pages (`tcl/help/*`) still say Scidb.

Status: proposal, 2026-10-09. Facts below were surveyed from the tree at `bb30e5e`.

## 0. Status (2026-10-11)

| | Windows | macOS |
|---|---|---|
| Build | Zig cross build from Linux (`build/wt-win`) | native Apple clang, static Aqua Tk 8.6.17; universal2 via `scripts/build-macos-app-binary.sh` |
| Package | folder (`make-windows-dist.sh`) + Inno Setup installer (`chesswiz.iss`), both built by CI | `.app` + DMG (`make-macos-app.sh`), ad-hoc signed; Developer ID/notarization wired, needs an Apple account |
| Verified on the real OS | Win 11 VM: startup, databases, fonts (private), Stockfish, MP4/WMV playback, HTTPS, credentials, installer; CI windows-latest launch | macOS 15 Intel VM: startup, media, HTTPS, Stockfish, credentials; CI macos-14 (arm64) build + launch |
| Open | — (pane-zoom glyph and native file dialogs checked on Win 11, 2026-10-11) | Apple Silicon only checked by CI launch; X11-only features are logged no-ops |

CI: `.github/workflows/port.yml` on github.com/m1k3hub/chesswiz (private); Zig comes from the
`toolchain-zig-0.16.0-dev.3133` release (checksum `.zig-sha256`). Release blockers that remain
are licensing, not porting: see `docs/legal/ASSET_LICENSE_AUDIT.md` and the splash artwork.

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
| Reckless engine | Rust (`engines/reckless`) | stays Rust (third-party engine); cargo cross-builds it, and `cargo-zigbuild` can use the Zig linker; ship prebuilt |
| Network (assistant, downloads) | `http::geturl` + `tls::` (tcltls) | Bundle tcltls with OpenSSL (Win) / use it on Mac too |

## 2. Decisions to make (recommendation first)

### D1. Toolkit version — **Tcl/Tk 8.6.x, bundled**
- 8.6 is what Linux builds use (`TCL_VERSION = 8.6`). 8.7/9.0 change the C API (Tcl_Size, UTF-8) and would add churn across 410 files.
- Ship a private Tcl/Tk (not the system one): macOS system Tk is deprecated/ancient; Windows has none.

### D2. Build system — **Zig toolchain (`zig cc` / `zig c++`), cross-compiling from Linux** (decided 2026-10-10)
- All three platforms are built from one Linux machine with Zig as the C/C++ compiler and linker: `CC="zig cc -target x86_64-windows-gnu"`, `aarch64-macos`, `x86_64-macos`, `x86_64-linux-gnu.2.31`. Zig bundles clang, libc++, the MinGW-w64 headers and import libs and the macOS libc stubs, so there is no MSYS2 install, no Xcode on a build Mac and no per-OS compiler drift.
- The existing `configure` / `Makefile.in` stay. A `--toolchain=zig --target=<triple>` option sets `CC`/`CXX`/`AR`/`RANLIB` and the platform blocks. GCC-isms (`__attribute__`, `-Wl,-rpath`) work under clang.
- Third-party C dependencies (Tcl/Tk 8.6, zlib, expat, OpenSSL for tcltls) are built from source with the same toolchain into a per-target sysroot, `build/<triple>/`. Prebuilt system libraries aren't used, which also makes builds reproducible.
- Windows target is the GNU ABI (`-windows-gnu`, MinGW-compatible). MSVC ABI is only needed if a Store listing or a third-party MSVC-only library demands it (see open questions).
- macOS: cross-compiled binaries still need **codesigning and notarization**, which run on a Mac or a macOS CI runner (`codesign`, `notarytool`); only the compile step moves to Linux.
- Pin the Zig version (`.zig-version` plus a CI check). Zig is pre-1.0 and every release can break the build; upgrade deliberately, one release at a time.
- Known gotcha: `configure` splits `OPTIMIZE=` at the second `=`; fix that parser while touching it.
- Known Windows blocker: `src/mstl/m_uint128_t.h` assumes `long` is 64-bit. Windows is LLP64, so under `x86_64-windows-gnu` it fails (`no type named 'uint128' in namespace 'mstl'`, redefinitions of `numeric_limits<int>` and `is_integral<int>`). Fix it with fixed-width types (`uint64_t`, `unsigned __int128`) before the first Windows build.

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
- **Done:** the name is now set at build time (`USERDIRNAME`, default `.` + basename of `DATADIR`, i.e. `.chesswiz`), and `SCIDB_USERDIR` overrides it. The launcher no longer derives its binary from its own name either: the binary name is substituted at build time (`TKPROGRAM`, default `tkchesswiz`) and symlinks are followed to the real script.
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
- **Media codecs — decided: the OS decoders.** Bundling libmpv/FFmpeg would make Chesswiz distribute H.264, HEVC, VC-1 and AAC decoders, which have live patent pools (`docs/legal/PATENT_REVIEW.md`). So the build picks a backend with `MEDIA_BACKEND`, and all three implement the same `::mpv::*` commands, so the Tcl media pane is unchanged:
  - `mpv` (default, Linux): `src/tcl/tcl_media.cpp`, `-lmpv`.
  - `mf` (Windows): `src/tcl/tcl_media_mf.cpp`, Media Foundation MFPlay rendering into the Tk window's HWND; links `-lmfplay -lmfplat -lole32 -luser32`. Windows decodes WMV/VC-1, H.264, AAC and MP3 itself; HEVC needs Microsoft's HEVC extension. Compiles cleanly with `zig cc -target x86_64-windows-gnu -Wall -Wextra`, and every MF import resolves against Zig's MinGW import libraries. Not yet run on Windows.
  - `avf` (macOS): `src/tcl/tcl_media_avf.mm`, AVPlayer with an AVPlayerLayer placed over the Tk window inside the toplevel's NSView; links the AVFoundation, CoreMedia, QuartzCore and AppKit frameworks. **Not compiled yet** (needs the macOS SDK). macOS has **no WMV/ASF decoder**, and those are the most common ChessBase lesson format: they report a load error, and the pane says to use "Open externally" (e.g. VLC). Revisit if WMV9/VC-1 patents are confirmed expired: a restricted FFmpeg with only the WMV decoders could then be added for macOS.

**Confirmed 2026-10-17:** Windows uses `MEDIA_BACKEND=mf` and macOS uses
`MEDIA_BACKEND=avf`; never bundle libmpv, FFmpeg or libVLC. Windows uses
Media Engine for links (including HLS), and macOS uses AVPlayer URL sources.
YouTube/Twitch links and links the OS backend cannot play open in an installed
VLC first, otherwise the default browser/OS handler.

### D9. Credentials — **OS keychain**
- API keys currently live in `user/config/ai-keys` (plain file). On Win/Mac use Credential Manager / Keychain (via a tiny C shim), file fallback on Linux (or libsecret).

### D10. CI — **implemented, running on GitHub** (GitHub Actions)

`.github/workflows/port.yml` is separate from the existing opening-report CI.
Its Linux job installs Tcl/Tk 8.6 development packages and the dependencies
listed in `INSTALL`/`configure`, builds `src` and the Tcl bundle, and runs
`make -C tests tcl` and `make -C tests app-tcl` under Xvfb.

The Windows cross job verifies the `.zig-version` release against the upstream
ziglang.org download index and SHA-256 before installing it, builds the pinned
sysroot and app with static Tcl/Tk and Media Foundation, builds Stockfish, and
uploads `build/dist/Chesswiz`. Dependency archives in `build/src` are cached
with a key derived from `scripts/sysroot-pins.sh`; builders recheck hashes.
`windows-test` downloads that folder and launches the packaged executable.

The `macos-14` Apple Silicon job builds the Aqua runtime, arm64 TLS, app binary
and Stockfish following `docs/dev/MACOS_PACKAGING.md`, assembles the app/DMG, and
runs the smoke test through the app launcher before uploading `Chesswiz.dmg`.
Both native smoke tests use `tests/smoke/launch-smoke.tcl`: source the packaged
bundle, poll until `.application` maps, write `OK`, and exit. A 60-second Tcl
timer and a 90-second external process timeout fail hung launches.

Developer ID signing is enabled only with `CHESSWIZ_SIGN_ID`; otherwise the
assembler uses its normal ad-hoc signature. The signing certificate and private
key must already be available in the runner keychain. Notarization additionally
requires `CHESSWIZ_NOTARY_APPLE_ID`, `CHESSWIZ_NOTARY_PASSWORD` (app-specific),
and `CHESSWIZ_NOTARY_TEAM_ID`. Step conditions use environment copies of secrets
because GitHub does not allow direct `secrets` references in `if` expressions.
No signing credentials or certificates are included in artifacts.

**Current blocker:** the pinned development Zig
`0.16.0-dev.3133+5ec8e45f3` is absent from the current upstream download index,
and its ziglang.org builds URL returns HTTP 404. Windows CI fails explicitly
until the toolchain owner deliberately updates the pin to an available version
or supplies an immutable verified archive. CI never silently substitutes a
new Zig version. Local validation and Linux reproduction results are recorded
in `tests/tmp-app/d10/report.md`. The fresh Linux build and app suite pass
(732 passed, 6 skipped); the Tcl suite has one existing audit failure because
its `make cpp` correspondence test does not link `crc32` from system zlib
(174 passed, 1 failed, 7 skipped). That test remains a CI gate. Hosted
Windows/macOS execution remains pending.

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
3. Zig cross-build (D2) compiles with X11 stubs (D3 step 1) → app starts on Windows, then macOS.
4. D6 exec replacements, D5 polling, D4 WebGL server in Tcl.
5. macOS `.app` build; signing/notarization.
6. Installers, CI matrix, keychain.

## 6. Replace Tcl/Tk? Move C++ to Zig? (decided 2026-10-10: **Zig**, not Rust)

Size today: **~260 k lines of Tcl** (UI and app logic), **~490 k lines of C++** (db 177 k, tk extensions 133 k, cql6 59 k, util 47 k, mstl 34 k, tcl bindings 31 k).

### Tcl/Tk — do **not** make replacing it a precondition of the port
- Tk *is* the cross-platform layer: it already runs natively on Windows and macOS. Most port cost is in our X11 extensions (§D3), not in Tk itself.
- Replacing Tk means rewriting all 260 k Tcl lines plus the 9 kLOC docking manager. That's a multi-year rewrite with nothing shippable until it's finished, and the fuzz and test corpus (all Tcl-driven) would be lost.
- If the UI is replaced later, the target is a **web UI in the system webview**, driven from Zig through the `webview/webview` C library (WebView2 on Windows, WKWebView on macOS, WebKitGTK on Linux):
  - the repo already has `web3d/` and a web front-end plan;
  - it adds no Rust/Tauri toolchain to a Zig project;
  - packaging and signing reuse D8.
  Migrate it **screen by screen** behind the same core API, not in one go.
- So: port on Tk first (months), and make the UI replacement a separate project that can start after.

### C++ → Zig — **strangler, not rewrite**
Why Zig:
- **Interop:** `@cImport` reads the C headers directly. Zig code exports a plain C ABI that the C++ core and the Tcl bindings call with no glue layer. The same toolchain (D2) already builds the C++.
- **One toolchain:** the language and the cross-compiler are the same install, so every ported module is cross-compiled for free.
- **The user already works in Zig.**

What Zig does *not* give, and how we cover it:

| Risk | Mitigation |
|---|---|
| No compile-time memory safety (Rust's main advantage for untrusted-input parsers) | Ship parsers built **`ReleaseSafe`** (bounds, integer overflow, optional-unwrap and `unreachable` checks stay on in release). Use slices, never raw `[*]` pointers, in parser code. Every allocation goes through an explicit allocator; tests use `std.testing.allocator`, which fails on any leak or double free. |
| Use-after-free isn't caught by `ReleaseSafe` | Parsers return owned, arena-allocated results (`std.heap.ArenaAllocator` per file read), so nothing is freed piecemeal. Run the fuzzer against `std.heap.DebugAllocator` (named `GeneralPurposeAllocator` before 0.14) configured with `.safety = true, .never_unmap = true, .retain_metadata = true`. That reports double frees and use-after-free during testing. |
| Pre-1.0 language churn | Pin the version (D2); one deliberate upgrade per release; keep Zig code behind the C ABI so a breaking change never reaches the C++ or Tcl side. |
| Thinner library ecosystem | Keep proven C libraries (zlib, expat, minizip, libharu, OpenSSL) and call them through `@cImport` rather than rewriting them. Use `std` where it suffices (`std.compress.flate`, `std.zip`, `std.unicode`). |

Plan:
1. **Freeze a C ABI around the core.** The Tcl bindings in `src/tcl` already outline it: db, game, pos, engine. Put it in one header, `src/abi/chesswiz.h`; both the C++ and the Zig side build against it.
2. **Add a Zig build** (`build.zig`) that produces a static library (`libchesswiz_zig.a`). The existing makefiles link it into `tkchesswiz`, so new code can be written in Zig from day one.
3. **Port the untrusted-input parsers first**, where the fuzzers have found the bugs: the PGN reader, the CBH/CBV/CBM codecs, the `.sci` index reader and zip/gzip handling.
   - Acceptance gate per module: the existing C++ tests pass against the Zig implementation, byte-identical output on the fixture corpus (`sas_mirror/fixt/`), and a clean run of the file-mutation fuzzer.
   - Fuzz with Zig's built-in fuzzing (`zig build test --fuzz`), feeding the existing `filefuzz/` corpus as seeds.
   - Keep the C++ implementation behind a build flag until the Zig one has shipped one release.
4. **Leave for last, or for never:**
   - `mstl` (disappears as its callers move);
   - the `tk` extensions (gone if the UI moves to a webview);
   - `cql6` (a port of the upstream C++; keep tracking upstream).
5. **Ordering with the port:** the Zig rewrite doesn't block the Windows/macOS port. The port starts by *compiling* the C++ with Zig (D2). Each ported module then removes a platform `#ifdef` set.

### Combined end state (if you go all the way)
Zig core (db, formats, engines, search) → C ABI → (a) the existing Tk UI during the transition, (b) a webview UI as the target. Both UIs run against the same core, so users are never left without a working app.

## 5. Open questions for you
- Is the MSVC ABI a hard requirement (e.g. for a Store listing), or is the GNU ABI that `zig cc -target x86_64-windows-gnu` produces acceptable?
- Apple Developer account for notarization — yes/no?
- Keep the 3D Togl board on Linux only, or drop Togl everywhere in favour of WebGL?
- Ship Sjeng (non-free licence terms?) in Win/Mac installers?
