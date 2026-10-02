#pragma once
#include "pathcon.h"
class StarCon: public PathCon{
public:
  PathCon*theCon{NULL};
  PathCon*getCon()const{return theCon;}
  StarCon(PathCon*);
  bool hasDash()const override {return false;}
  //  bool matchesNull() override;
  void print() override;
  vnode children()const override;
  void deepify() override;
  bool isStarCon()const override{return true;}
  StarCon* asStarCon()override{return this;}
  string thisclass()const override{return "StarCon";}
[[nodiscard]]  StarCon*clone()override;
  void setIsInitial()override;
  bool isWildcard()const override{return true;}
};
