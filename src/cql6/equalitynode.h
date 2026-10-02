#pragma once
#include "node.h"
class EqualityNode: public Node{
 public:
  Node*left{NULL};
  Node*right{NULL};
  EqualityNode(Node*,Node*);
  string thisclass()const{return "EqualityNode";}
[[nodiscard]]  EqualityNode*clone();
  bool match_position(QPos*);
  void print();
  vnode children()const;
  void deepify();
};
