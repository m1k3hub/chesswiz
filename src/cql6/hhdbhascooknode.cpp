#include "hhdbhascooknode.h"
bool HhdbHasCookNode::match_position(QPos*qpos){
  QGame*qgame=qpos->qgame;
  uassert(qgame&&qgame->foundCookValid,"HhdbHasCookNode: unable to ascertain cook because cook flag not valid");
  return qgame->foundCook;
}
