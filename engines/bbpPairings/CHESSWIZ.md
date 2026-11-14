# Chesswiz helper source pin

Unmodified upstream v6.0.0 source, commit
16a000f9811de322b0e835d5643198226165b5a9.
https://github.com/BieremaBoyzProgramming/bbpPairings

Build offline: bash scripts/build-bbp-pairings.sh (from the Chesswiz root).
Optional targets: x86_64-windows-gnu, x86_64-macos, aarch64-macos.
Install the executable beside tkchesswiz, or set SCIDB_BBP_PAIRINGS to its path.
Distribute LICENSE.txt, Apache-2.0.txt and runtime-notices alongside the binary.
Only --dutch is exposed by Chesswiz; Burstein is outside its supported scope.

The upstream OMIT_BURSTEIN build option is broken in this release's TRF module,
so the build retains upstream defaults without enabling Burstein in the app.
The Dutch C5/C9 regression fixtures are upstream examples, not falsely labelled
as FIDE-authored worked examples.
