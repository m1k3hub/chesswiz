#include "sequencebase.h"

/* This constituent holds a pair of a repeat constituent and an int indicating how
many repetitions have been seeing on the stack so far. The reason this is not a member in
a RepeatConstituent is that the same RepeatConstituent might be pushed on the stack multiple times, for
example as in
       check{1,3} +
and each of these instances might have seen different numbers of constituents so far. 

A RepeatInProcessConstituent is only intended to be stack allocated by SequenceBase::compute(RepeatInProcessConstituent*,QPos*) and that address pushed on the stack of constitutents. It is only allocated at run time, and all the usual
CQL-compile time methods, like deepify(), children() and clone() signal an error. 
*/

RepeatInProcessConstituent::RepeatInProcessConstituent(RepeatConstituent*r):
  theRepeatConstituent(r){
  uassert(theRepeatConstituent,"ripc arg");
  eassert(!theRepeatConstituent->constituent->matchesNull(),
	  "Attempt to create repetition regex when the filter being repeated can match an empty sequence of moves");
  uassert (min()>=0&&max()>=0&&min()<=max(),"Invalid ranges in constructing RepeatInProcessConstituent");
}
int RepeatInProcessConstituent::min(){
  return theRepeatConstituent->min;
}

RepeatInProcessConstituent*RepeatInProcessConstituent::clone(){
  uassert(false,"ripc clone");
  return NULL;
}


SeqConstituent*RepeatInProcessConstituent::getConstituent(){
  return theRepeatConstituent->constituent;
}

int RepeatInProcessConstituent::max(){
  return theRepeatConstituent->max;
}

bool RepeatInProcessConstituent::matchesNull(){
  return nSeen<=max() &&
    nSeen>=min();
}
void RepeatInProcessConstituent::deepify(){
  uassert(false,"ripc deepify");
}

vnode RepeatInProcessConstituent::children()const{
  uassert(false,"ripc children");
  return vnode{};
}
  
