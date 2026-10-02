#include "node.h"
class OnNode: public SetBase{
 public:
  SetBase* clause1{NULL};
  SetBase* clause2{NULL};
  SquareMask getSquares(QPos*) override;
  OnNode(SetBase* s1, SetBase* s2);
  vnode children()const override;
  void print() override;
[[nodiscard]]  OnNode*clone()override;
  string thisclass()const override{return "OnNode";}
  void deepify()override;
  static SetBase*makeVirtualOnNode(SetBase*left, SetBase*right);
};
