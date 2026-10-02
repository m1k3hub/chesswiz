#include "lcanode.h"
LcaNode::LcaNode(Node*l,Node*r):left(l),right(r){
  uassert(left&&right,"lcanode args");
  uassert(left->isPosition()&&right->isPosition(),
	  "lcanode parameters are not position filters");
}
vnode LcaNode::children()const{
  vnode ret{left};
  if(right!=left)ret.push_back(right);
  return ret;
}

void LcaNode::deepify(){
  left=left->clone();
  right=right->clone();
}

bool LcaNode::match_position(QPos*qpos){
  eassert(false,"attempt to match position of LCA filter. Although legal, this is likely an error");
  return true;
}

bool LcaNode::match_positionvalue(QPos*qpos, QPos**qposp){
  uassert(qpos&&qposp,"lcanode match_positionvalue params");
   QPos* leftpos{NULL};
  QPos* rightpos{NULL};
  if(!left->match_positionvalue(qpos,&leftpos))
    return false;
  if(!right->match_positionvalue(qpos,&rightpos))
    return false;
  uassert(leftpos&&rightpos,"lcanode::match_position internal");
  *qposp=QPos::lca(leftpos,rightpos);
  uassert(*qposp,"lcanodmpv int");
  return true;
}
    
