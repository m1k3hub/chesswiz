#include "sequencebase.h"
RepeatConstituent::RepeatConstituent(SeqConstituent*c,int tmin, int tmax){
  uassert(c,"nullscsc");
  constituent=c;
  uassert (tmin>=0 && tmax >=0,"RepeatConstituent: negative tmin or tmax parameter");
  min=tmin;
  max=tmax;
}

bool RepeatConstituent::matchesNull(){
  return min==0 ||
    constituent->matchesNull();
}
