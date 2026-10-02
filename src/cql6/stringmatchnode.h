#pragma once
#include "node.h"
#include <regex>
class StringMatchNode:public Node{
 public:
  Node* targetNode{NULL};
  string thePattern;
  StringMatchNode(Node*targetnode, const string& pattern);
  string thisclass()const{return "StringMatchNode";}
[[nodiscard]]  StringMatchNode* clone();
  void print();
  bool match_position(QPos*qpos);
  bool match_stringvalue(QPos*qpos,string*stringp);
  vnode children()const;
  bool isString()const{return true;}
  void deepify();
private:
  std::regex theRegex;
};

