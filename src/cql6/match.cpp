#include "node.h"

bool InitialNode::match_position(QPos*qpos){
  return qpos->initial();
}

bool TerminalNode::match_position(QPos*qpos){
  return qpos->terminal();
}


bool CheckNode::match_position(QPos*qpos){
  return qpos->check();
}

bool InVariationNode::match_position(QPos*qpos){
  return qpos->getDepth()>0;
}

bool InMainlineNode::match_position(QPos*qpos){
  return qpos->getDepth()==0;
}

bool MateNode::match_position(QPos*qpos){
  return qpos->mate();
}


bool StalemateNode::match_position(QPos*qpos){
  return qpos->stalemate()&&qpos->nChildren()==0;
}


