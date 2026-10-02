/* two pieces, non-king and non-pawn, follow the same path
   of three distinct squares. The moves need not be consecutive*/

cql(input hhdbvi.pgn quiet)
◭T1=♕♖♘♗♛♜♞♝――(from)

⊢◎T1 piecepath
    ―― x=to
    ―― y=to
    ―― z=to∩~x

find{
 ◭T2=♕♖♘♗♛♜♞♝∩~T1――(from)
 ⊢◎T2 piecepath
    ――x
    ――y
    ――z
}    