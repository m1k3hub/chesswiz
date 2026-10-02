#include "markt.h"
string markT::toString()const{
  uassert(isLegal(),"Illegal mark detected in markT::toString");
  stringstream s;
  s<<"<markT: "<<theValue<<'>';
  return s.str();
}

std::ostream&operator<<(std::ostream&os,markT const&mark){
  return os<<mark.toString();
}
