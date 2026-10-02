#pragma once
#include "tagentry.h"
#include "util.h"
class QGame;
class TagSection{
 public:
  vector<TagEntry>theEntries;
  bool exists(const string& name)const;
  void deleteTag(const string& name);
  bool getGameValue(const string&name, string*value)const;
  void setValue(const string& name, const string& value);
  void initialize(QGame*);
  string toString();
  static bool isForbiddenName(const string& name);
  static const vector<string> unchangeableTagNames;
  bool isInitialized{false};
  void merge(QGame*);
};
  
  
