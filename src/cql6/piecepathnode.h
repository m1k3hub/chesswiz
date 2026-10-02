#pragma once
#include "node.h"
class PiecePathNode : public Node{
 public:
  SetBase* theFrom{NULL}; //
  Node* theTo{NULL}; // a position filter
  bool isVerbose{false};
  PiecePathNode(SetBase* from, Node* to, bool isverbose);
  bool match_position(QPos*)override;
  bool match_stringvalue(QPos* qpos, string* stringval)override;
  bool isString()const override{return true;}
  string thisclass()const override{return "PiecePathNode";}
  void print()override;
[[nodiscard]]  PiecePathNode* clone() override;
  void deepify()override;
  vnode children()const override;
  bool canModifyCurpos()const override{return true;}
 private:
  string pathstring(squareT sq, QPos*start, QPos*to);
};
