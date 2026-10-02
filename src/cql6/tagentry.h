#pragma once
#include<string>
using std::string;
class TagEntry{
 public:  
  const string theName;
  string theValue;
  string gameValue;
  bool isDeleted{false};
  bool isModified{false};
  bool isFromGame{false};
  string toString()const;
  void setValue(const string& value);
  TagEntry(const string& name, const string& value, bool isfromgame=false);
  string getName()const{return theName;}
  string getValue()const{return theValue;}
  string getGameValue()const;
};
