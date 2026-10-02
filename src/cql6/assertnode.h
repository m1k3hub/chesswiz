#pragma once
#include "node.h"
class AssertNode:public Node{
 public:
  AssertNode(Node*node,string name);
  Node*theNode{NULL};
  Variable*theVariable{NULL};
  string theName;
  string thisclass()const{return "AssertNode";}
  [[nodiscard]]AssertNode* clone();
  vnode children()const;
  void print();
  bool match_position(QPos*);
  void deepify();
  
};

