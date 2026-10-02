#include "numericvariable.h"


/* added to fix bug CQLI9.186-6*/
bool NumericVariable::match_position(QPos* qpos){
  eassert(false,"Warning: attempt to match position of a filter consisting of a single numeric variable (which would always match): ", name);
  return false;
}

void NumericVariable::bindNumeric(NumValue v){
  value=v;
  bound=true;
  uassert (isBound(),"bindNumeric isbound internal");
};


NumValue NumericVariable::getValue()const{
  uassert (bound,"unbound numeric variable has no value: ",name);
  return value;
}

//should really call Variable(string) here
NumericVariable::NumericVariable(string nm){
  name=nm;
  uassert(name.size(),"nvnv nm");
  reset();
}

void NumericVariable::increment(){
  bindNumeric(getValue()+1);
}

bool NumericVariable::match_count(QPos*qpos,NumValue*v){
  eassert(isBound(),"Numeric variable is not bound but attempt to access its value was made: ",name);
  *v=value;
  return true;
}


void NumericVariable::reset(){
  value=999999; //included only to avoid race conditions. Not really necessary.
  if(isBound())unbind();
}

void NumericVariable::assignSortValue(SortValue*sortvaluep)const{
  uassert(sortvaluep&&sortvaluep->isNumeric(),"nv assignsortvalue arg");
  uassert(sortvaluep->isMax()||sortvaluep->isMin(),"nv assign sortvalue dir");
  if (isBound())
    sortvaluep->bind(value);
  else
    sortvaluep->unbind();
}

void NumericVariable::bindSortValue(const SortValue & sortvalue){
  if (sortvalue.isUnbound())
    unbind();
  else
    bindNumeric(sortvalue.getNumericValue());
}

void NumericVariable::assignAny(const Any&a){
  if(AnyValue::isUnbound(a))
    unbind();
  else if(AnyValue::isNumValue(a))
    bindNumeric(AnyValue::numValue(a));
  else uassert(false,"NV aa");
}

Any NumericVariable::getAny()const{
  if(isUnbound())
    return Any(false);
  return Any(value);
}
