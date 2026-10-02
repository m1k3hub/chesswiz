#include "typenamenode.h"
/* Keep in sync with piecenamenode.cpp*/

TypeNameNode::TypeNameNode(SetBase*s):
  theSet(s){
  uassert(theSet,"PNN: bad set");
}

vnode TypeNameNode::children()const{
  return vnode{theSet};
}

void TypeNameNode::deepify(){
  theSet=theSet->clone();
}

bool TypeNameNode::match_stringvalue(QPos*qpos,string*sp){
  uassert(sp&&qpos,"TNN msv bad sp or qpos");
  SquareMask mask=theSet->getSquares(qpos);
  if(mask.count()!=1) return false;
  ForMask(square,mask){
    pieceT piece=qpos->getBoard()[square];
    char c= piece_to_char(piece);
    if(c>='a'&&c<='z')
      c=c - 'a' + 'A';
    *sp=string{c};
    return true;
  }
  uassert(false,"tnn msv no match");
  return false;
}
  
 
bool TypeNameNode::match_position(QPos* qpos){
  eassert(false,"typename unexpectedly invoked for whether it matches without using the returned string value. This may be an error");
  return false;
}
