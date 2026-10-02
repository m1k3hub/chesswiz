#include "subsetnode.h"
SubsetNode::SubsetNode(SetBase*l,SetBase*r):theLeft(l),theRight(r){
  uassert(theLeft&&theRight,"SubsetNode: args");
}
bool SubsetNode::match_position(QPos*qpos){
  SquareMask left=theLeft->getSquares(qpos);
  SquareMask right=theRight->getSquares(qpos);
  return (left&right)==left;
}
vnode SubsetNode::children()const{
  vnode ret{theLeft};
  if (theLeft!=theRight)
    ret.push_back(theRight);
  return ret;
}

void SubsetNode::deepify(){
  theLeft=theLeft->clone();
  theRight=theRight->clone();
}
  
  
