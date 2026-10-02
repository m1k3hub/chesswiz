#pragma once
#include "node.h"
enum class AsciiDirection{None,ToAscii, FromAscii};
class StringAsciiNode : public Node{
 public:
  StringAsciiNode(Node*node, AsciiDirection);
  Node*theNode;
  AsciiDirection theDirection{AsciiDirection::None};
  bool isString()const{return theDirection==AsciiDirection::FromAscii;}
  bool isNumeric()const{return theDirection==AsciiDirection::ToAscii;}
  string thisclass()const{return "StringAsciiNode";}
[[nodiscard]]  StringAsciiNode* clone();
  void print();
  bool match_position(QPos*qpos);
  bool match_stringvalue(QPos*qpos,string*stringp);
  bool match_count(QPos*qpos,NumValue*valp);
  vnode children()const{return vnode{theNode};}
  void deepify();
};

