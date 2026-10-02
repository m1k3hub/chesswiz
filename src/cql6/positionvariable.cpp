#include "positionvariable.h"

void PositionVariable::bindPosition(QPos*qpos){
  value=qpos;
  uassert(value,"positionvariable: bindPosition: null argument");
  bound=true;
}

QPos* PositionVariable::getValue()const{
  return value;
}

PositionVariable::PositionVariable(string nm){
  name=nm;
  uassert(name.size(),"pvpv nm");
  bound=false;
}

bool PositionVariable::match_positionvalue(QPos*qpos, QPos**valuep){
  eassert(isBound(),"Position variable is not bound but attempt to access its value was made: ",name);
  *valuep=value;
  return true;
}

bool PositionVariable::match_position(QPos*qpos){
  eassert(isBound(),"Position variable is not bound but attempt to access its value was made in a match position: ",name);
  eassert(false,"an attempt to match a position when filter is a position variable. Although legal, this is likely an error: ",name);
  return true;
}

void PositionVariable::assignAny(const Any&a){
  if(AnyValue::isUnbound(a))
    unbind();
  else if(AnyValue::isQPos(a))
    bindPosition(AnyValue::qPosValue(a));
  else uassert(false,"position variable aa");
}

Any PositionVariable::getAny()const{
  if(isUnbound())
    return Any(false);
  return Any(value);
}
