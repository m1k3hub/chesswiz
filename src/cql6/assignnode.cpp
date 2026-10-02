#include "node.h"
#include "environment.h"
#include "numericvariable.h"
#include "squarevariable.h"
#include "positionvariable.h"
#include "stringvariable.h"
#include "assignnode.h"
					 
AssignNode* AssignNode::create(string name,
			       Environment*environment,
			       Node* node,
			       bool isconditional,
			       string& errormessage){
  errormessage="";
  stringstream s; //for error messages before conversion to errormessage
  uassert(name.size()&&node&&environment,"assignnode create bad args");
  ValueType nodetype=node->valuetype();
  bool isset= node->isSet();
  Variable* var=environment->find(name);
  ValueType variabletype=ValueType::None;
  uassert(!(isconditional&&!isset),"AssignNode::create: unexpected conditional assignment of non-set");
  if (!Node::valuetypeIsAssignable(nodetype)){
    s<<"Assignment to variable: "<<name<<" failed as right hand side is neither a set filter nor a numeric filter nor a position filter nor a string filter";
    goto fail;
  }
  if (!var)
    var=environment->createVariable(name,nodetype,false,errormessage);
  uassert(var,"unexpectedly could not create variable: ", name);
  variabletype=var->valuetype();
  if (var->isPieceId()){
    s<<"cannot assign to piece variable "+name;
    goto fail;
  }
  if (variabletype!=nodetype){
    s<<" Type mismatch on assignment. The variable "
     <<name
     <<" is of type "
     <<Node::valuetypeToString(variabletype)
     <<" but the right hand side of the assignment is of type: "
     <<Node::valuetypeToString(nodetype);
    goto fail;
  }
  switch(nodetype){
  case ValueType::Set:
    return new AssignSquareNode(var->asSquare(),node->asSet(),isconditional);
  case ValueType::Number:
    return new AssignNumericNode(var->asNumeric(),node);
  case ValueType::String:
    return new AssignStringNode(var->asString(),node);
  case ValueType::Position:
    return new AssignPositionNode(var->asPosition(),node);
  default:
    uassert(false,"bad nodetype in switch in AssignNode::create");
    return NULL;
  }//switch
 fail:
  errormessage=s.str();
  return NULL;
}
    
    
AssignNumericNode::AssignNumericNode(NumericVariable * var, Node * filter):variable(var),node(filter){
  uassert(variable,"AssignNumericNode: null variable");
  uassert(node&&node->isNumeric(),"AssignNode: null or nonnumeric node: ",variable->name);
}

AssignStringNode::AssignStringNode(StringVariable * var, Node * filter):variable(var),node(filter){
  uassert(variable,"AssignStringNode: null variable");
  uassert(node&&node->isString(),"AssignStringNode: null or nonnumeric node: ",variable->name);
}

bool AssignNumericNode::match_position(QPos*qpos){
  NumValue value{-1000};
  if(node->match_count(qpos,&value)){
    variable->bindNumeric(value);
    return true;}
  return false;
}
bool AssignStringNode::match_position(QPos*qpos){
  string value;
  if(node->match_stringvalue(qpos,&value)){
    variable->bindString(value);
    return true;}
  return false;
}

AssignPositionNode::AssignPositionNode(PositionVariable*var, Node*filter):variable(var),node(filter){
  uassert(variable,"AssignPositionNode: null variable");
  uassert(node&&node->isPosition(),"AssignPositionNode: null or non-position node: ", variable->name);
}

bool AssignPositionNode::match_position(QPos*qpos){
  QPos*value=NULL;
  uassert(node->isPosition(),"apnmp");
  if(node->match_positionvalue(qpos,&value)){
    uassert(value,"apn bad valueassign");
    variable->bindPosition(value);
    return true;
  }
  return false;
}
  
AssignSquareNode::AssignSquareNode(SquareVariable*var,SetBase*filter,bool isconditional):
  variable(var),node(filter),isConditional(isconditional){
  uassert(variable,"AssignSquareNode: null variable");
  uassert(node,"AssignSquareNode: null filter: ",variable->name);
  uassert(node->isSet(),"AssignNode: filter not a set: ",variable->name);
}

bool AssignSquareNode::match_position(QPos*qpos){
  uassert(qpos, "AssignSquareNode: match_position: parameter: ",variable->name);
  SquareMask mask=node->getSquares(qpos);
  if(isConditional&&mask.empty())return false;
  variable->bindMask(mask);
  return true;
}

vnode AssignNumericNode::children()const{
  vnode ret{variable};
  if(node!=variable) ret.push_back(node);
  return ret;
}
vnode AssignStringNode::children()const{
  vnode ret{variable};
  if(node!=variable) ret.push_back(node);
  return ret;
}

vnode AssignPositionNode::children()const{
  vnode ret{variable};
  if(node!=variable) ret.push_back(node);
  return ret;
}

vnode AssignSquareNode::children()const{
  vnode ret{variable};
  if(node!=variable) ret.push_back(node);
  return ret;
}
