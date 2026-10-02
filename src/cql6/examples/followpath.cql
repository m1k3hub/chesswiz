/*
 Two non-king, non-pawn pieces T1 and T2 trace identical non-intersecting
 paths in the same order. The path length must be at least 3.

 Method:
  From a given position C, local dictionary D holds the each element of the T1 path
  starting at C: D[1] is the first destination square, D[2] the second and so on.
  The 'local' means that the dictionary is run fresh on each game, it is not
  persistent in other words. This lets the code run multithreaded.

  Next, a sort on an echo (source target) is done to find all T2 such
  that, beginning at position target, T2 traverses as many D[1], D[2], D[3],...
  paths as it can. The length of this second path is held in the
  variable PathLength.

  Both traversed paths, T1 and T2 are then output (only the first PathLen
  squares of the T1 path is output).
*/  

cql(input hhdbvi.pgn quiet)
local dictionary D
unbind D
Seen=[]
◭T1=♖♘♗♕♜♞♝♛――(from)

⊢◎T1
 ―― not to∩Seen
    Seen=Seen∪to
    D[pathcount]=to {3,}

sort "path length"
 echo(source target){
  target>source
  piece T2= ~T1――(from)
  typename T2==typename T1
  PathLen=
   ⊢◎T2 title "T2" piecepath
    ―― D[pathcount]==to {3,}

  source: ⊢ title "T1" ◎T1 piecepath
    ―― pathcount ≤ PathLen +
 }
 