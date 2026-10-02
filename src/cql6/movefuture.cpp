#include "movebase.h"
MoveFutureNode::MoveFutureNode(SetBase*f,
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

SquareMask MoveFutureNode::getSquares(QPos*qpos){
  SquareMask ret;
  if(qpos->terminal()) return ret;
  setMasks(qpos);
  for(QMove* move:qpos->moves){
    if (requiredMove&&move!=requiredMove)continue;
    if(match_move(move)){
      squareT sq=returnSquare(move);
      uassert(square_valid(sq),"MoveFutureNode: internal sq");
      ret.insert(sq);
    }
  }
  return ret;
}

  
