#include "node.h"
EloNode::EloNode(Range* r,colorT c):range{r},color{c}{
  uassert(r&&range,"elonode internal");
  uassert(color==WHITE||color==BLACK||color==NOCOLOR,"playernode color");
}

bool EloNode::match_count(QPos*qpos,NumValue*value){
  int maxelo=0;
  QGame*qgame=qpos->qgame;
  int whiteelo=QMarkBoard::getElo(qgame,WHITE);
  int blackelo=QMarkBoard::getElo(qgame,BLACK);
  bool matched=false;
  if( (color==WHITE||color==NOCOLOR)
      && range->valid(whiteelo)){
    matched=true;
    maxelo=std::max(maxelo,whiteelo);
  }
  if ((color==BLACK||color==NOCOLOR)
      && range->valid(blackelo)){
    matched=true;
    maxelo=std::max(maxelo,blackelo); //fixing bug from 9.186 released as of build 9.187
  }
  if(!matched)return false;
  *value=(NumValue)maxelo;
  return true;
}

bool EloNode::match_game(QGame*qgame){
  NumValue n= -1;
  return match_count(qgame->root,&n);
}

