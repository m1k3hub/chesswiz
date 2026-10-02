#pragma once
#include "node.h"
class ToMoveNode:public Node{
 public:
  string thisclass()const{return "ToMoveNode";}
  void print();
  bool match_position(QPos*);
  colorT color;
  ToMoveNode(colorT c);
[[nodiscard]]  ToMoveNode*clone();
  vnode children()const;
  void transform_members(Transform*);
  void deepify();
  bool transformmemberless(const Node*)const;
};
