#include "sequencebase.h"

void SequenceBase::nestRegisterPosition(QPos*qpos){
  uassert(qpos,"sb nrp");
  nestIds.insert(qpos);
}

bool SequenceBase::nestSeenPosition(QPos*qpos){
  uassert(nestBan,"nestSeenPosition: internal");
  if(nestIds.count(qpos)>0)return true;
  return false;
}

void SequenceBase::nestClearPositions(){
  nestIds.clear();
}

void SequenceBase::nestRegisterPositions(QPos*start,QPos*finish){
  uassert(start&&finish,"sbnrp args");
  QPos*shallow=start;
  QPos*deep=finish;
  if(isPast()) {shallow=finish;deep=start;}
  uassert(shallow->getPly()<=finish->getPly(),"sbnrp: bad ply");
  colorT startcolor=shallow->toMove;
  if(isSkip()) uassert(startcolor==deep->toMove,"sbnrp color");
  QPos*current=deep;
  while(true){
    if(isSkip()&&current->toMove==startcolor ||
       !isSkip())
      nestRegisterPosition(current);
    if(current->getPly()<=shallow->getPly())break;
    current=current->parent;
    uassert(current&&current->getPly()>=shallow->getPly(),"sbnrp ply check");
  }
  uassert(current==shallow,"sbnrp loop exit");
}
  
  

