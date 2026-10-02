#include "repeatcon.h"
RepeatCon::RepeatCon(PathCon*con,int min,int max):theCon(con),theMin(min),theMax(max){
  uassert(theCon&&theMin>=0&&theMax>=theMin,"repeatcon: bad arguments");
}
bool RepeatCon::hasDash()const{
  if (theMin==0)return false;
  return theCon->hasDash();
}

vnode RepeatCon::children()const{
  return vnode{theCon};
}

void RepeatCon::deepify(){
  theCon=theCon->clone();
}


void RepeatCon::setIsInitial(){
  theIsInitial=true;
  theCon->setIsInitial();
}
