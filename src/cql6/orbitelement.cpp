#include "orbitelement.h"
OrbitElement::OrbitElement(Transform*t,Node*n):transform(t),node(n){
  uassert(transform!=NULL&&node!=NULL,"OrbitElement:args");
}
//operator< is defined in transformcompare.cpp
