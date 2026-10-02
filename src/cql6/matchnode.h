#pragma once
#include "node.h"
#include "transformvariable.h"
class MatchNode : public SetBase{
 public:
  MatchNode(TransformVariable* tvl, Node* l,TransformVariable* tvr, Node*r);
  bool isSet()const;
  TransformVariable*leftTransformVariable{NULL};
  Node* left{NULL};
  TransformVariable*rightTransformVariable{NULL};
  Node* right{NULL};
  string thisclass()const{return "MatchNode";}
[[nodiscard]]  MatchNode*clone();
  vnode children()const;
  void deepify();
  void print();
  SquareMask getSquares(QPos*);
  bool match_position(QPos*);
 private:
  SquareMask getSquaresSimple(QPos*leftpos, QPos*rightpos);
  SquareMask getSquaresGeneral(QPos*leftpos, QPos*rightpos);
  const pieceT* boardTransform(Transform*,QPos*, pieceT*);
};
