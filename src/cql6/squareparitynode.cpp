#include "squareparitynode.h"
SquareParityNode::SquareParityNode(SetBase*set,bool islight):theSet(set){
  uassert(set!=NULL,"SquareParityNode: bad input");
  if(islight) theMask= getLightMask();
  else theMask=getDarkMask();
}

SquareMask SquareParityNode::getSquares(QPos* qpos){
  return theMask & theSet->getSquares(qpos);
}

bool SquareParityNode::match_position(QPos*qpos){
  return getSquares(qpos).nonempty();
}

vnode SquareParityNode::children()const{
  return vnode{theSet};
}

void SquareParityNode::transform_members(Transform*t){
  if (t->flipsSquareParity())
    theMask = ~theMask;
}

void SquareParityNode::deepify(){
  theSet=theSet->clone();
}

bool SquareParityNode::isLight()const{
  return theMask==getLightMask();
}

bool SquareParityNode::isDark()const{
  return theMask==getDarkMask();}

SquareMask SquareParityNode::getDarkMask(){
  SquareMask mask;
  for (int sq=0;sq<64;sq++)
    if (squareIsDark(sq))
      mask.insert(sq);
  return mask;
}

SquareMask SquareParityNode::getLightMask(){
  return ~getDarkMask();
}
  
bool SquareParityNode::squareIsLight(squareT square){
  return (square_Rank(square) + square_Fyle(square)) % 2 != 0;}

bool SquareParityNode::squareIsDark(squareT square){
  return !squareIsLight(square);
}
