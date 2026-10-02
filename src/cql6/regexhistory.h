#pragma once
#include "util.h"
#include <regex>
class RegexHistory{
 public:
  void registerMatch(const std::smatch & matchresult);
  int getNgroups()const;
  bool groupString(int group, string*)const;
  int groupStart(int group)const; //return -1 if no match
  void clear();
  string toString()const;
 private:
  vector<string>groupStrings;
  vector<int>groupStarts;
  vector<bool>groupMatched;
};
