#pragma once
#include "pathreferencenode.h"
class PathDebugNode:public PathReferenceNode{
 public:
  bool isPathDebug()const override{return true;}
  PathDebugNode();
  string thisclass()const override{return "PathDebugNode";}
  bool match_position(QPos*) override;
[[nodiscard]]  PathDebugNode*clone()override;
};
