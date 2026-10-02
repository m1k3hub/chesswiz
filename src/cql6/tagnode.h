#pragma once
#include "node.h"
class TagNode:public Node{
 public:
  TagNode(string name);
  string theName;
  string getName() const{return theName;}
  string thisclass()const{return "TagNode";}
[[nodiscard]]  TagNode* clone();
  vnode children()const{return vnode{};}
  void print();
  TagNode(Node*np);
  bool match_position(QPos*);
  bool match_game(QGame*);
  bool match_stringvalue(QPos*,string*);
  bool match_stringvalue_game(QGame*,string*);
  void deepify(){};
  bool isString()const{return true;}
  bool isGameFilter()const{return true;}
  static Node* create(string name);
  static bool isQueryable(const string& name, string*message=NULL);
};

