#include "node.h"

bool ShiftTransform::isIdentity()const{
  return xoffset==0 && yoffset==0;
}

squareT ShiftTransform::transform(squareT square)const{
  uassert(square_valid(square),"shift t s");
  int x=square_file(square);
  int y=square_rank(square);
  int nx=x+xoffset;
  int ny=y+yoffset;
  if(!file_valid(nx)||!rank_valid(ny))
    return 65;
  return square_make(nx,ny);
}

ShiftTransform::ShiftTransform(int xoff,int yoff):xoffset(xoff),yoffset(yoff){
  uassert(xoff>=-7&&xoff<=7,"shift st off");
  uassert(yoff>=-7&&yoff<=7,"stst yoff");
  uassert(xoff!=0 || yoff!=0,"stst xoff yoff");
}


bool ShiftTransform::flipsSquareParity()const{
  int offsetsum=xoffset+yoffset;
  if (offsetsum<0) offsetsum= -offsetsum;
  return offsetsum %2 != 0;
}
    
vector<Transform*>ShiftTransform::allShift(){
  vector<Transform*>v;
  for(int xo=-7;xo<=7;++xo)
      for(int yo=-7;yo<=7;++yo)
	if(xo||yo)
	  v.push_back(new ShiftTransform(xo,yo));
  return v;
}

vector<Transform*>ShiftTransform::shiftHorizontal(){
  vector<Transform*>v;
  for(int xo=-7;xo<=7;++xo)
    if(xo)
      v.push_back(new ShiftTransform(xo,0));
  return v;
}

vector<Transform*>ShiftTransform::shiftVertical(){
  vector<Transform*>v;
  for(int yo=-7;yo<=7;++yo)
    if(yo)
      v.push_back(new ShiftTransform(0,yo));
  return v;
}

SquareMask ShiftTransform::transform(SquareMask mask)const{
  DihedralTransform swap(false,false,true);
  DihedralTransform vflip(true,false,false);
  uassert(xoffset||yoffset,"st:t xoyo");
  if(xoffset&&yoffset){
    ShiftTransform xt(xoffset,0);
    ShiftTransform yt(0,yoffset);
    return xt.transform(yt.transform(mask));
  }
  if(xoffset==0){
    ShiftTransform newxt(yoffset,0);
    return swap.transform(newxt.transform(swap.transform(mask)));
  }
  if(xoffset<0){
    ShiftTransform newxt(-xoffset,0);
    return vflip.transform(newxt.transform(vflip.transform(mask)));
  }
  uassert(xoffset>0&&yoffset==0,"tran xoyo");
  if(xoffset>1){
    ShiftTransform right(1,0);
    SquareMask current=mask;
    for(int i=0;i<xoffset;++i)
      current=right.transform(current);
    return current;
  }
  uassert(xoffset==1&&yoffset==0,"tran x1y0");
  SquareMask ret;
  for(int sq=0;sq<64;++sq){
    int newsq=transform(sq);
    if(square_valid(newsq)&&mask.member(sq))
      ret.insert(newsq);
  }
  for(int rank=0;rank<8;++rank)
    if (mask.rankCount(rank)==8){
      int popin=square_make(0,rank);
      if(mask.member(popin))
	ret.insert(popin);
    }
  return ret;
}

string ShiftTransform::toString()const{
  stringstream s;
  if (isIdentity())return "";
  if (xoffset>0) s<<"right^"<<xoffset<<' ';
  if (xoffset<0)s<<"left^"<< -xoffset<<' ';
  if(yoffset>0) s<<"up^"<<yoffset<<' ';
  if(yoffset<0) s<<"down^"<< -yoffset<< ' ';
  string ret=s.str();
  uassert(ret.size(),"shift tostring");
  if(ret.back()==' ')ret.pop_back();
  return ret;
}

  
