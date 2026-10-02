/*
 Reciprocal promotions (Babson theme)
 Black promotes to a type. On the next move, White promotes to the same type
 as a primary (first) move. This happens with at least two different types.
 The output includes the types promoted to in the comments
*/

cql(input hhdbvi.pgn variations quiet)
Ts="" //reciprocal promotion types seen so far

//set T successively to each possible type..
while ("RBNQ"~~"."){
 T=\0 //current type
 ⊢
  ♟――=T
      ///"thematic black promotion to " T
  ♙――=T primary
      ///"thematic reciprocal white promotion"
      if not T in Ts
       Ts+=T // Add T to Ts if no already there
}//while(...)
sort "#types: " #Ts≥2 // sort by number of types seen, if at least 2
///"Babson with types: " Ts
