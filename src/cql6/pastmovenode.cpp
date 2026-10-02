#include "pastmovenode.h"
#include "pieceloc.h"

PastMoveNode::PastMoveNode(PastMoveType t):theType(t){
}

PastMoveNode*PastMoveNode::makePromote(Node*node){
  uassert(node,"makePromote: arg");
  PastMoveNode*ret=new PastMoveNode(PastMoveType::Promote);
  PieceLoc*p=dynamic_cast<PieceLoc*>(node);
  if(p)
    ret->promotePieceLoc=p;
  else{
    uassert(node->isString(),"PastMoveNode: expected string filter");
    ret->promoteStringFilter=node;
  }
  return ret;
}

PastMoveNode*PastMoveNode::makeNullMove(){
  return new PastMoveNode(PastMoveType::NullMove);
}

PastMoveNode*PastMoveNode::makePrimary(){
  return new PastMoveNode(PastMoveType::Primary);
}

PastMoveNode*PastMoveNode::makeSecondary(){
  return new PastMoveNode(PastMoveType::Secondary);
}

PastMoveNode*PastMoveNode::makeEnPassant(){
  return new PastMoveNode(PastMoveType::EnPassant);
}

PastMoveNode*PastMoveNode::makeOO(){
  return new PastMoveNode(PastMoveType::OO);
}
PastMoveNode*PastMoveNode::makeOOO(){
  return new PastMoveNode(PastMoveType::OOO);
}
PastMoveNode*PastMoveNode::makeCastle(){
  return new PastMoveNode(PastMoveType::Castle);
}
PastMoveNode*PastMoveNode::makeCapture(SetBase*cap){
  uassert(cap,"pmn mc");
 PastMoveNode*ret=new PastMoveNode(PastMoveType::Capture);
 ret->theCapture=cap;
 return ret;
}

//modify as more sets added perhaps
bool PastMoveNode::isSet()const {
  return isCapture();
}

bool PastMoveNode::match_position(QPos*qpos){
  if(isSet())
    return getSquares(qpos).nonempty();
  if(qpos->initial())return false;
  QMove*qmove=qpos->getPreviousMove();
    uassert(qmove,"pastmovenode qm mp");
  if (isNullMove())
    return qmove->isNull();
  if(isEnPassant())
    return qmove->isEnPassant();
  if (isPromote()){
    if(!qpos->parent)return false;
    if(qmove->promote==EMPTY) return false;
    if (promotePieceLoc)
      return promotePieceLoc->match_piecetype(qmove->promote);
    else if (promoteStringFilter){
      string val;
      if(!promoteStringFilter->match_stringvalue(qpos->parent,&val))
	return false;
      if(val==""||val==".") return true;
      char pc=piece_to_char(qmove->promote);
      if(pc>='a'&&pc<='z')
	pc=pc-'a'+'A';
      for(char c: val){
	if(c>='a'&&c<='z')
	  c=c - 'a' + 'A';
	if(c==pc)return true;
      }
      return false;
    }//if(promoteStringFilter)

  }
  if (isPrimary())
    return qmove->index==0;
  if (isSecondary())
    return qmove->index>0;
  if(isOO())
    return qmove->isOO();
  if(isOOO())
    return qmove->isOOO();
  if(isCastle())
    return qmove->isCastle();
  uassert(false,"pmn not implemented");
  return false;
}

SquareMask PastMoveNode::getSquares(QPos*qpos){
  if(qpos->initial())return SquareMask{};
  QMove*qmove=qpos->getPreviousMove();
  uassert(qmove,"pastmovenode getsquares previous");
  squareT ret=65;
  switch(theType){
  case PastMoveType::Capture:{
    squareT capsq=qmove->getCaptureSquare();
    if (capsq>63)return SquareMask{};
    uassert(theCapture&&qmove->head,"missing parent pmtcapture");
    SquareMask mask=theCapture->getSquares(qmove->head);
    return mask&SquareMask::fromSquare(capsq);
  }
  default:
    uassert(false,"pmn fall through");
  }
  uassert(square_valid(ret),"pnm gs internal s");
  return SquareMask::fromSquare(ret);
}

void PastMoveNode::deepify(){
  //next line is likely not necessary but not quite sure of effects of having identical children
  //of different nodes. This is because promotePieceLoc is invariant to transforms. Should likely
  //modify how it transforms actually
  if (promotePieceLoc) promotePieceLoc=promotePieceLoc->clone();
  if(promoteStringFilter) promoteStringFilter=promoteStringFilter->clone();
  if (theCapture) theCapture=theCapture->clone();
}

vnode PastMoveNode::children()const{
  vnode ret;
  if (promotePieceLoc) ret.push_back(promotePieceLoc);
  if(promoteStringFilter)ret.push_back(promoteStringFilter);
  if (theCapture) ret.push_back(theCapture);
  uassert(ret.size()<=1,"odd ret in pmn ch");
  return ret;
}

string PastMoveNode::typetostring(){
  switch(theType){
  case PastMoveType::Promote:
    return "Promote";
  case PastMoveType::EnPassant:
    return "EnPassant";
  case PastMoveType::NullMove:
    return "NullMove";
  case PastMoveType::Primary:
    return "Primary";
  case PastMoveType::Secondary:
    return "Secondary";
  case PastMoveType::OO:
    return "OO";
  case PastMoveType::OOO:
    return "OOO";
  case PastMoveType::Castle:
    return "Castle";

  default:
    uassert(false,"bad type in pmn");
    return "";
  }
}
