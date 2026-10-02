#pragma once
#include "starcon.h"
class PlusCon: public PathCon{
public:
  StarCon*theStar{NULL};
  StarCon*getStar()const{return theStar;}
  PathCon*getCon()const{return theStar->getCon();}
  PlusCon(PathCon*);
  bool hasDash()const override;
  void print() override;
  vnode children()const override;
  void deepify() override;
  bool isPlusCon()const override{return true;}
  PlusCon* asPlusCon()override{return this;}
  string thisclass()const override{return "PlusCon";}
[[nodiscard]]  PlusCon*clone()override;
  void setIsInitial()override;
  bool isWildcard()const override{return true;}
};
