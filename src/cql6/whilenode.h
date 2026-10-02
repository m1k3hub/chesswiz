#pragma once
#include "node.h"
class WhileNode : public Node{
 public:
  Node*theTest{NULL};
  Node*theBody{NULL};
  string thisclass()const{return "WhileNode";}
  WhileNode(Node*test, Node*body);
[[nodiscard]]  WhileNode*clone();
  vnode children()const;
  void deepify();
  bool match_position(QPos*);
  void print();
};
