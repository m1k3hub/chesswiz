#include "node.h"
bool SetBase::match_position(QPos*qpos){
  return getSquares(qpos).nonempty();
}

SetBase* SetBase::asSet(){
  uassert(isSet(),"Cannot convert object to set");
  return this;
}
