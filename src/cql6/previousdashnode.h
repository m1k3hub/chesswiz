#pragma once
#include "node.h"
#include "dashnode.h"
class PreviousDashNode:public SetBase{
public:
  DashNode*theDash{NULL};
  DashNode*getDash(){return theDash;}
  PreviousDashNode(DashNode*);
  string thisclass()const override{return "PreviousDashNode";}
  vnode children()const override;
  void deepify()override;
  bool match_position(QPos*)override;
  bool match_stringvalue(QPos*,string*)override;
  bool match_positionvalue(QPos*,QPos**)override;
  bool match_count(QPos*,NumValue*valuep)override;
  SquareMask getSquares(QPos*)override;
  bool isNumeric()const override{return theDash->isNumeric();}
  bool isPosition()const override{return theDash->isPosition();}
  bool isString()const override{return theDash->isString();}
  bool isSet()const override{return theDash->isSet();}
  void print()override;
[[nodiscard]]  PreviousDashNode*clone()override;
};
    
