#pragma once
#include "node.h"
class ParentNode : public Node{
 public:
  ParentNode();
  string thisclass()const override{return "ParentNode";}
[[nodiscard]]  ParentNode*clone()override;
  void print()override;
  void deepify()override;
  vnode children()const override;
  bool isPosition()const override{return true;}
  bool match_position(QPos*)override;
  bool match_positionvalue(QPos*,QPos**)override;
  bool canModifyCurpos()const override{return true;}
};
  
