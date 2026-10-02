#include "numericiteratornode.h"
NumericIteratorNode::NumericIteratorNode
(NumericVariable*v,
 Node* lb,
 Node*ub,
 Node*body):
  theVariable(v),
  lowerBound(lb),
  upperBound(ub),
  theBody(body){
  uassert(theVariable &&lowerBound && upperBound &&theBody
	  &&lowerBound->isNumeric()
	  &&upperBound->isNumeric(),"nin args");
}
bool NumericIteratorNode::match_position(QPos*qpos){
  int x=qpos->markComments();
  if (theVariable->isBound()){
    stringstream s;
    string name=theVariable->name;
    s<<"when attempting to evaluate a numeric iterator of the form\n"
     <<"    int "<<name<< " in [...]...\n"
     <<" the variable "<<name<<" is already bound. This might indicate user error, since the previous value of "<<name<< " would be overwritten";
    eassert(false,s.str());
  }
  NumValue lower{0};
  NumValue upper{0};
  if(!lowerBound->match_count(qpos,&lower)||
     !upperBound->match_count(qpos,&upper)){
    qpos->restoreComments(x);
    return false;
  }
  for(NumValue i=lower;i<upper;++i){
    theVariable->bindNumeric(i);
    theBody->match_position(qpos);
  }
  theVariable->unbind();
  return true;
}
vnode NumericIteratorNode::children()const{
  vnode ret{theVariable};
  myinsert(ret,lowerBound);
  myinsert(ret,upperBound);
  myinsert(ret,theBody);
  return ret;
}

void NumericIteratorNode::deepify(){
  lowerBound=lowerBound->clone();
  upperBound=upperBound->clone();
  theBody=theBody->clone();
}
     
     
  
	  
					 
