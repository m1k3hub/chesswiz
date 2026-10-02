#include "node.h"
#include "variable.h"
#include "numericvariable.h"
#include "pieceidvariable.h"
#include "squarevariable.h"
#include "positionvariable.h"
#include "tokens.h"
#include "environment.h"

bool Tokens::isOpAssignmentName(const string& opassign){
  if (opassign.size()!=2|| opassign[1]!='=')return false;
  char op = opassign[0];
  return ArithmeticNode::isOp(op)||op=='|' || op=='&';
}

Node*Tokens::make_op_node(char op, Node*left, Node*right){
  uassert(left&&right,"make_op_node args");
  if (op=='+'&&left->isString()&&right->isString())
    return new ConcatenationNode(left,right);
  if (op=='|' && left->isSet()&&right->isSet())
    return new UnionNode(left->asSet(),right->asSet());
  if (op=='&' && left->isSet()&&right->isSet())
    return new OnNode(left->asSet(),right->asSet());
  if (ArithmeticNode::isOp(op)&&
      left->isNumeric()&&
      right->isNumeric())
    return new ArithmeticNode(op,left,right);
  if(op=='+')
    show_error("Invalid types of operands to '+' operator. Both operands must be numeric or both must be strings");
  if (ArithmeticNode::isOp(op))
    show_error("Invalid types of operands to arithmetic operator. Both sides must be numeric: ",string(1,op));
  if (op=='|'||op=='&')
    show_error("Invalid types of operands to set operator. Both sides must be sets: ",string(1,op));
  uassert(false,"unexpected data types or operands in creation op node from: ",string(1,op));
  return NULL;
}


string Tokens::match_opassignmentname(){ 
  int x=save();
  string name=match_special();
  if (!isOpAssignmentName(name)){
    restore(x);
    return "";
  }
  return name;
}

Node* Tokens::match_assignment(){
  int x=save();
  string errormessage;
  bool ispersistent=false; //persistent specified
  bool ispersistentquiet=false; //quiet persistence
  bool isatomic=false; //atomic specified
  bool issimpleassignment=false; //simple =
  bool isconditional=false; // =?
  bool isopassignment=false; // +=, /= etc.
  string assignmentname=""; //the full assignment, like "/=" or "=" or "=?"
  char op='Z'; //if isopassignment, the first character of assignmentname
  ValueType rhstype=ValueType::None;
  Node*rhs{NULL}; // the righthand side
  Variable*v{NULL}; // the variable on the left;
  if(match_keywords("atomic","piece"))
    show_error("'atomic piece' detected. atomic piece variables are not supported in this version of CQL.");
  if (match_keywords("persistent","atomic")||
      match_keywords("atomic","persistent"))
    show_error("combining 'atomic' and 'persistent' keywords is not currently supported");
  if (match_keywords("persistent","quiet")){
      ispersistent=true;
      ispersistentquiet=true;
  }
  else if (match_keyword("persistent"))
    ispersistent=true;
  else if (match_keyword("atomic"))
    isatomic=true;
  string name=match_id();
  if (name==""){
    restore(x);
    return NULL;
  }
  if (match_special("=")){
    issimpleassignment=true;
    assignmentname="=";
  }
  else if (match_special("=?")){
    isconditional=true;
    assignmentname="=?";
      }
  else {
    assignmentname=match_opassignmentname();
    if (assignmentname.empty()){
      restore(x);
      return NULL;
    }
    isopassignment=true;
    uassert(isOpAssignmentName(assignmentname),"assign internal opname");
    op=assignmentname[0];
  } //else
  uassert(issimpleassignment+isconditional+isopassignment==1,"match_assignment: internal 3");
  //Now we have parsed 'persistent'? id assignmentop
  rhs=match_relop_x();
  if(!rhs)
    show_error("could not parse right side of assignment statement for variable: ", name);

  rhstype=rhs->valuetype();
  
  v=environment->find(name);
  if(!v&&ispersistent){
    v=environment->createVariable(name,rhstype,ispersistent,errormessage);
    if (ispersistentquiet)
      environment->setQuietPersistentVariable(v);
    if (!v)
      show_error(errormessage);
  }
  if (ispersistent&&!v->isPersistent())
    show_error("Assignment specifies persistent variable but variable is already declared not persistent: ",name);
  //Handle the simple and conditional assignment
  Node*rhs_to_assign{rhs};
  if (isopassignment){
    if (!v)
      show_error ("Cannot use operation-assignment when variable does not exist: ",string(name)+" "+assignmentname);
    if (op=='+'&&v->isStringVariable()){
      if (!rhs||!rhs->isString())
	show_error("unable to parse += for string variable as right hand side is not a string: ",name);
      return new ConcatenationNode(v->asStringVariable(),rhs,true);
    }
  rhs_to_assign=make_op_node(op,v,rhs);
  }
  AssignNode*ret =AssignNode::create(name,
			   environment,
			   rhs_to_assign,
			   isconditional,
			   errormessage);
  if(errormessage.size())
    show_error(errormessage);
  if (isatomic){
    Variable*atomicvar=ret->getVariable();
    uassert(atomicvar,"atomic parse error null internal");
    if(!atomicvar->isAtomizable()){
      stringstream s;
      s<<"The type of the variable: "<<atomicvar->name<<" cannot be atomic. Internal class of variable: "<<atomicvar->thisclass();
      show_error(s.str());
    }
    getEnvironment()->registerAtomicVariable(atomicvar);
  }
  return ret;
}
