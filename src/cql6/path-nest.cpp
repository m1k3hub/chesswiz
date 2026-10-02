#include "pathnode.h"

void PathNode::nestRegisterPosition(QPos*qpos){
  uassert(qpos,"lb nrp");
  nestIds.insert(qpos);
}

bool PathNode::nestSeenPosition(QPos*qpos){
  uassert(nestBan,"nestSeenPosition: internal");
  if(nestIds.count(qpos)>0)return true;
  return false;
}

void PathNode::nestClearPositions(){
  nestIds.clear();
}

void PathNode::nestRegisterPositions(QPos*start,QPos*finish){
  uassert(start&&finish,"sbnrp args");
  QPos*shallow=start;
  QPos*deep=finish;
  uassert(shallow->getPly()<=finish->getPly(),"lbnrp: bad ply");
  QPos*current=deep;
  while(true){
    if(current->getPly()<=shallow->getPly())break;
    nestRegisterPosition(current->getParent());
    current=current->parent;
    uassert(current&&current->getPly()>=shallow->getPly(),"sbnrp ply check");
  }
  uassert(current==shallow,"lbnrp loop exit");
}
  
  

