#pragma once
#include "node.h"
class ChildNode : public Node{
 public:
  Node* indexNode{NULL};
  ChildNode(Node* index);
  string thisclass()const override{return "ChildNode";}
[[nodiscard]]  ChildNode*clone()override;
  void print()override;
  void deepify()override;
  vnode children()const override;
  bool isPosition()const override{return true;}
  bool match_position(QPos*)override;
  bool match_positionvalue(QPos*,QPos**)override;
  bool canModifyCurpos()const override{return true;}
};
  
