#pragma once
#include "node.h"
class FocusCaptureNode:public Node{
 public:
  SetBase* theSet{NULL};
  FocusCaptureNode(SetBase*);
  string thisclass()const{return "FocusCaptureNode";}
[[nodiscard]]  FocusCaptureNode* clone();
  vnode children()const;
  void print();
  bool match_position(QPos*);
  void deepify();
};

