#pragma once
#include "node.h"
class TrueNode: public Node{
 public:
  bool match_position(QPos*)override{return true;}
  TrueNode(){};
  vnode children()const override{return vnode{};}
  void print() override;
  string thisclass()const override{return "TrueNode";}
[[nodiscard]]  TrueNode*clone() override;
  bool isGameFilter()const override{return true;}
  void deepify()override{};
};

