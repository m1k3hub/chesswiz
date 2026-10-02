#pragma once
#include "node.h"
enum class CaseConvertDirection{None,ToLower, ToUpper};
class CaseConvertNode : public Node{
 public:
  CaseConvertNode(Node*, CaseConvertDirection dir);
  Node*theNode{NULL};
  CaseConvertDirection theDirection{CaseConvertDirection::None};
  string thisclass()const{return "CaseConvertNode";}
  void deepify();
  bool match_position(QPos*);
  bool match_stringvalue(QPos*,string*);
  void print();
[[nodiscard]]  CaseConvertNode*clone();
  bool isString()const{return true;}
  vnode children()const;
};
