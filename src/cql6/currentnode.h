#pragma once
#include "node.h"
class CurrentNode : public Node{
 public:
  CurrentNode();
  bool match_position(QPos*);
  void deepify();
  string thisclass()const{return "CurrentNode";}
[[nodiscard]]  CurrentNode*clone();
  vnode children()const;
  void print();
  bool match_positionvalue(QPos*, QPos**);
  bool isPosition()const{return true;}
};
  
