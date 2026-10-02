#include "cqlassert.h"
#include "focustype.h"
string focustype_to_string(FocusType f){
  switch(f){
  case FocusType::Unspecified: return "Unspecified";
  case FocusType::None: return "None";
  case FocusType::Normal: return "Normal";
  case FocusType::Capture: return "Capture";
  };
  uassert(false,"bad focus type");
  return "";
}
