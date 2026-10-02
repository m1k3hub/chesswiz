#include "equalitynode.h"
EqualityNode::EqualityNode(Node*l,Node*r):left(l),right(r){
  uassert(left&&right&&left->isSet()&&right->isSet(),"en args");
}

bool EqualityNode::match_position(QPos*qpos){
  int mark=qpos->markComments();
  SetBase * leftset=left->asSet();
  SetBase* rightset=right->asSet();
  SquareMask leftmask=leftset->getSquares(qpos);
  SquareMask rightmask=rightset->getSquares(qpos);
  if (leftmask==rightmask)return true;
  qpos->restoreComments(mark);
  return false;
}
vnode EqualityNode::children()const{
  vnode ret{left};
  if(left!=right)
    ret.push_back(right);
  return ret;
}
void EqualityNode::deepify(){
  left=left->clone();
  right=right->clone();
}


