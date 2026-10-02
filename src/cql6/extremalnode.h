#pragma once
#include "node.h"
class ExtremalNode : public Node{
 public:
  ExtremalNode(vector<Node*> args, bool ismax);
  vector<Node*>theNodes;
  bool theIsMax{false};
  string thisclass()const{return "ExtremalNode";}
[[nodiscard]]  ExtremalNode*clone();
  void print();
  bool match_position(QPos*);
  bool match_count(QPos*, NumValue*);
  bool match_stringvalue(QPos*,string*);
  bool isNumeric()const;
  bool isString()const;
  void deepify();
  vnode children()const;
  string name();
  SortValueType sortValueType{SortValueType::None};
};
    
