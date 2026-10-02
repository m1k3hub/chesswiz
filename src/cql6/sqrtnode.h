#pragma once
#include "node.h"
class SqrtNode: public Node{
 public:
  Node*node{NULL};
  SqrtNode(Node*);
  string thisclass()const{return "SqrtNode";}
[[nodiscard]]  SqrtNode* clone();
  vnode children()const;
  void deepify();
  void print();
  bool match_count(QPos*,NumValue*);
  bool match_position(QPos*);
  bool isNumeric()const{return true;}
};
  
