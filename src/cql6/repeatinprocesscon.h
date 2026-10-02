#pragma once
#include "repeatcon.h"
class RepeatInProcessCon: public PathCon{
public:
  RepeatCon*repeatCon{NULL};
  RepeatCon*getRepeatCon()const{return repeatCon;}
  PathCon*getCon()const{return repeatCon->getCon();} //constituent to be repeated
  RepeatInProcessCon(RepeatCon*);
  int nSeen{0};
  int min()const;
  int max()const;
  void print() override;
  vnode children()const override; //error
  void deepify() override;        //error
  bool isRepeatInProcessCon()const override{return true;}
  RepeatInProcessCon* asRepeatInProcessCon()override{return this;}
  string thisclass()const override{return "RepeatInProcessCon";}
[[nodiscard]]  RepeatInProcessCon*clone()override; // error
  void setIsInitial()override;
  bool hasDash()const override; //error
};
