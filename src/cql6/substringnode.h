#pragma once
#include "node.h"
#include "bracketrange.h"
class SubstringNode:public Node{
 public:
  SubstringNode(Node*target,BracketRange*bracket);
  Node*theTarget{NULL};
  BracketRange*theBracket{NULL};
  string thisclass()const{return "SubstringNode";}
[[nodiscard]]  SubstringNode* clone();
  bool isString()const{return true;}
  vnode children()const;
  void print();
  bool match_position(QPos*);
  bool match_stringvalue(QPos*,string*);
  void deepify();
  static const NumValue End;
};

