#pragma once
#include "cqlassert.h"
#include "abbreviations.h"
constexpr int markTMax=32;//exclusive upper bound (to support markt foo[markTMax];)
constexpr int markTInvalid=-1;
class markT{
 public:
  int theValue{markTInvalid};
  markT(){};
  explicit markT(int v):theValue(v){
    uassert(theValue==markTInvalid||
	    theValue>=0&&theValue<markTMax,"markT: invalid constructor parameter");
  }
  int getValue()const{return theValue;}
  void setValue(int v){
    theValue=v;
    uassert(isLegal(),"invalid argument to markT set");
  }
  bool isLegal()const{return theValue==markTInvalid||theValue>=0&&theValue<markTMax;}
  bool isValid()const{return theValue>=0&&theValue<markTMax;}
  bool isInvalid()const{return !isValid();}
  bool isIllegal()const{return !isLegal();}
  void makeInvalid(){theValue=markTInvalid;}
  static markT zero(){return markT{0};}
  string toString()const;
  string thisclass()const{return "markT";}
  bool operator==(markT g)const{return theValue==g.theValue;}
  void inc(){uassert(isValid(),"markT bad inc");
    ++theValue;
    if(theValue==markTMax) theValue=markTInvalid;}
};
std::ostream&operator<<(std::ostream&os,markT const&mark);
