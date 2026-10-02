#include "sequencebase.h"
OptionalConstituent::OptionalConstituent(SeqConstituent*c){
  uassert(c,"oc");
  constituent=c;
}


bool OptionalConstituent::matchesNull(){
  return true;
}
