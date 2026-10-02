#pragma once
#include "node.h"
#include "variable.h"
class IsBoundNode:public Node{
 public:
  IsBoundNode(string name);
  Variable*theVariable{NULL};
  string theName;
  string thisclass()const{return "isBoundNode";}
[[nodiscard]]  IsBoundNode* clone();
  vnode children()const;
  void print();
  bool match_position(QPos*);
  void deepify();
  Variable*getVariable()const{return theVariable;}
  string getName()const{return theName;}
  void setVariable(Variable*);
};

