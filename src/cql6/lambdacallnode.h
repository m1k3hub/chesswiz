#pragma once
#include "node.h"
#include "lambdavalue.h"
#include "assignnode.h"
class Environment;
class LambdaCallNode: public SetBase{
 public:
  string name;
  Environment*environment{NULL};
  vector<AssignNode*>assignments;
  Node* bodynode{NULL};
  LambdaValue lambda;
  LambdaCallNode(string n,Environment*e,vector<Node*>args,LambdaValue lambda);
  string thisclass()const{return "LambdaCallNode";}
[[nodiscard]]  LambdaCallNode* clone();
  bool match_position(QPos*qpos);
  static vector<Token*> replacebody(vector<Token*>body, string newname, string oldname);
  SquareMask getSquares(QPos*);
  bool match_count(QPos*,NumValue*v);
  bool match_positionvalue(QPos*,QPos**);
  bool match_stringvalue(QPos*,string*);
  bool isSet()const;
  bool isNumeric()const;
  bool isPosition()const;
  bool isString()const;
  
  void print();
  vnode children()const;
  void deepify();
};
