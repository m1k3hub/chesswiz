#pragma once
#include "node.h"

class StringLiteralNode:public Node{
 public:
  StringLiteralNode(string);
  bool isString()const{return true;}
  const string theName;
  string getName()const{return theName;}
  vnode children()const{return vnode();}
  bool match_position(QPos*qpos);
  bool match_stringvalue(QPos*qpos,string*stringp);
[[nodiscard]]  StringLiteralNode*clone();
  void deepify(){}
  string thisclass()const{return "StringLiteralNode";}
  void print();
  bool isGameFilter()const{return true;}
};
  
