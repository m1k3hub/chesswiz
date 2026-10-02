/* In the mainline wtm, a black pawn promotes to a queen.
   After the try, after at least two further primary moves,
   the same pawn promotes to a knight. This theme was suggested
   by Gady
*/   

cql (input hhdbvi.pgn variations quiet)
Start=∙
mainline
◭T∊♟ {
  ⊢ primary
   △―― ///"Holst theme"
   ―― *
   T――=♛ ///"thematic q promotion"
       
 
 ⊢
  △―― secondary ///"thematic try"
   ―― primary {2,}
  T――=♞ primary ///"thematic promotion"
}