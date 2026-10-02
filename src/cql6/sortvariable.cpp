#include "sortvariable.h"
#include "numericvariable.h"
bool  SortVariable::getSquare(squareT*s){
  uassert(false,"Attempt to treat a string or numeric variable as if it had a set value. This might indicate an internal error or a bad error message; please forward error message to support. Name of variable: ",name);
  return false;
}

string SortVariable::getStringValue()const{
  uassert(false,"SortVariable: attempt to extract string from non-string variable");
  return "";
}

NumValue SortVariable::getNumericValue()const{
  uassert(false, "SortVariable: attempt to extract number from non-numeric variable");
  return 0;
}


bool SortVariable::match_position(QPos*qpos){
  uassert(false, "Attempt to match a position on a variable, which is usually an error. Name: ",name);
  return false;
}
