#include "node.h"
#include "pieceloc.h"
#include "colorvaluenode.h"
#include "vectornode.h"
#include "tomovenode.h"
#include "tagbuiltinnode.h"
#include "raynode.h"

/* These functions are run AFTER transform_in_place() is run
   which transforms the children (which is run after clone())
   transform_members just transforms the non-child members after the
   children were transformed.
   See  nodetransform.cpp and some documentation there.
   Note that  OrbitNode has transform_in_place() method
   but not transform_members() method
*/

void ResultNode::transform_members(Transform*t){
  if(t->flipsColor()){
    switch(result){
    case RESULT_White: result=RESULT_Black; break;
    case RESULT_Black: result=RESULT_White; break;
    case RESULT_Draw: break;
    default: uassert(false, "bad result");
    }
  }
}
    

void PieceLoc::transform_members(Transform*t){
  vector<pieceT> newpieces;
  for(pieceT& piece : thePieces){
    uassert (piece_valid(piece),"transform_members: piece not valid");
    pieceT newpiece=t->transformPiece(piece);
    piece=newpiece;
    }
  if(t->flipsColor())
    std::swap(colorFlags[BLACK],colorFlags[WHITE]);
  squaremask=t->transform(squaremask);
  std::stable_sort(thePieces.begin(), thePieces.end());
}

void ToMoveNode::transform_members(Transform*t){
  color=t->transformColor(color);
}

void ColorValueNode::transform_members(Transform*t){
  color=t->transformColor(color);
}

/* this is called after Node::transform_in_place, which
   should swap the colors of the regexes as necessary. 
   If nocolor is specified this will leave them out of order
   and they must be swapped*/

void EloNode::transform_members(Transform*t){
  color=t->transformColor(color);
}

void RayNode::transform_members(Transform*t){
  for(int i=0;i<directions.size();++i)
    directions[i]=t->transform(directions[i]);
  std::stable_sort(directions.begin(),directions.end());
}

void VectorNode::transform_members(Transform*t){
  parameter=t->transform(parameter);
}



void TagBuiltInNode::transform_members(Transform*t){
  if(t->flipsColor()){
    if (theName=="White") theName="Black";
    else if (theName=="Black") theName="White";
  }
}
