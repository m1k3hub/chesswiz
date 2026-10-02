#pragma once
#include "variable.h"
#include <map>

class Dictionary:public Variable{
 private:
  std::map<Any,Any>theMap;
 public:
  Dictionary(string name, bool ispersistent);
  ValueType keyType{ValueType::None};
  ValueType valueType{ValueType::None};
  void setTypes(ValueType,ValueType);
  bool match_position(QPos*)override;
  bool isDictionary()const override{return true;}
  string toString()override;
  string thisclass()const override{return "Dictionary";}
[[nodiscard]]  Dictionary* clone()override{return this;}
  std::map<Any,Any>& getMap(){return theMap;}
  const std::map<Any,Any>& getMap()const{return theMap;}
  int count()const;
  void print()override;
  void clear();
  bool isNumericValue()const;
  bool isStringValue()const;
  bool isPositionValue()const;
  bool isSetValue()const;
  bool hasKey(const Any& key)const;
  void assignValue(const Any&key, const Any& value);
  bool getValue(const Any&key, Any * result)const;
  void deleteKey(const Any&key);
  vector<Any>getKeys()const;
  bool verifyKey(Node*key);
  bool verifyValue(Node*value);
  void reset()override;
};


