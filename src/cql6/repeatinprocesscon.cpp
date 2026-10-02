#include "repeatinprocesscon.h"
RepeatInProcessCon::RepeatInProcessCon(RepeatCon*r):repeatCon(r){
  uassert(repeatCon,"ripc arg");
}
int RepeatInProcessCon::min()const{
  return repeatCon->getMin();
}

int RepeatInProcessCon::max()const{
  return repeatCon->getMax();
}

bool RepeatInProcessCon::hasDash()const{
  uassert(false,"ripc ha");
  return false;
}

vnode RepeatInProcessCon::children()const{
  uassert(false,"ripc c");
  return vnode{};
}

void RepeatInProcessCon::deepify(){
  uassert(false,"ripc d");
}


void RepeatInProcessCon::setIsInitial(){
  uassert(false,"ripc sii");
}

RepeatInProcessCon*RepeatInProcessCon::clone(){
  uassert(false,"ripc clone");
  return NULL;
}
