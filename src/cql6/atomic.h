#include "variable.h"
#include "anyvalue.h"
typedef std::pair<Variable*,Any> Binding;
typedef vector<Binding> Bindings;
typedef vector<Variable*> VarList;
class Atomic{
public:
  static Bindings createBindings(const VarList& vars);
  static void applyBindings(const Bindings&);
  static Binding createBinding(Variable*);
  static void applyBinding(const Binding&);
  static Variable* variable_from_binding(const Binding&);
  static const Any& value_from_binding(const Binding&);
  static Variable* variable_from_binding(Binding&);
  static Any& value_from_binding(Binding&);
  static Any value_from_variable(const Variable*);
  static void assign(Variable*,const Any&);
  static bool isUnbound(const Any&);
  static bool isBound(const Any&);
  static string toString(const Binding&);
  static string toString(const Bindings&);
  static bool isAtomizable(const Variable*);
};
// add virtual void Variable::assignAny(const Any&){error}
// add virtual AnyValue Variable::getAny()const=0{error}

    
    
