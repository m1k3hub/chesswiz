#pragma once
#include "node.h"
class PinNode: public SetBase{
 private:
  SetBase*fromFilter{NULL};
  SetBase*throughFilter{NULL};
  SetBase*toFilter{NULL};
  bool returnFrom{false};
  bool returnThrough{false};
  bool returnTo{false};
  SquareMask computexrays(SquareMask from,
			  SquareMask through,
			  SquareMask to,
			  QPos*qpos);
 public:
  bool match_position(QPos*qpos);
  void print();
  string thisclass()const{return "PinNode";}
[[nodiscard]]  PinNode*clone();
  PinNode(SetBase*from, SetBase*through,SetBase*to,bool returnfrom, bool returnthrough, bool returnto);
  vnode children()const;
  void deepify();
  SquareMask getSquares(QPos*qpos);
  bool isSet()const{return true;}
};
			  
