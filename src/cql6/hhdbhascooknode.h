#pragma once
#include "node.h"
class HhdbHasCookNode : public Node{
 public:
  HhdbHasCookNode(){};
  bool match_position(QPos*qpos);
  string thisclass()const{return "HhdbHasCookNode";}
[[nodiscard]]  HhdbHasCookNode*clone();
  vnode children()const{return  vnode{};};
  void deepify(){};
  void print();
};
  
    
