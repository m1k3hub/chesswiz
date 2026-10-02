#pragma once
#include "node.h"
class SquareLoopNode: public SetBase{
 private:
  void execute(QPos*qpos, SquareMask*set_return,bool*allp);
  bool match_body(squareT square, QPos*qpos);
 public:
  SquareLoopNode(SquareVariable*v, SetBase*target, Node*body, bool all);
  SquareVariable*variable{NULL};
  SetBase*target{NULL};
  Node* theBody{NULL};
  bool isAll{false};
  string thisclass()const{return "SquareLoopNode";}
[[nodiscard]]  SquareLoopNode*clone();
  vnode children()const;
  SquareMask getSquares(QPos*qpos);
  bool isSet()const;
  void print();
  void deepify();
  bool match_position(QPos*qpos);
};
