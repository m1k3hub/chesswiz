#pragma once
#include "node.h"

class PieceLoc:public SetBase{
 public:
  /*caching related members*/
  PieceLoc(vector<PieceToken*>piecetokens,
	   vector<SquareToken*> squaretokens);
  static vector<pieceT>piecesFromChar(char c);
  void print();
  string thisclass()const{return "PieceLoc";}
[[nodiscard]]  PieceLoc*clone();
  vnode children()const{return vnode{};}
  bool isPurePiece();
  void transform_members(Transform *);
  bool transformmemberless(const Node*)const;
  bool hasEmptySquareMask()const;
  SquareMask getSquares(QPos*);
  SquareMask getPieceMask(QPos*);
  bool match_piecetype(pieceT);
  void deepify(){}
 private:
  vector<pieceT> thePieces;
  SquareMask squaremask;
  std::array<bool,2> colorFlags; //whether all pieces of that color included
};
