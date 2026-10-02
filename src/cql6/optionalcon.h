#pragma once
#include "pathcon.h"
class OptionalCon : public PathCon{
public:
  PathCon*theCon{NULL};
  PathCon*getCon()const{return theCon;}
  OptionalCon(PathCon*);
  bool hasDash()const override {return false;}
  //  bool matchesNull() override;
  void print() override;
  vnode children()const override;
  void deepify() override;
  bool isOptionalCon()const override{return true;}
  OptionalCon* asOptionalCon()override{return this;}
  string thisclass()const override{return "OptionalCon";}
[[nodiscard]]  OptionalCon*clone()override;
  void setIsInitial()override;
  bool isWildcard()const override{return true;}
};
