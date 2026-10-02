#include "chaincon.h"
ChainCon::ChainCon(vector<PathCon*> cs):theCons(cs){
  uassert(theCons.size()>0,"ccccc");
  for(auto l:theCons){
    uassert(l,"cccc bad null in arg");
    uassert(std::count(theCons.begin(),theCons.end(),l)==1,"Unexpected duplicate element in Chain constituent");
  }
}

bool ChainCon::hasDash()const{
  for (auto l:theCons)
    if (l->hasDash())return true;
  return false;
}

vnode ChainCon::children()const{
  vnode ret;
  for(auto l:theCons) //assumes that duplicate elements do not exist per constructor
    ret.push_back(l);
  return ret;
}
  
void ChainCon::deepify(){
  for(int i=0;i<(int)(theCons.size());++i){
    uassert(theCons.at(i),"ccdeepify");
    theCons[i]=theCons[i]->clone();
  }
}

/* the next 2 helper function could no doubt be rewritten using varargs, but we only need a few instances*/
ChainCon*ChainCon::makeChainCon2(PathCon*arg1, PathCon*arg2){
  uassert(arg1&&arg2&&arg1!=arg2,"mcc2 args");
  return new ChainCon(vector<PathCon*>{arg1,arg2});
}

ChainCon*ChainCon::makeChainCon3(PathCon*arg1, PathCon*arg2, PathCon*arg3){
  uassert(arg1&&arg2&&arg3&&arg1!=arg2&&arg1!=arg3&&arg2!=arg3,"mcc3 args");
  return new ChainCon(vector<PathCon*>{arg1,arg2,arg3});
}

void ChainCon::setIsInitial(){
  uassert(!isInitial(),"ccsii already");
  theIsInitial=true;
  theCons.at(0)->setIsInitial();
}

