#pragma once
#include <fstream>
#include <map>
#include "node.h"


class WriteFileNode:public Node{
 private:
  Node* fileNameNode{NULL};
  Node*contentNode{NULL};
 public:
  WriteFileNode(Node* filenameNode,Node*contentnode);
  bool match_position(QPos*);
  string thisclass()const{return "WriteFileNode";}
[[nodiscard]]  WriteFileNode* clone();
  void print();
  void deepify();
  vnode children()const;
  static std::map<string,std::ofstream*> fileMap;
};


