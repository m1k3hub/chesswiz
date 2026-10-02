#pragma once
#include "node.h"
class StringToIntNode : public Node{
 public:
  StringToIntNode(Node*);
  Node*theNode{NULL};
  string thisclass()const{return "StringToIntNode";}
  void deepify();
  bool match_position(QPos*);
  bool match_count(QPos*,NumValue*);
  void print();
[[nodiscard]]  StringToIntNode*clone();
  bool isNumeric()const{return true;}
  vnode children()const;
};
