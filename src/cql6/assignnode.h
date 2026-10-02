#pragma once
#include "node.h"
#include "variable.h"
#include "numericvariable.h"
#include "squarevariable.h"
#include "positionvariable.h"
#include "stringvariable.h"
class Environment;
class AssignNode: public Node{ //abstract
 public:
  Environment*environment{NULL};
  virtual bool match_position(QPos*)override=0;
  static AssignNode* create(string name, Environment*e, Node* node, bool isconditional, string&errormessage);
  [[nodiscard]]virtual AssignNode* clone()override=0;
  virtual Variable* getVariable() const=0;
  
};

class AssignNumericNode: public AssignNode{
 public:
  NumericVariable* const variable;
  Node* node; //not const for deepify 
  bool match_position(QPos*) override;
  void print() override;
  vnode children()const override;
  AssignNumericNode(NumericVariable*,Node*);
  string thisclass()const override{return "AssignNumericNode";}
  [[nodiscard]]AssignNumericNode*clone()override;
  void deepify()override{node=node->clone();}
  Variable*getVariable()const override{return variable;}
};

class AssignStringNode: public AssignNode{
 public:
  StringVariable* const variable;
  Node* node; //not const for deepify 
  bool match_position(QPos*)override;
  void print()override;
  vnode children()const override;
  AssignStringNode(StringVariable*,Node*);
  string thisclass()const override{return "AssignStringNode";}
  [[nodiscard]]AssignStringNode*clone()override;
  void deepify()override{node=node->clone();}
  Variable*getVariable()const override{return variable;}
};

class AssignSquareNode: public AssignNode{
 public:
  SquareVariable* const variable;
  SetBase* node; //not const for deepify()
  bool isConditional{false};
  bool match_position(QPos*)override;
  AssignSquareNode(SquareVariable*,SetBase*,bool isconditional);
  void print()override;
  vnode children()const override;
  string thisclass()const override{return "AssignSquareNode";}
  [[nodiscard]]AssignSquareNode*clone() override;
  void deepify()override{node=node->clone();}
  Variable*getVariable()const override{return variable;}
};

class AssignPositionNode: public AssignNode{
 public:
  PositionVariable* const variable;
  Node* node; //not const for deepify 
  bool match_position(QPos*)override;
  void print()override;
  vnode children()const override;
  AssignPositionNode(PositionVariable*,Node*);
  string thisclass()const override{return "AssignPositionNode";}
  [[nodiscard]]AssignPositionNode*clone()override;
  void deepify()override{node=node->clone();}
  Variable*getVariable()const override{return variable;}
};
