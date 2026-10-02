#pragma once
#include "node.h"
class BracketRange : public Node {
 public:
  BracketRange(Node*left, Node*right,bool singleindex);
  Node* theLeft{NULL};
  Node* theRight{NULL};
  bool singleIndex{false};
  string thisclass()const{return "BracketRange";}
  bool getBounds(QPos*,int len, NumValue* leftbound, NumValue* rightbound);
  void deepify();
[[nodiscard]]  BracketRange*clone();
  bool match_position(QPos*qpos);
  void print();
  vnode children()const;
};
  
