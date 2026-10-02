#include "holdercon.h"
HolderCon::HolderCon(Node* filter):theFilter(filter){
  uassert(theFilter,"hchc");
}

vnode HolderCon::children()const{
  return vnode{theFilter};
}

void HolderCon::deepify(){
  if(theFilter)theFilter=theFilter->clone();
}

