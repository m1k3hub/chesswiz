#include "vectornode.h"

VectorNode::VectorNode(DirectionParameter dp, SetBase*s):parameter{dp}{
  uassert(s,"vnvn arg");
  source=s;
}

vnode VectorNode::children()const{
  vnode v{source};
  return v;
}


bool VectorNode::match_position(QPos*qpos){
  return getSquares(qpos).nonempty();
}

SquareMask VectorNode::getSquares(QPos*qpos){
  int min=parameter.range->getMin();
  int max=parameter.range->getMax();
  if(min!=lastMin || max!=lastMax){
    neighborhoodsvalid=false;
    lastMin=min;
    lastMax=max;
  }
  if(!neighborhoodsvalid){
    makeNeighborhoods();
    uassert(neighborhoodsvalid,"vngs arg");}
  SquareMask ret;
  SquareMask sourcemask=source->getSquares(qpos);
  for (int sq=0;sq<64;++sq)
    if(sourcemask.member(sq))
      ret|=neighborhoods[sq];
  return ret;
}
  

void VectorNode::makeNeighborhoods(){
  uassert(!neighborhoodsvalid,"vector internal");
  for (int sq=0;sq<64;++sq){
    SquareMask mask=parameter.neighborhood(sq);
    neighborhoods[sq]=mask;
  }
  neighborhoodsvalid=true;
}
    
