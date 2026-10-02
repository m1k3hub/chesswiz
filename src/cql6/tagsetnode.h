#pragma once
#include "node.h"
class TagSetNode:public Node{
 public:
  TagSetNode(const string &name,Node* node);
  string theName;
  Node*theNode{NULL};
  string getName() const{return theName;}
  const Node*getNode()const{return theNode;}
  Node*getNode(){return theNode;}
  string thisclass()const{return "TagSetNode";}
[[nodiscard]]  TagSetNode* clone();
  vnode children()const;
  void print();
  bool match_position(QPos*);
  void deepify();
  static bool isSettable(const string& tagname, string*message=NULL);
  static const vector<string> forbiddenTags;
};

