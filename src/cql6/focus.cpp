#include "node.h"
#include "pathnode.h"
#include "complementnode.h"
#include "notnode.h"
#include "focus.h"
#include "dashcon.h"
#include "chaincon.h"
#include "holdercon.h"
#include "starcon.h"
#include "onnode.h"
#include "qpos.h"
#include "qgame.h"
#include "qmove.h"

Focus::Focus(SetBase*set,CaptureType c):
  theSetBase(set),
  theCaptureType(c)
{
  uassert(theSetBase,"ff args");
  uassert(captureTypeValid(c),"ff bad c");
}
   
  
vnode Focus::children()const{
  vnode ret;
  ret.push_back(theSetBase);
  return ret;
}

void Focus::deepify(){
  if (theSetBase) theSetBase=theSetBase->clone();
  uassert(!markMaskValid,"focus bad valid mark");
}
/*
If F is true in the target of a QMove, this method returns all
Qmoves X such that the following can match from current position root:
root: path
 (-- ~F* -- F curpos==X)

This function returns a vector of QMove* in preorder of their tails
of all focused QMoves whose origin descends from or equals root, but
if a QMove X is found, then no descendants of the target of X are included.
The key line here is:  currindex=currpos->lastDescendantIndex+1;

currindex is the index of the last focused position (that is, the target
of the last focusedmove), and currpos is the
tail of the current move. This skips over all moves
whose tails are descendants of currpos. 
*/

vector<QMove*> Focus::getFocusedChildMoves(const QPos*root)const{
  vector<QMove*>ret;
  if(root->terminal())return ret;
  for(QMove*qmove:root->moves){
    if (inFocus(qmove))
      ret.push_back(qmove);
  }
  return ret;
}
    
    
vector<QMove*> Focus::getFocusedMoves(const QPos*root)const{
  vector<QMove*>ret;
  if(root->terminal())return ret;
  const QGame*qgame=root->qgame;
  const int rootstart=root->index; //index of root
  const int rootstop=root->lastDescendantIndex; //index of last descendant of root
  uassert(qgame->getQPos(rootstart)==root,"pngfm bad root");
  //A QMove is represented by its target.
  int currindex=rootstart+1; //the current QMove or target
  while(currindex<=rootstop){
    QPos*currpos=qgame->getQPos(currindex);
    uassert(currpos&&currpos->index==currindex,"pn gfm bad currpos");
    QMove*qmove=currpos->getPreviousMove();
    uassert(qmove,"pn gfm qm");
    if(inFocus(qmove)){
      ret.push_back(qmove);
      currindex=currpos->lastDescendantIndex+1;
    }
    else
      ++currindex;
  }
  return ret;
}

bool Focus::inFocus(const QPos*qpos)const{
  uassert(qpos&&isValid(),"fif valid");
  if(qpos->initial())return false;
  const QMove*qmove=qpos->getPreviousMove();
  return inFocus(qmove);
}

bool Focus::inFocus(const QMove*qmove)const{
  if(0){cout<<endl<<"inFocus: at  QMove: ";
qmove->print();
cout<<"isNonCastle: "<<qmove->isNonCastle()<<endl;
 cout<<"isNonCapture: "<<qmove->isNonCapture()<<endl;
 cout<<"movingpieceid: "<<qmove->movingPieceId()<<endl;
 cout<<"isCapture(): "<<qmove->isCapture()<<endl;
 cout<<"markFocused(qmove->movingPieceId()): " << markFocused(qmove->movingPieceId())<<endl;
 if(qmove->isCapture())
   cout<<"markFocused(qmove->capturedPieceId())"<<markFocused(qmove->capturedPieceId())<<
endl;
  }
  uassert(qmove,"fif qmove");
  if(qmove->isNonCastle()){//Noncastle case (includes null move)
    if(qmove->isNonCapture()) // a noncapture, commonest case
      return markFocused(qmove->movingPieceId())
;
    uassert(qmove->isCapture(),"infocus error cap");
    return
      markFocused(qmove->movingPieceId())
      ||  isCapture()&&
      markFocused(qmove->capturedPieceId());
  }// ...if noncastle
  //here the qmove is a castle
  return markFocused(qmove->castleKingId())
    || markFocused(qmove->castleRookId());
}



bool Focus::markFocused(markT mark)const{
  uassert(mark.isValid(),"piecefocused: focus: bad mark");
  uassert (isValid(),"markFocused: not initialized");
  return markMask.at(mark.getValue());
}

    
void Focus::initialize(QPos*qpos){
  uassert(!markMaskValid,"Focus already initialized in Focus::initialize focus.cpp");
  uassert(theSetBase,"fi no setbase");
  clear();
  uassert(std::count(markMask.begin(),markMask.end(),true)==0,"focus::initialize markmask is not clear");
  const SquareMask setbasemask=theSetBase->getSquares(qpos);
  int nmarks=0;
  for(squareT sq=0;sq<64;++sq)
    if(setbasemask.member(sq)){
      markT mark=qpos->getMark(sq);
      if(mark.isValid()){
	++nmarks;
	markMask.at(mark.getValue())=true;
      }//mark is valid
    }//sq is in setbasemask
  markMaskValid=true;
  uassert(std::count(markMask.begin(),markMask.end(),true)==nmarks,
	  "count mismatch check in Focus::initialize in focus.cpp");
  for(markT mark=markT::zero();mark.isValid();mark.inc()){
    squareT marktosquare=qpos->getSquare(mark);
    if((markFocused(mark))!=
       ((square_valid(marktosquare)&&setbasemask.member(marktosquare)))){
      stringstream s;
      s<<"mask check failure in Focus::initialize()"<<endl
       <<" mark: " << mark
       <<" markfocused: "<< markFocused(mark)
       <<" setbasemask: \n";
      if(0){cout<<s.str();
	setbasemask.boardprint();}
      uassert(false,"focus.cpp mark check failure");
    }//mismatch error
  }//for each mark, checking the marks
}//void Focus::initialize

void Focus::clear(){
  for(bool& mark:markMask)
    mark=false;
  uassert(std::count(markMask.begin(),markMask.end(),true)==0,
	  "focusfc clear");
  markMaskValid=false;
}
    
  
