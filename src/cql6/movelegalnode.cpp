#include "node.h"
#include "attack.h"

/* Currently this complex constructor returns a set unless the range is nonzero, the range denoting the allowed counts.
   Exactly one of returnfrom or returnto must be true, which denotes which of the from or to sets is returned. 
   The reason for this construction has to do with ease of implementation for a complex method. It is used on CQL 6.1 and earlier
   and so is being retained. note added 10/17/2022 by stiller*. Note that if a set is not wanted, call this inside NonemptyNode/
*/

MoveLegalNode::MoveLegalNode(SetBase* fromn, SetBase* ton, SetBase* enpassant,Range* rn, bool pseudo, bool returnfrom, bool returnto):
  fromNode(fromn),toNode(ton), enpassantSquare(enpassant),range{rn},pseudoFlag(pseudo),returnFrom(returnfrom),returnTo(returnto){
  uassert(fromNode!=NULL && toNode!=NULL,"MoveLegalNode args");
  uassert(returnFrom+returnTo==1,"invalid return requests mln");
}
void MoveLegalNode::compute(QPos*qpos){
  count=0;
  toSquares.clear();
  fromSquares.clear();
  epSquares.clear();
  const pieceT* board=qpos->getBoard();
  colorT tomove=qpos->getToMove();
  SquareMask from1=fromNode->getSquares(qpos);
  SquareMask to1=toNode->getSquares(qpos);
  SquareMask enpassantSquareMask;
  if(enpassantSquare) enpassantSquareMask=enpassantSquare->getSquares(qpos);
  if(from1.empty()||to1.empty()) return;
  SquareMask ok;
  SquareMask colormasks[2];
  squareT kingsquares[2]; // not used, just a placeholder to call masks_from_board
  Attack::masks_from_board(board,colormasks,kingsquares);
  SquareMask from=colormasks[tomove] & from1;
  SquareMask occupied=colormasks[0]|colormasks[1];
  SquareMask empty = ~occupied;
  SquareMask destok=empty | colormasks[1-tomove];
  SquareMask to=to1 & destok;
  if(from.empty()||to.empty()) return;
  //Main loop for each fromsquare in from, first find pseudolegal in fromattacknormal
  //this does not consider castling or en passant
  //We don't have to worry about colors as the wrong colors were masked out
  ForMask(fromsquare,from){
    pieceT frompiece=board[fromsquare];
    SquareMask fromattacknormal;
    bool enpassantseen=false;
    squareT epsquare=64;
    squareT epto=64;
    SquareMask pawnnormal;
    SquareMask castlemask;
    switch(frompiece){
    case WP:case BP:{
      if(!enpassantSquare){
	SquareMask pawnnormal=Attack::pawnNormalMove(fromsquare,occupied,tomove);
	SquareMask pawnnormalattack = Attack::pawnAttacks(fromsquare,tomove) & occupied;
	fromattacknormal = (pawnnormal | pawnnormalattack) & to;
      }
      enpassantseen=Attack::enpassantAttack(qpos, fromsquare, board, &epsquare, &epto,pseudoFlag);
      if (enpassantseen &&
	  enpassantSquare &&
	  !enpassantSquareMask.member(epsquare))
	enpassantseen=false;
      /*CQLI9.198-1 Reported by Gamble 8/12/2019 check epto against to mask*/
      if (enpassantseen){
	uassert(square_valid(epto),"movelegal enpassant attack");
	if(!to.member(epto))enpassantseen=false;
      } // end enpassantseen to check
      break;
    }
    case WK: case BK:{
      if(enpassantSquare)break;
      fromattacknormal=Attack::kingAttacks(fromsquare)&to;
      castlemask = Attack::castle(qpos,colormasks,kingsquares);
      castlemask &= to;
      break;}
    default:{
      if (enpassantSquare)break;
      fromattacknormal=Attack::attacksquare(fromsquare,
					    frompiece,
					    occupied,
					    to);
      break;}
    }
    SquareMask pseudolegal;
    SquareMask currentTos;
    SquareMask currentEpsquare;
    if(!pseudoFlag)
      pseudolegal=filterPseudoLegal(fromsquare,fromattacknormal,board);
    else
      pseudolegal=fromattacknormal;
    currentTos |= pseudolegal;
    currentTos |= castlemask;
    if (enpassantseen){
      uassert(square_valid(epto)&&square_valid(epsquare),"ml eptop");
      currentTos.insert(epto);
      currentEpsquare.insert(epsquare);
    }
    if(range)
      count+=currentTos.count();
    if(currentTos.nonempty()){
      toSquares|=currentTos;
      fromSquares.insert(fromsquare);
      epSquares|=currentEpsquare;
    }
  }//for each fromsquare
}

SquareMask MoveLegalNode::filterPseudoLegal(squareT fromsquare, SquareMask unfiltered,const pieceT*board){
  uassert(square_valid(fromsquare)&&board[fromsquare]!=EMPTY,"fpl args");
  pieceT movingpiece=board[fromsquare];
  colorT movingcolor=piece_Color(movingpiece);
  uassert(movingcolor==WHITE||movingcolor==BLACK,"fpl color");
  pieceT newboard[64];
  SquareMask ret;
  ForMask(tosquare,unfiltered){
    for(int i=0;i<64;++i)newboard[i]=board[i];
    uassert(tosquare!=fromsquare,"fpl noneq");
    newboard[tosquare]=movingpiece;
    newboard[fromsquare]=EMPTY;
    if(!Attack::incheck(newboard,movingcolor))
      ret.insert(tosquare);
  }
  return ret;
}


vnode MoveLegalNode::children()const{
  vnode ret;
  uassert(fromNode&&toNode,"ml children");
  ret.push_back(fromNode);
  myinsert(ret,static_cast<Node*>(toNode));
  if(enpassantSquare)
    myinsert(ret,static_cast<Node*>(enpassantSquare));
  return ret;
}

void MoveLegalNode::deepify(){
  fromNode=fromNode->clone();
  toNode=toNode->clone();
  if(enpassantSquare)
    enpassantSquare=enpassantSquare->clone();
}

bool MoveLegalNode::match_position(QPos*qpos){
  compute(qpos);
  if(isNumeric()) return range->valid(count);
  uassert(isSet(),"MoveLegalNode: expecting a set in match_position (internal)");
  return toSquares.nonempty();
}

bool MoveLegalNode::isSet()const{
  return range==NULL;
}

bool MoveLegalNode::isNumeric()const{
  return range!=NULL;
}

bool MoveLegalNode::match_count(QPos*qpos, NumValue*value){
  uassert(isNumeric(),"MoveLegalNode: cannot use as numeric because range is not specified");
  compute(qpos);
  if(0){printf("movelegalnode::match_count: count is: %d\n",count);}
  if (range->valid(count)){
    *value=count;
    return true;
  }
  return false;
}

SquareMask MoveLegalNode::getSquares(QPos*qpos){
  uassert(isSet(),"MoveLegalNode: cannot use as set filter because range is specified");
  compute(qpos);
  if(returnTo)
    return toSquares;
  else if (returnFrom)
    return fromSquares;
  uassert(false,"movelegalnode:getsquares: internal");
  return toSquares;
}
