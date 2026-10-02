#pragma once
#include <variant>
#include <string>
#include "squaremask.h"
#include "numvalue.h"
class QPos;
class Node;
class AnyValue{
 public:
  typedef std::variant<
    bool,
    string,
    NumValue,
    SquareMask,
    QPos*>Any;
  static bool isString(const Any&a){return std::holds_alternative<string>(a);}
  static bool isNumValue(const Any&a){return std::holds_alternative<NumValue>(a);}
  static bool isSquareMask(const Any&a){return std::holds_alternative<SquareMask>(a);}
  static bool isQPos(const Any&a){return std::holds_alternative<QPos*>(a);}
  static bool isLogical(const Any&a){return std::holds_alternative<bool>(a);}
  static bool isFalse(const Any&a){return isLogical(a)&&!std::get<bool>(a);}
  static string stringValue(const Any&);
  static NumValue numValue(const Any&);
  static SquareMask squareMaskValue(const Any&);
  static QPos* qPosValue(const Any&);
  static bool logicalValue(const Any&);
  static string toString(const Any&);
  static void clear(Any&a){a=false;}
  static Any eval(Node*node,QPos*);
  static bool isUnbound(const Any&); //has a value false or a real value
  static bool isBound(const Any&); //has a real value
};
typedef AnyValue::Any Any;


