#include "distancenode.h"
#include "lcanode.h"
DistanceNode::DistanceNode(Node*l,Node*r):left(l),right(r){
  uassert(left&&right,"distancenode args");
  uassert(left->isPosition()&&right->isPosition(),
	  "distancenode parameters are not position filters");
}
vnode DistanceNode::children()const{
  vnode ret{left};
  if(right!=left)ret.push_back(right);
  return ret;
}

void DistanceNode::deepify(){
  left=left->clone();
  right=right->clone();
}

bool DistanceNode::match_position(QPos*qpos){
  eassert(false,"attempt to match position of distance filter. Although legal, this is likely an error");
  return true;
}

bool DistanceNode::match_count(QPos*qpos, NumValue*valuep){
  uassert(qpos&&valuep,"distancenode match_positionvalue params");
  QPos* leftpos{NULL};
  QPos* rightpos{NULL};
  if(!left->match_positionvalue(qpos,&leftpos))
    return false;
  if(!right->match_positionvalue(qpos,&rightpos))
    return false;
  uassert(leftpos&&rightpos,"distancenode::match_position internal");
  *valuep= QPos::distance(leftpos,rightpos);
  return true;
}
