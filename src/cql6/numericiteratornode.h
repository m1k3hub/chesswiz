#pragma once
#include "node.h"
#include "numericvariable.h"

class NumericIteratorNode:public Node{
 public:
  NumericVariable* theVariable{NULL};
  Node* lowerBound{NULL};
  Node* upperBound{NULL};
  Node* theBody{NULL};
  NumericIteratorNode(NumericVariable*,Node* lowerbound, Node*upperbound, Node*body);
  string thisclass()const{return "NumericIteratorNode";}
[[nodiscard]]  NumericIteratorNode* clone();
  void print();
  bool match_position(QPos*qpos);
  vnode children()const;
  void deepify();
};
