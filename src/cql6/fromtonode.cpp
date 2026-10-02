#include "fromtonode.h"
#include "cqlassert.h"
#include "dashcon.h"
#include "dashnode.h"
void FromToNode::setMasks(SquareMask frommask,SquareMask tomask){
  fromMask=frommask;
  toMask=tomask;
  uassert(!masksValid,"masks unexpectedly valid: FromToNode::setMasks");
  uassert(hasOwner(),"unexpected setting with no owner");
  masksValid=true;
}

void FromToNode::unsetMasks(){
  uassert(masksValid,"FTN: masks are valid");
  masksValid=false;
}
  

void FromToNode::setOwner(Node*owner){
  uassert(owner,"ftn owner null");
  DashCon* dashcon=dynamic_cast<DashCon*>(owner);
  DashNode* dashnode=dynamic_cast<DashNode*>(owner);
  vector<FromToNode*>*ownedlistp{NULL};
  uassert(dashcon||dashnode,"ftn sm type error");
  uassert(!(dashcon&&dashnode),"ftn eh??");
  uassert(owner,"ftn ote");
  uassert(!theOwner,"unexpected existing owner: setOwner");
  if(dashnode)
    ownedlistp= &dashnode->fromToNodeOwned;
  else if(dashcon)
    ownedlistp= &dashcon->fromToNodeOwned;
  uassert(std::count(ownedlistp->begin(),ownedlistp->end(),this)==0,"owned in ownedlist ftn");
  ownedlistp->push_back(this);
  theOwner=owner;
  masksValid=false;
}
  
vnode FromToNode::children()const{
  return vnode{};
}

void FromToNode::deepify(){
  uassert (theOwner==NULL,"deepify called too late on fromtonode");
}
