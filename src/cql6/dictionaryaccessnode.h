#pragma once
#include "node.h"
#include "dictionary.h"
#include "stringvariable.h"

class DictionaryAccessNode:public SetBase{
 public:
  DictionaryAccessNode(Dictionary*,Node*key=NULL,Node*value=NULL,Node*body=NULL,Variable*v=NULL);
  Dictionary* theDictionary{NULL};
  vnode children()const override;
  void print()override;
  bool match_position(QPos*)override=0;
  void deepify()override;
  string thisclass()const override=0;
  bool isSet()const override{return false;}
[[nodiscard]]  DictionaryAccessNode* clone()override=0;
  SquareMask getSquares(QPos*)override; //set this to error so children do not have to worry about it.
  /*we keep all the members here just to simplify printing, so just one method need print(). this also lets us consolidate all the children() and deepify() methods*/
  Node* theKey{NULL};
  Node* theValue{NULL};
  Node* theBody{NULL}; //used only by DictionaryIterateNode
  Variable* theVariable{NULL}; //used only DictionaryIterateNode
};

class DictionaryRetrieveNode:public DictionaryAccessNode{
public:
  DictionaryRetrieveNode(Dictionary*dict,Node*key);
  bool match_position(QPos*)override;
  bool match_stringvalue(QPos*,string*)override;
  bool match_positionvalue(QPos*,QPos**)override;
  bool match_count(QPos*,NumValue*)override;
  bool isNumeric()const override;
  bool isPosition()const override;
  bool isString()const override;
  bool isSet()const override;
  SquareMask getSquares(QPos*)override;
[[nodiscard]]  DictionaryRetrieveNode*clone()override;
  string thisclass()const override{return "DictionaryRetrieveNode";}
};

class DictionaryDeleteDictionaryNode:public DictionaryAccessNode{
public:
  DictionaryDeleteDictionaryNode(Dictionary*d);
  bool match_position(QPos*)override;
[[nodiscard]]  DictionaryDeleteDictionaryNode*clone()override;
  string thisclass()const override{return "DictionaryDeleteDictionaryNode";}
  
};

class DictionaryDeleteEntryNode:public DictionaryAccessNode{
public:
  DictionaryDeleteEntryNode(Dictionary*d,Node*key);
  bool match_position(QPos*)override;
  string thisclass()const override{return "DictionaryDeleteEntryNode";}
[[nodiscard]]  DictionaryDeleteEntryNode*clone()override;
};

class DictionaryCountNode:public DictionaryAccessNode{
public:
  DictionaryCountNode(Dictionary*d);
  bool match_position(QPos*)override;
  bool match_count(QPos*,NumValue*)override;
  bool isNumeric()const override{return true;}
  string thisclass()const override{return "DictionaryCountNode";}
[[nodiscard]]  DictionaryCountNode*clone()override;
};

class DictionaryAssignNode:public DictionaryAccessNode{
public:
  DictionaryAssignNode(Dictionary*d,Node*key,Node*value);
  bool match_position(QPos*)override;
  string thisclass()const override{return "DictionaryAssignNode";}
[[nodiscard]]  DictionaryAssignNode*clone()override;
};

class DictionaryIterateNode:public DictionaryAccessNode{
public:
  DictionaryIterateNode(Dictionary*d,Variable*v,Node*body);
  bool match_position(QPos*)override;
  string thisclass()const override{return "DictionaryIterateNode";}
[[nodiscard]]  DictionaryIterateNode*clone()override;
};
