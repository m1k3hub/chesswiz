#pragma once
#include "abbreviations.h"
#include "chesstypes.h"
#include "capturetype.h"

class QPos;
class QMove{
 public:
  QMove(Game*followinggame,const pieceT*previousboard);
  QMove(){};
  QPos*head{NULL};
  QPos*tail{NULL};
  squareT from {65};
  squareT to {65};
  squareT enpassant{65};
  pieceT promote{EMPTY};
  bool valid{false};
  int index{-10};
  bool isNull()const{return from==to;};
  void print()const;
  bool isEnPassant()const{return enpassant>=0&&enpassant<64;}
  squareT getEnPassantSquare()const{return enpassant;}
  pieceT getMovingPiece()const;
  markT movingPieceId()const;
  squareT getCaptureSquare()const;
  bool isCapture()const{return !isNonCapture();}
  bool isNonCapture()const;
  bool isOO()const;
  bool isOOO()const;
  bool isCastle()const;
  bool isNonCastle()const{return !isCastle();};
  markT capturedPieceId()const;
  markT castleKingId()const;
  markT castleRookId()const;
  squareT castleKingFrom()const;
  squareT castleKingTo()const;
  squareT castleRookFrom()const;
  squareT castleRookTo()const;
  SquareMask castleKingFromMask()const{return SquareMask::fromSquare(castleKingFrom());}
  SquareMask castleKingToMask()const{return SquareMask::fromSquare(castleKingTo());}
  SquareMask castleRookFromMask()const{return SquareMask::fromSquare(castleRookFrom());};
  SquareMask castleRookToMask()const{return SquareMask::fromSquare(castleRookTo());};
  SquareMask fatFrom()const;
  SquareMask fatTo()const;
  SquareMask castleFrom()const;
  SquareMask castleTo()const;
  SquareMask smartFrom(SquareMask frommask, SquareMask rightmask)const;
  SquareMask smartTo(SquareMask frommask, SquareMask rightmask)const;
  SquareMask getSimpleFromMask()const{return SquareMask::fromSquare(from);}
  SquareMask getSimpleToMask()const{return SquareMask::fromSquare(to);}
  bool validMove(SquareMask leftmask, SquareMask rightmask,CaptureType)const;
  bool invalidMove(SquareMask leftmask, SquareMask rightmask,CaptureType)const;
};
