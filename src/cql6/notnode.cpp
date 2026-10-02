#include "notnode.h"

NotNode::NotNode(Node*np):filter(np){
  uassert(filter,"Missing or illegal argument to :not specification");
}


bool NotNode::match_position(QPos*qpos){
  int mark=qpos->markComments();
  bool ret=!filter->match_position(qpos);
  qpos->restoreComments(mark);
  return ret;
}


vnode NotNode::children()const{
  return vnode{filter};
}
void NotNode::deepify(){
  filter=filter->clone();
}
bool NotNode::isGameFilter()const{
  return filter->isGameFilter();
}
