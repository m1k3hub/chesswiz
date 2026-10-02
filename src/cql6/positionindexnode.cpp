#include "positionindexnode.h"
PositionIndexNode::PositionIndexNode(){
}

vnode PositionIndexNode::children()const{
  return vnode{};
}

void PositionIndexNode::deepify(){
}

bool PositionIndexNode::match_position(QPos*qpos){
  eassert(false,"positionindex is asked if it matches a position. Although legal this is likely an error");
  return true;
}

bool PositionIndexNode::match_count(QPos*qpos,NumValue*valp){
  *valp=qpos->index;
  return true;
}

PositionIndexNode*PositionIndexNode::clone(){
  return this;
}
  
  
