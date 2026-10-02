#include "node.h"
class AttackNode : public SetBase{
 private:
  SquareMask allAttacked;
  SquareMask allAttacking;
  void compute(QPos*qpos);
 public:
  AttackNode(SetBase*s, SetBase*t, bool returnfrom, bool returnto);
  SetBase* attacking{NULL};
  SetBase* attacked{NULL};
  bool returnAttacking{false};
  bool returnAttacked{false};
  void print();
  bool match_position(QPos*qpos);
  SquareMask getSquares(QPos*);
  vnode children()const;
  string thisclass()const{return "AttackNode";}
  [[nodiscard]]AttackNode*clone();
  void deepify(){attacking=attacking->clone();attacked=attacked->clone();}
  bool isSet()const{return true;}
};

