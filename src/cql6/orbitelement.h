#pragma once
#include "node.h"
class Transform;

class OrbitElement{
 public:
  Transform* transform{NULL};
  Node* node{NULL};
  string thisclass()const{return "OrbitElement";}
  void print();
  OrbitElement(Transform*,Node*);
  bool operator<(const OrbitElement&)const;
};
