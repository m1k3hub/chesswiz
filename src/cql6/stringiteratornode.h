#pragma once
#include "node.h"
#include<regex>
#include "stringvariable.h"
class StringIteratorNode:public Node{
 public:
  Node* theTarget{NULL};
  string thePattern;
  Node* theBody{NULL};
  StringIteratorNode(Node* target, const string&pattern, Node*body);
  string thisclass()const{return "StringIteratorNode";}
[[nodiscard]]  StringIteratorNode* clone();
  void print();
  bool match_position(QPos*qpos);
  vnode children()const;
  void deepify();
private:
  std::regex theRegex;
};
