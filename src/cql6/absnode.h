#pragma once
#include "node.h"
class AbsNode: public Node{
 public:
  Node*node{NULL};
  AbsNode(Node*);
  string thisclass()const{return "AbsNode";}
  [[nodiscard]]AbsNode* clone();
  vnode children()const;
  void deepify();
  void print();
  bool match_count(QPos*,NumValue*);
  bool match_position(QPos*);
  bool isNumeric()const{return true;}
};
  
