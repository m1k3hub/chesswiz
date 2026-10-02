#include "concatenationnode.h"
#include "stringvariable.h"

ConcatenationNode::ConcatenationNode(Node*l, Node*r,bool isdestructive):theLeft(l), theRight(r),isDestructive(isdestructive){
  uassert(theLeft&&theRight&&theLeft->isString()&&theRight->isString(),"cncn bad args string concat");
  if(isDestructive)
    uassert(theLeft->isStringVariable(),"concatenation += bad left arg");
}

bool ConcatenationNode::match_position(QPos*qpos){
  if (isDestructive){
    string rights;
    if(!theRight->match_stringvalue(qpos,&rights))
      return false;
    StringVariable* sv=theLeft->asStringVariable();
    uassert(sv,"cnmp sv internal");
    if(sv->isUnbound())
      uassert(false,"unexpectedly unbound string variable when evaluating += : ",sv->name);
    string& ref=sv->getReference();
    ref+=rights;
    return true;
  }
  uassert(!isDestructive,"cnmp isd internal");
  cout << "An attempt to concatenation two string using '+' was made, but the value of the new string "
       << "would be discarded. This is not technically illegal but is likely due to a user error. "
       << "\n The left hand side of '+' is the filter: \n";
  theLeft->print();
  cout <<" The right hand side of '+' is the filter: \n";
  theRight->print();
    
  eassert(false,"Possible unwanted concatenation of two strings using '+'");
  return false;
}

bool ConcatenationNode::match_stringvalue(QPos*qpos,string*stringp){
  uassert(!isDestructive,"ConcatenationNode: internal: not a string value here");
  string lefts,rights;
  if (!theLeft->match_stringvalue(qpos,&lefts))
    return false;
  if (!theRight->match_stringvalue(qpos,&rights))
    return false;
  if (!stringp) return true;
  *stringp=lefts+rights;
  return true;
}
void ConcatenationNode::deepify(){
  theLeft=theLeft->clone();
  theRight=theRight->clone();}

vnode ConcatenationNode::children()const{
  vnode ret{theLeft};
  if (theLeft!=theRight)
    ret.push_back(theRight);
  return ret;
}
  
bool ConcatenationNode::isString()const{
  return !isDestructive;
}
