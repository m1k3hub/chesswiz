#pragma once
#include "node.h"
#include "variable.h"
#include "pieceidvariable.h"
#include "dictionary.h"

class StringConverter:public Node{
 public:
  vector<Node*>theNodes;
  StringConverter(vector<Node*>);
  StringConverter(Node*);
  string thisclass()const override{return "StringConverter";}
  bool match_position(QPos*qpos)override;
  bool match_stringvalue(QPos*qpos, string*stringp)override;
  bool isString()const override{return true;}
[[nodiscard]]  StringConverter* clone()override;
  void print()override;
  vnode children()const override;
  void deepify() override;
  string convert(QPos*);
  
private:
  void convertnode(Node*,QPos*,stringstream&);
  static bool convertUnboundVariable(Node*,QPos*,stringstream&);
  static bool convertString(Node*, QPos*,stringstream&);
  static bool convertNumeric(Node*,QPos*,stringstream&);
  static bool convertPieceIdVariable(Node*,QPos*,stringstream&);
  static bool convertSet(Node*, QPos*,stringstream&);
  static bool convertPosition(Node*, QPos*,stringstream&);
  static bool convertLogical(Node*, QPos*,stringstream&);
  static bool convertDictionary(Node*, QPos*,stringstream&);
};
