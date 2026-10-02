#include "lambdavariable.h"

void LambdaVariable::bindLambda(LambdaValue v){
  value=v;
  bound=true;
}

LambdaValue LambdaVariable::getValue()const{
  return value;
}

LambdaVariable::LambdaVariable(string nm,LambdaValue v):value(v){
  name=nm;
  uassert(name.size(),"lvlv nm");
  bound=true;
}



