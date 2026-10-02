#include "stringtointnode.h"
StringToIntNode::StringToIntNode(Node*node): theNode(node){
  uassert(theNode&&theNode->isString(),"stin arg");
}

bool StringToIntNode::match_position(QPos*qpos){
  return match_count(qpos,NULL);
}

bool StringToIntNode::match_count(QPos*qpos,NumValue*valp){
  string chars;
  if (!theNode->match_stringvalue(qpos,&chars))
    return false;
  int tmpint{0};
  if (!util::intValue(chars,&tmpint))
    return false;
  if (valp)*valp=(NumValue)tmpint;
  return true;
}

void StringToIntNode::deepify(){
  theNode=theNode->clone();
}

vnode StringToIntNode::children()const{
  return vnode{theNode};
}
