#include "substringnode.h"
#include "stringvariable.h"
SubstringNode::SubstringNode(Node*target,BracketRange*bracket):
  theTarget(target),
    theBracket(bracket){
  uassert(theTarget&&theTarget->isString() &&
	  theBracket, "substring node bad args");
}

bool SubstringNode::match_position(QPos*qpos){
  return match_stringvalue(qpos,NULL);
}

bool SubstringNode::match_stringvalue(QPos*qpos, string*stringp){
  /*slightly modified version in SubstringAssignmentNode::match_position(): keep in sync!*/
  NumValue bracketstart{0};
  NumValue bracketstop{0};
  bool singleindex=theBracket->singleIndex;
  bool isVariable=theTarget->isStringVariable();
  StringVariable *sv{NULL};
  string targetnonvar;
  string*targetp{NULL};
  int cstart=qpos->markComments();
  if (isVariable){
    sv=theTarget->asStringVariable();
    uassert(sv,"msv error");
    if (sv->isUnbound())
      eassert(false,"Unexpected attempt to apply the subscript operator [...] to the unbound variable: ",sv->name);
    string&targetvarref=sv->getReference();
    targetp=&targetvarref;
  }//isVariable
  if(!isVariable){
    if (!theTarget->match_stringvalue(qpos,&targetnonvar))
      return false;
    targetp= &targetnonvar;}
  uassert(targetp,"substringnode:match_stringvalue: internal targetp");
  string& targetref= *targetp;
  
  int len= (int)(targetref.size());
  if(!theBracket->getBounds(qpos,len,&bracketstart, &bracketstop)){
    qpos->restoreComments(cstart);
    return false;}
  if (singleindex){
    if(stringp)
      *stringp=string(1,targetref.at(bracketstart));
    return true;
  }
  uassert(!singleindex,"substring internal si");
  int count = bracketstop-bracketstart;
  if (count<0){
    stringstream s;
    s<<"substringnode bad count: targetref:  " << targetref
     <<" len: "<<len
     << " bracketstart: " <<bracketstart
     <<" bracketstop: "<< bracketstop<<endl;
    cout<<"bracket: "<<endl;
    theBracket->print();
    uassert(false,s.str());
  }
      
  uassert(count>=0,"substringnode bad count bracket");
  if(stringp)
    *stringp=targetref.substr((size_t)bracketstart, (size_t)count);
  return true;
}  
  
void SubstringNode::deepify(){
  theTarget=theTarget->clone();
  theBracket=theBracket->clone();
}
vnode SubstringNode::children()const{
  vnode ret{theTarget, theBracket};
  return ret;
}
