/* Theme based on Ding Liren 41. d5! in game 6 of the 2023 FIDE
   Championship versus Ian Nepomniachtchi.
   See https://www.chessgames.com/perl/chessgame?gid=2477747 ,
   specifically in the variation after 44. Qc7 Qg6 45. Qxg8+ Kxg8
   46. Ra8+ Kf7 47. Rf8#

   Theme definition:
   
   An unattacked white pawn T is more than 4 ranks or files away from
   the black king. T moves without moving again in sound win study,
   reaching an empty square Later, the black king is in pure mate with
   an empty square in its field guarded by T.
*/

cql(input hhdbvi.pgn quiet)
◭T∊♙a-h2-4
  ⊢◎△
   not ▲→T
   T――□       ///"thematic pawn move"
     not T→(▦←♚)∪♚
  ~T―― +
     puremate ///"pure mate guarded by " T
     T→(□←♚)

