#include "transformvariable.h"

void TransformVariable::bindTransform(Transform*transform){
  value=transform;
  uassert(value,"transformvariable: bindTransform: null argument");
  bound=true;
}

Transform* TransformVariable::getValue()const{
  return value;
}

TransformVariable::TransformVariable(string nm){
  name=nm;
  uassert(name.size(),"pvpv nm");
  bound=false;
}

bool TransformVariable::match_position(QPos*qpos){
  uassert(isBound(),"Transform variable is not bound but attempt to access its value was made in a match transform: ",name);
  uassert(false,"an attempt to match a transform when filter is a transform variable. Although legal, this is likely an error: ",name);
  return true;
}
