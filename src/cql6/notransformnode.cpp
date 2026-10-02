#include "notransformnode.h"
NoTransformNode::NoTransformNode(Node*filter):theFilter(filter){
  uassert(theFilter,"Illegal Null argument to NoTransformNode");
}

vnode NoTransformNode::children()const{return vnode{theFilter};}

bool NoTransformNode::match_position(QPos*qpos){
  return theFilter->match_position(qpos);
}

SquareMask NoTransformNode::getSquares(QPos*qpos){
  return theFilter->asSet()->getSquares(qpos);
}

void NoTransformNode::deepify(){
  theFilter=theFilter->clone();
}

bool NoTransformNode::isSet()const{
  return theFilter->isSet();
}

bool NoTransformNode::isPosition()const{
  return theFilter->isPosition();
}

bool NoTransformNode::isString()const{
  return theFilter->isString();
}

bool NoTransformNode::isNumeric()const{
  return theFilter->isNumeric();
}

bool NoTransformNode::match_count(QPos*qpos,NumValue*value){
  return theFilter->match_count(qpos,value);
}

bool NoTransformNode::match_positionvalue(QPos*qpos,QPos** result){
  return theFilter->match_positionvalue(qpos,result);
}

bool NoTransformNode::match_stringvalue(QPos*qpos,string* result){
  return theFilter->match_stringvalue(qpos,result);
}

bool NoTransformNode::isGameFilter()const{
  return theFilter->isGameFilter();
}

/* this is usually in transform_members.cpp*/

void NoTransformNode::transform_in_place(Transform*t){
}


