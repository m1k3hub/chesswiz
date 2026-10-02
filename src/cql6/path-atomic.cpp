#include "pathnode.h"
Bindings PathNode::createAtomicBindings(){
  return Atomic::createBindings(atomicVariables);
}

void PathNode::pushAtomicBindings(){
  if(hasAtomics())
    atomicBindingStack.push_back(createAtomicBindings());
}

void PathNode::popAtomicBindings(){
  if(hasAtomics()){
    uassert(atomicBindingStack.size(),"unexpected empty bindings stack lnpb");
    applyAtomicBindings(atomicBindingStack.back());
    atomicBindingStack.pop_back();
  }
}

void PathNode::applyAtomicBindings(const Bindings&bindings){
  if(hasAtomics())
    Atomic::applyBindings(bindings);
}
