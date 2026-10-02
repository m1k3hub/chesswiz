#pragma once
#include "node.h"
class VirtualMainlineNode : public Node{
 public:
  VirtualMainlineNode(){};
  string thisclass()const{return "VirtualMainlineNode";}
[[nodiscard]]  VirtualMainlineNode*clone();
  vnode children()const{return vnode{};}
  void deepify(){}
  bool match_position(QPos*);
  void print();
};
