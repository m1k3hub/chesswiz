/*
 Reciprocal promotions (partial Babson theme). Black promotes to a type. On the
 next move, White promotes to the same type as a primary move.  This
 happens with at least two different types.  Sorting by number of
 reciprocal promotion types, at least 2.

 For a shorter version, see babson3.cql
*/ 

cql(input hhdbvi.pgn variations quiet)
   
NTypes=0 // number of types seen

if {⊢♟――=♗         ///"bishop promotion"
     ♙――=♗ primary ///"Bishop reciprocal promotion"
   } NTypes+=1

if {⊢♟――=♖         ///"rook promotion"
     ♙――=♖ primary ///"Rook reciprocal promotion"
   } NTypes+=1

if {⊢♟――=♘         ///"knight promotion"
     ♙――=♘ primary ///"Knight reciprocal promotion"
   } NTypes+=1

if {⊢♟――=♕         ///"queen promotion"
     ♙――=♕ primary ///"Queen reciprocal promotion"
   } NTypes+=1

sort "Number of reciprocal promotions" NTypes≥2
