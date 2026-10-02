#pragma once
#include "node.h"
class FindNode : public Node{
 public:
  Node*filter{NULL};
  Range*range{NULL};
  bool isFuture{false};
  bool isQuiet{false};
  FindNode(Node*filter, Range*,bool isfuture, bool isquiet);
  bool isPosition()const override;
  bool isNumeric()const override;
  bool match_position(QPos*)override;
  bool match_positionvalue(QPos*,QPos**)override;
  bool match_count(QPos*,NumValue*)override;
  string thisclass()const override{return "FindNode";}
  vnode children()const override;
  void deepify()override;
  void print()override;
[[nodiscard]]  FindNode*clone()override;
  bool canModifyCurpos()const override{return true;}
 private:
  QPos*next(QPos*start, QPos*current);
};
