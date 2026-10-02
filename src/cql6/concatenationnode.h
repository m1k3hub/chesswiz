#pragma once
#include "node.h"
class ConcatenationNode:public Node{
 public:
  Node*theLeft{NULL};
  Node*theRight{NULL};
  bool isDestructive{false};
  ConcatenationNode(Node*l, Node*r,bool isdestructive=false);
  bool match_position(QPos*);
  bool match_stringvalue(QPos*, string*);
  bool isString()const;
  void deepify();
  string thisclass()const{return "ConcatenationNode";}
[[nodiscard]]  ConcatenationNode*clone();
  vnode children()const;
  void print();
};
