#include "pathstartnode.h"
PathStartNode::PathStartNode():PathReferenceNode(){}

bool PathStartNode::match_position(QPos*qpos){
  QPos*tmppos{NULL};
  return match_positionvalue(qpos,&tmppos);
}

bool PathStartNode::match_positionvalue(QPos*qpos, QPos**valuep){
  if (isInternal()){
    *valuep=getPath()->getStartQPos();
    uassert(*valuep,"lsnmpv");
    return true;
  }
  //external;
  QPos*start=qpos->qgame->getPathStatus().getStart();
  if(!start)return false;
  *valuep=start;
  return true;
}

