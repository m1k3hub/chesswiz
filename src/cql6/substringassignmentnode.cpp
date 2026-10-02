#include "substringassignmentnode.h"
SubstringAssignmentNode::SubstringAssignmentNode(StringVariable*target,BracketRange*bracket,Node*right):
  theTarget(target),
  theBracket(bracket),
  theRight(right){
  uassert(theTarget &&
	  theBracket&&
	  theRight &&
	  theRight->isString()
	  , "substring node bad args");
}

bool SubstringAssignmentNode::match_position(QPos*qpos){
  /* slightly modified from SubstringNode::match_stringvalue() - be sure to keep in sync*/
  NumValue bracketstart{0};
  NumValue bracketstop{0};
  eassert (theTarget->isBound(),"Unable to execute substring assignment of the form x[...]=y because the left hand side variable is currently unbound: ",theTarget->name);
  string& targetref=theTarget->getReference();
  string rightvalue;
  int cstart=qpos->markComments();
  int len= (int)(targetref.size());
  if(!theBracket->getBounds(qpos,len,&bracketstart, &bracketstop) ||
     !theRight->match_stringvalue(qpos,&rightvalue))
    {
      qpos->restoreComments(cstart);
      return false;
    }
  eassert((int)(targetref.size())==len,"target of string assignment illegally modified in subscript assignment ",theTarget->name);
  
  int count=bracketstop-bracketstart;
  uassert (bracketstart>=0&&bracketstart<=len&&bracketstop>=0&&bracketstop<=len&&count<=len,
	   "substring assignment: count error: ", theTarget->name);
  targetref.replace((size_t)bracketstart, (size_t)count, rightvalue);
  return true;
}
  
void SubstringAssignmentNode::deepify(){
  theTarget=theTarget->clone();
  theBracket=theBracket->clone();
  theRight=theRight->clone();
}
vnode SubstringAssignmentNode::children()const{
  vnode ret{theTarget, theBracket};
  if(theRight!=theTarget)
    ret.push_back(theRight);
  return ret;
}
