#include "piecepathnode.h"
PiecePathNode::PiecePathNode(SetBase*from,Node*to, bool isverbose):
  theFrom(from),
  theTo(to),
  isVerbose(isverbose){
  uassert(theFrom&&theFrom->isSet(),"ppn from");
  uassert(theTo&&theTo->isPosition(),"ppn to not a position");
}

bool PiecePathNode::match_position(QPos*qpos){
  uassert(false,"A piecepath filter was invoked only to determine whether it matched a position. Although legal, this might be due to user error");
  return false;
}

bool PiecePathNode::match_stringvalue(QPos*qpos, string*sval){
  uassert(qpos&&sval,"piecepathnode::match_stringvalue: invalid arguments");
  SquareMask fromsquares=theFrom->getSquares(qpos);
  if(fromsquares.empty())return false;
  QPos*topos{NULL};
  if(!theTo->match_positionvalue(qpos,&topos))
    return false;
  uassert(topos,"ppn msv topos");
  if(!QPos::isProperAncestor(qpos,topos))
    return false;
  vector<markT>pieceids; //just ints, the piece ids
  stringstream s;
  bool seenpiece{false};
  for(squareT sq=0;sq<64;++sq)
    if (fromsquares.member((int)sq)
	&&qpos->getPiece(sq)!=EMPTY){
    if (seenpiece)s<<' ';
    string nextpath=pathstring(sq,qpos,topos);
    if(nextpath.empty())continue;
    s<<nextpath;
    seenpiece=true;
  }
  if(seenpiece)
    *sval=s.str();
  return seenpiece;
}

string PiecePathNode::pathstring(const squareT sq, QPos*start, QPos*to){
  uassert(square_valid(sq)&&start&&to,"pathstring: bad args");
  uassert(start->getPiece(sq)!=EMPTY,"pathstring: empty piece");
  pieceT piece=start->getPiece(sq);
  uassert(piece!=EMPTY,"pathstring: bad piece");
  uassert(QPos::isProperAncestor(start,to),"unexpected nonancestor pathstring");
  markT mark=start->getMark(sq);
  uassert(mark.isValid(),"bad mark in ppnps");
  vector<QMove*>path=QPos::pathBetween(start,to);
  if(path.empty()) uassert(start==to,"bad path from pathBetween");
  else{
    uassert(path.back()->tail==to,"path err ppn");
    uassert(path.front()->head==start,"ppnps par");
  }
  stringstream s;
  s<<piece_to_char(piece)<<square_to_string(sq);
  uassert(to!=start,"expected distinct to,start piecepath");
  squareT lastsquare=sq;
  for(QMove* qmove:path){
    QPos*qpos=qmove->tail;
    squareT startsq=qpos->getSquare(mark);
    squareT currsq=startsq;
    if(!square_valid(currsq)){
      s<<'('<<'x'<<square_to_string(lastsquare)<<')';
      if (isVerbose)qpos->appendComment("path capture");
      break;
    }
    else if(currsq!=lastsquare){
      s<<'-'<<square_to_string(currsq);
      if(isVerbose)qpos->appendComment("path move");
      lastsquare=currsq;
    }
  }//for qpos:path
  string ret=s.str();
  if(ret.size()<=3) return "";
  return ret;
}
  
void PiecePathNode::deepify(){
  theFrom=theFrom->clone();
  theTo=theTo->clone();
}

vnode PiecePathNode::children()const{
  return vnode{theFrom,theTo};
}

