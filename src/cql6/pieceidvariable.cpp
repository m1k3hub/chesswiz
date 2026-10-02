#include "pieceidvariable.h"


PieceIdVariable::PieceIdVariable(string nm){
  name=nm;
  uassert(!name.empty(),"tvtv nm");
}

bool PieceIdVariable::getSquare(QPos*qpos, squareT*s){
  uassert(bound,"internal pieceid get");
  uassert(pieceid.isValid(),"tvgs valid");
  int soption=qpos->getSquare(pieceid);
  if (!square_valid(soption)) return false;
  *s=soption;
  return true;
}

void PieceIdVariable::bindPieceId(QPos*qpos,markT val){
  uassert(val.isValid(),"tvbt val");
  eassert(isUnbound(),"attempt to bind ID when it is already bound");
  pieceid=val;
  bound=true;
}

markT PieceIdVariable::getPieceId(){
  uassert(bound,"PieceIdVariable getPieceId: unbound");
  return pieceid;
}

SquareMask PieceIdVariable::getSquares(QPos*qpos){
  eassert(isBound(), "Unexpected unbound piece variable: ",name);
  squareT square=65;
  bool valid=getSquare(qpos,&square);
  if (valid){
    uassert(square_valid(square),"pieceid getsquares internal");
    return SquareMask::fromSquare(square);
  }
  else return SquareMask();
}


  
