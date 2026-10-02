#pragma once
#include "numvalue.h"
/* this is not to be confused with the similarly named file  path-status.h, which
   has to do with ongoing status of the path*/
class QPos;
/* This class holds information about a  (a path) after
   matching was completed and it was a success. For failure, use
   It is designed to be stored in a qgame after a successful
   match and queried later.
*/

class PathStatus{
public:
  QPos*theStart{NULL};
  QPos*theLast{NULL};
  int theCount{0};
  NumValue theMax{0};
  PathStatus(QPos* start, QPos*last, int length, NumValue bestmax);
  QPos*getLast()const{return theLast;}
  QPos*getStart()const{return theStart;}
  int getCount()const{return theCount;}
  NumValue getMax()const{return theMax;}
  bool isSuccess()const{return theStart!=NULL;}
  bool isFailure()const {return theStart==NULL;}
  PathStatus(){}
};

