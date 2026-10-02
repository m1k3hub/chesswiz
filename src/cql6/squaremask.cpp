#include "util.h"

int SquareMask::size()const{
  int s=0;
  Mask tmp=mask;
  while(tmp){
    s+=tmp%2;
    tmp=tmp>>1;
  }
  return s;
}


vector<squareT> SquareMask::getSquares()const{
  vector<squareT> v;
  for(int i=0;i<64;++i)
    if(member(i)) v.push_back(i);
  return v;
}

SquareMask::SquareMask(const vector<squareT>&squares){
  mask=0;
  for(auto sq:squares)
    mask |= ((Mask)1<<sq);
}

int SquareMask::rankCount(int rank)const{
  uassert(rank_valid(rank),"smrc rank");
  int count=0;
  for(int file=0;file<8;++file){
    squareT square=square_make(file,rank);
    if (member(square))++count;
  }
  return count;
}

SquareMask SquareMask::all(){
  Mask tmp=0;
  tmp= ~tmp;
  return SquareMask(tmp);
}
  
    
