#pragma once
#include "node.h"
class NoTransformNode:public SetBase{
 public:
  Node* theFilter{NULL}; 
  string thisclass()const{return "NoTransformNode";}
[[nodiscard]]  NoTransformNode* clone();
  vnode children()const;
  void print();
  NoTransformNode(Node*filter);
  bool match_position(QPos*);
  bool isPosition()const;
  bool isNumeric()const;
  bool isString()const;
  bool match_positionvalue(QPos*,QPos**);
  bool match_stringvalue(QPos*,string*);
  bool match_count(QPos*,NumValue*);
  SquareMask getSquares(QPos*);
  void deepify();
  bool isSet()const;
  void transform_in_place(Transform*t);
  bool transformmemberless(const Node*)const;
  bool isGameFilter()const;
};
