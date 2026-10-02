#pragma once
#include "node.h"
class ColorTypeNode : public Node{
 public:
  ColorTypeNode(SetBase*);
  SetBase* theSet{NULL};
  static const int PawnType=1;
  static const int KnightType=2;
  static const int BishopType=3;
  static const int RookType=4;
  static const int QueenType=5;
  static const int KingType=6;
  static const int EmptyType=0;
  string thisclass()const{return "ColorTypeNode";}
  vnode children()const;
  void deepify();
[[nodiscard]]  ColorTypeNode*clone();
  bool match_position(QPos*);
  bool match_count(QPos*,NumValue*);
  void print();
  int colortype_from_piece(pieceT piece);
  int type_from_piece(pieceT piece);
  int colortype_from_type_color(pieceT piece, colorT color);
  bool isNumeric()const{return true;};
};
