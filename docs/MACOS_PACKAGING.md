# macOS distribution

Run on a Mac with the Xcode command line tools. All dependency downloads use
`scripts/sysroot-pins.sh`, shared with the Windows sysroot builder. Cached
archives are verified on every invocation. Builds use deployment target 11.0.

From a configured native Aqua build, first build the AVFoundation backend:

```sh
export MACOSX_DEPLOYMENT_TARGET=11.0
make -C src -j16 MEDIA_BACKEND=avf
scripts/build-macos-tls.sh "$HOME/cw/sysroot" x86_64
scripts/build-macos-engines.sh
scripts/make-macos-app.sh . "$HOME/cw/Chesswiz.app" "$HOME/cw/sysroot"
```

The last command also writes `~/cw/Chesswiz.dmg`. The app has the same script
and data installation targets as the Windows folder, private fonts, Tcl/Tk
script libraries, tcllib 2.0 JSON, patched TclTLS 1.7.22 with static OpenSSL
3.5.9, pinned Mozilla CA roots, and Stockfish with embedded NNUE. Tcl/Tk are
linked statically into the executable. System Apple frameworks remain OS
provided. `CHESSWIZ_VERSION`, `CHESSWIZ_DMG`, and the engine directory (fourth
argument) are configurable. Stockfish defaults to both architectures;
`SF_ARCHS=x86_64` builds only Intel. Scratch builds live under `build/`.

For universal2, use a separate source copy and runtime prefix. From the VM
layout described above (the Intel prefix already has Tcl/Tk):

```sh
scripts/build-macos-runtime.sh "$HOME/cw/sysroot-universal"
scripts/build-macos-tls.sh "$HOME/cw/sysroot" x86_64
scripts/build-macos-tls.sh "$HOME/cw/sysroot-universal" arm64
scripts/lipo-macos-tls.sh "$HOME/cw/sysroot" "$HOME/cw/sysroot-universal"
scripts/build-macos-app-binary.sh "$HOME/cw/chesswiz-universal" \
  "$HOME/cw/sysroot-universal"
scripts/make-macos-app.sh "$HOME/cw/chesswiz-universal" \
  "$HOME/cw/Chesswiz.app" "$HOME/cw/sysroot-universal" \
  "$HOME/cw/chesswiz/build/engines-macos"
```

The binary builder removes all old `.o`/`.a` files before configuring the
scratch source copy, compiles with both clang architecture flags, extracts the
two executable slices and recombines them with `lipo`. A third argument of
`x86_64` selects an Intel-only build. **Do not point this builder at a working
source tree containing build artifacts you want to preserve.**

See `tests/tmp-app/macport/pkg-report.md` for the verified architectures and
runtime tests. Apple Silicon and macOS 11 runtime behavior need separate
hardware/VM testing; the Intel macOS 15 VM can inspect the arm64 slice but
cannot run it.

## Signing and notarization

By default every Mach-O binary (including TLS and engines) is signed ad hoc,
then the app is signed and its signature verified. To use a configured
Developer ID Application certificate instead:

```sh
CHESSWIZ_SIGN_ID='Developer ID Application: Your Name (TEAMID)' \
  scripts/make-macos-app.sh . "$HOME/cw/Chesswiz.app" "$HOME/cw/sysroot"
```

This adds hardened runtime and a secure timestamp and signs the DMG too.
Developer ID signing and notarization are not exercised by the VM tests.
The following are manual release steps, following Apple's
[custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
and [distribution requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
Use a Keychain credentials profile prepared separately; no credentials belong
in the repository:

```sh
xcrun notarytool submit "$HOME/cw/Chesswiz.dmg" \
  --keychain-profile chesswiz-notary --wait
# Only after an Accepted result:
xcrun stapler staple "$HOME/cw/Chesswiz.dmg"
xcrun stapler validate "$HOME/cw/Chesswiz.dmg"
spctl --assess --type open --context context:primary-signature \
  --verbose "$HOME/cw/Chesswiz.dmg"
```

For a separately distributed app, submit a `ditto -c -k --keepParent` ZIP of
the signed app and staple the app after acceptance. A DMG ticket does not
staple a separate loose copy of the app. Review `notarytool log` if the
submission is rejected. None of these commands run in the assembler.
