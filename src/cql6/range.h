#pragma once
#ifdef CQL6_EMBEDDED
#include "scidb_retain.h"
#endif
class NumericVariable;
class Range{
 public:
#ifdef CQL6_EMBEDDED // scidb: search ownership
  SCIDB_SEARCH_ALLOCATOR(Range)
#endif
  string thisclass()const{return "Range";}
  void print();
  Range(int m);
  Range(int mi,int ma);
  Range(int mi, int ma, NumericVariable* v1, NumericVariable*v2);
  bool valid(int i);
  int getMin();
  int getMax();
  string toString();
  bool isConstant();
 private:
  int theMin{-100000};
  int theMax{-100000};
  NumericVariable* theMinv{NULL};
  NumericVariable* theMaxv{NULL};
};

