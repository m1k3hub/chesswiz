#pragma once
#include "node.h"
class ComplementNode:public SetBase{
 public:
  SetBase* theSet{NULL};
  ComplementNode(SetBase*);
  string thisclass()const{return "ComplementNode";}
[[nodiscard]]  ComplementNode* clone();
  vnode children()const;
  void print();
  bool match_position(QPos*);
  bool isSet()const;
  SquareMask getSquares(QPos*);
  void deepify();
};

