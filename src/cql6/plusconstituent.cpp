#include "sequencebase.h"
PlusConstituent::PlusConstituent(SeqConstituent*c){
  uassert(c,"nullscsc");
  theStarConstituent=new StarConstituent(c);
}


bool PlusConstituent::matchesNull(){
  return getConstituent()->matchesNull();
}

SeqConstituent* PlusConstituent::getConstituent(){
  return theStarConstituent->constituent;
}


