#include "anyvalue.h"
#include "node.h"
#include "cqlassert.h"

string AnyValue::stringValue(const Any&a){
  uassert(isString(a),"bad variant value stringvalue");
  return std::get<string>(a);
}

NumValue AnyValue::numValue(const Any&a){
  uassert(isNumValue(a),"bad variant numvalue");
  return std::get<NumValue>(a);
}

SquareMask AnyValue::squareMaskValue(const Any&a){
  uassert(isSquareMask(a),"bad variant squaremask");
  return std::get<SquareMask>(a);
}

QPos* AnyValue::qPosValue(const Any&a){
  uassert(isQPos(a),"bad variant any");
  return std::get<QPos*>(a);
}

bool AnyValue::logicalValue(const Any&a){
  uassert(isLogical(a),"bad variant any");
  return std::get<bool>(a);
}

class tmpAnyValueToString{
public:
  string operator()(const string& s) {return "<string>"+s;}
  string operator() (const NumValue& n){
    stringstream s;
    s<<"<NumValue>"<<n;
    return s.str();
  }
  string operator()(const QPos* qpos){
    stringstream s;
    s<<"<QPos*>"<<qpos;
    return s.str();
  }
  string operator()(SquareMask sm){
    stringstream s;
    s<<"<SquareMask>"<<sm.listString();
    return s.str();
  }
  string operator()(bool v){
    if (v)return "<true>";
    return "<false>";
  }
};
  
string AnyValue::toString(const Any&a){
  return std::visit(tmpAnyValueToString(),a);
}

AnyValue::Any AnyValue::eval(Node*n,QPos*qpos){
  uassert(n,"anyvalue: bad arg to eval;");
  switch(n->valuetype()){
  case ValueType::Logical:{
    return n->match_position(qpos);
  }
  case ValueType::Set:{
    return n->asSet()->getSquares(qpos);
  }
  case ValueType::Number:{
    NumValue tmpnum{0};
    if(n->match_count(qpos,&tmpnum))
      return tmpnum;
    break;
  }
  case ValueType::String:{
    string tmps;
    if(n->match_stringvalue(qpos,&tmps))
      return tmps;
    break;
  }
  case ValueType::Position:{
    QPos*tmpqpos{NULL};
    if(n->match_positionvalue(qpos,&tmpqpos))
      return tmpqpos;
    break;
  }
  default:
    uassert(false,"unknown type in AnyValue::eval");
  }
  return false;
}

bool AnyValue::isUnbound(const Any& a){
  if (std::holds_alternative<bool>(a)){
    uassert(std::get<bool>(a)==false,"Atomic::isUnbound: expected false value");
    return true;
  }
  return false;
}

bool AnyValue::isBound(const Any&a){
  return !isUnbound(a);
}

bool AnyLess(const Any& a, const Any& b){
  if(a.index()<b.index())return true;
  if (a.index()>b.index())return false;
  return a<b;
}
