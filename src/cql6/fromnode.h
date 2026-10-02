#pragma once
#include "fromtonode.h"
class FromNode:public FromToNode{
 public:
[[nodiscard]]  FromNode*clone()override;
  SquareMask getSquares(QPos*qpos) override;
  string thisclass()const override{return "FromNode";}
  FromNode();
  bool isFromNode()const override{return true;}
};
  
