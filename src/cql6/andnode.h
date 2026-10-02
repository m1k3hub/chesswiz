#pragma once
#include "node.h"
class AndNode: public Node{
 public:
  Node* clause1{NULL};
  Node* clause2{NULL};
  bool match_position(QPos*)override;
  AndNode(Node*c1, Node*c2);
  vnode children()const override;
  void print() override;
  string thisclass()const override{return "AndNode";}
  [[nodiscard]]AndNode*clone() override;
  void deepify() override;
  bool isGameFilter()const override;
};

