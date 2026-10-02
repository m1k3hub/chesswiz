#pragma once
#include "pathcon.h"
class ChainCon: public PathCon{
public:
  vector<PathCon*>theCons;
  vector<PathCon*>& getCons(){return theCons;}
  int getLength()const{return (int)(theCons.size());}
  ChainCon(vector<PathCon*> cs);
  bool hasDash()const override;
  void print() override;
[[nodiscard]]  ChainCon*clone()override;
  string thisclass()const override{return "ChainCon";}
  vnode children()const override;
  void deepify()override;
  //  bool matchesNull()override;
  bool isChainCon()const override{return true;}
  ChainCon* asChainCon()override{return this;}
  void setIsInitial()override;
  bool canModifyCurpos()const override{return true;}
  static ChainCon* makeChainCon2(PathCon* arg1, PathCon* arg2);
  static ChainCon* makeChainCon3(PathCon* arg1, PathCon* arg2, PathCon* arg3);
};
