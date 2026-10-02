#pragma once
#include "pathcon.h"
class RepeatCon: public PathCon{
public:
  PathCon*theCon{NULL};
  PathCon*getCon()const{return theCon;}
  RepeatCon(PathCon*,int,int);
[[nodiscard]]  RepeatCon*clone()override;
  string thisclass()const override{return "RepeatCon";}
  int theMin=-1;
  int theMax=-1;
  int getMin()const{return theMin;}
  int getMax()const{return theMax;}
  void print()override;
  bool hasDash()const override;
  vnode children()const override;
  void deepify() override;
  bool isRepeatCon()const override{return true;}
  RepeatCon* asRepeatCon()override{return this;}
  void setIsInitial()override;
  bool isWildcard()const override{return true;}
};
