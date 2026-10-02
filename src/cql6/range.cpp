#include "node.h"
#include "range.h"
#include "numericvariable.h"

Range::Range(int m):theMin(m),theMax(m){
}

Range::Range(int min,int max):theMin(min),theMax(max){
  if (theMin>theMax){
    stringstream s;
    s<<"Attempt to create invalid range with min: "<<theMin<<" and max: "<<theMax;
    uassert(false,s.str());
  }
}

Range::Range(int min, int max, NumericVariable*minv, NumericVariable*maxv):
  theMin(min),theMax(max),
  theMinv(minv),theMaxv(maxv){
}

int Range::getMin(){
  if(!theMinv)return theMin;
  eassert(theMinv->isBound(),"In Range: unbound min numeric variable named: ",theMinv->name);
  return (int)(theMinv->getValue());
}

int Range::getMax(){
  if(!theMaxv)return theMax;
  eassert(theMaxv->isBound(),"In Range: unbound max numeric variable named: ",theMaxv->name);
  return (int)(theMaxv->getValue());
}

bool Range::valid(int x){
  int min=getMin();
  int max=getMax();
  return x>=min&&x<=max;
}

string Range::toString(){
  stringstream s;
  s<<" range[";
  if(theMinv)
    s<<theMinv->name<<": ";
  s<<getMin();
  if(theMaxv)
    s<<theMaxv->name<<": ";
  s<<getMax();
  s<<']';
  return s.str();
}
  
bool Range::isConstant(){
  return theMinv==NULL&&theMaxv==NULL;
}
