#pragma once
#include "node.h"
class NotNode:public Node{
 public:
  Node* filter{NULL};
  string thisclass()const{return "NotNode";}
[[nodiscard]]  NotNode* clone();
  vnode children()const;
  void print();
  NotNode(Node*np);
  bool match_position(QPos*);
  void deepify();
  bool isGameFilter()const;
};

