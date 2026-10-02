#pragma once
#include "node.h"
class RemoveCommentNode:public Node{
 public:
  RemoveCommentNode(){};
  string thisclass()const override{return "RemoveCommentNode";}
[[nodiscard]]  RemoveCommentNode*clone() override;
  bool match_position(QPos*qpos)override;
  void print() override;
  vnode children()const override{return vnode{};}
  void deepify()override{};
};
