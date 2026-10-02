#include "pathlastpositionnode.h"
/* this is exactly the same as pathstartnode.cpp except for messages*/
/*keep in sync with pathstartnode*/


PathLastPositionNode::PathLastPositionNode():PathReferenceNode(){}

bool PathLastPositionNode::match_position(QPos*qpos){
  QPos*tmppos{NULL};
  return match_positionvalue(qpos,&tmppos);
}

bool PathLastPositionNode::match_positionvalue(QPos*qpos, QPos**valuep){
  if (isInternal()){
    *valuep=getPath()->bestSoFar;
    return (*valuep!=NULL);
  }
  //external
  QPos*last=qpos->qgame->getPathStatus().getLast();
  if(last==NULL)return false;
  *valuep=last;
  return true;
}
