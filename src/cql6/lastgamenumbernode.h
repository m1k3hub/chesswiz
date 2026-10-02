#pragma once
#include "node.h"
class LastGameNumberNode: public Node{
 public:
  bool match_position(QPos*)override;
  LastGameNumberNode(){}
  vnode children()const override{return vnode{};}
  void print() override;
  string thisclass()const override{return "LastGameNumberNode";}
  [[nodiscard]]LastGameNumberNode*clone() override;
  void deepify() override{}
  bool match_count(QPos*qpos,NumValue*valuep)override;
  bool isNumeric()const override{return true;}
  static void initialize(string filename,Range*range);
};

