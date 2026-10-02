#pragma once
#include "node.h"
class SquareParityNode:public SetBase{
 public:
  string thisclass()const{return "SquareParityNode";}
  SquareMask theMask;
  SetBase* theSet{NULL};
  static bool squareIsLight(squareT sq);
  static bool squareIsDark(squareT sq);
  void print();
  bool match_position(QPos*);
  SquareMask getSquares(QPos*);
  SquareParityNode(SetBase*set,bool islight);
[[nodiscard]]  SquareParityNode*clone();
  vnode children()const;
  void transform_members(Transform*);
  bool transformmemberless(const Node*)const;
  void deepify();
  static SquareMask getLightMask();
  static SquareMask getDarkMask();
  bool isLight()const;
  bool isDark()const;
};
