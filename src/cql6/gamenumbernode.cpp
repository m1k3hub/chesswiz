#include "node.h"
GameNumberNode::GameNumberNode(Range*r):range(r){
  uassert(range,"GameNumberNode: bad argument");
}

bool GameNumberNode::match_count(QPos*qpos,NumValue*value){
  auto num=qpos->qgame->getGameNumber();
  if (range->valid(num)){
    *value=(NumValue)num;
    return true;
  }
  return false;
}

bool GameNumberNode::match_game(QGame*qgame){
  NumValue v{-1000};
  return match_count(qgame->root,&v);
}
