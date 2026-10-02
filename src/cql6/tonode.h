#pragma once
#include "fromtonode.h"
class ToNode:public FromToNode{
 public:
[[nodiscard]]  ToNode*clone()override;
  SquareMask getSquares(QPos*qpos) override;
  string thisclass()const override{return "ToNode";}
  ToNode();
  bool isToNode()const override{return true;}
};
  
