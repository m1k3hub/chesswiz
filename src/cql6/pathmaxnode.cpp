#include "pathmaxnode.h"
PathMaxNode::PathMaxNode():PathReferenceNode(){}

bool PathMaxNode::match_position(QPos*qpos){
  NumValue numtmp{0};
  return match_count(qpos,&numtmp);
}

bool PathMaxNode::match_count(QPos*qpos, NumValue*valuep){
  PathNode*path=thePath;
  NumValue max=-1;
  if (!path){   //external
    max=qpos->qgame->getPathStatus().getMax();
    if (max<=0)return false;
    *valuep=(NumValue)max;
    return true;
  }
  //internal
  uassert(path->hasMax(),"the pathmax filter invoked inside of a path for which there is no max filter indicated (possible user error)");
  if(!path->bestMaxValid)return false;
  *valuep=path->bestMax;
  return true;
}


