/*******
This is a simple version of a Queen/Bishop bristol.
T is a particular bishop selected with the piece filter at the start.
diagonal 1 T is all the squares diagonally adjacent to T
Q ∩ diagonal 1 T means the queen is diagonally adjacent to T
*******/

cql(input hhdbvi.pgn )

 ◭T∊♗ ⊢♕ ∩ diagonal 1 T
       T――
       ▲―― T→♕
       ♕――diagonal 1 T 

