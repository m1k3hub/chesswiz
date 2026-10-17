Tactics trainer tests run without a model, GPU, or chess engine process:

```
tclsh tests/test_tactics_trainer.tcl
```

This uses deterministic chess-facts and engine adapters. To exercise real move
legality and the Tk board, run in the application shell with a working display:

```
xvfb-run -a /usr/local/bin/tkchesswiz tests/test_tactics_trainer.tcl
```

Set `TACTICS_TEST_TMP` to an authorized scratch directory to enable the disk
persistence roundtrip. Progress is data, never sourced as Tcl.

Extras > Tactics Trainer opens FEN-based PGNs. The AI training-set button builds
these from database games; open its exported PGN in the trainer. Both ordinary
SAN mainlines and the training export's UCI `engine line` comments are supported.
Variations, comments, NAGs, and non-FEN games are excluded. Invalid solution
moves reject the import. PGNs should put tag pairs on separate lines.

The solver plays the FEN's side to move. Opponent replies are automatic. A
legal alternative is accepted when its engine score is at least +100cp and no
more than 30cp below the solution, with both child positions searched at depth
16 and scores converted to the solver's perspective. Engine failures leave the
attempt unchanged. Accepted alternatives continue along their own engine PV.

Scores count each puzzle's latest outcome: first try, with retries, or failed.
The streak counts consecutive first-try solves. Wrong moves, showing a solution,
skipping, and closing an unfinished puzzle mark failure. Retry restarts the
original position without restoring first-try eligibility. Failed puzzles lead
the next queue. Puzzle identity is the normalized FEN and solution, independent
of PGN path. Progress lives in `$::scidb::dir::home/training/tactics.dat`.
