#pragma once
#include "node.h"
class PlyNode : public Node{
 public:
  PlyNode(){};
  string thisclass()const{return "PlyNode";}
[[nodiscard]]  PlyNode*clone();
  bool match_count(QPos*,NumValue*value);
  string toString(){return "<PlyNode>";}
  vnode children()const{return vnode{};}
  bool match_position(QPos*qpos){return true;}
  bool isNumeric()const{return true;}
  void deepify(){};
  void print();
};
  
