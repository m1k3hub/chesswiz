#include "sequencebase.h"
void SequenceBase::mergeSuccess(QPos*qpos){
  bool swap=false;
  if(isFalse())
    swap=true;
  else{ //isTrue()
    uassert(bestSoFar,"sb ms mergesuccess last");
    int oldply=bestSoFar->getPly();
    int newply=qpos->getPly();
    if(isFuture())
      swap=(oldply<newply);
    else if(isPast())
      swap=(newply<oldply);
    else uassert(false,"mergesuccess bad direction");
  }
  if(swap){
    bestSoFar=qpos;
    swapComments(qpos);
  }
}

void SequenceBase::commentStacksValid(){
  uassert(mainStack,"sbsv no mainstack");
  uassert(mainStack->size()>=effectiveBottom && mainStack->size()>=effectiveTop&&effectiveBottom>=0&&effectiveTop>=effectiveBottom,"srsv 1");
  uassert(trueSize== effectiveTop-effectiveBottom+commentStack.size(),"srsv 2");
}
void SequenceBase::restoreComments(int desttop){
  if(desttop==mainStack->size())return;
  commentStacksValid();
  uassert(desttop>=0&&desttop<mainStack->size(),"srrc a");
  commentStacksValid();
  while(mainStack->size()>desttop)
    popComment();
  uassert(mainStack->size()==desttop,"srrc internal");
  commentStacksValid();
}

//popComment(): pop the current comment from the main comment stack, and push it onto commentStack if it is less than effectiveTop, which is decremented
void SequenceBase::popComment(){
  if(!CqlSmartComments)return;
  commentStacksValid();
  int maintop=mainStack->size();
  if(maintop>effectiveTop){
    mainStack->pop();
    uassert(maintop==mainStack->size()+1,"srpc int");
    return;}
  uassert(maintop>0,"srpc int 2");
  uassert(maintop==effectiveTop,"srpc maintop size");
  mainStack->transfer(maintop-1,&commentStack);
  --effectiveTop;
  commentStacksValid();
}

void SequenceBase::swapComments(QPos*qpos){
  if(!CqlSmartComments)return;
  uassert(mainStack&&qpos->qgame->getCommentStack()==mainStack,"seqret sc internal");
  commentStacksValid();
  commentStack.clear();
  effectiveTop=mainStack->size();
  trueSize=effectiveTop-effectiveBottom;
  commentStacksValid();
}

void SequenceBase::pushComments(){
  if(!CqlSmartComments)return;
  commentStacksValid();
  mainStack->restoreComments(effectiveTop);
  commentStack.reverse();
  commentStack.transfer(0,mainStack);
  effectiveTop=effectiveBottom;
  trueSize=0;
  commentStacksValid();
}

int SequenceBase::markComments(){
  return mainStack->markComments();
}

void SequenceBase::initializeComments(QPos*qpos){
  uassert(!bestSoFar,"SB cI bsf");
  uassert(qpos,"sbic qpos");
  mainStack=qpos->qgame->getCommentStack();
  effectiveBottom=mainStack->size();
  effectiveTop=effectiveBottom;
  uassert(mainStack,"sbic mainstack");
  commentStack.clear();
  trueSize=0;
}


