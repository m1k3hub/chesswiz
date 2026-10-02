#pragma once
#include "variable.h"
class SquareVariable:public Variable{
 private:
  SquareMask mask;
  bool used{false}; //make sure this is modified for current version!
 
 public:
  SquareVariable(string nm);
  bool isSet()const override{return true;}
  bool isSquare()const override{return true;}
  bool isUsed()const {return used;}
  string toString()override;
  string thisclass()const override{return "SquareVariable";}
[[nodiscard]]  SquareVariable* clone() override{return this;}
  void bindSquare(squareT s);
  void bindMask(SquareMask m);
  SquareMask getMask()const;
  SquareMask getSquares(QPos*qpos) override;
  void assignAny(const Any& a)override;
  Any getAny()const override;
  bool isAtomizable()const override{return true;}
};

