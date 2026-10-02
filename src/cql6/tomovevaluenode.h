#pragma once
#include "node.h"
class ToMoveValueNode : public Node{
 public:
  static const NumValue WhiteValue{1};
  static const NumValue BlackValue{-1};
  ToMoveValueNode();
  string thisclass()const{return "ToMoveValueNode";}
[[nodiscard]]  ToMoveValueNode*clone();
  void print();
  bool match_position(QPos*);
  bool match_count(QPos*,NumValue*);
  vnode children()const;
  void deepify();
  bool isNumeric()const{return true;}
};
    
