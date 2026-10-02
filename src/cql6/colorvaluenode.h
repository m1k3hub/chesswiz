#pragma once
#include "node.h"
class ColorValueNode : public Node{
 public:
  ColorValueNode(colorT color);
  string thisclass()const{return "ColorValueNode";}
  string name();
  colorT color;
  vnode children()const;
  void deepify();
  void transform_members(Transform*t);
  void print();
  bool match_position(QPos*qpos);
  bool match_count(QPos*,NumValue*);
  bool isNumeric()const{return true;}
[[nodiscard]]  ColorValueNode*clone();
  bool transformmemberless(const Node*)const;
};
