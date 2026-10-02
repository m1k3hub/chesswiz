#include "pathnode.h"

void PathNode::commentStacksValid(){
  uassert(mainStack,"sbsv no mainstack");
  uassert(mainStack->size()>=effectiveBottom && mainStack->size()>=effectiveTop&&effectiveBottom>=0&&effectiveTop>=effectiveBottom,"srsv 1");
  uassert(trueSize== effectiveTop-effectiveBottom+commentStack.size(),"srsv 2");
}
void PathNode::restoreComments(int desttop){
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
void PathNode::popComment(){
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

void PathNode::swapComments(QPos*qpos,bool clearold){
  if(!CqlSmartComments)return;
  uassert(mainStack&&qpos->qgame->getCommentStack()==mainStack,"pathret sc internal");
  commentStacksValid();
  if(clearold) commentStack.clear();
  effectiveTop=mainStack->size();
  trueSize=effectiveTop-effectiveBottom+commentStack.size();
  commentStacksValid();
}

void PathNode::pushComments(){
  if(!CqlSmartComments)return;
  commentStacksValid();
  mainStack->restoreComments(effectiveTop);
  commentStack.reverse();
  commentStack.transfer(0,mainStack);
  effectiveTop=effectiveBottom;
  trueSize=0;
  commentStacksValid();
}

int PathNode::markComments(){
  return mainStack->markComments();
}

void PathNode::initializeComments(QPos*qpos){
  uassert(!bestSoFar,"LB cI bsf");
  uassert(bestCount<=0,"LB bestcount init");
  uassert(qpos,"lnic qpos");
  uassert(!bestMaxValid,"pathnode ic: unexpected bestMaxValid");
  mainStack=qpos->qgame->getCommentStack();
  effectiveBottom=mainStack->size();
  effectiveTop=effectiveBottom;
  uassert(mainStack,"sbic mainstack");
  commentStack.clear();
  trueSize=0;
}


