#pragma once
#include "node.h"
class GotoNode : public Node{
 public:
  GotoNode(Node*);
  Node*target{NULL};
  string thisclass()const override{return "GotoNode";}
[[nodiscard]]  GotoNode*clone()override;
  string toString(){return "GotoNode";}
  vnode children()const override;
  bool match_position(QPos*qpos)override;
  bool isPosition()const override{return true;}
  bool match_positionvalue(QPos*,QPos**)override;
  void deepify()override;
  void print()override;
  bool canModifyCurpos()const override{return true;}
};
  
