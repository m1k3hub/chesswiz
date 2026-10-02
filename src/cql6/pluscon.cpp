#include "pluscon.h"
#include "starcon.h"
PlusCon::PlusCon(PathCon*con){
  uassert(con,"PlusCon pc con");
  theStar=new StarCon(con);
}

bool PlusCon::hasDash()const{
  return getCon()->hasDash();
}

vnode PlusCon::children()const{
  return vnode{theStar};
}

void PlusCon::deepify(){
  theStar=theStar->clone();
}

void PlusCon::setIsInitial(){
  theStar->setIsInitial();
  theIsInitial=true;
}

  
