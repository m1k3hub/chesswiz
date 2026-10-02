#include "isboundnode.h"
IsBoundNode::IsBoundNode(string name):theName(name){
  uassert(theName.size()>0,"isboundnode arg");
}
vnode IsBoundNode::children()const{
  if (theVariable)
    return vnode{theVariable};
  else return vnode{};
}

void IsBoundNode::deepify(){}

bool IsBoundNode::match_position(QPos*qpos){
  uassert(qpos,"isboundnode qpos");
  return theVariable&&theVariable->isBound();
}

void IsBoundNode::setVariable(Variable*v){
  uassert(v && v->name==theName,"isBoundNode: unexpected variable for node: ",theName);
  theVariable=v;
}

