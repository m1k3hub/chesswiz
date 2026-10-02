#pragma once
#include "node.h"
class PieceIdNode: public Node{
 public:
  PieceIdVariable*pieceidVariable{NULL};
  SetBase*theSet{NULL};
  PieceIdNode(Node*);
  bool match_position(QPos*);
  bool match_count(QPos*,NumValue*);
  string thisclass()const{return "PieceIdNode";}
  vnode children()const;
  void deepify();
  void print();
  bool isNumeric()const{return true;}
[[nodiscard]]  PieceIdNode*clone();
};
