#pragma once
#include "node.h"
#include "anyvalue.h"
class FromToNode;
class DashNode : public SetBase{
 public:
  DashNode(SetBase*left, SetBase*right, Node*target, CaptureType, bool iscount);
  SetBase*left{NULL};
  SetBase*right{NULL};
  Node*target{NULL};
  CaptureType theCaptureType{CaptureType::None};
  CaptureType getCaptureType()const{return theCaptureType;}
  QPos* theForceTail{NULL};
  void setForceTail(QPos* qpos){theForceTail=qpos;}
  bool isCount{false};
  vector<FromToNode*>fromToNodeOwned;     //see above
  SetBase*getLeft()const{return left;}
  SetBase*getRight()const{return right;}
  Node*getTarget()const{return target;}
  string thisclass()const override{return "DashNode";}
  vnode children()const override;
  void deepify()override;
[[nodiscard]]  DashNode*clone()override;
  bool match_count(QPos*,NumValue*value)override;
  void print()override;
  bool match_position(QPos*)override;
  bool match_stringvalue(QPos*,string*)override;
  bool match_positionvalue(QPos*,QPos**)override;
  SquareMask getSquares(QPos*)override;
  bool isNumeric()const override;
  bool isPosition()const override;
  bool isString()const override;
  bool isSet()const override;
  bool isDashNode()const override{return true;}
  bool isFromToOwner()const override{return true;}
  bool canModifyCurpos()const override{return true;}
 private:
  bool compute(QPos*,bool getvalue);
  AnyValue::Any theValue;
  bool handleTarget(QPos*tail,bool getvalue);
  int computeCount(QPos*); // for when the count specifier is used
};  
  
   
  
