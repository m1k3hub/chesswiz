#pragma once
#include "node.h"

class RelationalNode : public Node{
 public:
  const string name;
  Node* left{NULL};
  Node* right{NULL};
  static const vector<string>* allNames();
  static const vector<string>* positionComparisonNames();
  RelationalNode(string name, Node* l, Node* r);
  bool match_position(QPos*)override;
  bool match_count(QPos*,NumValue*)override;
  bool match_stringvalue(QPos*,string*)override;
  bool match_positionvalue(QPos*,QPos**)override;
  void print()override;
  string thisclass()const override{return "RelationalNode";}
[[nodiscard]]  RelationalNode*clone()override;
  bool compare(NumValue l, NumValue r);
  bool compare(const string&l, const string&r);
  bool compare(QPos*v1,QPos*v2);
  vnode children()const override;
  void deepify()override;
  bool isNumeric()const override;
  bool isString()const override;
  bool isPosition()const override;
 private:
  static vector<string>* theAllNames;
  static vector<string>* thePositionComparisonNames;
  bool positionArgs{false};
};

