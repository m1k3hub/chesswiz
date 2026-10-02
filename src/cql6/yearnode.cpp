#include "node.h"
YearNode::YearNode(Range* r):range{r}{
  uassert(r&&range,"yearnode internal");
}

bool YearNode::match_game(QGame*qgame){
  NumValue n= -1;
  return match_count(qgame->root,&n);
}

bool YearNode::match_count(QPos*qpos, NumValue*value){
  int year=QMarkBoard::getYear(qpos->qgame);
  if (range->valid(year)){
    *value=(NumValue)year;
    return true;
  }
  return false;
}
  
  

  
