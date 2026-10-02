#pragma once
#include "variable.h"
#include "sortvariable.h"

class StringVariable:public SortVariable{
 private:
  string value;
 public:
  bool match_position(QPos*)override;
  bool match_stringvalue(QPos*,string*)override;
  StringVariable(string nm);
  bool isString()const override{return true;}
  string toString()override;
  string thisclass()const override{return "StringVariable";}
[[nodiscard]]  StringVariable* clone()override{return this;}
  string& getReference();
  string getValue()const;
  void clear();
  void bindString(const string& v);
  void print()override;
  void reset()override;
  void assignSortValue(SortValue*)const override;
  void bindSortValue(const SortValue&)override;
  SortValueType getSortValueType()override{return SortValueType::String;}
  bool isStringVariable()const override{return true;}
  StringVariable* asStringVariable()override{return this;}
  void assignAny(const Any& a)override;
  Any getAny()const override;
  bool isAtomizable()const override{return true;}
};


