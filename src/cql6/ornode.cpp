#include "ornode.h"
OrNode::OrNode(Node*c1,Node*c2):clause1(c1),clause2(c2){
  uassert(clause1&&clause2,"internal OrNode, null args to constructor");
  eassert(clause1!=clause2,"in OrNode, the clauses are not distinct. This is likely an error");
}


bool OrNode::match_position(QPos*qpos){
  int mark=qpos->markComments();
  if(clause1->match_position(qpos)) return true;
  if (clause2->match_position(qpos))return true;
  qpos->restoreComments(mark);
  return false;
}


vnode OrNode::children()const{
  return vnode{clause1,clause2};
}

void OrNode::deepify(){
  clause1=clause1->clone();
  clause2=clause2->clone();
}

bool OrNode::isGameFilter()const{
  return clause1->isGameFilter()&&clause2->isGameFilter();
}
