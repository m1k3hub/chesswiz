#include "optionalcon.h"
OptionalCon::OptionalCon(PathCon*con):theCon(con){
  uassert(theCon,"scsc arg");
}

vnode OptionalCon::children()const{
  return vnode{theCon};
}

void OptionalCon::deepify(){
  theCon=theCon->clone();
}


void OptionalCon::setIsInitial(){
  theIsInitial=true;
  theCon->setIsInitial();
}

