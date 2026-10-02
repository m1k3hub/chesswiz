#pragma once
#include <map>
#ifdef CQL6_EMBEDDED // scidb: Task 3 §B — Environment object registry
#include "scidb_retain.h"
#endif
#include "lambdavalue.h"
#include "numericvariable.h"
#include "sortvariable.h"
#include "sortvalue.h"
#include "stringvariable.h"
#include "capturetype.h"
#include "dictionary.h"
using std::map;
class Variable;
class NumericVariable;
class SquareVariable;
class PieceIdVariable;
class PositionVariable;
class TransformVariable;
class LambdaVariable;
class Dictionary;
class Environment {
 public:
#ifdef CQL6_EMBEDDED // scidb: search owns heap allocations, including clones
  SCIDB_SEARCH_ALLOCATOR(Environment)
#endif
  vector<Variable*> theVariables;
  vector<SortVariable*>theSortVariables;
  vector<SortDirection>theSortDirections;
  vector<SortVariable*>*getSortVariables();
  vector<Variable*>getPersistentVariables();
  vector<SortVariable*>theQuietSortVariables;
  vector<Variable*>theQuietPersistentVariables;
  vector<Variable*>theAtomicVariables;
  int sortId{0};
  void setQuietSortVariable(SortVariable*);
  void registerAtomicVariable(Variable*);
  bool isQuietSortVariable(SortVariable*)const;
  void setQuietPersistentVariable(Variable*);
  bool isQuietPersistentVariable(Variable*)const;
  void registerSortVariable(SortVariable*nv, SortDirection);
  void registerVariable(Variable*);
  vector<Variable*>getAtomicVariables()const{return theAtomicVariables;}
  SortDirection getSortDirection(SortVariable*);
  Variable* find(string name)const;
  SquareVariable* createSquareVariable(string name);
  PieceIdVariable* createPieceIdVariable(string name);
  PositionVariable* createPositionVariable(string name);
  TransformVariable* createTransformVariable(string name);
  NumericVariable* createNumericVariable(string n);
  StringVariable* createStringVariable(string n);
  LambdaVariable* createLambdaVariable(string name,LambdaValue v);
  Dictionary* createDictionary(string name,bool ispersistent);
  void unbindPieceIds();
  NumericVariable* matchCountVariable();
  void reset();
  void print();
  Variable* createVariable(string name, ValueType vtype, bool ispersistent, string&errormessage);
};
