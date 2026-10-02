#include "stringasciinode.h"
StringAsciiNode::StringAsciiNode(Node*node,AsciiDirection dir):
  theNode(node),theDirection(dir){
  uassert(theDirection==AsciiDirection::FromAscii||theDirection==AsciiDirection::ToAscii,"san args");
  uassert(theNode,"san node");
  uassert(dir==AsciiDirection::FromAscii&&theNode->isNumeric()||
	  dir==AsciiDirection::ToAscii&&theNode->isString(),"san args 2");
  uassert(isNumeric()||isString(),"san args 3");
}
bool StringAsciiNode::match_position(QPos*qpos){
  if (isString())
    return match_stringvalue(qpos,NULL);
  else
    return match_count(qpos,NULL);
}
bool StringAsciiNode::match_stringvalue(QPos*qpos,string*stringp){
  uassert(isString(),"san msv");
  NumValue val{0};
  if (!theNode->match_count(qpos,&val))
    return false;
  if (val<=0 || val>255)
    return false; //should clear the stack here
  char c= static_cast<char>(val);
  if(stringp){
    *stringp=string(1,c);
    if(0)
      cout<<"StringAsciiNode::match_stringvalue(): val is: "<<val<<" and c is: "<<c<<endl;
    if(0) cout<<"StringAsciiNode;:match_stringvalue: *stringp is: "<<*stringp<<endl;
    uassert(stringp->size()==1, "bad stringp size san msv");
    char checkc = (stringp->front());
    if (checkc!=c){
      stringstream s;
      s<<"StringFromAscii for value of : "
       <<val<<" expected character: "<<c<<" but got character: "<<checkc<<endl;
      uassert(false,s.str());
    }
  }
  return true;
}

bool StringAsciiNode::match_count(QPos*qpos,NumValue*valp){
  uassert(isNumeric(),"san mc");
  string str;
  if (!theNode->match_stringvalue(qpos,&str))
    return false;
  if (str.size()!=1)
    return false; //should clear the stack here
  int charvalue=(int)static_cast<unsigned char>(str.at(0));
  uassert(charvalue>0&&charvalue<=255
	  ,"StringAsciiNode: unexpected out of bounds character in string: "
	  ,str);
  if(valp)
    *valp=(NumValue)charvalue;
  return true;
}
    
    
void StringAsciiNode::deepify(){
  theNode->deepify();
}
