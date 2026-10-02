#pragma once
#include "node.h"
#include "attackarrowdirection.h"

class RayNode: public SetBase{
 public:
    RayNode(vector<Direction>directions,
	  vector<SetBase*> ds,
	  bool isattack,
	  Range*r,
	  bool returnfirst);
  vector<Direction>directions;
  vector<SetBase*> designators;
  static RayNode* makeFromAttackArrow(vector<SetBase*>,AttackArrowDirection);
  bool isAttack{false};
  Range*theRange{NULL};
  bool theReturnFirst{false};
  bool match_position(QPos*qpos)override;
  string thisclass()const override{return "RayNode";}
  void print()override;
  vnode children()const override;
  bool transformmemberless(const Node*)const override;
  [[nodiscard]]RayNode*clone()override;
  void deepify()override;
  void transform_members(Transform*t)override;
  bool match_count(QPos*, NumValue* value)override;
  SquareMask getSquares(QPos*)override;
  bool isSet()const override;
  bool isNumeric()const override;
 private:
  SquareMask match_starting(const squareT square,
			    const int maskindex,
			    const vector<SquareMask>&masks,
			    Direction direction,
			    const SquareMask occupied);
  int count{0};
  SquareMask destMask;
  SquareMask fromMask;
  vector<SquareMask> designatorMasks;
  void compute(QPos*qpos);

};
