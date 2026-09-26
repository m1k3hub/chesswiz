# Stockfish for Scidb

This directory is the engine Scidb builds and installs as
`stockfish-scidb` (see `engines/Makefile`, `ENGINES` in `Makefile.in`).

## What it is

The official **Stockfish 19** release (tag `sf_19`, commit `edb0d9d`,
2026-09-05): `src/`, `scripts/`, `AUTHORS`, `Copying.txt`, `README.md`,
`CITATION.cff`, unchanged except for one Scidb addition:

- **`narrate`** UCI command: prints a JSON description of the current
  position (material, pawn structure, control, king safety) for the
  language layer (`tcl/ai-narrate.tcl`). It is shadow-only and never
  touches search or evaluation. Files: `src/narration.cpp`,
  `src/narration.h`; hooks: `Engine::narrate()` in `src/engine.{h,cpp}`,
  the `narrate` token in `src/uci.cpp`, and `narration.cpp`/`.h` in
  `src/Makefile`.

`./stockfish bench` gives **2497913** nodes, the signature of the
`sf_19` release, so search and evaluation are unchanged.

## Building

```bash
make -C engines/stockfish                    # -> engines/stockfish/stockfish-scidb (and src/stockfish)
make -C engines/stockfish SF_ARCH=x86-64-avx2   # portable build for other machines
sudo make -C engines/stockfish install       # -> $(ENGINESDIR)/stockfish-scidb
```

The network (`nn-1a298aa575a0.nnue` for sf_19) is embedded in the binary.
`src/Makefile` downloads it when `src/` lacks it, so the first build needs
curl or wget and network access, or the file copied into `src/`.

## Updating to a newer Stockfish

1. Export the new tag's `src scripts AUTHORS Copying.txt README.md
   CITATION.cff` over this directory (e.g. `git archive sf_20 ... | tar -x`).
2. Re-apply the `narrate` hooks listed above (four small edits).
3. Check `./stockfish bench` against the node count in the release commit.
4. Update the Stockfish entry of `tcl/engines/engines.dat` (identifier,
   variants, features, options), e.g. by probing the binary from Scidb.

The previous tree here (Stockfish 6 sources plus an untracked fork of
Stockfish master with `narrate`) was moved to
`engines/stockfish-fork-2026-09/` on 2026-09-26.
