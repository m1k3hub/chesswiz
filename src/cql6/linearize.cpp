#include "node.h"
#include "movebase.h"
#include "findnode.h"
#include "futurenode.h"
#include "childnode.h"
#include "parentnode.h"
#include "withpositionnode.h"
#include "echonode.h"

void FutureNode::computeLinearize(HolderConstituent* holder, QPos*qpos){
  int mark=markComments();
  size_t stacklen=seqStack.size();
  uassert(holder,"computerLinearize internal");
  Node*filter=holder->filter;
  uassert (filter, "computeLinearize: bad filter");
  vector<QMove*>*allmovesp=qpos->getMoves();
  int nchildren=qpos->nChildren();
  uassert(allmovesp->size()==nchildren,"moves/nchildren mismatch: computeLinearize");
  if(qpos->terminal()
     &&filter->match_position(qpos) &&
     computeNull()){
    if(!skipCurrentPosition(qpos))mergeSuccess(qpos);
    restoreComments(mark);
    return;
  }
  /*movefuturesp is a pointer to a vector of MoveFutureNodes that
    each are contained in the current filter, and each must be adjusted
    only to look at the specified variation*/
  vector<MoveFutureNode*>*movefuturesp=filter->linearize();
  uassert(!movefuturesp->empty(),"unexpected emptymovefutures");
  //Begin the main loop. Loop through each move and only consider variations along that move
  for (QMove*currentmove : *allmovesp){ //Main loop
    if(isPrimary&&currentmove->index>0||
       isSecondary&&currentmove->index==0) continue;
    if (firstMatch&&bestSoFar) continue; //added for 9.224 by stiller responding Gamble bug 9/21/2020. This prevents unnecessary evaluation of a filter with side-effects once firstMatch has been set
    /* Set the moveIndex of all the MoveFutureNodes in the current filter*/
    for (auto movefuture: *movefuturesp){ //set all the possible MoveFutures to this move
      uassert(movefuture->requiredMove==NULL,"cLmfrbmn");
      movefuture->requiredMove=currentmove;
    }//end set the MoveFutures
    /* Now match the position and restore the old moveIndex values*/
    bool matchedcurrentfilter=filter->match_position(qpos);
    for (auto movefuture: *movefuturesp){ //Clear the moveFutures
      uassert(movefuture->requiredMove==currentmove,"cLmfrbmn2");
      movefuture->requiredMove=NULL;
    } //end the clear of move futures
    /*now continue as usual for this childindex*/
    if(!matchedcurrentfilter)continue; //go on the next child;
    if(computeNull()&&!skipCurrentPosition(qpos))
      mergeSuccess(qpos);
    // Now the current filter is a match, but we just look the child'th child...
    QPos*child=currentmove->tail;
    uassert(child,"linearize child");
    uassert(child->parent==qpos&&child->getPreviousMove()==currentmove,"computelinear move check");
    SequenceBase::compute(child);
    restoreComments(mark); /*added by Stiller for build 2.19 to stop move comment line bug*/
  } // main loop, for currentmove : *allmovesp
  uassert(seqStack.size()==stacklen,"computeLinear stacksize");
  restoreComments(mark);
}


vector<MoveFutureNode*> * Node::linearize(){
  if(cachedLinearizeValid) return &cachedLinearize;
  cachedLinearizeValid=true; // not yet true actually;
  uassert(cachedLinearize.empty(),"linearize cached bug");
  MoveFutureNode* movefuturefilter=dynamic_cast<MoveFutureNode*>(this);
  MovePastNode* movepastfilter=dynamic_cast<MovePastNode*>(this);
  SequenceBase* seqfilter=dynamic_cast<SequenceBase*>(this);
  FindNode* findnode=dynamic_cast<FindNode*>(this);
  WithPositionNode*withpositionnode=dynamic_cast<WithPositionNode*>(this);
  EchoNode*echonode=dynamic_cast<EchoNode*>(this); //added 12/1/2019 for 9.221 stiller
  if (seqfilter ||
      findnode||
      movepastfilter||
      echonode|| //added 12/1/2019 for 9.221 stiller
      withpositionnode)
    return &cachedLinearize;
  if (movefuturefilter)
    {cachedLinearize.push_back(movefuturefilter);
      return &cachedLinearize;}
  for (auto child:children()){
    vector<MoveFutureNode*>*childlinear=child->linearize();
    for(auto childm: *childlinear){
      for (auto futurenode : cachedLinearize)
	uassert(childm!=futurenode,"Unexpected duplicate in cachedLinearize in linearize");
      cachedLinearize.push_back(childm);
    }
  }
  return &cachedLinearize;
}


