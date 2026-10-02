#pragma once
#include "variable.h"
#include "qpos.h"

class TransformVariable:public Variable{
 private:
  Transform* value;
 
 public:
  TransformVariable(string nm);
  bool isTransform()const{return true;}
  bool match_position(QPos*qpos);
  string toString();
  string thisclass()const{return "TransformVariable";}
[[nodiscard]]  TransformVariable* clone() {return this;}
  void bindTransform(Transform* value);
  Transform* getValue()const;
};
