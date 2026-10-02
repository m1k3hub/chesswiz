#include "withpositionnode.h"
WithPositionNode::WithPositionNode(Node*target, Node*filter):
  theTarget(target),theFilter(filter){
  uassert(theTarget&&theFilter,"wpn bad args");
  uassert(theTarget->isPosition(),"wpn target not a position");
}
void WithPositionNode::deepify(){
  theTarget=theTarget->clone();
  theFilter=theFilter->clone();
}
vnode WithPositionNode::children()const{
  vnode ret{theTarget};
  if(theFilter!=theTarget)
    ret.push_back(theFilter);
  return ret;
}
bool WithPositionNode::isPosition()const{
  return theFilter->isPosition();
}
bool WithPositionNode::isSet()const{
  return theFilter->isSet();
}

bool WithPositionNode::isNumeric()const{
  return theFilter->isNumeric();
}

bool WithPositionNode::isString()const{
  return theFilter->isString();
}


QPos*WithPositionNode::getPosition(QPos*qpos){
  uassert(qpos,"wpngp qpos");
  QPos*ret=NULL;
  if(theTarget->match_positionvalue(qpos,&ret)){
    uassert(ret,"wpngp: could not get positionvalue");
    return ret;
  }
  return NULL;
}

bool WithPositionNode::match_position(QPos* qpos){
  QPos* newpos=getPosition(qpos);
  if(!newpos)return false;
  return theFilter->match_position(newpos);
}

bool WithPositionNode::match_count(QPos*qpos,NumValue*val){
  QPos*newpos=getPosition(qpos);
  if(!newpos)return false;
  return theFilter->match_count(newpos,val);
}

bool WithPositionNode::match_positionvalue(QPos*qpos, QPos**valuep){
  QPos*newpos=getPosition(qpos);
  if(!newpos)return false;
  return theFilter->match_positionvalue(newpos,valuep);
}

bool WithPositionNode::match_stringvalue(QPos*qpos, string*valuep){
  QPos*newpos=getPosition(qpos);
  if(!newpos)return false;
  return theFilter->match_stringvalue(newpos,valuep);
}

SquareMask WithPositionNode::getSquares(QPos*qpos){
  uassert(isSet(),"WithPositionNode: attempt to get squares from a non-set");
  QPos*newpos=getPosition(qpos);
  if(!newpos)return SquareMask();
  SetBase*set=dynamic_cast<SetBase*>(theFilter);
  uassert(set,"WithPositionNode: cannot get set");
  return set->getSquares(newpos);
}

