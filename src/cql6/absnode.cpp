#include "absnode.h"
AbsNode::AbsNode(Node*n):node(n){
  uassert(node&&node->isNumeric(),"absnode arg");
}

vnode AbsNode::children()const{
  return vnode{node};
}

void AbsNode::deepify(){
  node=node->clone();
}

bool AbsNode::match_count(QPos*qpos, NumValue*valuep){
  uassert(valuep&&qpos,"anmc");
  NumValue val= -1;
  if (node->match_count(qpos,&val)){
    if (val<0) val=-val;
    *valuep=val;
    return true;}
  return false;
}

bool AbsNode::match_position(QPos*qpos){
  eassert(false,"Attempt to match an absolute value node (which may have arisen from a 'type' filter). Although technically legal, this is likely unintended");
  return false;
}
