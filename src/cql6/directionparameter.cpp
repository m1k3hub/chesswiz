#include "util.h"

SquareMask DirectionParameter::neighborhood(squareT square){
  int rangemin=range->getMin();
  int rangemax=range->getMax();
  if(rangemin<-7 || rangemax>7 || rangemin>rangemax){
    stringstream s;
    s<<"Invalid range (limit magnitude cannot exceed 7 and min must be less than max): "<<range->toString();
    eassert(false,s.str());
  }
  
  SquareMask mask;
  for (Direction direction:directions)
    for(int i=rangemin;i<=rangemax;++i){
      squareT newsquare=direction.apply(square,i);
      if(square_valid(newsquare))
	mask.insert(newsquare);
    }
  return mask;
}

SquareMask DirectionParameter::neighborhood(SquareMask mask){
  SquareMask m;
  for (squareT square : mask.getSquares())
    m|=neighborhood(square);
  return m;
}

DirectionParameter::DirectionParameter(vector<Direction> ds,Range *r){
  directions=ds;
  std::stable_sort(directions.begin(),directions.end());
  range=r;
}




    
