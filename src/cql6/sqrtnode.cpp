#include "sqrtnode.h"
#include <math.h>
SqrtNode::SqrtNode(Node*n):node(n){
  uassert(node&&node->isNumeric(),"sqrtnode arg");
}

vnode SqrtNode::children()const{
  return vnode{node};
}

void SqrtNode::deepify(){
  node=node->clone();
}

bool SqrtNode::match_count(QPos*qpos, NumValue*valuep){
  uassert(valuep&&qpos,"snmc");
  NumValue val= -1;
  if (node->match_count(qpos,&val)){
    if (val<0) return false;
    double root=sqrt((double)(val));
    *valuep=(NumValue)root;
    return true;}
  return false;
}

bool SqrtNode::match_position(QPos*qpos){
  eassert(false,"Attempt to match an sqrt value node (which may have arisen from a 'type' filter). Although technically legal, this is likely unintended");
  return false;
}
