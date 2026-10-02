#include "onnode.h"

SetBase*OnNode::makeVirtualOnNode(SetBase*left,SetBase*right){
  if(left==NULL)return right;
  if(right==NULL)return left;
  return new OnNode(left,right);
}

OnNode::OnNode(SetBase*s1, SetBase*s2){
  clause1=s1;
  clause2=s2;
  uassert(clause1&&clause2&&clause1->isSet()&&clause2->isSet(),"OnNode constructor: invalid args");
}

void OnNode::deepify(){
  clause1=clause1->clone();
  clause2=clause2->clone();
}

vnode OnNode::children()const{
  vnode ret{clause1};
  if(clause2!=clause1)
    ret.push_back(clause2);
  return ret;
}

SquareMask OnNode::getSquares(QPos*qpos){
  SquareMask ret1=clause1->getSquares(qpos);
  SquareMask ret2=clause2->getSquares(qpos);
  SquareMask ret=ret1&ret2;
  return ret;
}



