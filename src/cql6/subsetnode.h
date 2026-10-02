#pragma once
#include "node.h"
class SubsetNode:public Node{
 public:
  SetBase*theLeft{NULL};
  SetBase*theRight{NULL};
  SubsetNode(SetBase* l, SetBase*r);
  bool match_position(QPos*);
  void deepify();
  string thisclass()const{return "SubsetNode";}
[[nodiscard]]  SubsetNode*clone();
  vnode children()const;
  void print();
};
