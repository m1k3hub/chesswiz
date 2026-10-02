#include "node.h"
#include "variable.h"
#include "numericvariable.h"
#include "pieceidvariable.h"
#include "squarevariable.h"
#include "positionvariable.h"
#include "transformvariable.h"
#include "lambdavariable.h"
#include "stringvariable.h"
////////Node based items/////

SquareMask Variable::getSquares(QPos*qpos){
  uassert(false,"Unexpected attempt to getSquares() on a Variable, internal: ",name);
  return SquareMask();
}

Variable* Variable::clone(){return this;}

void Variable::reset(){
  if(bound) unbind();
}

void Variable::unbind(){
  uassert(!isDictionary(),"Internal: unbind Dictionary");
  bound=false;
}

bool Variable::eq(string n)const{
  uassert(!n.empty(),"bad arg to variable eq");
  return name==n;
}

    
  
PositionVariable* Variable::asPosition(){
  if(isPosition()){
    auto v=dynamic_cast<PositionVariable*>(this);
    uassert(v,"pvvasp");
    return v;
  }
  return NULL;
}

const PositionVariable* Variable::asPosition()const{
  if(isPosition()){
    auto v=dynamic_cast<const PositionVariable*>(this);
    uassert(v,"pvvaspc");
    return v;
  }
  return NULL;
}

TransformVariable* Variable::asTransform(){
  if(isTransform()){
    auto v=dynamic_cast<TransformVariable*>(this);
    uassert(v,"tvvasp");
    return v;
  }
  return NULL;
}

const TransformVariable* Variable::asTransform()const{
  if(isTransform()){
    auto v=dynamic_cast<const TransformVariable*>(this);
    uassert(v,"tvvasp");
    return v;
  }
  return NULL;
}

SquareVariable* Variable::asSquare(){
  if (isSquare()){
    auto v=dynamic_cast<SquareVariable*>(this);
    uassert(v,"vassv i2");
    return v;}
  return NULL;
}
const SquareVariable* Variable::asSquare()const{
  if (isSquare()){
    auto v=dynamic_cast<const SquareVariable*>(this);
    uassert(v,"vassv i2");
    return v;}
  return NULL;
}

LambdaVariable* Variable::asLambda(){
  if (isLambda()){
    auto v=dynamic_cast<LambdaVariable*>(this);
    uassert(v,"vassl i2");
    return v;}
  return NULL;
}

const LambdaVariable* Variable::asLambda()const{
  if (isLambda()){
    auto v=dynamic_cast<const LambdaVariable*>(this);
    uassert(v,"vassl i2");
    return v;}
  return NULL;
}

PieceIdVariable* Variable::asPieceId(){
  if (isPieceId()){
    auto v=dynamic_cast<PieceIdVariable*>(this);
    uassert(v,"vasspieceid i2");
    return v;}
  return NULL;
}

const PieceIdVariable* Variable::asPieceId()const {
  if (isPieceId()){
    auto v=dynamic_cast<const PieceIdVariable*>(this);
    uassert(v,"vasspieceid i2");
    return v;}
  return NULL;
}

const NumericVariable* Variable::asNumeric()const {
  if (isNumeric()){
    auto v=dynamic_cast<const NumericVariable*>(this);
    uassert(v,"vassnumeric i2");
    return v;}
  return NULL;
}

NumericVariable* Variable::asNumeric() {
  if (isNumeric()){
    auto v=dynamic_cast<NumericVariable*>(this);
    uassert(v,"vassnumeric i2");
    return v;}
  return NULL;
}

StringVariable* Variable::asString(){
  if(isString()){
    auto v=dynamic_cast<StringVariable*>(this);
    uassert(v,"stringcast asstring");
    return v;}
  return NULL;
}


const StringVariable* Variable::asString()const{
  if(isString()){
    auto v=dynamic_cast<const StringVariable*>(this);
    uassert(v,"stringcast asstring");
    return v;}
  return NULL;
}


void Variable::setPersistent(){
  uassert(!isPersistent(),"setPersistent internal");
  uassert (isUnbound(),"setPersistent: expecting unbound variable here");
  if (isNumeric())
    asNumeric()->bindNumeric(0);
  else if (isString())
    asString()->bindString("");
  else if (isSquare())
    asSquare()->bindMask(SquareMask());
  else if (isDictionary())
	 ;
  else
    uassert(false,"cannot make variable of this type persistent: ",name);
  theIsPersistent=true;
}

/* This utility function simply displays the value of a string, numeric or set variable as a string
   If unbound, <unbound> is returned.
   It is called only in cql_execute when all persistent variables are output*/
string Variable::persistentValueAsString()const{
  uassert(isString()||isNumeric()||isSquare(),"peristentValueAsString: type: ",name);
  uassert(isPersistent(),"persistentValueasString: expected a persistent variable");
  if(isUnbound())
    return "<unbound>";
  stringstream s;
  if (isString())
    s<< '"' << asString()->getValue()<<'"';
  else if (isNumeric())
    s<<asNumeric()->getValue();
  else if (isSquare())
    s<<asSquare()->getMask().listString();
  else
    uassert(false,"pvas fall through");
  return s.str();
}
  
void Variable::assignAny(const Any&a){
  stringstream s;
  s<<"Variable type does not support atomicity: Variable name: "<<name<<" class: "<<thisclass();
  uassert(false,s.str());
}

Any Variable::getAny()const{
  stringstream s;
  s<<"Variable type does not support atomicity 2: Variable name: "<<name<<" class: "<<thisclass();
  uassert(false,s.str());
  return Any(false);
}
  
