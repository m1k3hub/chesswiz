#include "caseconvertnode.h"
CaseConvertNode::CaseConvertNode(Node*n,CaseConvertDirection d):
  theNode(n),theDirection(d){
  uassert(theNode&&theNode->isString(),"ccn");
  uassert(theDirection==CaseConvertDirection::ToLower||
	  theDirection==CaseConvertDirection::ToUpper,"ccnd");
}
bool CaseConvertNode::match_position(QPos*qpos){
  eassert(true,"Attempt to evaluate whether 'lowercase F' or 'uppercase F' matches the current position, but such a filter always matches when the string filter 'F' matches, so this usage may be an error");
  return false;
}
bool CaseConvertNode::match_stringvalue(QPos*qpos,string*sp){
  uassert(sp,"CCN ms arg");
  if (!theNode->match_stringvalue(qpos,sp))
    return false;
  for(char&c:*sp)
    switch(theDirection){
    case CaseConvertDirection::ToLower:
      if(c>='A'&&c<='Z')
	c=(char)(c-'A'+'a');
      break;
    case CaseConvertDirection::ToUpper:
      if(c>='a'&&c<='z')
	c=(char)(c-'a'+'A');
      break;
    default:
      uassert(false,"CCN switch");
    }//switch theDirection
  return true;
}
vnode CaseConvertNode::children()const{
  return vnode{theNode};
}

void CaseConvertNode::deepify(){
  theNode=theNode->clone();
}
    
