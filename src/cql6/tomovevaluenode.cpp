#include "tomovevaluenode.h"
ToMoveValueNode::ToMoveValueNode(){}
bool ToMoveValueNode::match_position(QPos*qpos){
  uassert(false,"unexpected call to tomove here");
  return false;
}
bool ToMoveValueNode::match_count(QPos*qpos,NumValue*valuep){
  if (qpos->toMove==WHITE)
    *valuep=(NumValue)WhiteValue;
  else if (qpos->toMove==BLACK)
    *valuep=(NumValue)BlackValue;
  else
    uassert(false,"tmovemc");
  return true;
}
vnode ToMoveValueNode::children()const{
  return vnode{};
}
void ToMoveValueNode::deepify(){}

ToMoveValueNode*ToMoveValueNode::clone(){return this;}

  
