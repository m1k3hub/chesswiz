cql(input hhdbvi.pgn quiet)
/* OLD VERSION OF snake.cql USING CQL 6.1*/

/*Find the snake theme allowing gaps between moves. A snake theme begins
by a move from a piece T in a diagonal direction D. A secondary direction D' that is 90 degrees rotated from D is chosen. Subsequently, T alternately moves in directions D and D', with possibly non-T moves intervening. There are at least 5 T moves.

Results are sorted by number of T moves in the line. The file can be slightly modified to sort by number of gaps.

The T moves are commented, which requires most of the code here oddly enough.

This file runs single-threaded because a dictionary is retained of the theme moves seen. Unfortunately, nestgap does not fully work in this case due to the use of ✵: some spurious comments are added.
*/

//First move in theme
function First(){ 
  move from T to northeast 1 T
  }

//Second move in theme
function Second(){
  move from T to southeast 1 T
}

//nonthematic move inside thematic line
function Filler(){
  move from ~T}

//Start main part of program
dictionary ThemeDict // a dictionary to clean up commenting. Each entry
                     // is a position in a theme line already seen

not ThemeDict[fen] // cleans up commenting, to make sure we have not seen
                    //this position with another orientation (choice of D)


//The next two filters do all the work. The rest of the file is just commenting

piece T = move from . //thematic piece
✵
 LastPosition=line lastposition singlecolor
   --> First()
   --> (Filler()* --> Second() --> Filler()* -->First()){2,}
   --> (Filler()*-->Second())?

// end the actual work

//LastPosition is the last thematic position, from which theme piece moves

//Count thematic moves and gaps for commenting and sorting
ThemeCount=0 // # thematic moves
find all {currentposition<=LastPosition
          move from T  // count thematic moves
          ThemeCount+=1
          child:comment ("thematic move #" ThemeCount)
	  ThemeDict[fen]="seen"
	  }

GapCount=find count // count the number of gap moves
     {currentposition<=LastPosition
      sidetomove==LastPosition:sidetomove
      not move from T}

Start=currentposition //start of thematic line
LastPosition:child:comment ("Final thematic move from line starting at " Start)
//////////sorting: you can sort by #gaps or by #theme moves

/* comment out one of the following lines to sort
   by #theme moves or by # gap moves
*/

sort "Thematic moves" ThemeCount>=5 
//ThemeCount>=5 and sort "Gaps" GapCount

comment("Start of line with "
          ThemeCount " thematic moves and "
          GapCount " gaps")
   