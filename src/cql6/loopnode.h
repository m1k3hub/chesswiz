#pragma once
#include "node.h"
class LoopNode : public Node{
 public:
  Node*node{NULL};
  string thisclass()const{return "LoopNode";}
  LoopNode(Node*);
[[nodiscard]]  LoopNode*clone();
  vnode children()const;
  void deepify();
  bool match_position(QPos*);
  void print();
};
