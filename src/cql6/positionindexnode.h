#pragma once
#include "node.h"
class PositionIndexNode: public Node{
 public:
  PositionIndexNode();
  string thisclass()const{return "PositionIndexNode";}
[[nodiscard]]  PositionIndexNode*clone();
  vnode children()const;
  void deepify();
  bool isNumeric()const{return true;}
  bool match_position(QPos*);
  bool match_count(QPos*,NumValue*);
  void print();
};
    
