#include "arithmeticnode.h"
#include <cstring> //bug report by Lionel 4/9/2023. Necessary for gcc to parse std::strchr
const string ArithmeticNode::Ops="+-*/%";

bool ArithmeticNode::isOp(char c){
  return std::strchr(Ops.c_str(),c)!=NULL;
}

bool ArithmeticNode::isOp(const string& name){
  return name.size()==1 && isOp(name[0]);
}

ArithmeticNode::ArithmeticNode(char n,
			       Node* l,
			       Node* r):namec(n),
					     left(l),
					     right(r)
{
  uassert(left && right && left->isNumeric() && right->isNumeric(),
	  "ArithmeticNode: bad arguments: constructor");
  uassert(isOp(namec),"ArithmeticNode: bad operand: ",string(1,namec));
  if (left==right)
    uassert(dynamic_cast<Variable*>(left),"ArithmeticNode: args: unexpected equal arguments");
}

bool ArithmeticNode::match_position(QPos*qpos){
  return match_count(qpos,NULL);
}

bool ArithmeticNode::match_count(QPos*qpos,NumValue*val){
  NumValue val1{-1000};
  NumValue val2{-1000};
  if (left->match_count(qpos,&val1)&&
      right->match_count(qpos,&val2)){
    if (val2==0&&(namec=='/' || namec=='%'))return false;
    if (val) *val=operate(val1,val2);
    return true;
  }
  return false;
}

NumValue ArithmeticNode::operate(NumValue v1, NumValue v2){
  switch(namec){
  case '+': return v1+v2;
  case '-': return v1-v2;
  case '*': return v1*v2;
  case '/':
    eassert(v2!=0,
	    "Unexpected attempt to divide by 0 in ArithmeticNode::operate");
    return v1/v2;
  case '%':
    eassert(v2!=0,"Unexpected attempt to take modulos of 0 in ArithmeticNode::operate");
    return v1%v2;
  default:
    uassert(false,"rnoperate: bad name: ", string(1,namec));
  }
  return false;
}

vnode ArithmeticNode::children()const{
  Node*lnode=dynamic_cast<Node*>(left);
  Node*rnode=dynamic_cast<Node*>(right);
  uassert(lnode&&rnode, "RN children error");
  if (lnode==rnode)
    return vnode{lnode};
  return vnode{lnode,rnode};
}


  
  
  
      
  
