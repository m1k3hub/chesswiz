#include "node.h"
RangeNode::RangeNode(Range* r,Node* c):range(r),numeric(c){
  uassert(range&&numeric&&numeric->isNumeric(),"RangeNode parameters");
}

bool RangeNode::match_position(QPos*qpos){
  NumValue value{-1000};
  return match_count(qpos,&value);
}

bool RangeNode::match_count(QPos*qpos,NumValue* v){
  int mark=qpos->markComments();
  bool b=numeric->match_count(qpos,v);
  if (b&&range->valid(*v))
    return true;
  qpos->restoreComments(mark);
  return false;
}

vnode RangeNode::children()const{
  Node*node=dynamic_cast<Node*>(numeric);
  uassert(node,"rnc internal null cast children");
  return vnode{node};
}


  
