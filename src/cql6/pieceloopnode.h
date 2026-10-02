#pragma once
#include "node.h"
class PieceLoopNode: public SetBase{
 private:
  void execute(QPos*qpos, SquareMask*set_return,bool*allp);
  bool match_body(markT pieceid, QPos*qpos);
 public:
  PieceLoopNode(PieceIdVariable*v, SetBase*target, Node*body, bool all);
  PieceIdVariable*variable{NULL};
  SetBase*target{NULL};
  Node* theBody{NULL};
  bool isAll{false};
  string thisclass()const{return "PieceLoopNode";}
[[nodiscard]]  PieceLoopNode*clone();
  vnode children()const;
  SquareMask getSquares(QPos*qpos);
  bool isSet()const;
  void print();
  void deepify();
  bool match_position(QPos*qpos);
};
