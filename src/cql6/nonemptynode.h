#pragma once
#include "node.h"
class NonemptyNode : public Node{
 public:
  SetBase*set{NULL};
  NonemptyNode(SetBase*);
  string thisclass()const{return "NonemptyNode";};
[[nodiscard]]  NonemptyNode*clone();
  void deepify();
  vnode children()const;
  void print();
  bool match_position(QPos*);
};
