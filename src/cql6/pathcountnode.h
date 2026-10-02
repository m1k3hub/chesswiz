#pragma once
#include "pathreferencenode.h"
class PathCountNode:public PathReferenceNode{
 public:
  bool isPathCount()const override{return true;}
  PathCountNode();
  string thisclass()const override{return "PathCountNode";}
  bool match_position(QPos*) override;
  bool isNumeric()const override{return true;}
  bool match_count(QPos*,NumValue*) override;
[[nodiscard]]  PathCountNode*clone() override;
};
