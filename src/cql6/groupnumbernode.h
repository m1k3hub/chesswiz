#pragma once
#include "node.h"
class GroupNumberNode : public Node{
 public:
  GroupNumberNode(int group,const string&location, bool computeindex); 
  int theGroup{0};
  string theLocation;
  bool computeIndex{false};
  string thisclass()const{return "GroupNumberNode";}
[[nodiscard]]  GroupNumberNode* clone();
  void print();
  bool match_position(QPos*qpos);
  bool match_stringvalue(QPos*qpos,string*stringp);
  bool match_count(QPos*qpos,NumValue*valp);
  vnode children()const{return vnode{};}
  bool isString()const{return !computeIndex;}
  bool isNumeric()const{return computeIndex;}
  void deepify(){};
  bool isGameFilter()const{return true;}
  void makeComputeIndex();
private:
  bool match_groupindex(QPos*,NumValue*);
};

