#pragma once
#include "util.h"
enum class SortValueType{None, String,Numeric};
enum class SortDirection{None, Down, Up};
class SortValue{
 public:
  bool isMax()const{return theDirection==SortDirection::Down;}
  bool isMin()const{return theDirection==SortDirection::Up;}
  bool isString()const{return theSortValueType==SortValueType::String;}
  bool isNumeric()const{return theSortValueType==SortValueType::Numeric;}
  NumValue getNumericValue()const;
  string getStringValue()const;
  void print();
  SortValue(NumValue v,SortDirection dir);
  SortValue(string s, SortDirection dir);
  SortValue(SortValueType,SortDirection dir); //for unbound versions
  SortValue(){};
  bool isBound()const{return theIsBound;}
  bool isUnbound()const{return !theIsBound;}
  string thisclass()const{return "SortValue";}
  SortValueType getType()const{return theSortValueType;}
  void clear(){theIsBound=false;}
  void unbind(){theIsBound=false;}
  void bind(NumValue v);
  void bind(string s);
  string toString()const;
  bool isNone(){return theDirection == SortDirection::None;}
  SortDirection getDirection()const{return theDirection;}
 private:
  SortValueType theSortValueType{SortValueType::None};
  NumValue theNumericValue{559999}; //obviously these should be  union
  string theStringValue;
  SortDirection theDirection{SortDirection::None}; //greater is better. Not const so assignment works I guess.
  bool theIsBound{false};     //value has a meaning.
};

bool operator< (const SortValue& a, const SortValue& b);

  
  
