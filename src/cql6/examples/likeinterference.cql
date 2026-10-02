/*Theme by Steffen Slumstrup Nielsen.

The white queen T1 checks. A black rook or bishop T2 interposes along
the same line, itself attacking the black king. Then a white rook or
bishop T3 interposes again along the same line, giving check. At the
end, thus, the three thematic pieces and the black king are arranged
in a single line.*/

cql(input hhdbvi.pgn)
◭T1∊♕          //checking queen
 ◭T2∊♜♝        //black interposing piece
   ◭T3∊♖♗      //white final checker
    ⊢◎T1∪T2∪T3
      T1―― T1→♚
      T2―― T2→♚
      T3―― T3→♚
           T1→T2→T3→♚
