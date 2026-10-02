#pragma once
#include "node.h"
class GameFilterWrapper : public GameFilter{
 public:
  Node*theNode{NULL};
  GameFilterWrapper(Node*);
  string thisclass()const{return "GameFilterWrapper";}
[[nodiscard]]  GameFilterWrapper* clone();
  void deepify();
  vnode children()const;
  void print();
  bool match_game(QGame*qgame);
  bool match_position(QPos*);
};
