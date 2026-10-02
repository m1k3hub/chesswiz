/*Keep this file in sync with fromnode.cpp*/
#include "tonode.h"
ToNode::ToNode(){}

SquareMask ToNode::getSquares(QPos*qpos) {
  if(qpos->initial())return SquareMask{};
  if(hasOwner()) uassert(masksValid,"toNode: expected owner");
  QMove*qmove=qpos->getPreviousMove();
  if(qmove->isNonCastle())
    return qmove->getSimpleToMask();
  /*This should only be reached when the underlying dashnode or dashcon
    is NOT a capturing dashnode or dashcon. That is because the
    target should never arise in a capture if the current move is
    castling*/
  
  return qmove->smartTo(fromMask,toMask);
}



