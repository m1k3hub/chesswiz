#include "colortypenode.h"
ColorTypeNode::ColorTypeNode(SetBase*s):theSet(s){
  uassert(theSet&&theSet->isSet(),"ctn bad arg");
}

vnode ColorTypeNode::children()const{
  return vnode{theSet};
}

void ColorTypeNode::deepify(){
  theSet=theSet->clone();
}

bool ColorTypeNode::match_position(QPos*qpos){
  NumValue result{0};
  return match_count(qpos,&result);
}

bool ColorTypeNode::match_count(QPos*qpos,NumValue*valuep){
  uassert(qpos&&valuep,"ctnmc");
  SquareMask mask=theSet->getSquares(qpos);
  int n=mask.count();
  if (n!=1) return false;
  ForMask(square,mask){
    pieceT piece=qpos->getBoard()[square];
    int value=colortype_from_piece(piece);
    *valuep=(NumValue)value;
    return true;
  }
  uassert(false,"ctn match_count fall through");
  return false;
}

int ColorTypeNode::colortype_from_piece(pieceT piece){
  if (piece==EMPTY)
    return EmptyType;
  colorT color=piece_Color(piece);
  uassert(color==WHITE||color==BLACK,"ctnctfp color");
  int piecetype=type_from_piece(piece);
  if(color==WHITE) return piecetype;
  return -piecetype;
}

int ColorTypeNode::type_from_piece(pieceT piece){
  switch(piece){
  case WP: case BP: return PawnType;
  case WN: case BN: return KnightType;
  case WB: case BB: return BishopType;
  case WR: case BR: return RookType;
  case WQ: case BQ: return QueenType;
  case WK: case BK: return KingType;
  case EMPTY: return EmptyType;
  }
  stringstream s;
  s<<"Bad piece parameter to type_from_piece: "<<piece;
  uassert(false,s.str());
  return 0;
}

  

    
