#include "node.h"
//constructors
SortValue::SortValue(NumValue v, SortDirection dir):
  theSortValueType(SortValueType::Numeric),
  theNumericValue(v),
  theDirection(dir),
  theIsBound(true)
{
  uassert (isMax()||isMin(),"SVSV dir");
}

SortValue::SortValue(string v, SortDirection dir):
  theSortValueType(SortValueType::String),
  theStringValue(v),
  theDirection(dir),
  theIsBound(true)
{ uassert(isMax()||isMin(),"SVSV dir2");
}

SortValue::SortValue(SortValueType st, SortDirection dir):
  theSortValueType(st),
  theDirection(dir),
  theIsBound(false)
{
  uassert(isString()||isNumeric(),"SortValue constructor d st");
  uassert(isMax()||isMin(),"SVSV 3");
}


NumValue SortValue::getNumericValue()const{
  uassert(isNumeric()&&isBound(),"SortValue: bad numeric value");
  return theNumericValue;
}

string SortValue::getStringValue()const{
  uassert(isString()&&isBound(),"SortValue: bad string value");
  return theStringValue;
}
  

//And unbound value is worse than anything
//"greater is better" when ismax is true
//"less is better" when ismax is false
bool operator< (const SortValue& a, const SortValue& b){
  uassert(a.getDirection()==b.getDirection()&&(a.isMax()||a.isMin()),
	  "sortvalue operator< direction");
  uassert(a.getType()==b.getType()
	  && (a.isNumeric()||a.isString()),
	  "SortValue operator< args");
  bool abound=a.isBound();
  bool bbound=b.isBound();
  bool ismin=a.isMin();
  if (abound&&bbound){
    bool compare= false;
    if (a.isNumeric()){
      NumValue anum=a.getNumericValue();
      NumValue bnum=b.getNumericValue();
      compare= ismin? (bnum<anum) : (anum<bnum);
    }
    else if (a.isString()){
      string astring=a.getStringValue();
      string bstring=b.getStringValue();
      compare= ismin? (bstring<astring) : (astring<bstring);
    }
    else
      uassert(false,"operator< type error");
    return compare;
  }//if (abound &&bbound)
  else if (abound && !bbound)
    return false;
  else if (!abound && bbound)
    return true;
  else if (!abound&&!bbound)
    return false;
  uassert(false,"operator< fall through");
  return false;
}      
  
void SortValue::bind(NumValue v){
  uassert(isNumeric(),"SortValue::bind: wrong binding type numeric");
  theNumericValue=v;
  theIsBound=true;
}

void SortValue::bind(string s){
  uassert(isString(),"SortValue::bind: wrong binding type string");
  theStringValue=s;
  theIsBound=true;
}

string SortValue::toString()const{
  if (isUnbound())return "none";
  if (isNumeric())return std::to_string(getNumericValue());
  if (isString())return getStringValue();
  uassert(false,"sortvalue tostring");
  return "";
}
