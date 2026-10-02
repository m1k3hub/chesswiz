#pragma once
#include "node.h"
/* keep in sync with piecenamenode.h*/
class TypeNameNode: public Node{
 public:
  SetBase* theSet{NULL};
  TypeNameNode(SetBase* s);
  vnode children()const override;
  void print() override;
[[nodiscard]]  TypeNameNode*clone()override;
  string thisclass()const override{return "TypeNameNode";}
  void deepify()override;
  bool match_stringvalue(QPos*, string*)override;
  bool match_position(QPos*)override;
  bool isString()const override{return true;}
};
