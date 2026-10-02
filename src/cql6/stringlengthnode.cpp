#include "stringlengthnode.h"
#include "stringvariable.h"
StringLengthNode::StringLengthNode(Node*node): theNode(node){
  uassert(theNode&&theNode->isString(),"stcnin arg");
}

bool StringLengthNode::match_position(QPos*qpos){
  eassert(false,"An attempt was made to get the length of a string expression using '#', but the actual length was ignored. This is likely due to a user error");
  return false;
}

bool StringLengthNode::match_count(QPos*qpos,NumValue*valp){
  if (theNode->isStringVariable()){
    StringVariable *sv=theNode->asStringVariable();
    uassert(sv,"stringlengthnode: internal");
    if(sv->isUnbound())
      eassert(false,"cannot get length of unbound string variable: ",sv->name);
    if(valp)
      *valp= (NumValue)(sv->getReference().size());
    return true;
  }
  string chars;
  if (!theNode->match_stringvalue(qpos,&chars))
    return false;
  *valp=(NumValue)(chars.size());
  return true;
}

void StringLengthNode::deepify(){
  theNode=theNode->clone();
}

vnode StringLengthNode::children()const{
  return vnode{theNode};
}
