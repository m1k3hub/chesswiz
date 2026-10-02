#pragma once
#include "node.h"
#include "variable.h"
class UnbindNode:public Node{
 public:
  explicit UnbindNode(Variable*);
  Variable*theVariable{NULL};
  string thisclass()const{return "UnbindNode";}
[[nodiscard]]  UnbindNode*clone();
  vnode children()const;
  void print();
  void deepify();
  bool match_position(QPos*);
};
