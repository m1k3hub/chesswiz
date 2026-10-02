#include "complementnode.h"
ComplementNode::ComplementNode(SetBase*s):theSet(s){
  uassert(theSet,"cncn arg");
}
vnode ComplementNode::children()const{
  return vnode{theSet};
}

void ComplementNode::deepify(){
  theSet=theSet->clone()->asSet();
}

SquareMask ComplementNode::getSquares(QPos*qpos){
  return ~(theSet->getSquares(qpos));
}

bool ComplementNode::match_position(QPos*qpos){
  return getSquares(qpos).nonempty();
}

bool ComplementNode::isSet()const{
  return true;
}


