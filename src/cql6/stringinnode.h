#pragma once
#include "node.h"
class StringInNode:public Node{
 public:
  Node*theLeft{NULL};
  Node*theRight{NULL};
  bool computeIndex{false}; //return the index of pattern in target
  bool isImplicit{false}; // true if this node is formed from an implicit parameter
  int implicitParameterIndex{-1}; //location in the Tokens stream where the implicit parameter occurred
  StringInNode(Node*l, Node*r, bool computeindex=false);
  bool match_position(QPos*);
  bool match_count (QPos*qpos,NumValue*valp);
  bool isNumeric()const{return computeIndex;}
  void deepify();
  string thisclass()const{return "StringInNode";}
[[nodiscard]]  StringInNode*clone();
  vnode children()const;
  void print();
};
