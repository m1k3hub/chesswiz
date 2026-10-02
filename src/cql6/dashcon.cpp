#include "dashcon.h"
DashCon::DashCon(SetBase*left,SetBase*right,Node*target,CaptureType cap):
  theLeft(left),
  theRight(right),
  theTarget(target),
  theCaptureType(cap){
  uassert(captureTypeValid(theCaptureType),"bad cap in dcdc");
}

vnode DashCon::children()const{
  vnode ret;
  if(theLeft)ret.push_back(theLeft);
  if(theRight&&theRight!=theLeft)
    ret.push_back(theRight);
  if(theTarget&&
     std::count(ret.begin(),ret.end(),theTarget)==0)
    ret.push_back(theTarget);
  return ret;
}

void DashCon::deepify(){
  if (theLeft)theLeft=theLeft->clone();
  if(theRight)theRight=theRight->clone();
  if (theTarget) theTarget=theTarget->clone();
}


void DashCon::setLeft(SetBase*left){
  uassert(theLeft==NULL,"dcsl ts");
  theLeft=left;
}
  
void DashCon::setOwnedMasks(SquareMask left, SquareMask right){
  for(auto owned:fromToNodeOwned)
    owned->setMasks(left,right);
}
void DashCon::unsetOwnedMasks(){
  for(auto owned:fromToNodeOwned)
    owned->unsetMasks();
}
