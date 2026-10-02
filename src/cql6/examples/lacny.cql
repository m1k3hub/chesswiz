cql(input hhdbvi.pgn quiet variations)
/*
 3-fold Lacny theme in mate-in-2
 After the key:
     black moves x, y, z
 are mated respectively by
       white moves X, Y, Z
 Set play: After initial null move by white,
      black moves x, y, z
 are mated respectively by
      white moves Z, X, Y

 The "current move" is the move whose tail is the current position.
 We identify a "move" with its tail position below.

 key: the White key move (i.e., position after the White key)
 Set: the White null move (i.e., position after that)

 We use two helper functions:
    S(Other) is true if the current move is the Same as the move
     whose tail is Other.

    D(Other) is true if the current move is Different from the
     move whose tail is Other
*/

function S(Other){
   from == Other:from
     to == Other:to
}

function D(other){
  from ≠ other:from or
    to ≠ other:to
}

initial start=∙ wtm
⊢ primary
    ―― key=∙                  ///"key"
    ―― x=∙                    ///"x"
    ―― mate X=∙               ///"X"


key:⊢ 
     ―― y=∙ D(x)              ///"y"
     ―― mate Y=∙ D(X)         ///"Y"
 key:⊢
       ―― z=∙ D(x) D(y)       ///"z"
       ―― mate Z=∙ D(X) D(Y)  ///"Z"
  start:⊢ 
          ―― nullmove Set=∙   ///"null move"
          ―― S(x)             ///"set x"
          ―― mate S(Z)        ///"set Z"
   Set:⊢ 
           ―― S(y)            ///"set y"
	   ―― mate S(X)       ///"set X"
    Set:⊢
	    ―― S(z)           ///"set z"
	    ―― mate S(Y)      ///"set Y"


