#include "node.h"
#include <utility>

Transform* Transform::transform(const Transform*t)const{
  uassert(t,"tttt");
  return new ComposeTransform(this,t);
}

Node* Transform::transform(Node*filter){
  uassert(filter,"tt filter");
  return filter->transform(this);
}

  
DirectionParameter Transform::transform(DirectionParameter directionparameter)const{
  vector<Direction>v;
  for(auto d:directionparameter.directions)
    v.push_back(transform(d));
  return DirectionParameter(v,directionparameter.range);
}


pieceT Transform::transformPiece(pieceT piece)const{
  uassert(piece_valid(piece),"ttp p");
  pieceT ret=50;
  if(flipsColor()) 
    ret= PIECE_FLIP[piece]; //copied from egs/pieceLoc.cpp:385, cleaner ways exist
  else
    ret=piece;
  uassert(piece_valid(ret),"ttp pv");
  return ret;
}

colorT Transform::transformColor(colorT color)const{
  if(!flipsColor())return color;
  if(color==WHITE)return BLACK;
  if(color==BLACK) return WHITE;
  if(color==NOCOLOR) return NOCOLOR;
  uassert(false,"bad color transformcolor");
  return NOCOLOR;
}

Transform* Transform::compose(Transform * t){
  uassert(t,"tc t");
  return new ComposeTransform(this,t);
}

vector<Transform*> Transform::nonidentity(const vector<Transform*>& transforms){
  vector<Transform*> ret;
  for(auto t:transforms)
    if (!dynamic_cast<IdentityTransform*>(t))
      ret.push_back(t);
  return ret;
}


