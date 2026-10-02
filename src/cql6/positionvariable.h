#pragma once
#include "variable.h"
#include "qpos.h"

class PositionVariable:public Variable{
 private:
  QPos* value;
 
 public:
  PositionVariable(string nm);
  bool isPosition()const override{return true;}
  bool match_position(QPos*qpos)override;
  bool match_positionvalue(QPos*, QPos**)override;
  string toString()override;
  string thisclass()const override{return "PositionVariable";}
[[nodiscard]]  PositionVariable* clone() override{return this;}
  void bindPosition(QPos* value);
  QPos* getValue()const;
  void assignAny(const Any& a)override;
  Any getAny()const override;
  bool isAtomizable()const override{return true;}

};
