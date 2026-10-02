/*
 Reciprocal promotions (Babson theme)
 Black promotes to a type. On the next move, White promotes to the same type as a
 primary move.
 This happens with at least two different types.
 Minimal output annotations.
*/ 

cql(input hhdbvi.pgn variations)
/* if black can promote to type T, followed by a white primary promotion to T,
   then increment the variable NTypes. This function always matches*/
   
function IsBabson(T){
 if ⊢♟――=T
     ♙――=T primary

  NTypes+=1
}

NTypes=0
IsBabson("Q")
IsBabson("R")
IsBabson("B")
IsBabson("N")
sort "# reciprocal promotions" NTypes≥2
