#include "unionnode.h"
UnionNode::UnionNode(SetBase*c1,SetBase*c2):clause1(c1),clause2(c2){
  uassert(clause1&&clause2,"internal UnionNode, null args to constructor");
  eassert(clause1!=clause2,"in UnionNode, the clauses are not distinct. This is likely an error");
  uassert(clause1->isSet()&&clause2->isSet(),"internal unionnode: clause arguments are not sets");
}

bool UnionNode::match_position(QPos*qpos){
  return getSquares(qpos).nonempty();
}

SquareMask UnionNode::getSquares(QPos*qpos){
  SquareMask m1=clause1->getSquares(qpos);
  SquareMask m2=clause2->getSquares(qpos);
  return m1|m2;
}

vnode UnionNode::children()const{
  return vnode{clause1,clause2};
}

void UnionNode::deepify(){
  clause1=clause1->clone();
  clause2=clause2->clone();
}
