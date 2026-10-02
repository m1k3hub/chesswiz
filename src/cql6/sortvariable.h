#pragma once
#include "variable.h"
#include "sortvalue.h"
class SortVariable: public Variable{
 public:
  bool match_position(QPos*);
  bool isSet()const{return false;}
  virtual string getStringValue()const;
  virtual NumValue getNumericValue()const;
  virtual bool isString()const{return false;}
  virtual bool isSort() const {return true;}
  virtual bool isNumeric()const{return false;}
  virtual bool getSquare(squareT*s);//for compilation only - error to call
  virtual string toString()=0;
  virtual void assignSortValue(SortValue*)const=0;
  virtual void bindSortValue(const SortValue&)=0;
  virtual SortValueType getSortValueType()=0;
  virtual SortVariable* asSortVariable(){return this;}
  //  virtual string thisclass()const=0;
[[nodiscard]]  SortVariable* clone(){return this;}

};
