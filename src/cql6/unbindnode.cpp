#include "unbindnode.h"
UnbindNode::UnbindNode(Variable*v):theVariable(v){
  uassert(theVariable,"ubn arg");
}
vnode UnbindNode::children()const{
  return vnode{theVariable};
}

void UnbindNode::deepify(){}

bool UnbindNode::match_position(QPos*qpos){
  theVariable->unbind();
  uassert(!theVariable->isBound(),"ubnmp internal");
  return true;
}
