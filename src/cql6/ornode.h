#pragma once
#include "node.h"
class OrNode: public Node{
 public:
  Node* clause1{NULL};
  Node* clause2{NULL};
  bool match_position(QPos*);
  OrNode(Node*c1, Node*c2);
  vnode children()const;
  void print();
  string thisclass()const{return "OrNode";}
[[nodiscard]]  OrNode*clone();
  void deepify();
  bool isGameFilter()const;
};

