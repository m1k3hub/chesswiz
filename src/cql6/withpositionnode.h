#pragma once
#include "node.h"
class WithPositionNode : public SetBase{
 private:
  Node* theTarget{NULL};
  Node* theFilter{NULL};
 public:
  WithPositionNode(Node*target, Node*filter);
  string thisclass()const override{return "WithPositionNode";}
  void deepify()override;
[[nodiscard]]  WithPositionNode*clone() override;
  vnode children()const override;
  void print() override;
  bool isPosition()const override;
  bool isSet()const override;
  bool isNumeric()const override;
  bool isString()const override;
  bool match_count(QPos*, NumValue*val) override;
  bool match_positionvalue(QPos*, QPos**) override;
  bool match_stringvalue(QPos*, string*) override;
  bool match_position(QPos*) override;
  QPos* getPosition(QPos*qpos);
  SquareMask getSquares(QPos*) override;
  bool isWithPositionNode()const override{return true;}
  bool canModifyCurpos()const override{return true;}
};
		    
