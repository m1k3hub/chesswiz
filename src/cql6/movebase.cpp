#include "movebase.h"
#include "pieceloc.h"
MoveBase::MoveBase(SetBase*f,
		   SetBase*t,
		   PieceLoc*p,
		   SetBase* e,
		   SetBase*c,
		   CommentNode*com,
		   bool nullmove,
		   bool mainline,
		   bool variation,
		   bool returnfrom,
		   bool returnto,
		   bool returncapture):
  from(f),
  to(t),
  promote(p),
  enpassantsquare(e),
  capture(c),
  commentNode(com),
  nullMove(nullmove),
  primaryMove(mainline),
  secondaryMove(variation),
  returnFrom(returnfrom),
  returnTo(returnto),
  returnCapture(returncapture)
{
  uassert(!(primaryMove&&secondaryMove),"Movebase args");
  uassert(returnFrom+returnTo+returnCapture==1,"movebase: returnfrom/returnto/capture args");
}

squareT MoveBase::returnSquare(const QMove*qmove)const{
  uassert(qmove,"movebase returnSquare internal");
  squareT ret=65;
  if(returnTo) ret=qmove->to;
  else if (returnFrom) ret=qmove->from;
  else if (returnCapture) ret=qmove->getCaptureSquare();
  else uassert(false,"mbrs internal");
  uassert(square_valid(ret),"movebase returnSquare internal bad ret");
  return ret;
}
    
void MoveBase::setMasks(QPos*qpos){
  SquareMask ones= ~SquareMask();
  if(from)fromMask=from->getSquares(qpos);
  else fromMask=ones;
  if(to) toMask=to->getSquares(qpos);
  else toMask=ones;
  if(capture) captureMask=capture->getSquares(qpos);
  else captureMask.clear();
  if(enpassantsquare) enpassantMask=enpassantsquare->getSquares(qpos);
  else enpassantMask.clear();
}
		    
 
bool MoveBase::match_position(QPos*qpos){
  return getSquares(qpos).nonempty();
}

bool MoveBase::match_move(QMove* move){
  if(primaryMove && move->index>0) return false;
  if(secondaryMove && move->index==0) return false;
  if(nullMove && !move->isNull())
    return false;
  if(!fromMask.member(move->from))
    return false;
  if(!toMask.member(move->to))
    return false;
  if(promote){
    bool pok= promote->match_piecetype(move->promote);
    if(!pok)return false;}
  if(enpassantsquare){
    if(!move->isEnPassant())return false;
    squareT epsquare=move->getEnPassantSquare();
    uassert(square_valid(epsquare),"epsquare invalid");
    if(!enpassantMask.member(epsquare)) return false;
  }
  if(capture){
    squareT capturesquare=move->getCaptureSquare();
    if(!square_valid(capturesquare)) return false;
    if(!captureMask.member(capturesquare))return false;
  }//if capture
  if(commentNode){
    QPos*target=move->tail;
    uassert(target,"MoveBase:match_move: cannot get target");
    commentNode->match_position(target);
  }
  return true;
}

vnode MoveBase::children()const{
  vnode v;
  if(from)myinsert(v,dynamic_cast<Node*>(from));
  if(to)myinsert(v,dynamic_cast<Node*>(to));
  if(promote)myinsert(v,dynamic_cast<Node*>(promote));
  if(enpassantsquare)myinsert(v,dynamic_cast<Node*>(enpassantsquare));
  if(capture)myinsert(v,dynamic_cast<Node*>(capture));
  if(commentNode)myinsert(v,dynamic_cast<Node*>(commentNode));
  for(auto n:v)uassert(n!=NULL,"movebase children error");
  return v;
}
  

void MoveBase::deepify(){
  if(from) from=from->clone();
  if(to) to=to->clone();
  if(promote) promote=promote->clone();
  if(enpassantsquare) enpassantsquare=enpassantsquare->clone();
  if(capture) capture=capture->clone();
  if(commentNode) commentNode=commentNode->clone();
}
