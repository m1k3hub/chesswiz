#include "util.h"

squareT Direction::apply(squareT square)const{
  return apply(square, 1);
}

squareT Direction::apply(squareT square, int times)const{
  uassert(times>=-7&&times<=7,"Direction::apply times out of range");
  uassert(square_valid(square),"Direction::apply: square not valid");
  int x= square_file(square);
  int y= square_rank(square);
  int nx= x+xoffset*times;
  int ny= y+yoffset*times;
  if(file_valid(nx)&&rank_valid(ny)){
    squareT ret=square_make(nx,ny);
    uassert(square_valid(ret),"Direction::apply ret not valid");
    return ret;
  }
  return 65;
}

bool Direction::reachable(squareT source, squareT target)const{
  uassert(square_valid(source)&&square_valid(target),"Drsvssvt");
  int dx=square_file(target)-square_file(source);
  int dy=square_rank(target)-square_rank(source);
  if (xoffset==0){
    uassert(yoffset,"Direction::reachable: yoffset check");
    return dx==0&& dy/yoffset >0;
  }
  else if(yoffset==0){
    uassert(xoffset,"Direction::reachable: xoffset check");
    return dy==0&&dx/xoffset>0;
  }
  else
    return dx/xoffset==dy/yoffset&&
      dx/xoffset>0;
}

SquareMask Direction::between(squareT source, squareT target){
  SquareMask mask;
  uassert(square_valid(source)&&square_valid(target),"Direction::between: squares input");
  if (source==target)return mask;
  int sx=square_file(source);
  int sy=square_rank(source);
  int tx=square_file(target);
  int ty=square_rank(target);
  int deltax=tx-sx;
  int deltay=ty-sy;
  if (deltax && deltay && abs(deltax)!=abs(deltay)) return mask;
  int xsign=deltax>0?1 : deltax< 0 ? -1 : 0;
  int ysign=deltay>0?1 : deltay< 0 ? -1 : 0;
  squareT current=source;
  int currentx=sx;
  int currenty=sy;
  while(true){
    currentx+=xsign;
    currenty+=ysign;
    current=square_make(currentx,currenty);
    uassert(square_valid(current),"Direction::between internal current");
    if(current==target)return mask;
    mask.insert(current);
  }
  return mask;
}  

Direction::Direction(int xoff, int yoff):xoffset{xoff},yoffset{yoff}{
  uassert(validOffset(xoff,yoff),"Direction::Direction params");
}

bool Direction::validOffset(int xoff, int yoff){
  return validOffset(xoff)
    &&validOffset(yoff)&&
    (xoff||yoff);
}

bool Direction::validOffset(int off){
  return off>=-1&&off<=1;
}

bool Direction::eq(const Direction & other)const{
  return xoffset==other.xoffset && yoffset==other.yoffset;
}

vector<Direction>Direction::orthogonalDirections(){
  vector<Direction>ret;
  for (Direction& d : allDirections())
    if (d.isOrthogonal())
      ret.push_back(d);
  return ret;
}

vector<Direction>Direction::diagonalDirections(){
  vector<Direction>ret;
  for (Direction d : allDirections())
    if (d.isDiagonal())
      ret.push_back(d);
  return ret;
}

vector<Direction>Direction::allDirections(){
  vector<Direction>ret;
  for(int xo= -1;xo<=1;++xo)
    for(int yo= -1;yo<=1;++yo)
      if(validOffset(xo,yo))
	ret.push_back(Direction(xo,yo));
  return ret;
}


bool Direction::isCompatible(pieceT piece)const{
  pieceT newp=piece_Type(piece);
  if (newp==ROOK) return isOrthogonal();
  else if(newp==BISHOP) return isDiagonal();
  else if(newp==QUEEN) return isOrthogonal()||isDiagonal();
  else return false;
}

bool Direction::isOrthogonal()const{
  return xoffset==0||yoffset==0;
}

bool Direction::isDiagonal()const{
  return xoffset&&yoffset;
}
  
//Direction::operator< and DirectionParameter::operator< are in transformcompare.cpp  
  
