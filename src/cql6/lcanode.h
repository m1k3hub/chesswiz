#pragma once
#include "node.h"
class LcaNode: public Node{
 public:
  LcaNode(Node*l, Node*r);
  Node*left{NULL};
  Node*right{NULL};
  string thisclass()const{return "LcaNode";}
[[nodiscard]]  LcaNode*clone();
  bool isPosition()const{return true;}
  void deepify();
  vnode children()const;
  bool match_position(QPos*qpos);
  bool match_positionvalue(QPos*qpos, QPos**qposp);
  void print();
};
