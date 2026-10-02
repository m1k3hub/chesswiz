#pragma once
#include "common.h"
#include "abbreviations.h"
typedef unsigned long long Mask;
class SquareMask{
 public:
  Mask mask{0};
  explicit SquareMask(Mask m){mask=m;}
  static SquareMask fromSquare(squareT square){return SquareMask((Mask)1<<square);}
  SquareMask(const vector<squareT>&);
  SquareMask(){}
  void print()const;
  void printconst();
  void boardprint()const;
  static void boardprint(Mask m);
  string thisclass()const{return "SquareMask";}
  void printnl();
  int size()const;
  void clear(){mask=0;}
  bool empty()const{return mask==0;}
  static SquareMask all();
  bool nonempty()const{return !empty();}
  int count()const{return size();}
  bool full() const{return (~mask)==0;}
  bool member(int s) const {return (mask>>s)%2;}
  void insert(int s){mask|=((Mask)1<<s);}
  int rankCount(int rank)const;
  vector<squareT> getSquares()const;
  void operator|= (SquareMask o){mask|=o.mask;}
  SquareMask operator|(SquareMask o)const{return SquareMask(mask|o.mask);}
  void operator&= (SquareMask o){mask&=o.mask;}
  bool operator==(SquareMask o)const{return mask==o.mask;}
  bool operator<(SquareMask o)const{return mask<o.mask;}
  SquareMask operator&(SquareMask o)const{return SquareMask(mask&o.mask);}
  SquareMask operator~()const{return SquareMask(~mask);}
  string listString()const;
};
  
#ifndef ForMask
#define ForMask(square,mask) for(squareT square=0;square<64;++square)if((mask).member(square))
#endif

