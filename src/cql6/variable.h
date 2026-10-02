#pragma once
#include "node.h"
#include "lambdavalue.h"
#include "anyvalue.h"
class SquareVariable;
class PieceIdVariable;
class NumericVariable;
class LambdaVariable;
class PositionVariable;
class TransformVariable;
class SortVariable;
class StringVariable;
class Dictionary;

/* Variable inherits from SetBase so that the subclasses of variables that are Set (piecevariable and setvariable) do not have to use multiple inheritance. Be cautious about overriding default SetBase implementations in subclasses!*/

class Variable: public SetBase{
 private:
  static void registerVariable(Variable*);
 public:
  //methods
  static vector<Variable*>*getVariables();
  virtual SquareMask getSquares(QPos*qpos) override;
  virtual bool isSet()const override{return false;}
[[nodiscard]]  Variable* clone()override;
  string name;
  bool theIsPersistent{false};
  bool isPersistent()const{return theIsPersistent;};
  void setPersistent();
  bool eq (string name)const;
  bool bound{false};
  virtual bool isSquare()const {return false;}
  virtual bool isPieceId()const {return false;}
  virtual bool isNumeric() const override{return false;}
  virtual bool isPosition() const override{return false;}
  virtual bool isSort() const{return false;}
  virtual bool isLambda() const{return false;}
  virtual bool isTransform() const{return false;}
  virtual bool isAtomizable()const{return false;}
  virtual PieceIdVariable*  asPieceId();
  virtual NumericVariable*  asNumeric();
  virtual LambdaVariable* asLambda();
  virtual PositionVariable* asPosition();
  virtual TransformVariable* asTransform();
  virtual StringVariable* asString();
  virtual SquareVariable* asSquare();

  virtual const PieceIdVariable*  asPieceId()const;
  virtual const NumericVariable*  asNumeric()const;
  virtual const LambdaVariable* asLambda()const;
  virtual const PositionVariable* asPosition()const;
  virtual const TransformVariable* asTransform()const;
  virtual const StringVariable* asString()const;
  virtual const SquareVariable* asSquare()const;

  string persistentValueAsString()const;
  bool isBound() const{return bound;}
  bool isUnbound()const {return !isBound();}
  bool isVariable()const override{return true;}
  Variable*asVariable()override{return this;}
  virtual void print()override;
  virtual string toString()=0;
  virtual string thisclass()const override=0;
  void unbind();
  vnode children()const override{return vnode{};}
  void registerSortVariable();
  void deepify()override{}
  virtual void reset();
  /*anyvalue stuff*/
  virtual void  assignAny(const Any& a);
  virtual Any getAny()const;
};

  

