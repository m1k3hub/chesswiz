#include "sequencebase.h"

VectorConstituent::VectorConstituent(vector<SeqConstituent*>&cs,SeqDir dir):
  constituents(cs),direction(dir){
  uassert(constituents.size()&&seqdir_valid(dir),"invalid vectorconstituent arguments");
  for(auto c:constituents)
    uassert(c,"vcvc");
}

vnode VectorConstituent::children()const{
  vnode v{constituents.begin(),constituents.end()};
  return v;
}

bool VectorConstituent::matchesNull(){
  for(auto c:constituents)
    if(!c->matchesNull())return false;
  return true;
}
