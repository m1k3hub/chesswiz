#pragma once
#include "node.h"
#include "sortvalue.h"
#include "sortvariable.h"
class Environment;
class SortNode : public Node{
 public:
  string documentation; //user documentation string
  bool isQuiet{false};  //whether to output header information
  Node*theFilter{NULL};    //the actual filter in the body to be sorted
  string getName();     
  SortNode(Environment*environment,string doc, SortDirection dir, bool isquiet, Node*fil);
  bool isNumeric()const override{return theSortValueType==SortValueType::Numeric;}
  bool isString()const override{return theSortValueType==SortValueType::String;}
  bool isMin(){return theDirection==SortDirection::Up;}
  bool isMax(){return theDirection==SortDirection::Down;}
  string thisclass()const override{return "SortNode";}
[[nodiscard]]  SortNode*clone()override;
  bool match_position(QPos*)override;
  bool match_count(QPos*,NumValue*)override;
  bool match_stringvalue(QPos*,string*)override;
  void print()override;
  vnode children()const override;
  void deepify()override;
  bool canModifyCurpos()const override{return true;}
  static string convertName(const string& varname);
  void clear();
  CommentStack* getCommentStack();
  void makeComments();
  Variable* getVariable()const{return theVariable;}
  SortDirection getDirection(){return theDirection;}
 private:
  void handle_new_value(SortValue v,int top);
  static string prefix();
  CommentStack commentStack;
  QGame*qgame{NULL};
  SortVariable * theVariable{NULL};
  int gamenumber{0};
  const SortDirection theDirection{SortDirection::None};
  SortValue commentValue; //best value so far
  SortValueType theSortValueType{SortValueType::None};
  SortValueType getSortValueType(){return theSortValueType;}
  bool match_sortvalue(QPos*qpos, SortValue*sortvalue);
  static bool match_filtersortvalue(Node*node, QPos*qpos, SortValue*sortvalue);
};
bool operator< (const SortNode& lhs, const SortNode& rhs);
