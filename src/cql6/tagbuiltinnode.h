#pragma once
#include "node.h"
class TagBuiltInNode : public Node{
 public:
  TagBuiltInNode(const string& name);
  string theName;
  bool match_position(QPos*qpos);
  bool match_stringvalue(QPos*,string*);
  bool isString()const{return true;}
  string getName()const{return theName;}
  vnode children()const{return vnode{};}
  void deepify();
  void transform_members(Transform*);
  bool transformmemberless(const Node*)const;
  static bool isBuiltInTag(const string& name);
  string thisclass()const{return "TagBuiltInNode";}
[[nodiscard]]  TagBuiltInNode*clone();
  void print();
  bool match_game(QGame*qgame);
  bool isGameFilter()const{return true;}
  static vector<string>builtInTags;
  bool match_stringvalue_game(QGame*qgame, string*stringp);
};
  
