#include "node.h"

BetweenNode::BetweenNode(SetBase*s, SetBase*t){
  uassert(s&&t,"BetweenNode: null parameter");
  source=s;
  target=t;
}


SquareMask BetweenNode::getSquares(QPos*qpos){
  SquareMask mask;
  SquareMask sm=source->getSquares(qpos);
  SquareMask tm=target->getSquares(qpos);
  for(squareT sourcesquare=0;sourcesquare<64;++sourcesquare)
    if (sm.member(sourcesquare))
      for(squareT targetsquare=0;targetsquare<64;++targetsquare)
	if(tm.member(targetsquare))
	  mask|=Direction::between(sourcesquare,targetsquare);
  return mask;
}


