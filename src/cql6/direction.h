#pragma once
#ifdef CQL6_EMBEDDED
#include "scidb_retain.h"
#endif
class Range;
class Direction{
 public:
   int xoffset;
   int yoffset;
  Direction(int xoff,int yoff);
  string toString ()const;
  static vector<Direction> directionsFromString(string s);
  void print()const;
  squareT apply(squareT square)const;
  squareT apply(squareT square, int ntimes)const;
  bool reachable(squareT source, squareT target)const;
  static SquareMask between(squareT source, squareT target);
  static Direction fromString(string name);
  bool eq(const Direction& other)const;
  Direction reverse()const;
  static vector<Direction> allDirections();
  static vector<Direction> orthogonalDirections();
  static vector<Direction> diagonalDirections();
  bool isDiagonal()const;
  bool isOffdiagonal()const;
  bool isOrthogonal()const;
  static bool validOffset(int xoffset, int yoffset);
  static bool validOffset(int offset);
  bool isCompatible(pieceT piece)const;
  bool operator<(const Direction&other)const;
};
  
class DirectionParameter {
 public:
#ifdef CQL6_EMBEDDED
  SCIDB_SEARCH_ALLOCATOR(DirectionParameter)
#endif
  vector<Direction> directions;
  Range*range {NULL};
  string thisclass()const{return "DirectionParameter";}
  void print();
  SquareMask neighborhood(squareT square);
  SquareMask neighborhood(SquareMask mask);
  DirectionParameter(vector<Direction> v, Range*r);
  bool operator<(const DirectionParameter& other)const;
};
  
