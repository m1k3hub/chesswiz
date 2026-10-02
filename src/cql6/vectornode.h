#pragma once
#include "node.h"
class VectorNode : public SetBase{
 public:
  DirectionParameter parameter;
  SetBase* source{NULL};
  string thisclass()const{return "VectorNode";}
[[nodiscard]]  VectorNode*clone();
  void print();
  bool transformmemberless(const Node*)const;
  vnode children()const;
  bool match_position(QPos*qpos);
  SquareMask getSquares(QPos*qpos);
  VectorNode(DirectionParameter dp,SetBase* source);
  void deepify(){source=source->clone();}
  void transform_members(Transform*);
 private:
  SquareMask neighborhoods[64];
  int lastMin{-8};
  int lastMax{-8};
  bool neighborhoodsvalid{false};
  void makeNeighborhoods();
};
