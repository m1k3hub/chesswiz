#include "movebase.h"

MovePastNode::MovePastNode(SetBase*f,
			   SetBase*t,
			   PieceLoc*p,
			   SetBase* e,
			   SetBase*c,
			   CommentNode*com,
			   bool nullmove,
			   bool mainline,
			   bool variation,
			   bool returnfrom,
			   bool returnto,
			   bool returncapture):
  MoveBase(f, t, p, e,c,com,nullmove,mainline,variation,returnfrom,returnto,returncapture){}

SquareMask MovePastNode::getSquares(QPos*qpos){
  SquareMask ret;
  if(qpos->initial())return ret;
  setMasks(qpos->parent);
  QMove*previous=qpos->getPreviousMove();
  uassert(previous,"movepastnode getsquares previous");
  if(match_move(previous)){
    squareT sq=returnSquare(previous);
    uassert(square_valid(sq),"MovePastNode: internal sq");
    ret.insert(sq);
  }
  return ret;
}
 
