#include "node.h"

bool MoveNumberNode::match_count(QPos*qpos, NumValue*value){
  *value=qpos->getMoveNumber();
  return true;
}
