#include "gotonode.h"
GotoNode::GotoNode(Node*target):target(target){
  uassert(target&&target->isNumeric(),"gotonode arg");
}
/* fixes bug CQLI9.186-2 reported by Gamble: when position was used only for whether it matches it would always return true. This is because the match_position() method in gotonode.h always returned true for some reason*/

bool GotoNode::match_position(QPos*qpos){
  QPos * tmp{NULL}; //ignored
  return match_positionvalue(qpos,&tmp);
}
  
  
bool GotoNode::match_positionvalue(QPos*qpos,QPos**valuep){
  uassert(qpos&&valuep,"gnmpv");
  NumValue id{-1};
  if(!target->match_count(qpos,&id))
    return false;
  QGame*qgame=qpos->qgame;
  uassert(qgame,"gnmpv game");
  if(id<0||id>=qgame->allQPos.size())
    return false;
  *valuep=qgame->allQPos[id];
  return true;
}

vnode GotoNode::children()const{
  return vnode{target};
}
void GotoNode::deepify(){
  target=target->clone();
}
