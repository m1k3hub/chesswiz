#include "tomovenode.h"
bool ToMoveNode::match_position(QPos*qpos){
  colorT tomove=qpos->toMove;
  uassert(tomove==WHITE||tomove==BLACK,"cnmp color");
  return color==tomove;
}

ToMoveNode::ToMoveNode(colorT c):color(c){
  uassert(color==WHITE||color==BLACK,"tmntmn c");
}

vnode ToMoveNode::children()const{return vnode{};}
void ToMoveNode::deepify(){};
