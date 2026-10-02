#pragma once

/* This file MUST TRACK the file mates/matefunction-cql. It eliminates the cql() header and some tests at the end*/
const string MateFunctionString=
  R"~~~~(
{
  function cql_KingsField(){a-h1-8<-k}

function cql_Checkers(){A->k}

/* all squares in the king's field guarded by a white piece x*/

function cql_GuardedSquares(x){
  (cql_KingsField()<-x)
    | (cql_KingsField()<-k<-x)
    }

/*all white pieces guarding the square s in the black king's field)*/
  function cql_GuardingPieces(s) { 
  square cql_Fy in A
   s&cql_GuardedSquares(cql_Fy)
}
     

// every flight square guarded exactly once
function cql_FlightSquaresGuardedOnce(){
  square all cql_FlightSquare in cql_KingsField()&[_A]
   cql_GuardingPieces(cql_FlightSquare)==1
}

//every selfblocker is either unguarded, or, if it is not double check,
// (a) pinned and (b) could interfere with a checker

function cql_SelfBlockersUnguarded(){
  square all cql_SelfBlocker in cql_KingsField() & a {
   cql_SelfBlockerGuards=cql_GuardingPieces(cql_SelfBlocker)
   if cql_Checkers()>1 
     cql_SelfBlockerGuards==0
   else{ //single-check case
    cql_SelfBlockerGuards==0
    or
     {cql_SelfBlockerGuards==1
      pin through cql_SelfBlocker
      pseudolegal
       cql_SelfBlocker--{cql_Checkers()|between(cql_Checkers() k)}
      or pseudolegal cql_SelfBlocker--(enpassant)
      }
   } // end the single-check case
  } //end considering the cql_SelfBlocker
}
  /* a (white) checker is cql_Necessary if there is some
  nonpinned black piece that can capture another checker or
  can interpose between another checker and the black king
*/

function cql_Necessary(checker){
  cql_OtherChecker=cql_Checkers() & ~checker
    cql_RefutationSquares= cql_OtherChecker | between (cql_OtherChecker k)
    cql_NonPinnedBlackPiece= {a & ~pin} & ~k
    cql_NonPinnedBlackPiece->cql_RefutationSquares
    }                       

/* cql_This test verifies that if there is a double check, then both
   checkers are cql_Necessary */

function cql_NecessaryDoubleCheck(){
  if cql_Checkers()>1 
	       square all cql_Checker in cql_Checkers()
	       cql_Necessary(cql_Checker)
	       }

function cql_WhiteParticipants(){
  square  cql_Attacker in A
    cql_Attacker in cql_Checkers()
    or cql_Attacker->cql_KingsField()
    or pin through cql_Attacker
    or cql_Checkers() ==1
    and pin from cql_Attacker through cql_PossibleRefuters()
    or cql_Checkers()==1
    and cql_PossibleRefuters()->cql_Attacker->cql_RefuterSquares()
    }


function cql_BlackParticipants(){
  square X in a 
    X==k or
    X in cql_KingsField() or
    a->X->K or
    cql_Checkers()==1 and
    a->X->cql_RefuterSquares()
}

function cql_Participants(){
  cql_WhiteParticipants()|cql_BlackParticipants()
}

function cql_PureMate(){
  btm mate
  cql_FlightSquaresGuardedOnce()
    cql_SelfBlockersUnguarded()
    cql_NecessaryDoubleCheck()
}
 
/* cql_The code above this line is identical to puremate.cql */

function cql_RefuterSquares(){
  K |
    cql_Checkers() |
    between(cql_Checkers() k)
    }

function cql_PossibleRefuters(){
  square cql_TmpSquare in a
    pseudolegal cql_TmpSquare--cql_RefuterSquares()
    }


function cql_ModelMate(){
  cql_PureMate()
  [RNBQ] in cql_WhiteParticipants()
}  

function cql_IdealMate(){
  cql_PureMate()
    A==cql_WhiteParticipants()
    a==cql_BlackParticipants()
    }

function cql_TruePureMate(){
 flipcolor {cql_PureMate() cql_Participants()}
 }

function cql_TrueModelMate(){
 flipcolor {cql_ModelMate() cql_Participants()}
 }

function cql_TrueIdealMate(){
 flipcolor {cql_IdealMate() cql_Participants()}
}

function cql_PureStalemate(){
  btm stalemate
  cql_StalemateSelfBlockers= a & cql_KingsField()
  cql_PossibleFlightSquares=cql_KingsField() & [A_]
  square all cql_FlightSquare in cql_PossibleFlightSquares
     A->cql_FlightSquare==1
  square all cql_SelfBlocker in cql_StalemateSelfBlockers & pin
    A->cql_SelfBlocker==1
  square all cql_SelfBlocker in cql_StalemateSelfBlockers & ~pin
    not A->cql_SelfBlocker
}
  
function cql_StalemateWhiteParticipants(){
 pin through A
 | pin from A
 | (A->cql_KingsField())
}

 function cql_TruePureStalemate(){
    flipcolor {cql_PureStalemate() cql_StalemateWhiteParticipants()|a}
}    


function cql_ModelStalemate(){
     cql_PureStalemate()
     [RBNQ] in cql_StalemateWhiteParticipants()
}

function cql_TrueModelStalemate(){
     flipcolor {cql_ModelStalemate() cql_StalemateWhiteParticipants()|a}
}     

function cql_IdealStalemate(){
     cql_PureStalemate()
     A==cql_StalemateWhiteParticipants()
}

function cql_TrueIdealStalemate(){
   flipcolor {cql_IdealStalemate() cql_StalemateWhiteParticipants()|a}
}  
} 
)~~~~";
