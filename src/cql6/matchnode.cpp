#include "matchnode.h"
MatchNode::MatchNode(TransformVariable*tvl,Node*l,TransformVariable*tvr,Node*r):
  leftTransformVariable(tvl),
  left(l),
  rightTransformVariable(tvr),
  right(r){
  uassert(left&&right,"null arg to MatchNode");
  uassert(left->isPosition(),"first argument to 'match' is not a position filter");
  uassert(right->isPosition(),"second argument to 'match' is not a position filter");
}

vnode MatchNode::children()const{
  vnode ret{left};
  if(right!=left)ret.push_back(right);
  return ret;
}

void MatchNode::deepify(){
  left=left->clone();
  right=right->clone();
}

bool MatchNode::isSet()const{return true;}

SquareMask MatchNode::getSquares(QPos*qpos){
  uassert(isSet(),"'&' filter used as a set filter, but it is not a set filter in this context. (tomove parameter specified)");
  SquareMask ret;
  QPos* leftpos{NULL};
  QPos* rightpos{NULL};
  if(!left->match_positionvalue(qpos,&leftpos)){
    return ret;}
  if(!right->match_positionvalue(qpos,&rightpos)){
    return ret;}
  uassert(leftpos&&rightpos,"matchnodegetsquares lrpos");
  if(!leftTransformVariable&&!rightTransformVariable)
    return getSquaresSimple(leftpos,rightpos);
  return getSquaresGeneral(leftpos,rightpos);
}
SquareMask MatchNode::getSquaresSimple(QPos*leftpos,QPos*rightpos){
  uassert(leftpos&&rightpos, "mngss args");
  SquareMask ret;
#define lrcompare(piece) (leftpos->thePieceMasks.at(piece)&rightpos->thePieceMasks.at(piece))
  ret |=
    (lrcompare(EMPTY) |
     lrcompare(WK) |
    lrcompare(WQ) |
    lrcompare(WR) |
    lrcompare(WB) |
    lrcompare(WN) |
    lrcompare(WP) |
    lrcompare(BK) |
    lrcompare(BQ) |
    lrcompare(BR) |
    lrcompare(BB) |
    lrcompare(BN) |
     lrcompare(BP));
  return ret;
}
    

//This is not strictly speaking correct. Should modify later
bool MatchNode::match_position(QPos*qpos){
  eassert(false,
		  "Attempt to determine if 'position & position' matches a position. Although not strictly illegal, this is ordinarily an error, since this  filter returns a set that is almost never nonempty. ");
  return true;
}

SquareMask MatchNode::getSquaresGeneral(QPos*leftpos, QPos*rightpos){
  uassert(leftpos&&rightpos,"mngsg args");
  Transform*lefttransform{NULL};
  if(leftTransformVariable){
    lefttransform=leftTransformVariable->getValue();
    uassert(lefttransform,"mngsg: null transform for lefttransformvariable");
  }
  Transform*righttransform{NULL};
  if(rightTransformVariable){
    righttransform=rightTransformVariable->getValue();
    uassert(righttransform,"mngsg: null transform for righttransformvariable");
  }
  
  pieceT tleftboardbuffer[64];
  pieceT trightboardbuffer[64];
  const pieceT*tleftboard = boardTransform(lefttransform,leftpos,tleftboardbuffer);
  const pieceT*trightboard = boardTransform(righttransform,rightpos,trightboardbuffer);
  SquareMask ret;
  for (int sq=0;sq<64;++sq)
    if(tleftboard[sq]==trightboard[sq])
      ret.insert(sq);
  return ret;
}

/*This does NOT yet allow color flips*/
const pieceT* MatchNode::boardTransform(Transform*t, QPos*qpos, pieceT * board){
  uassert(qpos&&board,"mn boardTransform args");
  const pieceT* qboard=qpos->getBoard();
  if(!t)return qboard;
  for(int sq=0;sq<64;++sq)board[sq]=EMPTY;
  for (int sq=0;sq<64;++sq){
    int transformedsq=t->transform(sq);
    if(square_valid(transformedsq))
      board[sq]=qboard[sq];
  }
    return board;
}
