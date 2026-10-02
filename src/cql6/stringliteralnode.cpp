#include "stringliteralnode.h"

StringLiteralNode::StringLiteralNode(string s):
  theName(s){
}
bool StringLiteralNode::match_stringvalue(QPos*qpos,string*stringp){
  *stringp=theName;
  return true;
}

bool StringLiteralNode::match_position(QPos*qpos){
  eassert(false,"Attempt to match the position to a string literal, which is unnecessary because string literals always match so is probably inadvertent. The string literal is: ",theName);
  return true;
}
  
  
