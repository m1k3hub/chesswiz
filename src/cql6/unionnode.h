#pragma once
#include "node.h"
class UnionNode: public SetBase{
 public:
  SetBase* clause1{NULL};
  SetBase* clause2{NULL};
  bool match_position(QPos*);
  SquareMask getSquares(QPos*);
  UnionNode(SetBase*c1, SetBase*c2);
  vnode children()const;
  void print();
  string thisclass()const{return "UnionNode";}
[[nodiscard]]  UnionNode*clone();
  void deepify();
};


