#include "nonemptynode.h"
NonemptyNode::NonemptyNode(SetBase*s):set(s){
  uassert(set,"nn no node");
}

void NonemptyNode::deepify(){
  set=set->clone();
}

vnode NonemptyNode::children()const{
  return vnode{set};
}

bool NonemptyNode::match_position(QPos*qpos){
  SquareMask s=set->getSquares(qpos);
  return s.nonempty();
}
