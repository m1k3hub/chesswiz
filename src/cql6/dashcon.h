#pragma once
#include "pathcon.h"
#include "capturetype.h"
#include "fromtonode.h"

class DashCon: public PathCon{
public:
  DashCon(SetBase*left,SetBase*right,Node*target,CaptureType cap);
  SetBase*theLeft{NULL};
  SetBase*theRight{NULL};
  Node*theTarget{NULL};
  Node*getTarget()const{return theTarget;}
  CaptureType theCaptureType{CaptureType::None};
  CaptureType getCaptureType()const{return theCaptureType;}
  vector<FromToNode*>fromToNodeOwned;     //see above
  void setOwnedMasks(SquareMask left, SquareMask right);
  void unsetOwnedMasks();
  void appendTarget(Node*);
  void prependTarget(Node*);
  SetBase*getLeft()const{return theLeft;}
  SetBase*getRight()const{return theRight;}
  void setLeft(SetBase*);
  bool hasDash()const override{return true;}
  void print() override;
  vnode children()const override;
  void deepify()override;
  bool isFromToOwner()const override{return true;} // supports owning a from or to node
  string thisclass()const override{return "DashCon";}
  bool canModifyCurpos()const override{return true;}
[[nodiscard]]  DashCon*clone()override;
  bool isDashCon()const override{return true;}
  DashCon*asDashCon()override{return this;}
};
