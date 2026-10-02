#include "sequencebase.h"

HolderConstituent::HolderConstituent(Node*f):filter(f){
  uassert(filter,"holderconstituent constructor");
}



bool HolderConstituent::matchesNull(){
  return false;
}
