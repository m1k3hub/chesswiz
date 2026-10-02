#include "dashnode.h"
#include "myvector.h"
#include "fromtonode.h"
DashNode::DashNode(SetBase*left
		   ,SetBase*right
		   ,Node*target
		   ,CaptureType cap
		   ,bool iscount):
  left(left),right(right),target(target),theCaptureType(cap),isCount(iscount){
  uassert(captureTypeValid(theCaptureType),"dashnode bad cap");
}
bool DashNode::match_count(QPos*qpos,NumValue*valuep){
  if (isCount){
    *valuep=computeCount(qpos);
    return true;
  }
  if(compute(qpos,true)){
    *valuep=AnyValue::numValue(theValue);
    return true;
  }
  return false;
}
bool DashNode::match_position(QPos*qpos){
  if(isCount) {
    NumValue tmp{0};
    match_count(qpos,&tmp);
    return true;
  }
  return compute(qpos,false);
}

bool DashNode::match_stringvalue(QPos*qpos,string*valuep){
  if(compute(qpos,true)){
    *valuep=AnyValue::stringValue(theValue);
    return true;
  }
  return false;
}

bool DashNode::match_positionvalue(QPos*qpos,QPos**valuep){
  if(compute(qpos,true)){
    *valuep=AnyValue::qPosValue(theValue);
    return true;
  }
  return false;
}
SquareMask DashNode::getSquares(QPos*qpos){
  if(compute(qpos,true))
    return AnyValue::squareMaskValue(theValue);
  return SquareMask{};
}

bool DashNode::isNumeric()const{
  if (isCount)return true;
  return target&&target->isNumeric();
}
bool DashNode::isPosition()const{
  if(isCount)return false;
  return target && target->isPosition();
}
bool DashNode::isString()const{
  if (isCount)return false;
  return target&&target->isString();
}
bool DashNode::isSet()const{
  if (isCount)return false;
  return target&&target->isSet();
}

vnode DashNode::children()const{
  vnode ret;
  if (left) ret.push_back((Node*)left);
  if (right) myinsert(ret,(Node*)right);
  if(target) myinsert(ret,target);
  return ret;
}

void DashNode::deepify(){
  if (left) left=left->clone();
  if (right) right=right->clone();
  if (target) target=target->clone();
}

/* get value is true if a value is requested*/
bool DashNode::compute(QPos*qpos, bool getvalue){
  if (isCount) return computeCount(qpos);
  if(qpos->terminal()) return false;
  int x=qpos->markComments();
  SquareMask leftmask =SetBase::virtualGetSquares(qpos,left);
  SquareMask rightmask =SetBase::virtualGetSquares(qpos,right);
  for(auto owned:fromToNodeOwned)
    owned->setMasks(leftmask,rightmask);
  bool foundMatch{false};
  for (QMove*qmove:qpos->moves){
    if(theForceTail&&qmove->tail!=theForceTail)
      continue;//for previousmove
    if(qmove->validMove(leftmask,rightmask,theCaptureType)
       &&handleTarget(qmove->tail,getvalue))
      foundMatch=true;
    if (foundMatch) break;
  }
  if(!foundMatch)qpos->restoreComments(x);
  for(auto owned:fromToNodeOwned)
    owned->unsetMasks();
  return foundMatch;
}

/* get value is true if a value is requested*/
bool DashNode::handleTarget(QPos*tail,bool getvalue){
  if(!getvalue){
    if(target==NULL)return true;
    return target->match_position(tail);
  }
  /* we need a value here*/
  /* this defaults to  "currentposition" as the value of target */
  if(target==NULL){
    uassert(false,"A dash filter is requested with a null target, but that construction has no value.");
    return false;
  }
  theValue=AnyValue::eval(target,tail);
  if (AnyValue::isLogical(theValue)){
    uassert(!AnyValue::logicalValue(theValue),"expected a false value when value is missing here");
    return false;
  }
  return true;
}

int DashNode::computeCount(QPos*qpos){
  if(qpos->terminal()) return 0;
  int ret=0;
  SquareMask leftmask =SetBase::virtualGetSquares(qpos,left);
  SquareMask rightmask =SetBase::virtualGetSquares(qpos,right);
  for(auto owned:fromToNodeOwned)
    owned->setMasks(leftmask,rightmask);
  for (QMove*qmove:qpos->moves){
    if(qmove->invalidMove(leftmask,rightmask,theCaptureType))
      continue;
    if (target==NULL||target->match_position(qmove->tail))
      ++ret;
  }
  for(auto owned:fromToNodeOwned)
    owned->unsetMasks();
  return ret;
}  

