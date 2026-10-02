#include "assertnode.h"
#include "variable.h"
AssertNode::AssertNode(Node*node,string name):theNode(node),theName(name){
  uassert(theNode,"assertnode bad arg");
}

bool AssertNode::match_position(QPos*qpos){
  bool ok=false;
  if(theNode->isVariable())
    ok=(theNode->asVariable()->isBound());
  else
    ok=theNode->match_position(qpos);
  if (ok) return true;
  stringstream s;
  s<<"assert filter in .cql file failed at gamenumber "<<qpos->qgame->getGameNumber()<<
    " and positionid: "<<qpos->index<<": "<<theName;
  eassert(false,s.str());
  return false;
}

void AssertNode::deepify(){
  theNode=theNode->clone();
}

vnode AssertNode::children()const{
  return vnode{theNode};
}
  
