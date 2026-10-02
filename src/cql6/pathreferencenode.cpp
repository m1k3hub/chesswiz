#include "pathreferencenode.h"
void PathReferenceNode::deepify(){
  uassert (!hasPath(),"PathReferenceNode::deepify: unexpected containing path is unexpectedly set");
}

void PathReferenceNode::setPath(PathNode*s){
  uassert(s,"lsn: s");
  uassert(!thePath,"lsn::setPath: double set internal");
  thePath=s;
}

bool PathReferenceNode::isInternal()const{
  return thePath!=NULL;
}

bool PathReferenceNode::isExternal()const{
  return !isInternal();
}
