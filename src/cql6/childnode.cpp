#include "childnode.h"
ChildNode::ChildNode(Node* index):indexNode(index){
  uassert(indexNode&&indexNode->isNumeric(),"childnode arg");
}

void ChildNode::deepify(){
  indexNode=indexNode->clone();
}

vnode ChildNode::children()const{
  return vnode{indexNode};
}

bool ChildNode::match_position(QPos*qpos){
  QPos*value{NULL};
  return match_positionvalue(qpos,&value);
}

bool ChildNode::match_positionvalue(QPos*qpos,QPos**valuep){
  uassert(qpos&&valuep,"cnmpv args");
  int childindex=-1;
  if(!indexNode->match_count(qpos,&childindex))
      return false;
  if (childindex<0 || childindex >= (int)(qpos->children.size()))
    return false;
  *valuep=qpos->children.at(childindex);
  return true;
}
