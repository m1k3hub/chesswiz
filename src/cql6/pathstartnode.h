#pragma once
#include "pathreferencenode.h"
class PathStartNode:public PathReferenceNode{
 public:
  bool isPathStart()const override{return true;}
  PathStartNode();
  string thisclass()const override{return "PathStartNode";}
  bool match_position(QPos*) override;
  bool isPosition()const override{return true;}
  bool match_positionvalue(QPos*,QPos**) override;
[[nodiscard]]  PathStartNode*clone()override;
};
