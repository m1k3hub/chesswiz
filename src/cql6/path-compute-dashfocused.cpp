#include "pathnode.h"
#include "dashcon.h"

/*Keep this in sync with PathNode::computeDashUnfocused. 
  It is separated out to try and reduce stack pressure
*/

void PathNode::computeDashConFocused(DashCon*dashcon){
  uassert(dashcon,"pncdnc focused eh?");
  if(currentPosition->terminal())return;
  if(0){
      cout<<"computeDashConFocused: called at currentPosition: \n";
      currentPosition->print();
  }

  int currentmark=currentPosition->markComments();
  size_t constacklen=conStack.size(); //for error checking
  int oldcount=theCount; //error checking
  QPos*oldcp=currentPosition; //convenience
  vector<QMove*>moves;
  if(currentPosition==getStartQPos())
    moves=theFocus->getFocusedChildMoves(currentPosition);
  else
    moves=theFocus->getFocusedMoves(currentPosition);
  uassert(currentPosition==oldcp,"pcdf cp");
  if(0)cout<<"computeDashConFocused: number of moves retrieved: "<<moves.size()<<endl;
  for(QMove*qmove:moves){
    if(0){
cout<<endl<<"computeDashConFocused looking at qmove: "<<endl;
      qmove->print();
    }
    if(isPrimary&&qmove->index>0)
      continue;
    uassert(theFocus->inFocus(qmove),"expected in focus move pcdf");
    currentPosition=qmove->head;
    SquareMask left=SetBase::virtualGetSquares(currentPosition,dashcon->getLeft());
    SquareMask right=SetBase::virtualGetSquares(currentPosition,dashcon->getRight());
    if(0){
      cout<<"left mask: " << left.listString()<<endl;
      cout<<"right mask: "<<right.listString()<<endl;
    }
    if(qmove->invalidMove(left,right,dashcon->getCaptureType()))continue;
    if(qmove->isCastle()){ //set the global masks for a castle
      markT kmark=qmove->castleKingId();
      if(!theFocus->markFocused(kmark)){
	left&= ~qmove->castleKingFromMask();
	right&= ~qmove->castleKingToMask();
      }
      markT rmark=qmove->castleRookId();
      if(!theFocus->markFocused(rmark)){
	left&= ~qmove->castleRookFromMask();
	right&= ~qmove->castleRookToMask();
      }
      if(qmove->invalidMove(left,right,dashcon->getCaptureType())) continue;
    }//if qmove->isCastle
    pushAtomicBindings();
    currentPosition=qmove->tail;
    ++theCount;
    dashcon->setOwnedMasks(left,right);
    if(!dashcon->theTarget||
       dashcon->theTarget->match_position(currentPosition)){
      dashcon->unsetOwnedMasks();
      compute();
      uassert(currentPosition==qmove->tail,"computedashcon tail");
      uassert(conStack.size()==constacklen,"cac constack dash");
    }//this dashcon matches
    else // if(!dashcon->theTarget)...
      dashcon->unsetOwnedMasks();
    --theCount;
    currentPosition=oldcp;
    popAtomicBindings();
    restoreComments(currentmark);
    uassert(currentPosition==oldcp,"cdnc bad cp");
    uassert(theCount==oldcount,"cdnc bad count");
    uassert(conStack.size()==constacklen,"cdnc bad csl");
  } //for each qmove
  currentPosition=oldcp;
};
      
  
  
