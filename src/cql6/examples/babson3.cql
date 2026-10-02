/*
 Reciprocal promotions (Babson theme)
 Black promotes to a type. On the next move, White promotes to the same type
 as a primary (first) move. This happens with at least two different types.
 The output includes a summary of all the types promoted to.
*/

cql(input hhdbvi.pgn variations quiet)
Ts="" //reciprocal promotion types seen so far

 ⊢ keepallbest 
  ♟――=△ T=typename to ///"black promotes to " T
  ♙――=T primary       ///"white promotes to " T
      if not T in Ts 
        Ts+=T 

sort "#types: " #Ts≥2 
///"Babson with types: " Ts
