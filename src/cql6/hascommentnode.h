#pragma once
#include "node.h"
/* The class now only searches for NAGs and should be renamed */

class HasCommentNode: public Node{
 public:
  int nag{-1};
  bool nagValid{false};
  HasCommentNode(int nag);
  HasCommentNode();
  string thisclass()const{return "HasCommentNode";}
[[nodiscard]]  HasCommentNode* clone();
  void print();
  vnode children()const{return vnode{};}
  bool match_position(QPos*qpos);
  bool match_stringvalue(QPos*qpos,string*stringp);
  bool isString()const{return !nagValid;}
  void deepify(){}
  static int nag_from_string(const string& v);
};
