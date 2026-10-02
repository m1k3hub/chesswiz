#include "focuscapturenode.h"
//Remember to clone the argument!
/*
 A focus capturenode of a set F (which MUST BE CLONE OR NOT USED AGAIN)
 is the same as 
      from&parent:F or capture F
 It is a separate filter mostly to make printing look cleaner.
*/

FocusCaptureNode::FocusCaptureNode(SetBase*set):theSet(set){
  uassert(theSet,"fcn arg null");
}
vnode FocusCaptureNode::children()const{
  return vnode{theSet};
}

bool FocusCaptureNode::match_position(QPos*qpos){
  uassert(qpos,"fcn mp qpos");
  if(qpos->initial())return false;
  QMove*qmove=qpos->getPreviousMove();
  uassert(qmove,"fcn no previous move");
  squareT fromsquare=qmove->from;
  squareT capturesquare=qmove->getCaptureSquare();
  QPos*head=qmove->head;
  uassert(head,"fcnmp head");
  SquareMask fmask=theSet->getSquares(head);
  return (fmask&
	  (SquareMask::fromSquare(fromsquare)
	   |SquareMask::fromSquare(capturesquare))).nonempty();
}

void FocusCaptureNode::deepify(){
  theSet=theSet->clone();
}
