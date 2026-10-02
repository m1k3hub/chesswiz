#include "pathcountnode.h"
PathCountNode::PathCountNode():PathReferenceNode(){}

bool PathCountNode::match_position(QPos*qpos){
  if (thePath)
    uassert(false,"warning: pathcount node invoked for its truth value inside of 'path', but the pathcount filter is always true there");
  NumValue numtmp{0};
  return match_count(qpos,&numtmp);
}

bool PathCountNode::match_count(QPos*qpos, NumValue*valuep){
  PathNode*path=thePath;
  int count=-1;
  if (!path){   //external
    count=qpos->qgame->getPathStatus().getCount();
    if (count<=0)return false;
    *valuep=(NumValue)count;
    return true;
  }
  //internal
  if(0)cout<<"pathcount got count of: "<<path->theCount<<endl;
    *valuep=path->theCount;
    return true;
}


