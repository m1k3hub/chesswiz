#pragma once
#include "abbreviations.h"
#include "numvalue.h"
#include "util.h"
#include "cqlglobals.h"
#include "token.h"
#include "sortvalue.h"
#include "markt.h"
#include "qmarkboard.h"
#include "squaremask.h"
#include "clonevec.h"
#include "gamesortinfo.h"
#include "cql.h"
#include "qgame.h"

class CqlNode;
class Environment;
class GameFilter;
class HolderConstituent;
class PathCon;
class MoveFutureNode;
class Node;
class NumericVariable;
class OrbitNode;
class PieceLoc;
class Range;
class RepeatConstituent;
class SeqConstituent;
class SetBase;
class SortValue;
class SortVariable;
class SquareVariable;
class StringVariable;
class StarConstituent;
class PieceIdVariable;
class Dictionary;
class Tokens;
class Transform;
class Variable;


typedef vector<Node*> vnode;
#define CVV(name) string thisclass()const{return #name;} [[nodiscard]]name* clone() 

enum class ValueType{None,Set,Number,String,Position,Logical};

class Node { //abstract
 public:
#ifdef CQL6_EMBEDDED // scidb: search owns heap allocations, including clones
  SCIDB_SEARCH_ALLOCATOR(Node)
  virtual ~Node() = default;
#endif
  bool annotateFlag{false};
  bool removedParens{false}; //Invalid if this is Variable*
  virtual void print();
  virtual string thisclass()const=0;
  virtual vnode children()const=0;
  vnode descendants();
  void alldescendants(vnode*);
  virtual bool transformless(const Node* other)const;
  virtual bool transformmemberless(const Node* other) const;
  virtual void deepify()=0; //called by clone() after copying argument
  void cloneverify(Node*source,Node*target);
  [[nodiscard]]virtual Node* clone()=0;
  virtual void transform_members(Transform*){}
  virtual void transform_in_place(Transform*);
  virtual void computeOrbit(); //see computeorbit.cpp
  void makeSilentRecursively();
  void makeNotNodeSilentRecursively();
  virtual Node* transform(Transform*t);
  virtual bool hasEmptySquareMask()const;
  virtual bool isGameFilter()const{return false;}
  virtual bool match_game(QGame*);
  virtual bool isSet() const{return false;}
  virtual SetBase* asSet(){return NULL;}
  virtual bool isNumeric() const{return false;}
  virtual bool isSortable(){return isNumeric()||isString();}
  virtual SortVariable* asSortVariable(){return NULL;}
  virtual bool isPosition()const {return false;}
  virtual bool isFromNode()const{return false;}
  virtual bool isToNode()const{return false;}
  virtual bool isFromToNode()const{return false;}
  virtual bool isSequence() {return false;}
  virtual bool isPathNode()const{return false;}
  virtual bool isPathCon()const{return false;}
  virtual bool isDathCon()const{return false;}
  virtual bool isDashNode()const{return false;}
  virtual bool isFromToOwner()const{return false;}
  virtual bool isWithPositionNode()const{return false;}
  virtual bool isCaptureNode()const{return false;}
  virtual bool canModifyCurpos()const{return false;}
  virtual PathCon* asPathCon(){return NULL;}
  virtual PathNode* asPathNode(){return NULL;}
  virtual bool isString()const{return false;}
  virtual bool isDictionary()const{return false;}
  virtual bool match_count(QPos*, NumValue*value); //should never be invoked
  virtual bool match_position(QPos*)=0; //should never be invoked
  virtual bool match_positionvalue(QPos*, QPos**value); //should never be invoked
  virtual bool match_stringvalue(QPos*, string*);
  virtual Variable* asVariable(){return NULL;} //cannot be const for obscure reasons
  virtual StringVariable* asStringVariable(){return NULL;}
  virtual Dictionary* asDictionary();
  virtual const Dictionary* asDictionary()const;
  vector<MoveFutureNode*>*linearize();
  virtual PieceIdVariable* asPieceIdVariable(){return NULL;}
  virtual bool isVariable()const{return false;}
  virtual bool isStringVariable()const{return false;}
  virtual bool isPieceIdVariable()const{return false;}
  static GameFilter* createVirtualPlayerNode(string name);
  static bool valuetypeIsPersistent(ValueType);
  static string valuetypeToString(ValueType);
  static bool valuetypeIsAssignable(ValueType);
  virtual ValueType valuetype()const;

 protected:
  vector<MoveFutureNode*> cachedLinearize;
  bool cachedLinearizeValid{false};
};
  
class NeverMatch: public Node{
 public:
  bool match_position(QPos*){uassert(false,"Internal error: match_position() invoked");return false;}
};

class SetBase: public Node{ //abstract
 public:
  virtual bool match_position(QPos*);
[[nodiscard]]  virtual SetBase* clone()=0;
  virtual SquareMask getSquares(QPos*)=0;
  virtual bool isSet()const{return true;} //this can be false in a subclass though.
  virtual SetBase* asSet();
  static SquareMask virtualGetSquares(QPos*qpos,SetBase*s){
    if(s)return s->getSquares(qpos);else return SquareMask::all();
  }
};


class GameFilter:public Node{ //abstract
 public:
  virtual bool match_game(QGame*qgame)=0;
  bool match_position(QPos*);
[[nodiscard]]  virtual GameFilter*clone()=0;
  virtual bool isGameFilter()const{return true;}
  void deepify(){}
};



////////Simple keyword specs with no arguments, base class is KeywordNode

class KeywordNode: public NeverMatch{
 public:
  const string value;
  KeywordNode(string v);
  string thisclass()const{return "KeywordNode";}
  void print();
  bool eq(string);
  void deepify(){}
  vnode children()const{return vnode{};}
};

class SilentFeatureNode: public KeywordNode{
 public:
  CVV(SilentFeatureNode);
 SilentFeatureNode(): KeywordNode("silent"){};
};

class VariationsNode: public KeywordNode{
 public:
  CVV(VariationsNode);
 VariationsNode(): KeywordNode("variations"){}
};


class AnyNode:public SetBase{
 public:
  SquareMask getSquares(QPos*){return SquareMask::all();}
  bool match_position(QPos*){return true;}
  vnode children()const{return vnode{};}
  CVV(AnyNode);
  void deepify(){}
};


class SimpleNode:public Node { //no arg keywords corresponding to a filter, abstract
 public:
[[nodiscard]]  virtual SimpleNode*clone()=0;
  vnode children()const{return vnode{};}
  void deepify(){}
};

class CheckNode:public SimpleNode{
  CVV(CheckNode);
  bool match_position(QPos*);
};

class StalemateNode:public SimpleNode{
  CVV(StalemateNode);
  bool match_position(QPos*);
};

class MateNode:public SimpleNode{
  CVV(MateNode);
  bool match_position(QPos*);
};



class InitialNode:public SimpleNode{
  CVV(InitialNode);
  bool match_position(QPos*);
};

class InVariationNode:public SimpleNode{
 public:
  CVV(InVariationNode);
  bool match_position(QPos*);
};

class InMainlineNode:public SimpleNode{
 public:
  CVV(InMainlineNode);
  bool match_position(QPos*);
};



class TerminalNode:public SimpleNode{
  CVV(TerminalNode);
  bool match_position(QPos*);
};


class RangeNode: public Node{
 public:
  Range*const range;
  Node* numeric{NULL};
  CVV(RangeNode);
  bool match_position(QPos*);
  bool match_count(QPos*,NumValue*);
  RangeNode(Range*,Node*);
  void print();
  vnode children()const;
  void deepify(){numeric=numeric->clone();};
  bool isNumeric()const{return true;}
};

class MatchCountNode: public NeverMatch{
 public:
  Range*range{NULL};
  MatchCountNode(Range*,bool);
  bool sort{false};
  void print();
  vnode children()const{return vnode{};}
  CVV(MatchCountNode);
  void deepify(){}
};

class PgnNode: public NeverMatch{
 public:
 PgnNode(string v):value(v){}
  string value;
  CVV(PgnNode);
  void print();
  vnode children()const{return vnode{};}
  void deepify(){}
};

class OutputNode: public NeverMatch{
 public:
 OutputNode(string v):value(v){}
  const string value;
  CVV(OutputNode);
  void print();
  vnode children()const{return vnode{};}
  void deepify(){}
};

class ResultNode: public GameFilter{
 public:
  ResultNode(string);
  resultT result{RESULT_None};
  bool transformmemberless(const Node*)const;
  void transform_members(Transform*t);
  CVV(ResultNode);
  void print();
  bool match_game(QGame*qgame);
  vnode children()const{return vnode{};}
};


class EloNode: public GameFilter{
 public:
  Range*range{NULL};
  colorT color {NOCOLOR};
  vnode children()const{return vnode{};}
  bool match_game(QGame*qgame);
  bool match_count(QPos*qpos, NumValue*value);
  void print();
  CVV(EloNode);
  EloNode(Range*range,colorT);
  void transform_members(Transform*);
  bool isNumeric()const{return true;}
  bool transformmemberless(const Node*)const;

};

  
class YearNode: public GameFilter{
 public:
  Range*range{NULL};
  vnode children()const{return vnode{};}
  bool match_game(QGame*qgame);
  bool match_count(QPos*qpos, NumValue*value);
  void print();
  CVV(YearNode);
  YearNode(Range*range);
  bool isNumeric()const{return true;}
};

class GameNumberNode: public GameFilter{
 public:
  Range * range;
  CVV(GameNumberNode);
  GameNumberNode(Range* r);
  vnode children()const{return vnode{};};
  bool match_game(QGame*qgame);
  bool match_count(QPos*qpos, NumValue*value);
  void print();
  bool isNumeric()const{return true;}
};

class CountSquaresNode:public Node{
 public:
  SetBase* set;
  CVV(CountSquaresNode);
  bool match_count(QPos*qpos, NumValue* value);
  void print();
  CountSquaresNode(SetBase* s);
  vnode children()const {return vnode{set};}
  virtual bool match_position(QPos*){return true;}
  bool isNumeric()const{return true;}
  void deepify(){set=set->clone();}
};





class SquareCoordinateNode: public Node{
 public:
  SetBase* theSquare;
  bool isRank{false};
  SquareCoordinateNode(SetBase*square, bool isrank);
  CVV(SquareCoordinateNode);
  vnode children()const;
  void print();
  void deepify(){theSquare=theSquare->clone();}
  bool match_position(QPos*);
  bool match_count(QPos*, NumValue*value);
  bool isNumeric()const{return true;}
};





  
class MoveNumberNode: public Node{
 public:
  CVV(MoveNumberNode);
  MoveNumberNode(){}
  vnode children()const{return vnode{};}
  bool match_position(QPos*){return true;}
  bool match_count(QPos*qpos, NumValue*n);
  void print();
  bool isNumeric()const{return true;}
  void deepify(){}
};

class BetweenNode: public SetBase {
 public:
  SetBase* source{NULL};
  SetBase* target{NULL};
  void print();
  //  bool match_square(squareT square, QPos*qpos);
  SquareMask getSquares(QPos*qpos);
  CVV(BetweenNode);
  void deepify(){source=source->clone();target=target->clone();}
  vnode children()const{return vnode{source,target};}
  BetweenNode(SetBase*s,SetBase*t);
};

class ExtensionNode:public Node{
 public:
  CVV(ExtensionNode);
  bool match_position(QPos*qpos);
  vnode children()const{return vnode{};}
  void print();
  ExtensionNode(){};
  void deepify(){}
};

class PowerNode: public Node{
 public:
  SetBase* set;
  void print();
  bool match_count(QPos*qpos, NumValue*value);
  CVV(PowerNode);
  void deepify(){set=set->clone();}
  vnode children()const{return vnode{set};}
  PowerNode(SetBase*s);
  bool match_position(QPos*qpos){return true;}
  static int pieceValue(pieceT p);
  bool isNumeric()const{return true;}
};

class NumberNode: public Node{
 public:
  NumberNode(NumValue);
  const NumValue value{0};
  CVV(NumberNode);
  void print();
  bool match_count(QPos*,NumValue*);
  vnode children()const{return vnode{};}
  bool match_position(QPos*);
  bool isNumeric()const{return true;}
  void deepify(){}
  string toString();
  bool isGameFilter()const{return true;}
};
  
class VariableFilter {
 public:
  virtual string thisclass()const=0;
  virtual string toString()=0;
};


  
#include "transform.h"

#include "cqlnode.h"
#include "movelegalnode.h"
#undef CVV
