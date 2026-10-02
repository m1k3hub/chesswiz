#include "node.h"
bool CountSquaresNode::match_count(QPos*qpos,NumValue*value){
  SquareMask m=set->getSquares(qpos);
  *value=(NumValue)(m.size());
  return true;
}

CountSquaresNode::CountSquaresNode(SetBase* dp):set(dp){
  uassert(set,"CountSquaresNode: dp");
}


