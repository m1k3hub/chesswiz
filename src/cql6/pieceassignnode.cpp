#include "pieceassignnode.h"
#include "pieceidvariable.h"

PieceAssignNode::PieceAssignNode(PieceIdVariable*v,SetBase*s):var(v),set(s){
  uassert(var&&set,"pan args");
}

void PieceAssignNode::deepify(){
  set=set->clone();
}

vnode PieceAssignNode::children()const{
  vnode ret{var};
  if(set!=var) ret.push_back(set);
  return ret;
}

bool PieceAssignNode::match_position(QPos*qpos){
  SquareMask squares=set->getSquares(qpos);
  if(squares.count()!=1)return false;
  ForMask(sq,squares){
    markT pieceid=qpos->getMark(sq);
    if(!pieceid.isValid())return false;
    uassert(qpos->getSquare(pieceid)==sq,"pieceassignnode pieceid square");
    if(var->isBound())var->unbind();
    var->bindPieceId(qpos,pieceid);
    return true;
  }
  uassert(false,"PieceAssignNode loop");
  return false;
}
