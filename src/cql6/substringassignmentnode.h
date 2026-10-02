#pragma once
#include "node.h"
#include "bracketrange.h"
#include "stringvariable.h"
class SubstringAssignmentNode:public Node{
 public:
  SubstringAssignmentNode(StringVariable*target,BracketRange*bracket,Node*right);
  StringVariable*theTarget{NULL};
  BracketRange*theBracket{NULL};
  Node*theRight{NULL};
  string thisclass()const{return "SubstringAssignmentNode";}
[[nodiscard]]  SubstringAssignmentNode* clone();
  vnode children()const;
  void print();
  bool match_position(QPos*);
  void deepify();
};

