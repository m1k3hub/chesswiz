#pragma once
#include "node.h"

class MoveLegalNode:public SetBase{
 public:
  string thisclass()const{return "MoveLegalNode";}
[[nodiscard]]  MoveLegalNode* clone();
  MoveLegalNode(SetBase*from, SetBase*to, SetBase* enpassant, Range*range,bool allowPseudo,bool returnfrom, bool returnto);
  SetBase* fromNode{NULL};
  SetBase* toNode{NULL};
  SetBase* enpassantSquare{NULL};
  Range* range{NULL};
  bool pseudoFlag{false}; // if true, allow pseudolegal non-castling moves
  bool returnFrom{false};
  bool returnTo{false};
  bool match_position(QPos*);
  SquareMask getSquares(QPos*);
  bool isSet()const;
  bool isNumeric()const;
  void print();
  void deepify();
  vnode children()const;
  bool match_count(QPos*,NumValue*value);
 private:
  int count{0};
  void compute(QPos*);
  static bool unmoved(QGame*qgame, SquareMask mask);
  static SquareMask filterPseudoLegal(squareT from, SquareMask candidates, const pieceT*board);
  SquareMask toSquares;
  SquareMask fromSquares;
  SquareMask epSquares;
};

