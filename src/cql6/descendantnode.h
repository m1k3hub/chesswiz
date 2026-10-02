#pragma once
#include "node.h"
class DescendantNode: public Node{
 public:
  DescendantNode(Node*l, Node*r);
  Node*left{NULL};
  Node*right{NULL};
  string thisclass()const{return "DescendantNode";}
[[nodiscard]]  DescendantNode*clone();
  bool isNumeric()const{return true;}
  void deepify();
  vnode children()const;
  bool match_position(QPos*qpos);
  void print();
};
