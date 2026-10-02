#pragma once
#include "node.h"
class CompoundNode: public SetBase{
 public:
  vector<Node*> specs;
  CompoundNode(vector<Node*>);
  void print();
  string thisclass()const{return "CompoundNode";}
[[nodiscard]]  CompoundNode*clone();
  vnode children()const;
  bool match_position(QPos*);
  SquareMask getSquares(QPos*);
  bool match_count(QPos*, NumValue*val);
  bool match_positionvalue(QPos*, QPos**);
  bool match_stringvalue(QPos*,string*);
  void deepify(){clonevec(specs);}
  bool isSet()const;
  bool isNumeric()const;
  bool isPosition()const;
  bool isString()const;
  Node* last()const;
  bool isGameFilter()const;
};
