#pragma once
#include "variable.h"
#include "sortvariable.h"

class NumericVariable:public SortVariable{
 private:
  NumValue value{0};
 public:
  bool match_count(QPos*,NumValue*)override;
  bool match_position(QPos*)override;
  bool isNumeric()const override{return true;}
  void increment();
  NumericVariable(string nm);
  SortValueType getSortValueType()override{return SortValueType::Numeric;}
  string toString()override;
  string thisclass()const override{return "NumericVariable";}
[[nodiscard]]  NumericVariable* clone()override{return this;}
  NumValue getValue()const;
  void clear();
  void bindNumeric(NumValue v);
  void print()override;
  void reset()override;
  void assignSortValue(SortValue*)const override;
  void bindSortValue(const SortValue&)override;
  void assignAny(const Any& a)override;
  Any getAny()const override;
  bool isAtomizable()const override{return true;}
};


