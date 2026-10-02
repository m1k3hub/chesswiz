#include "stringvariable.h"


bool StringVariable::match_position(QPos* qpos){
  uassert(false,"Warning: attempt to match position of a filter consisting of a single string variable (which would always match): ", name);
  return false;
}

void StringVariable::bindString(const string &v){
  value=v;
  bound=true;
  uassert (isBound(),"bindString isbound internal");
};


string StringVariable::getValue()const{
  uassert (bound,"unbound string variable has no value: ",name);
  return value;
}

//should really call Variable(string) here
StringVariable::StringVariable(string nm){
  name=nm;
  uassert(name.size(),"nvnv nm");
  reset();
}

bool StringVariable::match_stringvalue(QPos*qpos,string*v){
  uassert(isBound(),"string variable is not bound but attempt to access its value was made: ",name);
  *v=value;
  return true;
}

void StringVariable::reset(){
  value=""; //included only to avoid race conditions. Not really necessary.
  if(isBound())unbind();
}

void StringVariable::assignSortValue(SortValue*sortvaluep)const{
  uassert(sortvaluep&&sortvaluep->isString(),"sv assignsortvalue arg");
  uassert(sortvaluep->isMax()||sortvaluep->isMin(),"sv assign sortvalue dir");
  if (isBound())
    sortvaluep->bind(value);
  else
    sortvaluep->unbind();
}

void StringVariable::bindSortValue(const SortValue & sortvalue){
  if (sortvalue.isUnbound())
    unbind();
  else
    bindString(sortvalue.getStringValue());
}

string& StringVariable::getReference(){
  eassert(isBound(),"attempt to access the string value of unbound variable: ", name);
  return value;
}

void StringVariable::assignAny(const Any&a){
  if(AnyValue::isUnbound(a))
    unbind();
  else if(AnyValue::isString(a))
    bindString(AnyValue::stringValue(a));
  else uassert(false,"string variable aa");
}

Any StringVariable::getAny()const{
  if(isUnbound())
    return Any(false);
  return Any(value);
}
