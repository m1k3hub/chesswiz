#include "descendantnode.h"
DescendantNode::DescendantNode(Node*l,Node*r):left(l),right(r){
  uassert(left&&right,"descendantnode args");
  uassert(left->isPosition()&&right->isPosition(),
	  "descendantnode parameters are not position filters");
}
vnode DescendantNode::children()const{
  vnode ret{left};
  if(right!=left)ret.push_back(right);
  return ret;
}

void DescendantNode::deepify(){
  left=left->clone();
  right=right->clone();
}

bool DescendantNode::match_position(QPos*qpos){
  uassert(qpos,"descendantnode match_position params");
  QPos* leftpos{NULL};
  QPos* rightpos{NULL};
  if(!left->match_positionvalue(qpos,&leftpos))
    return false;
  if(!right->match_positionvalue(qpos,&rightpos))
    return false;
  uassert(leftpos&&rightpos,"descendantnode::match_position internal");
  int rindex=rightpos->index;
  int lindex=leftpos->index;
  return lindex>rindex
    && lindex <= rightpos->lastDescendantIndex;
}
