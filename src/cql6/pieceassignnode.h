#pragma once
#include "node.h"
class PieceAssignNode : public Node{
 public:
  PieceIdVariable* var{NULL};
  SetBase*set{NULL};
  PieceAssignNode(PieceIdVariable*,SetBase*);
  string thisclass()const{return "PieceAssignNode";};
  void deepify();
  vnode children()const;
  void print();
  bool match_position(QPos*qpos);
[[nodiscard]]  PieceAssignNode *clone();
};
