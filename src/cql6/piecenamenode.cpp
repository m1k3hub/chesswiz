#include "piecenamenode.h"
/* Keep in sync with typenamenode.cpp*/
PieceNameNode::PieceNameNode(SetBase*s):
  theSet(s){
  uassert(theSet,"PNN: bad set");
}

vnode PieceNameNode::children()const{
  return vnode{theSet};
}

void PieceNameNode::deepify(){
  theSet=theSet->clone();
}

bool PieceNameNode::match_stringvalue(QPos*qpos,string*sp){
  uassert(sp&&qpos,"PNN msv bad sp or qpos");
  SquareMask mask=theSet->getSquares(qpos);
  if(mask.count()!=1) return false;
  ForMask(square,mask){
    pieceT piece=qpos->getBoard()[square];
    char c= piece_to_char(piece);
    *sp=string{c};
    return true;
  }
  uassert(false,"pnn msv no match");
  return false;
}
  
bool PieceNameNode::match_position(QPos* qpos){
  eassert(false,"piecename unexpectedly invoked for whether it matches without using the returned string value. This may be an error");
  return false;
}
