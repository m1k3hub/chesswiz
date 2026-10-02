#include "andnode.h"
//AndNode is the same as compoundnode except that it
//is never a set or a position, only logical. That is why
// we are making a separate Node for it; also for printing.

AndNode::AndNode(Node*c1,Node*c2):clause1(c1),clause2(c2){
  uassert(clause1&&clause2,"internal AndNode, null args to constructor");
  eassert(clause1!=clause2,"in AndNode, the clauses are not distinct. This is likely an error");
}


bool AndNode::match_position(QPos*qpos){
  int mark=qpos->markComments();
  bool ret=clause1->match_position(qpos)
	 &&clause2->match_position(qpos);
  if(!ret)qpos->restoreComments(mark);
  return ret;
}


vnode AndNode::children()const{
  return vnode{clause1,clause2};
}

void AndNode::deepify(){
  clause1=clause1->clone();
  clause2=clause2->clone();
}

bool AndNode::isGameFilter()const{
  return clause1->isGameFilter()&&clause2->isGameFilter();
}
