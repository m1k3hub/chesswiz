#include "node.h"
SquareCoordinateNode::SquareCoordinateNode(SetBase*square, bool isr):theSquare(square),isRank(isr){
  uassert(theSquare,"scn bad arg");
}

vnode SquareCoordinateNode::children()const{
  return vnode{theSquare};
}


bool SquareCoordinateNode::match_position(QPos*qpos){
  return theSquare->getSquares(qpos).count()==1;
}

bool SquareCoordinateNode::match_count(QPos*qpos,NumValue*value){
  SquareMask squares=theSquare->getSquares(qpos);
  if(squares.count()!=1) return false;
  ForMask (square,squares){
    if (isRank)
      *value=square_Rank(square)+1;
    else
      *value=square_Fyle(square)+1;
    return true;
  }
  uassert(false,"scn mach_count internal");
  return false;
}

  
