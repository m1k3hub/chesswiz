#pragma once
#include "node.h"
class FromToNode : public SetBase{
 public:
  SquareMask fromMask{SquareMask::all()}; //cannot easily make const because of clone, setMasks
  SquareMask toMask{SquareMask::all()};   // cannot easily make clone, setMasks
  bool masksValid{true};
  Node* theOwner{NULL};
  void setMasks(SquareMask f, SquareMask t);
  void setOwner(Node*owner);
  bool isFromToNode()const override{return true;}
  bool hasOwner()const{return theOwner!=NULL;}
  void unsetMasks();
  void deepify()override;
  vnode children()const override;
  void print()override;
};
