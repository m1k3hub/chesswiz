#pragma once
#include "node.h"
class IfNode : public SetBase{
 public:
  Node* predicateFilter; // nonnull
  Node* thenFilter; // nonnull
  Node* elseFilter; // may be null
  string thisclass()const{return "IfNode";}
[[nodiscard]]  IfNode*clone();
  SquareMask getSquares(QPos*qpos);
  bool match_count(QPos*qpos, NumValue*v);
  bool isSet()const;
  bool isNumeric()const;
  bool isPosition()const;
  bool isString()const;
  void deepify();
  vnode children()const;
  bool match_position(QPos*);
  bool match_positionvalue(QPos*, QPos**);
  bool match_stringvalue(QPos*,string*);
  void print();
  IfNode(Node*,Node*,Node*);
};
