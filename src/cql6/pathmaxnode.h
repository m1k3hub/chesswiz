#pragma once
#include "pathreferencenode.h"
class PathMaxNode:public PathReferenceNode{
 public:
  bool isPathMax()const override{return true;}
  PathMaxNode();
  string thisclass()const override{return "PathMax";}
  bool match_position(QPos*) override;
  bool isNumeric()const override{return true;}
  bool match_count(QPos*,NumValue*) override;
[[nodiscard]]  PathMaxNode*clone() override;
};
