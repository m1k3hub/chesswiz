#pragma once
#include "node.h"
class GenericEqualNode: public Node{
 public:
  Node*theLeft{NULL};
  Node*theRight{NULL};
  GenericEqualNode(Node*,Node*);
  string thisclass()const override{return "GenericEqualNode";}
[[nodiscard]]  GenericEqualNode*clone()override;
  bool match_position(QPos*)override;
  void print()override;
  vnode children()const override;
  void deepify() override;
};
