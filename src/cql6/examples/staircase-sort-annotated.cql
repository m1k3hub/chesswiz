/*********
Find queen staircases with possible gaps between the steps.

Like staircase-sort, but with more comments. In particular, the path
of the queen is given at the start.

(Technically we should use a piece variable to loop over the queens in
the positions, but usually there is just one queen of a given color).

Here, the 'verbose' means to annotate each move separately.  The
'piecepath' means to include the path of the queen at the start in the
PGN file, like 'queen staircase: Qa1-a2-b2-b3-c3-c4'

***********/

cql(input hhdbvi.pgn quiet)
✵⬓
  8≤sort "staircase size"
   ⊢◎♕ title "queen staircase" verbose nestban piecepath
   (――up 1 ♕
    ――right 1 ♕)+
    ――up 1 ♕ ? 



