#pragma once
#include "node.h"
class DistanceNode: public Node{
 public:
  DistanceNode(Node*l, Node*r);
  Node*left{NULL};
  Node*right{NULL};
  string thisclass()const{return "DistanceNode";}
[[nodiscard]]  DistanceNode*clone();
  bool isNumeric()const{return true;}
  void deepify();
  vnode children()const;
  bool match_position(QPos*qpos);
  bool match_count(QPos*qpos, NumValue*value);
  void print();
};
