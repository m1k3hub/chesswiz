#include "starcon.h"
StarCon::StarCon(PathCon*con):theCon(con){
  uassert(theCon,"scsc arg");
}

vnode StarCon::children()const{
  return vnode{theCon};
}

void StarCon::deepify(){
  theCon=theCon->clone();
}

void StarCon::setIsInitial(){
  theIsInitial=true;
  theCon->setIsInitial();
}

  
