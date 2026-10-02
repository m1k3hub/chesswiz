#include "previousdashnode.h"

PreviousDashNode::PreviousDashNode(DashNode*dash):theDash(dash){
  uassert(theDash,"illegal arg to pdn constructor");
}

vnode PreviousDashNode::children()const{
  uassert(theDash,"pdn children");
  return vnode{theDash};
}

void PreviousDashNode::deepify(){
  uassert(theDash,"pdn deep");
  theDash=theDash->clone();
}

bool PreviousDashNode::match_position(QPos* qpos){
  if(!qpos->parent)return false;
  theDash->setForceTail(qpos);
  return theDash->match_position(qpos->parent);
}
bool PreviousDashNode::match_stringvalue(QPos*qpos,string*sval){
  if(!qpos->parent)return false;
  theDash->setForceTail(qpos);
  return theDash->match_stringvalue(qpos->parent,sval);
}

bool PreviousDashNode::match_positionvalue(QPos*qpos,QPos**qposp){
  if(!qpos->parent)return false;
  theDash->setForceTail(qpos);
  return theDash->match_positionvalue(qpos->parent,qposp);
}

SquareMask PreviousDashNode::getSquares(QPos*qpos){
  if(!qpos->parent)return SquareMask();
  theDash->setForceTail(qpos);
  return theDash->getSquares(qpos->parent);
}

bool PreviousDashNode::match_count(QPos*qpos,NumValue*valuep){
  if(!qpos->parent)return false;
  theDash->setForceTail(qpos);
  return theDash->match_count(qpos->parent,valuep);
}


