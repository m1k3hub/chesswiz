#include "qpos.h"
#include "cqlassert.h"
#include "pathstatus.h"
PathStatus::PathStatus(QPos*start, QPos*last, int count,NumValue bestmax):theStart(start),theLast(last),theCount(count),theMax(bestmax){
  uassert(theStart!=NULL && theLast!=NULL && theCount>0,"PathStatus: invalid arguments");
}
