/* file to be included in pathnode.h
   contains members relating to atomic variables
*/
vector<Variable*> atomicVariables;
vector<Variable*>&getAtomicVariables(){return atomicVariables;}
Bindings bestAtomicBindings;
vector<Bindings> atomicBindingStack;
bool hasAtomics()const{return atomicVariables.size();}
Bindings createAtomicBindings();
void pushAtomicBindings();
void popAtomicBindings(); 
void applyAtomicBindings(const Bindings&);


