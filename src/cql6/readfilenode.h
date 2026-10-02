#pragma once
#include "node.h"

class ReadFileNode:public Node{
 private:
  Node* fileNameNode;
 public:
  ReadFileNode(Node* filename);
  bool match_position(QPos*);
  bool match_stringvalue(QPos*,string*);
  bool isString()const {return true;}
  string thisclass()const{return "ReadFileNode";}
[[nodiscard]]  ReadFileNode* clone();
  void print();
  void deepify();
  vnode children()const;
};


