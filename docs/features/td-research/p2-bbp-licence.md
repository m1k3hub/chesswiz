# P2 step 0: bbpPairings licence verification

Verified from a fresh clone of https://github.com/BieremaBoyzProgramming/bbpPairings
at v6.0.0, commit `16a000f9811de322b0e835d5643198226165b5a9` (2026-11-14).

Verdict: **compatible with the requested GPL-2-or-later project as a separate
helper program**. LICENSE.txt declares Apache License 2.0 and copyright
2016–2026 Jeremy Bierema; Apache-2.0.txt supplies the terms. It is not MIT.
Apache-2.0 is compatible with GPLv3, available through the GPL-2-or-later
option, **not GPLv2-only**. Keep the helper separately licensed and invoked
through TRF files; do not copy its implementation into Chesswiz.

Primary evidence:
- https://github.com/BieremaBoyzProgramming/bbpPairings/blob/v6.0.0/LICENSE.txt
- https://github.com/BieremaBoyzProgramming/bbpPairings/blob/v6.0.0/Apache-2.0.txt
- https://github.com/BieremaBoyzProgramming/bbpPairings/blob/v6.0.0/Makefile

The Makefile links only C++ sources and compiler/platform runtimes. Retain both
licence files, copyright headers and platform runtime notices with binary
packages. MinGW packaging explicitly appends MinGW-w64 and, where relevant,
winpthread notices. Upstream refuses automatic licence generation for unsupported
toolchains: Zig builds require explicit runtime notice packaging. No binary
redistribution is certified merely by this source-licence verdict.

This qualifies the shorter compatibility statement in regulations.md.

Build evidence: native Linux (GCC), x86_64 Windows GNU (Zig), and aarch64
macOS (Zig) compile successfully. Cross binaries are build artifacts, not yet
runtime-tested on their target OS. Upstream's OMIT_BURSTEIN option fails to
compile v6.0.0; its source is unchanged, and the application invokes only Dutch.
