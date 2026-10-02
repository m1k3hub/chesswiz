#include "parentnode.h"
ParentNode::ParentNode(){}

void ParentNode::deepify(){
}

vnode ParentNode::children()const{
  return vnode{};}

bool ParentNode::match_position(QPos*qpos){
  QPos*value{NULL};
  return match_positionvalue(qpos,&value);
}

bool ParentNode::match_positionvalue(QPos*qpos,QPos**valuep){
  uassert(qpos&&valuep,"cnmpv args");
  QPos*parent=qpos->getParent();
  if(!parent)return false;
  *valuep=parent;
  return true;
}
