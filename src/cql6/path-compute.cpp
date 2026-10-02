#include "pathnode.h"
#include "dashcon.h"
#include "chaincon.h"
#include "holdercon.h"
#include "optionalcon.h"
#include "pluscon.h"
#include "starcon.h"
#include "repeatcon.h"
#include "repeatinprocesscon.h"

void PathNode::compute(){
  QPos*oldcp=currentPosition;
  if(conStack.empty()){
    if (oldcp==getStartQPos()){
      return; // for now we do not allow matches at the start
    }
    mergeSuccess();
    return;
  }
  if(firstMatch&&bestSoFar)return;
  size_t startlen=conStack.size();
  PathCon*top=conStack.back();
  uassert(top,"null top of stack in path-compute");
  conStack.pop_back();
  if(top->isHolderCon())
    computeHolderCon(top->asHolderCon());
  else if (top->isDashCon()){
    if(hasFocus())
      computeDashConFocused(top->asDashCon());
    else
      computeDashConUnfocused(top->asDashCon());
  }
  else if (top->isChainCon())
    computeChainCon(top->asChainCon());
  else if (top->isPlusCon())
    computePlusCon(top->asPlusCon());
  else if (top->isOptionalCon())
    computeOptionalCon(top->asOptionalCon());
  else if (top->isStarCon())
    computeStarCon(top->asStarCon());
  else if (top->isRepeatCon())
    computeRepeatCon(top->asRepeatCon());
  else if (top->isRepeatInProcessCon())
    computeRepeatInProcessCon(top->asRepeatInProcessCon());
  else
    uassert(false,"unknown pathconstituent type in ln:compute");
  conStack.push_back(top);
  uassert(conStack.size()==startlen,"bad stacksize lncmain");
  uassert(currentPosition==oldcp,"pathnode compute bad cp");
}


void PathNode::computeChainCon(ChainCon*vc){
  size_t constacklen=conStack.size();
  QPos*oldcp=currentPosition;
  vector<PathCon*>&v=vc->theCons;
  int ncons=(int)(v.size());
  uassert(ncons,"lncvc");
  for(int i=ncons-1;i>=0;--i)
    conStack.push_back(v.at(i));
  uassert(conStack.size()==constacklen+ncons,"lnclen");
  compute();
  uassert(conStack.size()==constacklen+ncons,"lnclen");
  uassert (currentPosition==oldcp,"lchain compute cp");
  for(int i=0;i<ncons;++i)
    conStack.pop_back();
  uassert(conStack.size()==constacklen,"lnclen3");
}

void PathNode::computeHolderCon(HolderCon*holder){
  size_t constacklen=conStack.size();
  QPos*oldcp=currentPosition;
  if(!holder->getFilter()->match_position(currentPosition))
    return;
  uassert(conStack.size()==constacklen&&currentPosition==oldcp,"computeholdercon mismatch");
  compute();
  uassert(conStack.size()==constacklen&&currentPosition==oldcp,"computeholdercon mismatch");
}

void PathNode::computeStarCon(StarCon*star){
  compute();
  PathCon*c=star->getCon();
  size_t constacklen=conStack.size();
  conStack.push_back(star);
  conStack.push_back(c);
  compute();
  uassert(conStack.size()==constacklen+2,"sbcompute constacklen star");
  conStack.pop_back();
  conStack.pop_back();
  uassert(conStack.size()==constacklen,"sbcompute constacklen star 2");
}

void PathNode::computePlusCon(PlusCon*plus){
  StarCon*star=plus->getStar();
  PathCon*c=plus->getCon();
  size_t constacklen=conStack.size();
  conStack.push_back(star);
  conStack.push_back(c);
  compute();
  uassert(conStack.size()==constacklen+2,"sbcompute constacklen plus");
  conStack.pop_back();
  conStack.pop_back();
  uassert(conStack.size()==constacklen,"sbcompute constacklen plus 2");
}

void PathNode::computeOptionalCon(OptionalCon*optional){
  PathCon*c=optional->getCon();
  size_t constacklen=conStack.size();
  QPos*oldcp=currentPosition;
  compute();
  conStack.push_back(c);
  compute();
  uassert(conStack.size()==constacklen+1,"sbcompute constacklen plus");
  conStack.pop_back();
  uassert(conStack.size()==constacklen&&currentPosition==oldcp,"coptcompute");
}


void PathNode::computeRepeatCon(RepeatCon*repeat){
  QPos*oldcp=currentPosition;
  size_t constacklen=conStack.size();
  RepeatInProcessCon rprocess(repeat);
  conStack.push_back(&rprocess);
  compute();
  uassert(conStack.size()==constacklen+1,"PathNode: compute RepeatConstituent: stack");
  conStack.pop_back();
  uassert(conStack.size()==constacklen,"crcbrc stack");
  uassert(oldcp==currentPosition,"lncr repeat cp");
}

void PathNode::computeRepeatInProcessCon(RepeatInProcessCon*rprocess){
  int min=rprocess->min();  //min allowed matches
  int max=rprocess->max();  //max allowed matches
  QPos*oldcp=currentPosition;
  int nseen=rprocess->nSeen; // number of constituents pushed on the stack by this method so far
  size_t constacklen=conStack.size();
  PathCon*con=rprocess->getCon(); //constituent to be repeated
  uassert(min>=0&&nseen<=max,"lnnbcrpc minmax");
  if(nseen>=min&&nseen<=max) //if we have seen enough to be ok then match what is left
    compute();
  if(nseen<max){             //if we might benefit by trying a new constituent?
    conStack.push_back(rprocess);  // (this follows compute(StarConstituent*...)
    conStack.push_back(con);     // push a new constituent
    rprocess->nSeen++;        // and tell the RepeatInProcessConstituent on the stack it has seen another
    compute();            // and try again.
    uassert(conStack.size()==constacklen+2,"lnbc rpc stack");
    uassert(rprocess->nSeen==nseen+1,"lnbc rpc nseen");
    rprocess->nSeen--;
    conStack.pop_back();
    conStack.pop_back();
  }
  uassert(conStack.size()==constacklen,"lnbc rpc stack2");
  uassert(rprocess->nSeen==nseen,"lnbc rpc nseen2");
  uassert(currentPosition==oldcp,"lnbc oldcp/cp");
}
    


