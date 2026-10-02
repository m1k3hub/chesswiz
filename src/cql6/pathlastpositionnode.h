#pragma once
#include "pathreferencenode.h"
class PathLastPositionNode:public PathReferenceNode{
 public:
  bool isPathLastPosition()const override{return true;}
  PathLastPositionNode();
  string thisclass()const override{return "PathLastPositionNode";}
  bool match_position(QPos*) override;
  bool isPosition()const override{return true;}
  bool match_positionvalue(QPos*,QPos**) override;
[[nodiscard]]  PathLastPositionNode*clone()override;
};
