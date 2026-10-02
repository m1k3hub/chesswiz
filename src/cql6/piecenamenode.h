#pragma once
#include "node.h"
/* keep in sync with piecenamenode.h*/
class PieceNameNode: public Node{
 public:
  SetBase* theSet{NULL};
  PieceNameNode(SetBase* s);
  vnode children()const override;
  void print() override;
[[nodiscard]]  PieceNameNode*clone()override;
  string thisclass()const override{return "PieceNameNode";}
  void deepify()override;
  bool match_stringvalue(QPos*, string*)override;
  bool match_position(QPos*)override;
  bool isString()const override{return true;}
};
