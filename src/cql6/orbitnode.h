#pragma once
#include "node.h"
#include "orbitelement.h"
class OrbitNode: public SetBase{
 private:
  OrbitNode(vector<Transform*> ts,Node*f,Range*range);
  Node* originalFilter{NULL};
 public:
  bool hasEmptySquareMask()const; 
  vector<Transform*> transforms;
  Node* filter{NULL};
  Range*range{NULL};
  string thisclass()const{return "OrbitNode";}
[[nodiscard]]  OrbitNode*clone();
  int orbitLength()const;
  vector<OrbitElement> theOrbit;
  bool theOrbitComputed{false};
  static OrbitNode* create(vector<Transform*>, Node*, Range*);
  void print();
  vnode children()const;
  void computeOrbit();
  void deepify();
  void transform_in_place(Transform*t);
  bool transformless(const Node*)const;
  bool isOrbitComputed()const{return theOrbitComputed;}
  SquareMask getSquares(QPos*qpos);
  virtual bool isSet()const;
  virtual bool isNumeric()const;
  vector<Transform*> getTransforms(){return transforms;}
  Node* getSource(){return filter;}
  bool match_position(QPos*qpos);
  bool match_count_max(QPos*qpos,NumValue*value);
  int compute_match_count(QPos*qpos);
  bool match_range(QPos*,NumValue*);
  bool match_count(QPos*qpos, NumValue*value);
};


