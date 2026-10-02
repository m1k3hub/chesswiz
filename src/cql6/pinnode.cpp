#include "node.h"
#include "attack.h"
#include "pinnode.h"
PinNode::PinNode(SetBase* _from,
		 SetBase* _through,
		 SetBase* _to,
		 bool returnfrom,
		 bool returnthrough,
		 bool returnto):
  fromFilter(_from),
  throughFilter(_through),
  toFilter(_to),
  returnFrom(returnfrom),
  returnThrough(returnthrough),
  returnTo(returnto)
{
  uassert(returnfrom+returnthrough+returnto==1,"pinnode arg");
}

SquareMask PinNode::getSquares(QPos*qpos){
  SquareMask fromMask, throughMask, toMask;
  if(fromFilter)
    fromMask=fromFilter->getSquares(qpos);
  else
    fromMask= SquareMask::all();
  if(throughFilter)
    throughMask=throughFilter->getSquares(qpos);
  else throughMask=SquareMask::all();
  if(toFilter)
    toMask=toFilter->getSquares(qpos);
  else{
    auto pmasks=qpos->getPieceMasks();
    toMask=pmasks->at(WK)|pmasks->at(BK);
  }
  SquareMask ret;
  if(fromMask.empty()||toMask.empty()||throughMask.empty())return ret;
  SquareMask occupied=qpos->getColorMask(WHITE)|qpos->getColorMask(BLACK);
  SquareMask emptymask= ~occupied;
  for(colorT color=WHITE;color<=BLACK;++color){
    colorT othercolor= 1-color;
    uassert(othercolor==WHITE||othercolor==BLACK,"pinnodeinternal");
    SquareMask colormask=qpos->getColorMask(color);
    SquareMask othercolormask=qpos->getColorMask(othercolor);
    SquareMask colorfrom=fromMask&colormask;
    SquareMask othercolorthrough=throughMask&othercolormask;
    SquareMask othercolorto=toMask&(othercolormask|emptymask);
    ret|=computexrays(colorfrom,othercolorthrough,othercolorto,qpos);
  }
  return ret;
}
SquareMask PinNode::computexrays(SquareMask frommask,
				 SquareMask throughmask,
				 SquareMask tomask,
				 QPos*qpos){
  SquareMask fromret,throughret,toret;
  if(frommask.empty()||throughmask.empty()||tomask.empty()) return fromret;
  SquareMask occupied=
    qpos->getColorMask(WHITE)
    | qpos->getColorMask(BLACK);
  static vector<Direction> alldirections;
  const pieceT*board=qpos->getBoard();
  ForMask(fromsquare,frommask){
    pieceT piece=board[fromsquare];
    SquareMask shifts;
    if(piece==WR||piece==BR||piece==WQ||piece==BQ)
      shifts|=Attack::orthogonalShift(fromsquare);
    if(piece==WB||piece==BB||piece==WQ||piece==BQ)
      shifts|=Attack::diagonalShift(fromsquare);
    SquareMask target=shifts&tomask;
    if(target.empty())continue;
    if((throughmask&shifts).empty())continue;
    ForMask(targetsquare,target){
      SquareMask between=Attack::betweenmask(fromsquare,targetsquare);
      SquareMask pinmask=throughmask&between;
      if(pinmask.empty())continue;
      if((between&occupied).count()>1)continue;
      fromret.insert(fromsquare);
      throughret|=pinmask;
      toret.insert(targetsquare);
    }//For targetsquare
  }// For fromsquare
  if(returnFrom)return fromret;
  else if(returnTo)return toret;
  else if (returnThrough)return throughret;
  uassert(false,"pinnode computexrays loop");
  return fromret;
}//computexrays;

bool PinNode::match_position(QPos*qpos){
  SquareMask mask=getSquares(qpos);
  return mask.nonempty();
}

vnode PinNode::children()const{
  vnode ret;
  if(fromFilter) ret.push_back(fromFilter);
  if(throughFilter) ret.push_back(throughFilter);
  if(toFilter) ret.push_back(toFilter);
  return ret;
}

void PinNode::deepify(){
  if(fromFilter)
    fromFilter=fromFilter->clone();
  if(throughFilter)
    throughFilter=throughFilter->clone();
  if(toFilter)
    toFilter=toFilter->clone();
}
