#pragma once
#include "pathcon.h"
class HolderCon: public PathCon{
public:
  HolderCon(Node*);
  Node*theFilter{NULL};
  bool theIsInitial{false};
  Node* getFilter()const{return theFilter;}
  bool hasDash()const override{return false;}
[[nodiscard]]  HolderCon*clone()override;
  void print() override;
  vnode children()const override;
  void deepify()override;
  //  bool matchesNull()override;
  bool isHolderCon()const override{return true;}
  HolderCon* asHolderCon()override{return this;}
  string thisclass()const override{return "HolderCon";}
};

