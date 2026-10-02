#include "node.h"

bool PiOver4Transform::isIdentity()const{
  return times%8==0;
}

squareT PiOver4Transform::transform(squareT s)const{
  eassert(false,"An attempt to transform a particular square by 45 degrees was made. The rotate45 filter cannnot be used on individual squares");
  return 0;
}

bool PiOver4Transform::flipsSquareParity()const{
  eassert(false,"An attempt was made to determine the effect of a 45 degree transform on square color, which is undefined. This is likely due to applying the 'rotate45' transform to a 'light' or 'dark' filter");
  return false;
}

PiOver4Transform::PiOver4Transform(int t):times{t}{
  uassert(times>=0&&times<8,"PiOver4transform arg");
}

vector<Transform*>PiOver4Transform::rotations(){
  vector<Transform*> v;
  for (int t=1;t<8;++t)
    v.push_back(new PiOver4Transform(t));
  return v;
}

Direction PiOver4Transform::transform(Direction d)const{
  Direction ret=d;
  for (int i=0;i<times;++i)
    ret=rotate45(ret);
  return ret;
}

Direction PiOver4Transform::rotate45(Direction d)const{
  static vector<Direction> directions{
      Direction (1,0),
      Direction (1,1),
      Direction (0,1),
      Direction (-1,1),
      Direction (-1,0),
      Direction (-1,-1),
      Direction (0,-1),
      Direction (1,-1),
      };
  uassert(directions.size()==8,"static directions size");
  for(int i=0;i<8;++i)
    if (d.eq(directions[i]))
      return directions[(i+1)%8];
  uassert(false,"rotate45 internal loop");
  return Direction(0,1);
}

SquareMask PiOver4Transform::transform(SquareMask mask)const{
  if (mask.full()) return mask;
  if (mask.empty())return mask;
  eassert(false,"rotate45 cannot be applied to a particular square");
  return mask;
}

string PiOver4Transform::toString()const{
  stringstream s;
  s<<"rotate45^"<<times;
  return s.str();
}

