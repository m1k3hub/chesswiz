#include "sequencebase.h"
StarConstituent::StarConstituent(SeqConstituent*c){
  uassert(c,"nullscsc");
  constituent=c;
}


bool StarConstituent::matchesNull(){
  return true;
}

