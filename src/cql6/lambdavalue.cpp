#include "lambdavalue.h"
#include "myvector.h"
#include "cqlassert.h"
LambdaValue::LambdaValue(vector<string>ps,vector<Token*>b):
  parameters(ps), body(b){
  for (auto s : parameters)
    uassert(s.size(),"null param to lambdavalue::lambdavalue");
  uassert(myisset(parameters),"repeated formal parameter LVLV");
  uassert(body.size(),"Empty body LVLV");
}

void LambdaValue::print(){
  printf("%s",toString().c_str());
}

  
  
