#pragma once
#include "node.h"
class CurrentTransformNode:public Node{
public:
  vector<Transform*>theTransforms;
  CurrentTransformNode();
  string thisclass()const override{return "CurrentTransformNode";}
  vnode children()const override{return vnode{};}
  void print() override;
  void deepify() override;
  void transform_members(Transform*t) override;
  bool transformmemberless(const Node*)const override;
[[nodiscard]]  CurrentTransformNode*clone() override;
  bool isString()const override{return true;}
  bool match_position(QPos*qpos)override;
  bool match_stringvalue(QPos*,string*)override;
};
