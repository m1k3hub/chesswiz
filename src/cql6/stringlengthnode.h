#pragma once
#include "node.h"
class StringLengthNode : public Node{
 public:
  StringLengthNode(Node*);
  Node*theNode{NULL};
  string thisclass()const{return "StringLengthNode";}
  void deepify();
  bool match_position(QPos*);
  bool match_count(QPos*,NumValue*);
  void print();
[[nodiscard]]  StringLengthNode*clone();
  bool isNumeric()const{return true;}
  vnode children()const;
};
