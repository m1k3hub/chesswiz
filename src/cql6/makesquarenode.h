#pragma once
#include  "node.h"
class MakeSquareNode: public SetBase{
 public:
  MakeSquareNode(Node* file, Node* rank);
  MakeSquareNode(Node* name);
  Node* theFile{NULL};//numeric
  Node* theRank{NULL};//numeric
  Node* theName{NULL};//string
  vnode children()const;
  void print();
  string thisclass()const{return "MakeSquareNode";}
[[nodiscard]]  MakeSquareNode*clone();
  void deepify();
  bool match_position(QPos*);
  SquareMask getSquares(QPos*);
  SquareMask getSquaresNumeric(QPos*);
  SquareMask getSquaresString(QPos*); 
 private:
  bool isFromFileRank()const;
  bool isFromName()const;
};
