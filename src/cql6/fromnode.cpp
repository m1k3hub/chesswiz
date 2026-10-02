/*Keep this file in sync with tonode.cpp*/
#include "fromnode.h"
FromNode::FromNode(){}

SquareMask FromNode::getSquares(QPos*qpos) {
  if(qpos->initial())return SquareMask{};
  if(hasOwner()) uassert(masksValid,"fromNode: expected owner");
  QMove*qmove=qpos->getPreviousMove();
  if(qmove->isNonCastle())
    return qmove->getSimpleFromMask();
  /*This should only be reached when the underlying dashnode or dashcon
    is NOT a capturing dashnode or dashcon. That is because the
    target should never arise in a capture if the current move is
    castling*/
  
  return qmove->smartFrom(fromMask,toMask);
}



