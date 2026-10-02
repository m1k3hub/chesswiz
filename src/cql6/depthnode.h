#pragma once
#include "node.h"
class DepthNode : public Node{
 public:
  DepthNode(){};
  string thisclass()const{return "DepthNode";}
[[nodiscard]]  DepthNode*clone();
  bool match_count(QPos*,NumValue*value);
  string toString(){return "DepthNode";}
  vnode children()const{return vnode{};}
  bool match_position(QPos*qpos){return true;}
  bool isNumeric()const{return true;}
  void deepify(){};
  void print();
};
  
