   /* Theme based on Ding Liren 41. d5! in game 6 of the 2023 FIDE
   Championship versus Ian Nepomniachtchi.
   See https://www.chessgames.com/perl/chessgame?gid=2477747 ,
   specifically in the variation after 44. Qf7 Qg5 45. Qxg8+ Kxg8
   46. Ra8+ Kf7 47. Rf8#

   Theme definition:
   
   A white pawn T moves for the last time. The black king is not in
   check, nor does T attack a square in the black king's field. Later,
   the black king is in model mate with some  square in its field
   guarded by T.
*/

cql(input hhdbvi.pgn quiet)
◭T∊♙a-h2-4
  ⊢ T――□       ///"thematic pawn move"
     not T→(▦←♚)
     not check
   ~T―― +
     modelmate ///"model mate guarded by " T
     T→(▦←♚)

