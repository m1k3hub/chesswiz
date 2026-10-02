#include "squarevariable.h"
  
SquareVariable::SquareVariable(string nm){
  name=nm;
  uassert(name.size(),"sv internal");
}

SquareMask SquareVariable::getSquares(QPos*qpos){
  eassert(bound,"attempt to access unbound square variable: ",name);
  return mask;
}
SquareMask SquareVariable::getMask()const{
  eassert(isBound(),"Attempt to access the value of a square variable that is not bound: ",name);
  return mask;
}

void SquareVariable::bindMask(SquareMask m){
  mask=m;
  bound=true;
  used=false;
}

void SquareVariable::bindSquare(squareT s){
  uassert(!bound,"attempt to bind variable already bound: ",name);
  uassert(square_valid(s),"internal bad square argument to bindSquare");
  mask=SquareMask::fromSquare(s);
  used=false;
  bound=true;
}


void SquareVariable::assignAny(const Any&a){
  if(AnyValue::isUnbound(a))
    unbind();
  else if(AnyValue::isSquareMask(a))
    bindMask(AnyValue::squareMaskValue(a));
  else uassert(false,"Sqv aa");
}

Any SquareVariable::getAny()const{
  if(isUnbound())
    return Any(false);
  return Any(mask);
}

  
    
