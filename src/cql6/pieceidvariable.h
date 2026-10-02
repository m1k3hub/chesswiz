#pragma once
#include "variable.h"

class PieceIdVariable:public Variable{
 private: markT pieceid;
 public:
  string thisclass()const{return "PieceIdVariable";}
[[nodiscard]]  PieceIdVariable* clone(){return this;}
  PieceIdVariable(string name);
  bool getSquare(QPos*qpos, squareT*s);
  bool isSet()const{return true;}
  bool isPieceId()const{return true;}
  void bindPieceId(QPos*qpos, markT t);
  markT getPieceId();
  string toString();
  bool isPieceIdVariable()const{return true;}
  PieceIdVariable* asPieceIdVariable(){return this;}
  SquareMask getSquares(QPos*qpos);
};
