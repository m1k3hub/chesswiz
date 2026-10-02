#include "genericequalnode.h"
#include "anyvalue.h"

GenericEqualNode::GenericEqualNode(Node* l,Node*r):theLeft(l),theRight(r){
  uassert(theLeft&&theRight,"gen args");
}
bool GenericEqualNode::match_position(QPos*qpos){
  AnyValue::Any aleft=AnyValue::eval(theLeft,qpos);
  AnyValue::Any aright=AnyValue::eval(theRight,qpos);
  return aleft==aright;
}

vnode GenericEqualNode::children()const{
  uassert(theLeft&&theRight,"genc genc");
  vnode ret{theLeft};
  if (theLeft!=theRight)
    ret.push_back(theRight);
  return ret;
}

void GenericEqualNode::deepify(){
  if(theLeft)theLeft=theLeft->clone();
  if(theRight)theRight=theRight->clone();
}
  
