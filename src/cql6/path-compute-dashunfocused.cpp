#include "pathnode.h"
#include "dashcon.h"
#include "qmove.h"
#include "qpos.h"
/*Keep this in sync with PathNode::computeDashFocusCon. 
  It is separated out to try and reduce stack pressure
*/

void PathNode::computeDashConUnfocused(DashCon*dashcon){
  uassert(dashcon,"pncdnc eh?");
  if(currentPosition->terminal())return;
  int commentmark=currentPosition->markComments();
  size_t constacklen=conStack.size(); //for error checking
  int oldcount=theCount; //error checking
  QPos*oldcp=currentPosition; //convenience
  SquareMask leftmask=SetBase::virtualGetSquares(currentPosition,dashcon->getLeft());
  SquareMask rightmask=SetBase::virtualGetSquares(currentPosition,dashcon->getRight());
  for(QMove*qmove:currentPosition->moves){
    if(qmove->invalidMove(leftmask,rightmask,dashcon->getCaptureType()))continue;
    if(isPrimary&&qmove->index>0)
      continue;
    pushAtomicBindings();
    currentPosition=qmove->tail;
    ++theCount;
    dashcon->setOwnedMasks(leftmask,rightmask);
    if(!dashcon->theTarget||
       dashcon->theTarget->match_position(currentPosition)){
      dashcon->unsetOwnedMasks();
      compute();
      uassert(currentPosition==qmove->tail,"computedashcon tail");
      uassert(conStack.size()==constacklen,"cac constack dash");
    }//this dashcon matches
    else
      dashcon->unsetOwnedMasks();
    --theCount;
    currentPosition=oldcp;
  popAtomicBindings();
  restoreComments(commentmark);
  uassert(currentPosition==oldcp,"cdnc bad cp");
  uassert(theCount==oldcount,"cdnc bad count");
  uassert(conStack.size()==constacklen,"cdnc bad csl");
  }//for each qmove
  return;
};
      
  
  
