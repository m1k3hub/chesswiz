#pragma once
#include "node.h"
#include "positionvariable.h"
class EchoNode : public Node{
 private:
  PositionVariable*sourcevar{NULL};
  PositionVariable*targetvar{NULL};
  Node* theFilter{NULL};
  bool searchAll{false};
  bool isQuiet{false};
  NumValue maxValue{0};
  NumValue currentValue{0};
  bool theIsNumeric{false};
  bool compute(QPos*qpos);
  bool isSort{false};
 public:
  EchoNode(PositionVariable*svar, PositionVariable* tvar, Node* filter, bool searchall,bool isquiet);
  bool match_position(QPos*)override;
  string thisclass()const override{return "EchoNode";}
[[nodiscard]]  EchoNode*clone()override;
  vnode children()const override;
  void deepify()override;
  void print()override;
  bool isNumeric()const override;
  bool match_count(QPos*,NumValue*)override;
  void setIsSort();
  bool canModifyCurpos()const override{return true;}
};
