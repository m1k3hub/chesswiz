#include "atomic.h"
Bindings Atomic::createBindings(const VarList& vars){
  Bindings ret;
  for(Variable* v:vars)
    ret.push_back(createBinding(v));
  return ret;
}

void Atomic::applyBindings(const Bindings&bs){
  for(const Binding& binding:bs)
    applyBinding(binding);
}

void Atomic::applyBinding(const Binding&b){
  Variable*v=variable_from_binding(b);
  const Any& val=value_from_binding(b);
  assign(v,val);
}

Variable* Atomic::variable_from_binding(const Binding& binding){
  return binding.first;
}

Variable* Atomic::variable_from_binding(Binding& binding){
  return binding.first;
}

const Any& Atomic::value_from_binding(const Binding& binding){
  return binding.second;
}

Any& Atomic::value_from_binding(Binding& binding){
  return binding.second;
}

Any Atomic::value_from_variable(const Variable* v){
  return v->getAny();
}

void Atomic::assign(Variable* v, const Any &a){
  v->assignAny(a);
}


string Atomic::toString(const Binding& b){
  stringstream s;
  s<<'<'<<b.first->name<<'='<<AnyValue::toString(b.second)<<'>';
  return s.str();
}

string Atomic::toString(const Bindings& bs){
  stringstream s;
  for(const Binding& b:bs)
    s<<toString(b)<<' ';
  return s.str();
}
  
bool Atomic::isAtomizable(const Variable*v){
  uassert(v,"unexpected null variable to isAtomizable");
  return v->isAtomizable();
}

Binding Atomic::createBinding(Variable*v){
  uassert(v,"null in acb");
  return std::make_pair(v,v->getAny());
}
