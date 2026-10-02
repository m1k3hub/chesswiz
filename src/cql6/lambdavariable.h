#pragma once
#include "variable.h"
#include "lambdavalue.h"

class LambdaVariable:public Variable{
 private:
  LambdaValue value;
 
 public:
  LambdaVariable(string nm,LambdaValue lv);
  bool isLambda()const{return true;}
  bool match_position(QPos*qpos) {return true;}
  string toString();
  string thisclass()const{return "LambdaVariable";}
[[nodiscard]]  LambdaVariable* clone() {return this;}
  void bindLambda(LambdaValue value);
  LambdaValue getValue()const;
};
